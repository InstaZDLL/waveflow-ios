import Foundation

/// La bibliothèque locale, telle que chargée à un instant donné.
///
/// Une seule source : `songs`. Albums, artistes et index en sont des vues
/// dérivées. Android les calcule paresseusement (`by lazy`) ; ici ils sont
/// calculés une fois à la construction — une `struct` n'a pas de mémoïsation
/// sûre à partager entre threads, et recalculer à chaque lecture ferait payer
/// le regroupement à chaque tic de position du lecteur.
nonisolated struct Library: Sendable {

    let isLoading: Bool
    let songs: [Song]
    let errorMessage: String?

    let albums: [Album]
    let artists: [Artist]

    /// Index morceau par identifiant : le lecteur retrouve le morceau courant
    /// en temps constant plutôt qu'en parcourant la liste.
    let songsByID: [String: Song]

    init(isLoading: Bool = true, songs: [Song] = [], errorMessage: String? = nil) {
        self.isLoading = isLoading
        self.songs = songs
        self.errorMessage = errorMessage
        self.albums = songs.toAlbums()
        self.artists = songs.toArtists()
        self.songsByID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Bibliothèque vide alors que le chargement s'est bien terminé.
    var isEmpty: Bool { !isLoading && errorMessage == nil && songs.isEmpty }

    func album(_ albumId: String) -> Album? { albums.first { $0.id == albumId } }

    func artist(_ artistId: String) -> Artist? { artists.first { $0.id == artistId } }

    /// Morceaux d'un album, dans l'ordre de la bibliothèque.
    func songsOfAlbum(_ albumId: String) -> [Song] { songs.filter { $0.albumId == albumId } }

    func songsOfArtist(_ artistId: String) -> [Song] { songs.filter { $0.artistId == artistId } }
}
