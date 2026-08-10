import SwiftUI

/// Onglet Artistes : liste, une ligne par artiste.
struct ArtistsScreen: View {

    /// Pile détenue par `RootView` — voir le commentaire là-bas.
    @Binding var path: NavigationPath

    @Environment(LibraryStore.self) private var store
    @Environment(\.requestImport) private var requestImport

    var body: some View {
        NavigationStack(path: $path) {
            LibraryStateContainer(
                library: store.library,
                onRetry: { store.retry() },
                onImport: requestImport,
            ) {
                List(store.library.artists) { artist in
                    NavigationLink(value: artist) {
                        MediaRow(
                            artworkURL: artist.artworkURL,
                            title: artist.name,
                            subtitle: "\(albumCountLabel(artist.albumCount)) · \(trackCountLabel(artist.trackCount))",
                            artworkCornerRadius: 24,
                        )
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Artistes")
            .navigationDestination(for: Artist.self) { artist in
                ArtistDetailScreen(artistId: artist.id)
            }
        }
    }
}
