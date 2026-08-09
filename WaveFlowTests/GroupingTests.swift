import Foundation
import Testing
@testable import WaveFlow

/// Portage de `GroupingTest` (Android).
///
/// Les identifiants de regroupement sont posés à la main plutôt que dérivés :
/// ce qui est testé ici, c'est le regroupement lui-même, pas la lecture des
/// tags — celle-ci vit dans `LibraryScanner`, qui exige AVFoundation.
struct GroupingTests {

    // MARK: - Albums

    @Test func regroupeLesMorceauxParAlbum() {
        let songs = [
            song(id: "1", title: "A", albumId: "album:ep", album: "EP"),
            song(id: "2", title: "B", albumId: "album:ep", album: "EP"),
            song(id: "3", title: "C", albumId: "album:autre", album: "Autre"),
        ]

        let albums = songs.toAlbums()

        #expect(albums.count == 2)
        #expect(albums.map(\.id).sorted() == ["album:autre", "album:ep"])
        #expect(albums.first { $0.id == "album:ep" }?.trackCount == 2)
    }

    /// Le cas qui motive tout `collectionArtist` : un EP dont une piste est
    /// créditée à plusieurs artistes reste **un** album, et la carte affiche
    /// l'artiste du regroupement, pas le crédit complet de la première piste
    /// rencontrée.
    @Test func afficheLArtisteDuRegroupementPasLeCreditComplet() {
        let songs = [
            song(
                id: "1",
                title: "NO PROBLEM",
                albumId: "album:na",
                album: "NA",
                artist: "NAYEON, Felix of Stray Kids",
                collectionArtist: "NAYEON",
            ),
            song(
                id: "2",
                title: "ABCD",
                albumId: "album:na",
                album: "NA",
                artist: "NAYEON",
                collectionArtist: "NAYEON",
            ),
        ]

        let albums = songs.toAlbums()

        #expect(albums.count == 1)
        #expect(albums[0].artist == "NAYEON")
    }

    @Test func cumuleLesDureesDeLAlbum() {
        let songs = [
            song(id: "1", title: "A", albumId: "album:x", duration: 180),
            song(id: "2", title: "B", albumId: "album:x", duration: 240.5),
        ]

        #expect(songs.toAlbums()[0].duration == 420.5)
    }

    /// Beaucoup de fichiers n'embarquent pas de pochette : l'album prend la
    /// première disponible parmi ses morceaux plutôt que celle de la première
    /// piste, qui peut être nulle.
    @Test func retientLaPremierePochetteDisponible() {
        let artwork = URL(fileURLWithPath: "/tmp/cover.artwork")
        let songs = [
            song(id: "1", title: "A", albumId: "album:x", artworkURL: nil),
            song(id: "2", title: "B", albumId: "album:x", artworkURL: artwork),
        ]

        #expect(songs.toAlbums()[0].artworkURL == artwork)
    }

    @Test func trieLesAlbumsSansTenirCompteDeLaCasse() {
        let songs = [
            song(id: "1", title: "A", albumId: "album:zebra", album: "zebra"),
            song(id: "2", title: "B", albumId: "album:alpha", album: "Alpha"),
            song(id: "3", title: "C", albumId: "album:beta", album: "beta"),
        ]

        #expect(songs.toAlbums().map(\.title) == ["Alpha", "beta", "zebra"])
    }

    @Test func retombeSurAlbumInconnuSansTag() {
        let albums = [song(id: "1", title: "A", albumId: "album:", album: nil)].toAlbums()

        #expect(albums[0].title == "Album inconnu")
    }

    // MARK: - Artistes

    /// `albumCount` compte les albums *distincts*, pas les morceaux : un
    /// artiste avec deux albums de trois titres affiche « 2 albums ».
    @Test func compteLesAlbumsDistinctsDUnArtiste() {
        let songs = [
            song(id: "1", title: "A", albumId: "album:un", artistId: "artist:x", collectionArtist: "X"),
            song(id: "2", title: "B", albumId: "album:un", artistId: "artist:x", collectionArtist: "X"),
            song(id: "3", title: "C", albumId: "album:deux", artistId: "artist:x", collectionArtist: "X"),
        ]

        let artists = songs.toArtists()

        #expect(artists.count == 1)
        #expect(artists[0].albumCount == 2)
        #expect(artists[0].trackCount == 3)
    }

    @Test func trieLesArtistesSansTenirCompteDeLaCasse() {
        let songs = [
            song(id: "1", title: "A", artistId: "artist:zaz", collectionArtist: "zaz"),
            song(id: "2", title: "B", artistId: "artist:abba", collectionArtist: "ABBA"),
        ]

        #expect(songs.toArtists().map(\.name) == ["ABBA", "zaz"])
    }

    @Test func retombeSurArtisteInconnuSansTag() {
        let artists = [song(id: "1", title: "A", artistId: "artist:", collectionArtist: nil)].toArtists()

        #expect(artists[0].name == "Artiste inconnu")
    }

    // MARK: - Bibliothèque

    @Test func bibliothequeVideNeProduitAucunRegroupement() {
        let library = Library(isLoading: false, songs: [])

        #expect(library.albums.isEmpty)
        #expect(library.artists.isEmpty)
        #expect(library.isEmpty)
    }

    /// `isEmpty` ne veut pas dire « aucun morceau » mais « chargement terminé,
    /// sans erreur, et rien trouvé » — c'est ce qui distingue l'écran d'accueil
    /// vide de l'écran de chargement.
    @Test func nEstPasVidePendantLeChargementNiEnErreur() {
        #expect(!Library(isLoading: true, songs: []).isEmpty)
        #expect(!Library(isLoading: false, songs: [], errorMessage: "boum").isEmpty)
    }

    @Test func indexeLesMorceauxParIdentifiant() {
        let songs = [
            song(id: "a/1.mp3", title: "A"),
            song(id: "b/2.mp3", title: "B"),
        ]
        let library = Library(isLoading: false, songs: songs)

        #expect(library.songsByID["a/1.mp3"]?.title == "A")
        #expect(library.songsByID["inconnu"] == nil)
    }

    @Test func filtreLesMorceauxDUnAlbumEtDUnArtiste() {
        let songs = [
            song(id: "1", title: "A", albumId: "album:un", artistId: "artist:x"),
            song(id: "2", title: "B", albumId: "album:deux", artistId: "artist:x"),
            song(id: "3", title: "C", albumId: "album:deux", artistId: "artist:y"),
        ]
        let library = Library(isLoading: false, songs: songs)

        #expect(library.songsOfAlbum("album:deux").map(\.id) == ["2", "3"])
        #expect(library.songsOfArtist("artist:x").map(\.id) == ["1", "2"])
        #expect(library.songsOfAlbum("album:absent").isEmpty)
    }

    // MARK: - Fixture

    private func song(
        id: String,
        title: String,
        albumId: String = "album:defaut",
        album: String? = "Album",
        artistId: String = "artist:defaut",
        artist: String? = "Artiste",
        collectionArtist: String? = "Artiste",
        duration: TimeInterval = 0,
        artworkURL: URL? = nil,
    ) -> Song {
        Song(
            id: id,
            url: URL(fileURLWithPath: "/tmp/\(id)"),
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
}
