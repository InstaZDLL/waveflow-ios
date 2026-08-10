import Foundation

/// Ce qui peut échouer en manipulant les playlists.
nonisolated enum PlaylistError: Error, Equatable {

    /// L'identifiant ne désigne aucune playlist — supprimée depuis un autre
    /// écran, ou jamais créée.
    case unknownPlaylist(Playlist.ID)

    /// Un nom vide ou fait d'espaces : une playlist doit rester désignable.
    case invalidName
}

/// Les playlists locales, vues par le reste de l'application.
///
/// Séparé de [MusicRepository] parce que les deux sources n'ont rien en
/// commun : l'une lit un dossier, l'autre écrit dans un stockage dont
/// l'application est propriétaire. C'est aussi la première donnée que la
/// synchronisation serveur devra faire remonter, d'où les horodatages portés
/// par [Playlist].
///
/// Le contrat est volontairement plus étroit que le modèle : les mutations
/// désignent une playlist par son identifiant plutôt que d'en rendre une copie
/// à modifier, pour qu'un écran ne puisse pas écrire par-dessus une
/// modification faite ailleurs entre-temps.
nonisolated protocol PlaylistRepository: Sendable {

    /// Flux des playlists, ré-émis à chaque modification, triées par nom.
    ///
    /// L'état courant est émis dès l'abonnement : un écran qui s'ouvre n'a
    /// rien à demander de plus.
    func playlists() -> AsyncThrowingStream<[Playlist], Error>

    /// Crée une playlist, éventuellement pourvue de son premier morceau.
    ///
    /// L'ajout se fait dans la même opération plutôt qu'en deux appels : une
    /// interruption ne peut pas laisser une playlist vide derrière elle.
    ///
    /// - Throws: [PlaylistError.invalidName] si `name` est blanc.
    @discardableResult
    func create(name: String, containing songId: String?) async throws -> Playlist

    /// - Throws: [PlaylistError.invalidName] si `name` est blanc.
    func rename(_ id: Playlist.ID, to name: String) async throws

    func delete(_ id: Playlist.ID) async throws

    /// Ajoute un morceau en fin de playlist. Sans effet s'il y figure déjà.
    func add(_ songId: String, to id: Playlist.ID) async throws

    func remove(_ songId: String, from id: Playlist.ID) async throws

    /// Réordonne la playlist selon `orderedSongIds`.
    ///
    /// L'ordre complet plutôt qu'un couple (morceau, destination) : c'est ce
    /// que l'écran connaît après un glisser-déposer. La normalisation — les
    /// identifiants étrangers écartés, les morceaux omis replacés à la suite —
    /// appartient à [Playlist.reorder(to:at:)].
    func reorder(_ id: Playlist.ID, to orderedSongIds: [String]) async throws
}

nonisolated extension PlaylistRepository {

    /// Crée une playlist vide.
    @discardableResult
    func create(name: String) async throws -> Playlist {
        try await create(name: name, containing: nil)
    }
}
