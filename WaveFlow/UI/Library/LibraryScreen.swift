import SwiftUI

/// Onglet Titres : toute la bibliothèque, à plat.
///
/// La file de lecture démarrée depuis cet écran est la bibliothèque entière —
/// même contrat que sur Android.
struct LibraryScreen: View {

    @Environment(LibraryStore.self) private var store
    @Environment(PlaybackController.self) private var player
    @Environment(\.requestImport) private var requestImport

    /// Morceau dont la feuille « ajouter à une playlist » est ouverte.
    @State private var songToAdd: Song?

    var body: some View {
        NavigationStack {
            LibraryStateContainer(
                library: store.library,
                onRetry: { store.retry() },
                onImport: requestImport,
            ) {
                List(store.library.songs) { song in
                    Button {
                        player.play(song, in: store.library.songs)
                    } label: {
                        SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(.horizontal, 16)
                    .addToPlaylistMenu(for: song, selection: $songToAdd)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Titres")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Importer", systemImage: "plus", action: requestImport)
                }
                if !store.library.songs.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Aléatoire", systemImage: "shuffle") {
                            player.playShuffled(store.library.songs)
                        }
                    }
                }
            }
        }
        .sheet(item: $songToAdd) { AddToPlaylistSheet(song: $0) }
    }
}
