import SwiftUI

/// Onglet Albums : grille de pochettes adaptative.
struct AlbumsScreen: View {

    /// Pile détenue par `RootView` — voir le commentaire là-bas.
    @Binding var path: NavigationPath

    @Environment(LibraryStore.self) private var store
    @Environment(\.requestImport) private var requestImport

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]

    var body: some View {
        NavigationStack(path: $path) {
            LibraryStateContainer(
                library: store.library,
                onRetry: { store.retry() },
                onImport: requestImport,
            ) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(store.library.albums) { album in
                            NavigationLink(value: album) {
                                AlbumCell(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Albums")
            .navigationDestination(for: Album.self) { album in
                AlbumDetailScreen(albumId: album.id)
            }
        }
    }
}

private struct AlbumCell: View {

    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: album.artworkURL, cornerRadius: 8)
                .aspectRatio(1, contentMode: .fit)

            Text(album.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(album.displayArtist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
