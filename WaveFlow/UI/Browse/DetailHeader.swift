import SwiftUI

/// En-tête commun aux écrans d'album, d'artiste (et de playlist à venir) :
/// pochette, intitulés, et les deux actions qui démarrent la lecture.
struct DetailHeader: View {

    let artworkURL: URL?
    let title: String
    let subtitle: String
    let songs: [Song]

    @Environment(PlaybackController.self) private var player

    var body: some View {
        VStack(spacing: 12) {
            ArtworkView(url: artworkURL, cornerRadius: 12)
                .frame(width: 180, height: 180)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)

            VStack(spacing: 4) {
                Text(title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    player.playFirst(songs)
                } label: {
                    Label("Lecture", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    player.playShuffled(songs)
                } label: {
                    Label("Aléatoire", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.waveEmerald)
            .disabled(songs.isEmpty)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}
