import SwiftUI

/// Barre de lecture compacte, logée dans l'accessoire bas du `TabView`.
///
/// Android pose sa propre carte au-dessus de la barre de navigation ; iOS 26
/// offre l'emplacement natif (`tabViewBottomAccessory`), celui qu'occupe le
/// mini-lecteur de Musique — il se fond dans la barre d'onglets et suit ses
/// animations.
///
/// Un tap n'importe où ouvre le lecteur plein écran ; seules lecture/pause et
/// piste suivante restent accessibles directement.
struct MiniPlayer: View {

    @Environment(PlaybackController.self) private var player

    let onExpand: () -> Void

    var body: some View {
        if let song = player.currentSong {
            HStack(spacing: 12) {
                ArtworkView(url: song.artworkURL, cornerRadius: 4)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(song.title)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                    Text(song.displayArtist)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Lecture")

                Button {
                    player.skipNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Morceau suivant")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .contentShape(.rect)
            .onTapGesture(perform: onExpand)
        }
    }
}
