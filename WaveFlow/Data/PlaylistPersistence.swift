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
        ///
        /// [displacedTo] est renseigné quand l'ancienne base avait déjà été
        /// écartée avant que la recréation échoue : elle a beau ne pas être
        /// remplacée, elle a bel et bien été déplacée, et le taire laisserait
        /// croire que les playlists sont toujours là.
        case unavailable(displacedTo: URL?)
    }

    struct Opening {
        let repository: PlaylistRepository
        let outcome: Outcome
    }

    /// - Parameter makeContainer: point d'injection réservé aux tests. Le
    ///   chemin « base écartée puis recréation impossible » n'est pas
    ///   reproductible en manipulant seulement le système de fichiers, et c'est
    ///   justement celui où l'information de l'écartement se perdait.
    static func open(
        in directory: URL = .applicationSupportDirectory,
        makeContainer: (URL) throws -> ModelContainer = {
            try SwiftDataPlaylistRepository.makeContainer(in: $0)
        },
    ) -> Opening {
        if let container = try? makeContainer(directory) {
            return Opening(repository: SwiftDataPlaylistRepository(container: container), outcome: .opened)
        }

        // Deuxième essai après avoir écarté ce qui traîne : une base illisible
        // le reste, la rouvrir telle quelle échouerait indéfiniment.
        let displacedTo = displaceStore(in: directory)

        if let displacedTo, let container = try? makeContainer(directory) {
            return Opening(
                repository: SwiftDataPlaylistRepository(container: container),
                outcome: .reset(displacedTo: displacedTo),
            )
        }

        // Rien d'ouvrable : le disque est probablement inaccessible. Les
        // playlists vivront le temps de la session plutôt que d'empêcher
        // l'application de démarrer — mais si l'ancienne base a malgré tout été
        // écartée entre-temps, il faut le dire, sinon l'utilisateur croirait
        // ses playlists simplement en attente.
        return Opening(
            repository: InMemoryPlaylistRepository(),
            outcome: .unavailable(displacedTo: displacedTo),
        )
    }

    /// Déplace la base et ses fichiers annexes dans un sous-dossier daté.
    ///
    /// Déplacée, pas supprimée : elle contient les playlists de l'utilisateur,
    /// et une base illisible par SwiftData peut rester récupérable autrement.
    ///
    /// Les annexes `-wal` et `-shm` partent avec elle : les laisser ferait
    /// reprendre un journal périmé à la base neuve.
    ///
    /// Ne lève pas, et chaque fichier est tenté indépendamment : un
    /// déplacement partiel doit être rapporté, pas perdu. Échouer en bloc
    /// aurait deux effets, tous deux faux — l'écartement de la base principale
    /// passerait sous silence alors qu'elle a bougé, et l'appelant renoncerait
    /// à recréer une base alors que la place est justement libre.
    ///
    /// - Returns: le dossier d'accueil, ou `nil` si rien n'a bougé.
    private static func displaceStore(in directory: URL) -> URL? {
        // Horodatage *et* tirage unique. La seconde seule ne suffit pas : deux
        // récupérations dans la même seconde viseraient le même dossier, et
        // comme `createDirectory` réussit sur un dossier existant, les
        // déplacements échoueraient sur des fichiers déjà là — puis le retour
        // à vide plus bas effacerait l'archive précédente, playlists comprises.
        // L'horodatage reste devant pour que les archives se lisent dans
        // l'ordre.
        let stamp = Int(Date().timeIntervalSince1970)
        let unique = UUID().uuidString.prefix(8)
        let destination = directory.appending(
            path: "DamagedStore-\(stamp)-\(unique)",
            directoryHint: .isDirectory,
        )
        guard (try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)) != nil
        else { return nil }

        var moved = false
        for name in SwiftDataPlaylistRepository.storeFileNames {
            let source = directory.appending(path: name)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }

            // Une annexe récalcitrante ne doit pas annuler le déplacement de la
            // base elle-même : c'est elle qui bloque la recréation.
            if (try? FileManager.default.moveItem(at: source, to: destination.appending(path: name))) != nil {
                moved = true
            }
        }

        // Rien n'a bougé : l'ouverture a échoué pour une autre raison, et la
        // relancer à l'identique échouerait pareil. On le dit plutôt que de
        // laisser croire à une remise à neuf. Le dossier effacé ici est
        // forcément celui qu'on vient de créer — c'est le tirage unique du nom
        // qui le garantit.
        guard moved else {
            try? FileManager.default.removeItem(at: destination)
            return nil
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

        case .unavailable(displacedTo: nil):
            """
            Les playlists ne peuvent pas être enregistrées sur cet appareil : \
            elles disparaîtront à la fermeture. Ta musique importée est intacte.
            """

        case .unavailable:
            """
            Tes playlists n'ont pas pu être relues, et elles ne peuvent pas non \
            plus être enregistrées sur cet appareil : elles disparaîtront à la \
            fermeture. Ta musique importée, elle, est intacte.
            """
        }
    }
}
