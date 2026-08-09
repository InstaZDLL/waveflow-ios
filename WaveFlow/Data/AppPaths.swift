import Foundation

/// Emplacements sur disque utilisés par l'application.
nonisolated enum AppPaths {

    /// Le dossier `Documents` de l'app — la bibliothèque de l'utilisateur.
    ///
    /// Exposé dans l'app Fichiers (`UIFileSharingEnabled`) : c'est là que
    /// l'utilisateur dépose sa musique, et c'est là qu'atterriront les
    /// téléchargements depuis le serveur WaveFlow.
    static let documents: URL = {
        // `Documents` existe toujours dans le conteneur d'une app iOS ; s'il
        // manquait, rien de ce qui suit n'aurait de sens.
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            preconditionFailure("Dossier Documents introuvable dans le conteneur de l'application")
        }
        return url
    }()

    /// Pochettes extraites des fichiers. Dans `Caches` : régénérable au
    /// prochain scan, donc le système peut le purger sous pression disque.
    static let artworkCache: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? documents
        return base.appendingPathComponent("Artwork", isDirectory: true)
    }()
}
