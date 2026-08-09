import AVFoundation
import MediaPlayer
import UIKit

/// Mode de répétition, indépendant des constantes d'`AVFoundation`.
nonisolated enum RepeatMode: Sendable, CaseIterable {

    /// La file se termine après le dernier morceau.
    case off

    /// La file reboucle au début.
    case all

    /// Le morceau courant se répète.
    case one

    /// Off → All → One → Off.
    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// Façade de la lecture audio.
///
/// Android délègue à un `MediaSessionService` Media3, qui apporte la lecture
/// en arrière-plan et les contrôles d'écran verrouillé. iOS n'a pas de service
/// équivalent : c'est le mode d'arrière-plan `audio` qui maintient l'app en vie,
/// et il faut alimenter `MPNowPlayingInfoCenter` et `MPRemoteCommandCenter` à
/// la main — ce que cette classe centralise.
///
/// La file est tenue ici plutôt que confiée à un `AVQueuePlayer` : aléatoire,
/// répétition et « précédent » demandent de contrôler l'ordre de traversée, ce
/// que la file interne d'`AVQueuePlayer` ne permet pas.
@Observable
@MainActor
final class PlaybackController {

    // MARK: - État observable

    private(set) var queue: [Song] = []
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var shuffleEnabled = false
    private(set) var repeatMode: RepeatMode = .off

    var currentSong: Song? {
        guard let index = currentQueueIndex, queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    /// Avancement dans le morceau, entre 0 et 1 (0 si la durée est inconnue).
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    // MARK: - Interne

    private let player = AVPlayer()

    /// Ordre de traversée : des index dans `queue`. En lecture normale c'est
    /// `0..<queue.count`, en aléatoire une permutation.
    private var order: [Int] = []

    /// Position courante *dans `order`*, pas dans `queue`.
    private var orderPosition: Int?

    private var currentQueueIndex: Int? {
        guard let orderPosition, order.indices.contains(orderPosition) else { return nil }
        return order[orderPosition]
    }

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

    /// Un « précédent » en deçà de ce seuil revient au morceau d'avant ;
    /// au-delà, il rembobine le morceau courant. Convention iOS habituelle.
    private let restartThreshold: TimeInterval = 3

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
        guard songs.indices.contains(startIndex) else { return }
        queue = songs
        rebuildOrder(startingAt: startIndex)
        loadCurrent(autoplay: true)
    }

    /// Démarre [song] avec [queue] comme file — la bibliothèque entière depuis
    /// l'onglet Titres, l'album ou l'artiste depuis leur écran.
    func play(_ song: Song, in songs: [Song]) {
        guard let index = songs.firstIndex(where: { $0.id == song.id }) else { return }
        play(songs, startIndex: index)
    }

    /// Démarre [songs] par son premier morceau. Sans effet si la file est vide.
    func playFirst(_ songs: [Song]) {
        guard let first = songs.first else { return }
        play(first, in: songs)
    }

    /// Charge [songs] en activant l'aléatoire et démarre sur un morceau au hasard.
    func playShuffled(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        shuffleEnabled = true
        queue = songs
        rebuildOrder(startingAt: Int.random(in: songs.indices))
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

    func skipNext() { advance(by: 1, userInitiated: true) }

    func skipPrevious() {
        if position > restartThreshold {
            seek(to: 0)
            return
        }
        advance(by: -1, userInitiated: true)
    }

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

    func toggleShuffle() {
        shuffleEnabled.toggle()
        guard let index = currentQueueIndex else { return }
        // Rebâtir autour du morceau courant : basculer l'aléatoire ne doit
        // jamais interrompre ce qui joue.
        rebuildOrder(startingAt: index)
    }

    func cycleRepeatMode() { repeatMode = repeatMode.next }

    // MARK: - File d'attente

    private func rebuildOrder(startingAt queueIndex: Int) {
        if shuffleEnabled {
            var rest = Array(queue.indices)
            rest.remove(at: queueIndex)
            order = [queueIndex] + rest.shuffled()
            orderPosition = 0
        } else {
            order = Array(queue.indices)
            orderPosition = queueIndex
        }
    }

    /// Avance de [step] dans l'ordre de traversée.
    ///
    /// - Parameter userInitiated: un appui sur « suivant » ignore le mode
    ///   « répéter le morceau » — sinon le bouton ne ferait rien. La fin
    ///   naturelle d'un morceau, elle, le respecte.
    private func advance(by step: Int, userInitiated: Bool) {
        guard let orderPosition, !order.isEmpty else { return }

        if repeatMode == .one && !userInitiated {
            seek(to: 0)
            player.play()
            return
        }

        let target = orderPosition + step
        switch target {
        case order.indices:
            self.orderPosition = target
            loadCurrent(autoplay: true)

        case _ where repeatMode == .all:
            self.orderPosition = target < 0 ? order.count - 1 : 0
            loadCurrent(autoplay: true)

        case _ where target < 0:
            // Avant le premier morceau sans répétition : on rembobine.
            seek(to: 0)

        default:
            // Fin de file sans répétition : on s'arrête sur le dernier morceau.
            player.pause()
            seek(to: 0)
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
            MainActor.assumeIsolated { self?.advance(by: 1, userInitiated: false) }
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
