import SwiftUI

/// Détail d'un album : en-tête et pistes.
///
/// L'écran ne reçoit que l'identifiant et relit la bibliothèque, comme les
/// routes paramétrées d'Android : si un scan retire un fichier pendant qu'on
/// est dessus, l'affichage suit au lieu de montrer un instantané périmé.
struct AlbumDetailScreen: View {

    let albumId: String

    @Environment(LibraryStore.self) private var store
    @Environment(PlaybackController.self) private var player

    /// Morceau dont la feuille « ajouter à une playlist » est ouverte.
    @State private var songToAdd: Song?

    private var album: Album? { store.library.album(albumId) }
    private var songs: [Song] { store.library.songsOfAlbum(albumId) }

    var body: some View {
        Group {
            if let album {
                List {
                    Section {
                        ForEach(songs) { song in
                            Button {
                                player.play(song, in: songs)
                            } label: {
                                SongRow(
                                    song: song,
                                    isCurrent: player.currentSong?.id == song.id,
                                    showArtwork: false,
                                )
                            }
                            .buttonStyle(.plain)
                            .addToPlaylistMenu(for: song, selection: $songToAdd)
                        }
                    } header: {
                        DetailHeader(
                            artworkURL: album.artworkURL,
                            title: album.title,
                            subtitle: "\(album.displayArtist) · \(trackCountLabel(album.trackCount)) · \(formatTotalDuration(album.duration))",
                            songs: songs,
                        )
                        .textCase(nil)
                    }
                }
                .listStyle(.plain)
            } else {
                ContentUnavailableView("Album introuvable", systemImage: "square.stack.slash")
            }
        }
        .navigationTitle(album?.title ?? "Album")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $songToAdd) { AddToPlaylistSheet(song: $0) }
    }
}
