import AVFoundation
import CryptoKit
import Foundation

/// Lecture d'un dossier de fichiers audio et de leurs tags.
///
/// C'est le pendant iOS de la requête `MediaStore` d'Android : là-bas le
/// système tient un index de tous les fichiers audio de l'appareil, ici il
/// n'en existe aucun. On énumère donc le dossier de l'app et on ouvre chaque
/// fichier avec `AVURLAsset` pour en lire les tags.
nonisolated enum LibraryScanner {

    /// Formats qu'`AVFoundation` sait décoder. Volontairement restrictif :
    /// mieux vaut ignorer un fichier que peupler la bibliothèque d'entrées
    /// injouables (Ogg/Vorbis et Opus nu, notamment, ne sont pas supportés).
    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "flac", "wav", "aif", "aiff", "caf", "mp4",
    ]

    /// Nombre de fichiers ouverts en parallèle. Sans borne, une bibliothèque
    /// de plusieurs milliers de titres ouvrirait autant d'`AVURLAsset` d'un
    /// coup et épuiserait les descripteurs de fichiers.
    private static let maxConcurrentReads = 6

    /// Énumère [root], lit les tags, et renvoie les morceaux triés par titre.
    ///
    /// Les fichiers illisibles sont ignorés plutôt que remontés en erreur :
    /// un seul fichier corrompu ne doit pas priver l'utilisateur de toute sa
    /// bibliothèque.
    static func scan(root: URL, artworkDirectory: URL) async -> [Song] {
        let files = audioFiles(in: root)
        guard !files.isEmpty else { return [] }

        try? FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)

        let songs = await withTaskGroup(of: Song?.self) { group in
            var iterator = files.makeIterator()
            var results: [Song] = []
            results.reserveCapacity(files.count)

            for _ in 0..<maxConcurrentReads {
                guard let file = iterator.next() else { break }
                group.addTask { await read(file, root: root, artworkDirectory: artworkDirectory) }
            }

            // Une tâche relancée à chaque complétion : la fenêtre reste pleine
            // sans jamais dépasser la borne.
            while let finished = await group.next() {
                if let finished { results.append(finished) }
                if let file = iterator.next() {
                    group.addTask { await read(file, root: root, artworkDirectory: artworkDirectory) }
                }
            }
            return results
        }

        return songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Fichiers candidats de [root], sous-dossiers compris — l'utilisateur
    /// range souvent sa musique en `Artiste/Album/`.
    private static func audioFiles(in root: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
        )
        guard let enumerator else { return [] }

        return enumerator.compactMap { entry in
            guard let url = entry as? URL,
                  supportedExtensions.contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { return nil }
            return url
        }
    }

    private static func read(_ url: URL, root: URL, artworkDirectory: URL) async -> Song? {
        let asset = AVURLAsset(url: url)

        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty,
              let (assetDuration, metadata) = try? await asset.load(.duration, .metadata)
        else { return nil }

        let seconds = assetDuration.seconds
        let duration = seconds.isFinite && seconds > 0 ? seconds : 0

        let title = await string(from: metadata, .commonIdentifierTitle)
            ?? url.deletingPathExtension().lastPathComponent
        let artist = await string(from: metadata, .commonIdentifierArtist)
        let album = await string(from: metadata, .commonIdentifierAlbumName)

        // L'artiste de l'album prime pour le regroupement. Écrit en étapes
        // plutôt qu'en chaîne de `??` : `await` ne peut pas apparaître à
        // droite d'un opérateur non-affectant.
        var collectionArtist = await string(from: metadata, .iTunesMetadataAlbumArtist)
        if collectionArtist == nil {
            collectionArtist = await string(from: metadata, .id3MetadataBand)
        }
        // Faute de tag dédié, on déduit l'artiste principal du crédit complet :
        // sinon chaque featuring ouvre son propre album.
        if collectionArtist == nil {
            collectionArtist = artist?.primaryArtist
        }

        let albumId = "album:\((album ?? "").groupingKey)|\((collectionArtist ?? "").groupingKey)"
        let artistId = "artist:\((collectionArtist ?? "").groupingKey)"

        let artworkURL = await artwork(from: metadata, albumId: albumId, directory: artworkDirectory)

        return Song(
            id: relativePath(of: url, in: root),
            url: url,
            title: title,
            artist: artist,
            artistId: artistId,
            album: album,
            albumId: albumId,
            collectionArtist: collectionArtist,
            duration: duration,
            artworkURL: artworkURL,
        )
    }

    private static func string(
        from metadata: [AVMetadataItem],
        _ identifier: AVMetadataIdentifier,
    ) async -> String? {
        let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first
        guard let item, let value = try? await item.load(.stringValue) else { return nil }
        return value.nonBlank
    }

    /// Extrait la pochette et la dépose dans le cache, une fois par album.
    ///
    /// Elle est écrite sur disque plutôt que gardée en mémoire : une pochette
    /// pèse souvent plusieurs centaines de kilo-octets, et la bibliothèque
    /// entière reste chargée tant que l'app tourne.
    private static func artwork(
        from metadata: [AVMetadataItem],
        albumId: String,
        directory: URL,
    ) async -> URL? {
        let destination = directory.appendingPathComponent(filename(for: albumId))
        if FileManager.default.fileExists(atPath: destination.path) { return destination }

        let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first
        guard let item,
              let data = try? await item.load(.dataValue),
              !data.isEmpty,
              (try? data.write(to: destination, options: .atomic)) != nil
        else { return nil }

        return destination
    }

    /// Nom de fichier stable et sûr pour un identifiant d'album quelconque —
    /// celui-ci contient des tags bruts, donc potentiellement des `/`.
    private static func filename(for albumId: String) -> String {
        let digest = SHA256.hash(data: Data(albumId.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".artwork"
    }

    private static func relativePath(of url: URL, in root: URL) -> String {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return path }
        return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
