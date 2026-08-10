import AVFoundation
import MediaPlayer
import UIKit

/// Façade de la lecture audio.
///
/// Android délègue à un `MediaSessionService` Media3, qui apporte la lecture
/// en arrière-plan et les contrôles d'écran verrouillé. iOS n'a pas de service
/// équivalent : c'est le mode d'arrière-plan `audio` qui maintient l'app en vie,
/// et il faut alimenter `MPNowPlayingInfoCenter` et `MPRemoteCommandCenter` à
/// la main — ce que cette classe centralise.
///
/// L'ordre de traversée n'est pas confié à un `AVQueuePlayer`, qui ne l'expose
/// pas : il vit dans [PlaybackQueue], du domaine pur, et cette classe se limite
/// à exécuter les intentions qu'elle rend.
@Observable
@MainActor
final class PlaybackController {

    // MARK: - État observable

    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    /// Toute la décision de file — ordre, aléatoire, répétition — est déléguée
    /// ici. Les propriétés ci-dessous ne font que la relayer aux vues, qui
    /// n'ont pas à connaître ce type.
    private var playbackQueue = PlaybackQueue()

    var queue: [Song] { playbackQueue.songs }
    var shuffleEnabled: Bool { playbackQueue.shuffleEnabled }
    var repeatMode: RepeatMode { playbackQueue.repeatMode }
    var currentSong: Song? { playbackQueue.current }

    /// Avancement dans le morceau, entre 0 et 1 (0 si la durée est inconnue).
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    // MARK: - Interne

    private let player = AVPlayer()

    // Plomberie, pas de l'état d'affichage : `@ObservationIgnored` leur évite
    // d'invalider les vues, et les laisse stockées — `@Observable` transforme
    // sinon toute propriété mutable en propriété calculée, à laquelle
    // `nonisolated` ne peut pas s'appliquer.
    //
    // `nonisolated(unsafe)` parce que `deinit` n'est pas isolé au main actor et
    // doit pouvoir les défaire. Elles ne sont touchées qu'à la construction et
    // à la destruction, donc jamais en concurrence.
    @ObservationIgnored private nonisolated(unsafe) var timeObserver: Any?
    @ObservationIgnored private nonisolated(unsafe) var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private nonisolated(unsafe) var endObserver: NSObjectProtocol?

    init() {
        configureAudioSession()
        observePlayer()
        configureRemoteCommands()
    }

    deinit {
        // `deinit` n'est pas isolé : on ne touche qu'à des objets qui tolèrent
        // d'être défaits depuis n'importe quel thread.
        statusObservation?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    // MARK: - Commandes

    /// Charge [songs] comme file d'attente et démarre à [startIndex].
    func play(_ songs: [Song], startIndex: Int) {
        guard playbackQueue.load(songs, startingAt: startIndex) else { return }
        loadCurrent(autoplay: true)
    }

    /// Démarre [song] avec [songs] comme file — la bibliothèque entière depuis
    /// l'onglet Titres, l'album ou l'artiste depuis leur écran.
    func play(_ song: Song, in songs: [Song]) {
        guard playbackQueue.load(songs, startingAt: song) else { return }
        loadCurrent(autoplay: true)
    }

    /// Démarre [songs] par son premier morceau. Sans effet si la file est vide.
    func playFirst(_ songs: [Song]) {
        play(songs, startIndex: 0)
    }

    /// Charge [songs] en activant l'aléatoire et démarre sur un morceau au hasard.
    ///
    /// Le tirage est fait ici : la file reste déterministe, donc testable, et
    /// le hasard ne vit qu'au bord.
    func playShuffled(_ songs: [Song]) {
        guard !songs.isEmpty,
              playbackQueue.loadShuffled(songs, startingAt: Int.random(in: songs.indices))
        else { return }

        loadCurrent(autoplay: true)
    }

    func togglePlayPause() {
        guard currentSong != nil else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            activateSession()
            player.play()
        }
        updateNowPlayingPlaybackState()
    }

    func skipNext() { apply(playbackQueue.next(userInitiated: true)) }

    func skipPrevious() { apply(playbackQueue.previous(elapsed: position)) }

    func seek(to seconds: TimeInterval) {
        let clamped = duration > 0 ? min(max(seconds, 0), duration) : max(seconds, 0)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600)) { [weak self] _ in
            MainActor.assumeIsolated { self?.didSeek(to: clamped) }
        }
    }

    private func didSeek(to seconds: TimeInterval) {
        position = seconds
        updateNowPlayingPlaybackState()
    }

    func toggleShuffle() { playbackQueue.toggleShuffle() }

    func cycleRepeatMode() { playbackQueue.cycleRepeatMode() }

    // MARK: - File d'attente

    /// Exécute l'intention rendue par la file.
    ///
    /// C'est le seul endroit qui traduit une décision de file en commandes
    /// `AVPlayer` — la file, elle, ne connaît pas le lecteur.
    private func apply(_ step: PlaybackStep?) {
        switch step {
        case .play:
            loadCurrent(autoplay: true)

        case .restart:
            seek(to: 0)
            player.play()

        case .rewind:
            seek(to: 0)

        case .stop:
            player.pause()
            seek(to: 0)

        case nil:
            break
        }
    }

    private func loadCurrent(autoplay: Bool) {
        guard let song = currentSong else { return }

        player.replaceCurrentItem(with: AVPlayerItem(url: song.url))
        position = 0
        duration = song.duration

        if autoplay {
            activateSession()
            player.play()
        }
        updateNowPlayingInfo(for: song)
    }

    // MARK: - Session audio et observation

    private func configureAudioSession() {
        // `.playback` : le son continue quand l'écran se verrouille et ignore
        // l'interrupteur silencieux — c'est ce qu'on attend d'un lecteur.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main,
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(at: time) }
        }

        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            Task { @MainActor [weak self] in
                self?.isPlaying = playing
                self?.updateNowPlayingPlaybackState()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            // Fin naturelle du morceau : `userInitiated: false` laisse le mode
            // « répéter le morceau » s'appliquer, contrairement au bouton.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.apply(self.playbackQueue.next(userInitiated: false))
            }
        }
    }

    private func tick(at time: CMTime) {
        position = time.seconds.isFinite ? time.seconds : 0

        // La durée du tag peut manquer ou mentir : dès que l'item connaît la
        // sienne, elle fait foi.
        if let itemDuration = player.currentItem?.duration.seconds,
           itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }
    }

    // MARK: - Écran verrouillé et centre de contrôle

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.remote { $0.resume() } ?? .commandFailed }
        }

        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.remote { $0.player.pause() } ?? .commandFailed }
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.remote { $0.togglePlayPause() } ?? .commandFailed }
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.remote { $0.skipNext() } ?? .commandFailed }
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.remote { $0.skipPrevious() } ?? .commandFailed }
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }
                return self.remote { $0.seek(to: event.positionTime) }
            }
        }
    }

    /// Exécute une commande venue de l'écran verrouillé, sauf si la file est
    /// vide — auquel cas iOS doit savoir qu'il n'y a rien à commander.
    private func remote(_ action: (PlaybackController) -> Void) -> MPRemoteCommandHandlerStatus {
        guard currentSong != nil else { return .noSuchContent }
        action(self)
        return .success
    }

    /// Reprise depuis un contrôle distant : la session peut avoir été
    /// désactivée par une interruption (appel, autre app).
    private func resume() {
        activateSession()
        player.play()
    }

    private func updateNowPlayingInfo(for song: Song) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.displayArtist,
            MPMediaItemPropertyAlbumTitle: song.displayAlbum,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: player.rate,
        ]

        if let artworkURL = song.artworkURL,
           let data = try? Data(contentsOf: artworkURL),
           let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Met à jour la position et le taux sans reconstruire la pochette — c'est
    /// appelé à chaque lecture/pause et à chaque déplacement du curseur.
    private func updateNowPlayingPlaybackState() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
        info[MPMediaItemPropertyPlaybackDuration] = duration
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
