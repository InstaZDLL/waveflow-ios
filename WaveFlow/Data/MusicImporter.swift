import Foundation

/// Copie des fichiers choisis dans le dossier `Documents`.
///
/// Sans équivalent Android : là-bas la musique est déjà sur l'appareil et le
/// `MediaStore` la référence. Ici, rien n'entre dans le bac à sable de l'app
/// sans une copie explicite.
nonisolated enum MusicImporter {

    struct Result: Sendable {
        var imported: Int = 0
        var failed: Int = 0
    }

    /// Copie [urls] dans [destination] et renvoie le bilan.
    ///
    /// Les fichiers viennent du sélecteur de documents, donc d'en dehors du bac
    /// à sable : chacun doit être ouvert sous accès à portée sécurisée, sinon
    /// la lecture échoue avec une erreur de permission.
    static func copy(_ urls: [URL], into destination: URL = AppPaths.documents) -> Result {
        var result = Result()

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            do {
                try FileManager.default.copyItem(at: url, to: uniqueDestination(for: url, in: destination))
                result.imported += 1
            } catch {
                result.failed += 1
            }
        }

        return result
    }

    /// Évite d'écraser un fichier existant : « Track.mp3 » devient
    /// « Track 2.mp3 ». Deux morceaux différents peuvent porter le même nom.
    private static func uniqueDestination(for source: URL, in directory: URL) -> URL {
        let name = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension

        var candidate = directory.appendingPathComponent(source.lastPathComponent)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name) \(suffix)").appendingPathExtension(ext)
            suffix += 1
        }
        return candidate
    }
}
