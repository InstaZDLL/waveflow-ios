import Foundation
import SwiftData

/// La forme stockée d'une [Playlist].
///
/// Entité distincte du modèle plutôt que `Playlist` annotée `@Model`, pour deux
/// raisons. `@Model` remplace les propriétés stockées par des accès observés et
/// impose une classe : le domaine perdrait sa sémantique de valeur, et ses
/// mutations `mutating` avec elle. Surtout, `Model/` ne doit dépendre que de
/// Foundation — c'est ce qui le garde vérifiable sans Mac (voir
/// `Tools/LinuxHarness`), et SwiftData n'existe pas sur Linux.
///
/// C'est aussi le découpage d'Android, où `PlaylistEntity` (Room) et `Playlist`
/// (domaine) sont deux types.
@Model
final class PlaylistEntity {

    /// Identifiant du domaine, pas une clé attribuée par le stockage : c'est
    /// [Playlist] qui le tire, et la synchronisation serveur devra le retrouver
    /// à l'identique sur un autre appareil.
    @Attribute(.unique) var id: UUID

    var name: String

    /// L'ordre est porté par le tableau, comme dans le domaine.
    ///
    /// Pas de colonne `position` ni d'entité fille : SwiftData sait stocker un
    /// `[String]`, et une liste ordonnée en un seul champ ne peut ni se trouer
    /// après un retrait, ni entrer en collision. Le jour où une playlist
    /// devient assez grosse pour que ce soit un problème, ce sera un
    /// changement de schéma — pas un changement de domaine.
    var songIds: [String]

    var createdAt: Date

    var updatedAt: Date

    init(_ playlist: Playlist) {
        self.id = playlist.id
        self.name = playlist.name
        self.songIds = playlist.songIds
        self.createdAt = playlist.createdAt
        self.updatedAt = playlist.updatedAt
    }

    /// Vue domaine de l'entité.
    var asPlaylist: Playlist {
        Playlist(
            id: id,
            name: name,
            songIds: songIds,
            createdAt: createdAt,
            updatedAt: updatedAt,
        )
    }

    /// Recopie l'état du domaine.
    ///
    /// `id` et `createdAt` ne sont pas réécrits : ils sont immuables côté
    /// domaine, et les toucher ici masquerait une confusion d'identité plutôt
    /// que de la révéler.
    func apply(_ playlist: Playlist) {
        name = playlist.name
        songIds = playlist.songIds
        updatedAt = playlist.updatedAt
    }
}
