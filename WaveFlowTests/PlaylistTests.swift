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

    @Test func addKeepsInsertionOrderAndStampsUpdate() {
        var playlist = makePlaylist()
        playlist.add("a", at: modification)
        playlist.add("b", at: modification)
        playlist.add("c", at: modification)

        #expect(playlist.songIds == ["a", "b", "c"])
        #expect(playlist.updatedAt == modification)
    }

    @Test func addingTheSameSongTwiceCreatesOneEntry() {
        var playlist = makePlaylist(songIds: ["a"])
        playlist.add("a", at: modification)

        #expect(playlist.songIds == ["a"])
    }

    @Test func duplicateAddLeavesUpdatedAtUntouched() {
        var playlist = makePlaylist(songIds: ["a"])
        playlist.add("a", at: modification)

        #expect(playlist.updatedAt == creation)
    }

    @Test func removeDropsTheSongAndStampsUpdate() {
        var playlist = makePlaylist(songIds: ["a", "b"])
        playlist.remove("a", at: modification)

        #expect(playlist.songIds == ["b"])
        #expect(playlist.updatedAt == modification)
    }

    @Test func removingAnAbsentSongLeavesUpdatedAtUntouched() {
        var playlist = makePlaylist(songIds: ["a"])
        playlist.remove("z", at: modification)

        #expect(playlist.songIds == ["a"])
        #expect(playlist.updatedAt == creation)
    }

    // MARK: - Réordonnancement

    @Test func reorderAppliesTheRequestedOrder() {
        var playlist = makePlaylist(songIds: ["a", "b", "c"])
        playlist.reorder(to: ["c", "a", "b"], at: modification)

        #expect(playlist.songIds == ["c", "a", "b"])
        #expect(playlist.updatedAt == modification)
    }

    @Test func reorderToTheSameOrderLeavesUpdatedAtUntouched() {
        var playlist = makePlaylist(songIds: ["a", "b"])
        playlist.reorder(to: ["a", "b"], at: modification)

        #expect(playlist.updatedAt == creation)
    }

    @Test func reorderOnAnEmptyPlaylistLeavesUpdatedAtUntouched() {
        var playlist = makePlaylist()
        playlist.reorder(to: [], at: modification)

        #expect(playlist.songIds.isEmpty)
        #expect(playlist.updatedAt == creation)
    }

    @Test func reorderIgnoresSongsForeignToThePlaylist() {
        var playlist = makePlaylist(songIds: ["a", "b"])
        playlist.reorder(to: ["b", "inconnu", "a"], at: modification)

        #expect(playlist.songIds == ["b", "a"])
    }

    @Test func reorderIgnoresARepeatedIdentifier() {
        var playlist = makePlaylist(songIds: ["a", "b"])
        playlist.reorder(to: ["b", "b", "a"], at: modification)

        #expect(playlist.songIds == ["b", "a"])
    }

    /// Le cas qui motive la normalisation : l'écran ne liste que les morceaux
    /// résolus contre la bibliothèque. Un fichier disparu de `Documents` reste
    /// dans la playlist sans figurer dans le glisser-déposer — il doit
    /// survivre au réordonnancement, pas être emporté par lui.
    @Test func reorderKeepsStoredSongsTheCallerOmitted() {
        var playlist = makePlaylist(songIds: ["a", "disparu", "b"])
        playlist.reorder(to: ["b", "a"], at: modification)

        #expect(playlist.songIds == ["b", "a", "disparu"])
    }

    @Test func reorderKeepsOneOccurrenceOfEachSong() {
        var playlist = makePlaylist(songIds: ["a", "b", "c"])
        playlist.reorder(to: ["c", "c", "a", "inconnu", "a"], at: modification)

        #expect(playlist.songIds.sorted() == ["a", "b", "c"])
        #expect(playlist.songIds == ["c", "a", "b"])
    }

    // MARK: - Nom

    @Test func renameStampsUpdate() {
        var playlist = makePlaylist(name: "Été")
        playlist.rename(to: "Hiver", at: modification)

        #expect(playlist.name == "Hiver")
        #expect(playlist.updatedAt == modification)
    }

    @Test func renamingToTheSameNameLeavesUpdatedAtUntouched() {
        var playlist = makePlaylist(name: "Été")
        playlist.rename(to: "Été", at: modification)

        #expect(playlist.updatedAt == creation)
    }

    @Test func aBlankNameIsRejected() {
        var playlist = makePlaylist(name: "Été")
        playlist.rename(to: "   ", at: modification)

        #expect(playlist.name == "Été")
        #expect(playlist.updatedAt == creation)
    }

    @Test func theNameIsTrimmed() {
        var playlist = makePlaylist(name: "Été")
        playlist.rename(to: "  Hiver  ", at: modification)

        #expect(playlist.name == "Hiver")
    }

    // MARK: - Résolution contre la bibliothèque

    @Test func resolvesSongsInPlaylistOrder() {
        let library = Library(isLoading: false, songs: [song("a"), song("b"), song("c")])
        let playlist = makePlaylist(songIds: ["c", "a"])

        #expect(playlist.songs(in: library).map(\.id) == ["c", "a"])
    }

    /// Un identifiant sans morceau correspondant est sauté à l'affichage, mais
    /// la playlist le garde : le fichier peut être réimporté.
    @Test func skipsASongMissingFromTheLibraryWithoutForgettingIt() {
        let library = Library(isLoading: false, songs: [song("a")])
        let playlist = makePlaylist(songIds: ["a", "disparu"])

        #expect(playlist.songs(in: library).map(\.id) == ["a"])
        #expect(playlist.songIds == ["a", "disparu"])
    }

    @Test func anEmptyPlaylistResolvesToNoSongs() {
        let library = Library(isLoading: false, songs: [song("a")])

        #expect(makePlaylist().songs(in: library).isEmpty)
    }

    // MARK: - Fixtures

    private func makePlaylist(name: String = "Playlist", songIds: [String] = []) -> Playlist {
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
