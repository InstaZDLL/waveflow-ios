import AVFoundation
import CryptoKit
import Foundation
import Testing
@testable import WaveFlow

/// Le scanner, sur une arborescence fabriquée pour l'occasion.
///
/// Les fichiers audio sont écrits par le test — silence encodé en AAC, puis
/// taggé — plutôt que déposés dans le dépôt : un `.m4a` de fixture serait un
/// binaire opaque, impossible à relire et à modifier, et le tag qu'on veut
/// éprouver n'apparaîtrait nulle part dans le code.
///
/// - Note: exclue du harnais Linux, AVFoundation n'y existant pas.
struct LibraryScannerTests {

    /// MARK: - Énumération

    @Test func readsFilesFromSubdirectoriesAndNamesThemByRelativePath() async throws {
        let root = try Fixtures()
        defer { root.remove() }

        try await root.writeSong(at: "Nayeon/Im Nayeon/pop.m4a", title: "POP!")
        try await root.writeSong(at: "single.m4a", title: "Abbey")

        let songs = await root.scan()

        // Triés par titre, insensible à la casse : c'est le contrat de `scan`.
        #expect(songs.map(\.title) == ["Abbey", "POP!"])
        #expect(songs.map(\.id) == ["single.m4a", "Nayeon/Im Nayeon/pop.m4a"])
    }

    /// Un fichier illisible ne doit pas priver l'utilisateur du reste.
    @Test func skipsWhatItCannotDecodeWithoutLosingTheRest() async throws {
        let root = try Fixtures()
        defer { root.remove() }

        try await root.writeSong(at: "bon.m4a", title: "Bon")
        // Une extension reconnue sur un contenu qui n'a rien d'audio.
        try root.write(Data("ceci n'est pas de l'audio".utf8), at: "menteur.m4a")
        try root.write(Data("notes".utf8), at: "notes.txt")

        let songs = await root.scan()

        #expect(songs.map(\.title) == ["Bon"])
    }

    @Test func ignoresHiddenFiles() async throws {
        let root = try Fixtures()
        defer { root.remove() }

        try await root.writeSong(at: "visible.m4a", title: "Visible")
        try await root.writeSong(at: ".cache.m4a", title: "Caché")

        let songs = await root.scan()

        #expect(songs.map(\.title) == ["Visible"])
    }

    /// MARK: - Tags

    @Test func fallsBackToTheFileNameWhenTheTitleIsMissing() async throws {
        let root = try Fixtures()
        defer { root.remove() }

        try await root.writeSong(at: "Sans tag.m4a", title: nil)

        let songs = await root.scan()

        #expect(songs.map(\.title) == ["Sans tag"])
    }

    /// L'artiste de l'album prime sur l'interprète : sans ça, un album dont
    /// deux titres portent un featuring se scinderait en trois.
    ///
    /// L'interprète est choisi pour qu'aucun repli ne puisse rendre la bonne
    /// réponse : « Wonstein » ne se ramène pas à « Nayeon ». Un test où les
    /// deux tags s'accordent passerait même si celui-ci n'était jamais lu.
    @Test func groupsOnTheAlbumArtistWhenItIsTagged() async throws {
        let root = try Fixtures()
        defer { root.remove() }

        try await root.writeSong(
            at: "a.m4a", title: "A",
            artist: "Nayeon", album: "Im Nayeon", albumArtist: "Nayeon",
        )
        try await root.writeSong(
            at: "b.m4a", title: "B",
            artist: "Wonstein", album: "Im Nayeon", albumArtist: "Nayeon",
        )

        let songs = await root.scan()

        #expect(songs.count == 2)
        #expect(songs.map(\.artist) == ["Nayeon", "Wonstein"])
        #expect(songs.allSatisfy { $0.collectionArtist == "Nayeon" })
        #expect(Set(songs.map(\.albumId)).count == 1)
        #expect(Set(songs.map(\.artistId)).count == 1)
    }

    /// Faute de tag dédié — le cas de la plupart des `.m4a` — l'artiste
    /// principal est déduit du crédit complet.
    @Test func fallsBackToThePrimaryArtistWhenNoAlbumArtistIsTagged() async throws {
        let root = try Fixtures()
        defer { root.remove() }

        try await root.writeSong(
            at: "a.m4a", title: "A",
            artist: "Nayeon", album: "Im Nayeon",
        )
        try await root.writeSong(
            at: "b.m4a", title: "B",
            artist: "Nayeon feat. Wonstein", album: "Im Nayeon",
        )

        let songs = await root.scan()

        // Le crédit complet est conservé, mais c'est « Nayeon » qui regroupe.
        // Compter les identifiants ne suffirait pas : sans repli, les deux
        // morceaux tomberaient sur un artiste vide — donc sur un identifiant
        // unique lui aussi, et le test passerait sans rien avoir éprouvé.
        #expect(songs.map(\.artist) == ["Nayeon", "Nayeon feat. Wonstein"])
        #expect(songs.allSatisfy { $0.collectionArtist == "Nayeon" })
        #expect(Set(songs.map(\.albumId)).count == 1)
        #expect(Set(songs.map(\.artistId)).count == 1)
    }

    /// MARK: - Pochettes

    /// Déposée dans le cache et nommée d'après l'album, donc partagée : deux
    /// titres du même album désignent le même fichier.
    ///
    /// Ce que le test ne montre pas, c'est que l'extraction n'a lieu qu'une
    /// fois — le nom se déduisant de l'album, les deux titres pointeraient au
    /// même endroit même sans le cache. Il faudrait observer les écritures.
    @Test func sharesOneArtworkFilePerAlbum() async throws {
        let root = try Fixtures()
        defer { root.remove() }

        try await root.writeSong(
            at: "a.m4a", title: "A",
            artist: "Nayeon", album: "Im Nayeon", albumArtist: "Nayeon", artwork: Fixtures.pngPixel,
        )
        try await root.writeSong(
            at: "b.m4a", title: "B",
            artist: "Nayeon", album: "Im Nayeon", albumArtist: "Nayeon", artwork: Fixtures.pngPixel,
        )

        let songs = await root.scan()

        // Les deux morceaux d'abord : sans ce compte, une pochette unique ne
        // prouverait rien — un seul morceau lu en donnerait autant.
        #expect(songs.count == 2)

        let artworks = Set(songs.compactMap(\.artworkURL))
        #expect(artworks.count == 1)

        let artwork = try #require(artworks.first)
        #expect(FileManager.default.fileExists(atPath: artwork.path))
        #expect(artwork.deletingLastPathComponent().standardizedFileURL == root.artwork.standardizedFileURL)
        #expect(try Data(contentsOf: artwork) == Fixtures.pngPixel)
    }

    @Test func leavesArtworkNilWhenTheFileHasNone() async throws {
        let root = try Fixtures()
        defer { root.remove() }

        try await root.writeSong(at: "a.m4a", title: "A")

        let songs = await root.scan()

        // Le morceau doit exister : une fixture illisible rendrait une liste
        // vide, et `first?.artworkURL` serait nul sans que rien n'ait été lu.
        #expect(songs.count == 1)
        #expect(songs.first?.artworkURL == nil)
    }
}

/// Une arborescence temporaire et de quoi la peupler.
///
/// Neuve à chaque test, effacée derrière : aucune dépendance à l'ordre
/// d'exécution, et rien ne traîne dans le conteneur de l'hôte de tests.
private struct Fixtures {

    let root: URL
    let artwork: URL

    /// Un PNG de 1×1 pixel — le plus petit contenu qu'un lecteur de pochettes
    /// acceptera de recopier tel quel.
    static let pngPixel = Data(base64Encoded: """
        iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
        """)!

    init() throws {
        let base = URL.temporaryDirectory.appending(path: UUID().uuidString)
        root = base.appending(path: "Documents")
        artwork = base.appending(path: "Artwork")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    func scan() async -> [Song] {
        await LibraryScanner.scan(root: root, artworkDirectory: artwork)
    }

    func write(_ data: Data, at path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try data.write(to: url)
    }

    /// Écrit un vrai `.m4a` : du silence encodé en AAC, puis remuxé avec ses
    /// tags. En deux temps parce que `AVAudioFile` sait produire le flux mais
    /// pas les métadonnées, et l'export en passthrough les pose sans réencoder.
    func writeSong(
        at path: String,
        title: String?,
        artist: String? = nil,
        album: String? = nil,
        albumArtist: String? = nil,
        artwork: Data? = nil,
    ) async throws {
        let destination = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )

        let silence = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: silence) }
        try Self.writeSilence(to: silence)

        var items: [AVMetadataItem] = []
        if let title { items.append(Self.item(.commonIdentifierTitle, title as NSString)) }
        if let artist { items.append(Self.item(.commonIdentifierArtist, artist as NSString)) }
        if let album { items.append(Self.item(.commonIdentifierAlbumName, album as NSString)) }
        if let albumArtist {
            items.append(Self.item(.iTunesMetadataAlbumArtist, albumArtist as NSString))
        }
        if let artwork { items.append(Self.item(.commonIdentifierArtwork, artwork as NSData)) }

        let session = try #require(
            AVAssetExportSession(asset: AVURLAsset(url: silence), presetName: AVAssetExportPresetPassthrough),
        )
        session.metadata = items
        try await session.export(to: destination, as: .m4a)
    }

    private static func writeSilence(to url: URL, seconds: Double = 0.4) throws {
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
        ])

        let format = file.processingFormat
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        // Le tampon est déjà à zéro : du silence fait un fichier valide, et
        // c'est tout ce que le scanner demande.
        buffer.frameLength = frames

        try file.write(from: buffer)
    }

    private static func item(
        _ identifier: AVMetadataIdentifier,
        _ value: some NSCopying & NSObjectProtocol,
    ) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value
        item.extendedLanguageTag = "und"
        return item
    }
}
