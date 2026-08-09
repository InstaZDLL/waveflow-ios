import SwiftUI

/// Détail d'un artiste : en-tête et tous ses morceaux.
struct ArtistDetailScreen: View {

    let artistId: String

    @Environment(LibraryStore.self) private var store
    @Environment(PlaybackController.self) private var player

    private var artist: Artist? { store.library.artist(artistId) }
    private var songs: [Song] { store.library.songsOfArtist(artistId) }

    var body: some View {
        Group {
            if let artist {
                List {
                    Section {
                        ForEach(songs) { song in
                            Button {
                                player.play(song, in: songs)
                            } label: {
                                SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        DetailHeader(
                            artworkURL: artist.artworkURL,
                            title: artist.name,
                            subtitle: "\(albumCountLabel(artist.albumCount)) · \(trackCountLabel(artist.trackCount))",
                            songs: songs,
                        )
                        .textCase(nil)
                    }
                }
                .listStyle(.plain)
            } else {
                ContentUnavailableView("Artiste introuvable", systemImage: "person.slash")
            }
        }
        .navigationTitle(artist?.name ?? "Artiste")
        .navigationBarTitleDisplayMode(.inline)
    }
}
