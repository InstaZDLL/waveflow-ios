import Foundation
import SwiftData

/// Ouverture du stockage des playlists, avec dégradation par paliers.
///
/// Ne lève jamais. Refuser de démarrer serait la pire issue sur iOS : le seul
/// recours d'un utilisateur bloqué au lancement est de désinstaller
/// l'application — ce qui efface aussi `Documents`, donc toute sa musique
/// importée. Perdre une bibliothèque entière pour réparer une base de playlists
/// est sans commune mesure avec la panne.
///
/// Le déclencheur attendu n'est d'ailleurs pas la corruption mais l'échec de
/// migration après une mise à jour : le schéma va bouger quand la
/// synchronisation serveur arrivera.
nonisolated enum PlaylistPersistence {

    /// Ce qu'il est advenu du stockage à l'ouverture.
    enum Outcome: Sendable, Equatable {

        /// Base ouverte normalement.
        case opened

        /// Base illisible, écartée puis recréée vide. Les playlists
        /// précédentes sont perdues ; l'ancienne base est conservée à
        /// [displacedTo] plutôt que détruite.
        case reset(displacedTo: URL)

        /// Rien n'a pu être ouvert : les playlists ne seront pas persistées.
        /// Le reste de l'application fonctionne, la musique est intacte.
        case unavailable
    }

    struct Opening {
        let repository: PlaylistRepository
        let outcome: Outcome
    }

    static func open(in directory: URL = .applicationSupportDirectory) -> Opening {
        if let container = try? SwiftDataPlaylistRepository.makeContainer(in: directory) {
            return Opening(repository: SwiftDataPlaylistRepository(container: container), outcome: .opened)
        }

        // Deuxième essai après avoir écarté ce qui traîne : une base illisible
        // le reste, la rouvrir telle quelle échouerait indéfiniment.
        if let displacedTo = try? displaceStore(in: directory),
           let container = try? SwiftDataPlaylistRepository.makeContainer(in: directory) {
            return Opening(
                repository: SwiftDataPlaylistRepository(container: container),
                outcome: .reset(displacedTo: displacedTo),
            )
        }

        // Ni l'une ni l'autre : le disque est probablement inaccessible. Les
        // playlists vivront le temps de la session plutôt que d'empêcher
        // l'application de démarrer.
        return Opening(repository: InMemoryPlaylistRepository(), outcome: .unavailable)
    }

    /// Déplace la base et ses fichiers annexes dans un sous-dossier daté.
    ///
    /// Déplacée, pas supprimée : elle contient les playlists de l'utilisateur,
    /// et une base illisible par SwiftData peut rester récupérable autrement.
    ///
    /// Les annexes `-wal` et `-shm` partent avec elle : les laisser ferait
    /// reprendre un journal périmé à la base neuve.
    private static func displaceStore(in directory: URL) throws -> URL {
        let stamp = Int(Date().timeIntervalSince1970)
        let destination = directory.appending(path: "DamagedStore-\(stamp)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        var moved = false
        for name in SwiftDataPlaylistRepository.storeFileNames {
            let source = directory.appending(path: name)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.moveItem(at: source, to: destination.appending(path: name))
            moved = true
        }

        // Rien à écarter : l'ouverture a échoué pour une autre raison, et la
        // relancer à l'identique échouerait pareil. On le dit plutôt que de
        // laisser croire à une remise à neuf.
        guard moved else {
            try? FileManager.default.removeItem(at: destination)
            throw CocoaError(.fileNoSuchFile)
        }

        return destination
    }
}

nonisolated extension PlaylistPersistence.Outcome {

    /// Message à montrer à l'utilisateur, `nil` quand tout s'est bien passé.
    ///
    /// Il nomme ce qui est perdu *et* ce qui ne l'est pas : la panne touche les
    /// playlists, jamais la musique importée.
    var notice: String? {
        switch self {
        case .opened:
            nil

        case .reset:
            """
            Tes playlists n'ont pas pu être relues et ont été réinitialisées. \
            Ta musique importée, elle, est intacte.
            """

        case .unavailable:
            """
            Les playlists ne peuvent pas être enregistrées sur cet appareil : \
            elles disparaîtront à la fermeture. Ta musique importée est intacte.
            """
        }
    }
}
