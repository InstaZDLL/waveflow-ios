import Foundation
import Testing
@testable import WaveFlow

/// Portage de `PlaylistDaoTest` (Android).
///
/// Les cas de ce test-là portent sur une base Room ; ici, ce sont ceux qui
/// survivent au changement de représentation — l'ordre est un tableau, pas une
/// colonne `position`. Les cas de compactage des positions n'ont donc plus
/// d'objet, mais toute la normalisation du réordonnancement, elle, reste :
/// c'est l'écran qui envoie l'ordre, et il peut en omettre.
struct PlaylistTests {

    private let creation = Date(timeIntervalSince1970: 1_000)
    private let modification = Date(timeIntervalSince1970: 2_000)

    // MARK: - Ajout et retrait

    @Test func lAjoutConserveLOrdreEtDateLaModification() {
        var playlist = nouvellePlaylist()
        playlist.add("a", at: modification)
        playlist.add("b", at: modification)
        playlist.add("c", at: modification)

        #expect(playlist.songIds == ["a", "b", "c"])
        #expect(playlist.updatedAt == modification)
    }

    @Test func unMorceauAjouteDeuxFoisNeCreeQuUneEntree() {
        var playlist = nouvellePlaylist(songIds: ["a"])
        playlist.add("a", at: modification)

        #expect(playlist.songIds == ["a"])
    }

    @Test func unAjoutEnDoublonNeModifiePasUpdatedAt() {
        var playlist = nouvellePlaylist(songIds: ["a"])
        playlist.add("a", at: modification)

        #expect(playlist.updatedAt == creation)
    }

    @Test func retirerUnMorceauLeRetireEtDateLaModification() {
        var playlist = nouvellePlaylist(songIds: ["a", "b"])
        playlist.remove("a", at: modification)

        #expect(playlist.songIds == ["b"])
        #expect(playlist.updatedAt == modification)
    }

    @Test func retirerUnMorceauAbsentNeModifiePasUpdatedAt() {
        var playlist = nouvellePlaylist(songIds: ["a"])
        playlist.remove("z", at: modification)

        #expect(playlist.songIds == ["a"])
        #expect(playlist.updatedAt == creation)
    }

    // MARK: - Réordonnancement

    @Test func reorderReecritLOrdreDemande() {
        var playlist = nouvellePlaylist(songIds: ["a", "b", "c"])
        playlist.reorder(to: ["c", "a", "b"], at: modification)

        #expect(playlist.songIds == ["c", "a", "b"])
        #expect(playlist.updatedAt == modification)
    }

    @Test func reorderALOrdreIdentiqueNeTouchePasUpdatedAt() {
        var playlist = nouvellePlaylist(songIds: ["a", "b"])
        playlist.reorder(to: ["a", "b"], at: modification)

        #expect(playlist.updatedAt == creation)
    }

    @Test func reorderSurUnePlaylistVideNeTouchePasUpdatedAt() {
        var playlist = nouvellePlaylist()
        playlist.reorder(to: [], at: modification)

        #expect(playlist.songIds.isEmpty)
        #expect(playlist.updatedAt == creation)
    }

    @Test func reorderIgnoreUnMorceauEtrangerALaPlaylist() {
        var playlist = nouvellePlaylist(songIds: ["a", "b"])
        playlist.reorder(to: ["b", "inconnu", "a"], at: modification)

        #expect(playlist.songIds == ["b", "a"])
    }

    @Test func reorderIgnoreUnIdentifiantDemandeDeuxFois() {
        var playlist = nouvellePlaylist(songIds: ["a", "b"])
        playlist.reorder(to: ["b", "b", "a"], at: modification)

        #expect(playlist.songIds == ["b", "a"])
    }

    /// Le cas qui motive la normalisation : l'écran ne liste que les morceaux
    /// résolus contre la bibliothèque. Un fichier disparu de `Documents` reste
    /// dans la playlist sans figurer dans le glisser-déposer — il doit
    /// survivre au réordonnancement, pas être emporté par lui.
    @Test func reorderOmettantUnMorceauStockeNeLePerdPas() {
        var playlist = nouvellePlaylist(songIds: ["a", "disparu", "b"])
        playlist.reorder(to: ["b", "a"], at: modification)

        #expect(playlist.songIds == ["b", "a", "disparu"])
    }

    @Test func reorderNeGardeQuUneOccurrenceDeChaqueMorceau() {
        var playlist = nouvellePlaylist(songIds: ["a", "b", "c"])
        playlist.reorder(to: ["c", "c", "a", "inconnu", "a"], at: modification)

        #expect(playlist.songIds.sorted() == ["a", "b", "c"])
        #expect(playlist.songIds == ["c", "a", "b"])
    }

    // MARK: - Nom

    @Test func renommerDateLaModification() {
        var playlist = nouvellePlaylist(name: "Été")
        playlist.rename(to: "Hiver", at: modification)

        #expect(playlist.name == "Hiver")
        #expect(playlist.updatedAt == modification)
    }

    @Test func renommerAlIdentiqueNeTouchePasUpdatedAt() {
        var playlist = nouvellePlaylist(name: "Été")
        playlist.rename(to: "Été", at: modification)

        #expect(playlist.updatedAt == creation)
    }

    @Test func unNomBlancEstRefuse() {
        var playlist = nouvellePlaylist(name: "Été")
        playlist.rename(to: "   ", at: modification)

        #expect(playlist.name == "Été")
        #expect(playlist.updatedAt == creation)
    }

    @Test func leNomEstDebarrasseDeSesEspacesDeBordure() {
        var playlist = nouvellePlaylist(name: "Été")
        playlist.rename(to: "  Hiver  ", at: modification)

        #expect(playlist.name == "Hiver")
    }

    // MARK: - Résolution contre la bibliothèque

    @Test func resoutLesMorceauxDansLOrdreDeLaPlaylist() {
        let library = Library(isLoading: false, songs: [song("a"), song("b"), song("c")])
        let playlist = nouvellePlaylist(songIds: ["c", "a"])

        #expect(playlist.songs(in: library).map(\.id) == ["c", "a"])
    }

    /// Un identifiant sans morceau correspondant est sauté à l'affichage, mais
    /// la playlist le garde : le fichier peut être réimporté.
    @Test func ignoreUnMorceauAbsentDeLaBibliothequeSansLOublier() {
        let library = Library(isLoading: false, songs: [song("a")])
        let playlist = nouvellePlaylist(songIds: ["a", "disparu"])

        #expect(playlist.songs(in: library).map(\.id) == ["a"])
        #expect(playlist.songIds == ["a", "disparu"])
    }

    @Test func unePlaylistVideNeResoutAucunMorceau() {
        let library = Library(isLoading: false, songs: [song("a")])

        #expect(nouvellePlaylist().songs(in: library).isEmpty)
    }

    // MARK: - Fixtures

    private func nouvellePlaylist(name: String = "Playlist", songIds: [String] = []) -> Playlist {
        Playlist(name: name, songIds: songIds, createdAt: creation)
    }

    private func song(_ id: String) -> Song {
        Song(
            id: id,
            url: URL(fileURLWithPath: "/tmp/\(id)"),
            title: id,
            artist: "Artiste",
            artistId: "artist:defaut",
            album: "Album",
            albumId: "album:defaut",
            collectionArtist: "Artiste",
            duration: 0,
            artworkURL: nil,
        )
    }
}
