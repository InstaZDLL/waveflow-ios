import SwiftUI

/// Lecteur plein écran.
///
/// Le fond reprend la couleur dominante de la pochette (voir [ArtworkAccent]),
/// fondue vers le noir : c'est ce qui donne l'impression que l'écran « habite »
/// l'album en cours.
struct NowPlayingScreen: View {

    @Environment(PlaybackController.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var accent = ArtworkAccent.fallback

    /// Position en cours de glissement. Tant que le doigt est posé, le curseur
    /// suit la main et non le lecteur — sinon il sauterait en arrière à chaque
    /// tic de position.
    @State private var scrubbing: TimeInterval?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [accent, accent.mix(with: .black, by: 0.65), .black],
                startPoint: .top,
                endPoint: .bottom,
            )
            .ignoresSafeArea()

            if let song = player.currentSong {
                content(for: song)
            } else {
                ContentUnavailableView("Rien en lecture", systemImage: "music.note")
                    .foregroundStyle(.white)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: player.currentSong?.artworkURL) {
            accent = await ArtworkAccent.color(for: player.currentSong?.artworkURL)
        }
    }

    private func content(for song: Song) -> some View {
        VStack(spacing: 0) {
            header(for: song)

            Spacer(minLength: 16)

            ArtworkView(url: song.artworkURL, cornerRadius: 16)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                .padding(.horizontal, 24)

            Spacer(minLength: 16)

            title(for: song)
            seekBar
            controls

            Spacer().frame(height: 24)
        }
        .foregroundStyle(.white)
    }

    private func header(for song: Song) -> some View {
        ZStack {
            VStack(spacing: 2) {
                Text("EN LECTURE")
                    .font(.caption2)
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.6))
                Text(song.album ?? "Bibliothèque locale")
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
            }

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Réduire le lecteur")
                Spacer()
            }
        }
        .padding(.horizontal, 12)
    }

    private func title(for song: Song) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.title)
                .font(.title2.bold())
                .lineLimit(2)
            Text(song.displayArtist)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private var seekBar: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { scrubbing ?? player.position },
                    set: { scrubbing = $0 },
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    guard !editing, let target = scrubbing else { return }
                    player.seek(to: target)
                    scrubbing = nil
                },
            )
            .tint(.white)

            HStack {
                Text(formatDuration(scrubbing ?? player.position))
                Spacer()
                Text(formatDuration(player.duration))
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var controls: some View {
        HStack {
            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(player.shuffleEnabled ? Color.waveEmerald : .white.opacity(0.6))
            }
            .accessibilityLabel("Lecture aléatoire")

            Spacer()

            Button { player.skipPrevious() } label: {
                Image(systemName: "backward.fill").font(.title)
            }
            .accessibilityLabel("Morceau précédent")

            Spacer()

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Lecture")

            Spacer()

            Button { player.skipNext() } label: {
                Image(systemName: "forward.fill").font(.title)
            }
            .accessibilityLabel("Morceau suivant")

            Spacer()

            Button { player.cycleRepeatMode() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(player.repeatMode == .off ? .white.opacity(0.6) : Color.waveEmerald)
            }
            .accessibilityLabel("Mode de répétition")
        }
        .font(.title3)
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.horizontal, 32)
        .padding(.top, 12)
    }
}
