import SwiftUI

/// Ligne de morceau, partagée par la bibliothèque et les écrans de détail.
///
/// Le morceau en cours est signalé par la couleur d'accent et un indicateur à
/// droite, à la place de la durée.
struct SongRow: View {

    let song: Song
    let isCurrent: Bool

    /// Masquable sur un écran d'album, où répéter la même pochette à chaque
    /// ligne n'apporte rien.
    var showArtwork = true

    var body: some View {
        HStack(spacing: 12) {
            if showArtwork {
                ArtworkView(url: song.artworkURL)
                    .frame(width: 48, height: 48)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .foregroundStyle(isCurrent ? Color.waveEmerald : .primary)
                    .lineLimit(1)
                Text(song.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isCurrent {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(Color.waveEmerald)
                    .accessibilityLabel("Morceau en cours")
            } else if song.duration > 0 {
                Text(formatDuration(song.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(.rect)
    }
}
