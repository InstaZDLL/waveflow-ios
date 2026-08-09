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
                        HStack(spacing: 12) {
                            ArtworkView(url: artist.artworkURL, cornerRadius: 24)
                                .frame(width: 48, height: 48)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(artist.name)
                                    .font(.body)
                                    .lineLimit(1)
                                Text("\(albumCountLabel(artist.albumCount)) · \(trackCountLabel(artist.trackCount))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
