import Foundation

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

/// Ce que le lecteur doit faire après un déplacement dans la file.
///
/// La file décide *quoi* jouer, jamais *comment* : elle ne connaît pas
/// `AVPlayer`. Elle rend donc une intention, que `PlaybackController`
/// traduit en commandes.
nonisolated enum PlaybackStep: Sendable, Equatable {

    /// Charger le morceau devenu courant et le jouer.
    case play

    /// Reprendre le morceau courant depuis le début, en lecture — la
    /// répétition d'un seul morceau.
    case restart

    /// Revenir au début du morceau sans toucher à l'état de lecture : un
    /// « précédent » avant le premier morceau rembobine plutôt que de sortir
    /// de la file.
    case rewind

    /// Fin de file sans répétition : s'arrêter, revenu au début du dernier
    /// morceau.
    case stop
}

/// La file de lecture et son ordre de traversée.
///
/// Extraite de `PlaybackController` pour être testable : c'est de
/// l'arithmétique d'index, sans rien d'`AVFoundation`, et c'est la pièce la
/// plus piégeuse du lecteur — l'aléatoire, les trois modes de répétition et le
/// double sens du bouton « précédent » s'y croisent. Elle vit dans `Model/`
/// pour cette raison, alors que le reste de la lecture est dans `Playback/`.
///
/// Elle ne joue rien et n'observe rien : chaque déplacement rend un
/// [PlaybackStep] que le contrôleur exécute.
///
/// - Note: la file est tenue à la main plutôt que confiée à un
///   `AVQueuePlayer`, qui n'expose pas l'ordre de traversée dont l'aléatoire,
///   la répétition et le « précédent » ont besoin.
nonisolated struct PlaybackQueue: Sendable {

    /// Morceaux de la file, dans l'ordre où ils ont été chargés.
    private(set) var songs: [Song] = []

    private(set) var shuffleEnabled = false

    var repeatMode: RepeatMode = .off

    /// Ordre de traversée : des index dans [songs]. En lecture normale c'est
    /// `0..<songs.count`, en aléatoire une permutation.
    private var order: [Int] = []

    /// Position courante *dans [order]*, pas dans [songs].
    private var cursor: Int?

    /// Un « précédent » en deçà de ce seuil revient au morceau d'avant ;
    /// au-delà, il rembobine le morceau courant. Convention iOS habituelle.
    static let restartThreshold: TimeInterval = 3

    // MARK: - Lecture de l'état

    /// Index du morceau courant dans [songs].
    var currentIndex: Int? {
        guard let cursor, order.indices.contains(cursor) else { return nil }
        return order[cursor]
    }

    var current: Song? {
        guard let index = currentIndex, songs.indices.contains(index) else { return nil }
        return songs[index]
    }

    var isEmpty: Bool { songs.isEmpty }

    // MARK: - Chargement

    /// Charge `songs` et se place sur `index`.
    ///
    /// - Returns: `false` si l'index ne désigne aucun morceau — la file est
    ///   alors laissée intacte, plutôt que vidée.
    @discardableResult
    mutating func load(_ songs: [Song], startingAt index: Int) -> Bool {
        guard songs.indices.contains(index) else { return false }

        self.songs = songs
        rebuildOrder(startingAt: index)
        return true
    }

    /// Charge `songs` et se place sur `song`, cherché par identifiant.
    @discardableResult
    mutating func load(_ songs: [Song], startingAt song: Song) -> Bool {
        guard let index = songs.firstIndex(where: { $0.id == song.id }) else { return false }
        return load(songs, startingAt: index)
    }

    /// Charge `songs` en aléatoire, à partir de `index`.
    ///
    /// L'index de départ est fourni par l'appelant plutôt que tiré ici : le
    /// hasard reste au bord, et la file demeure prévisible sous test.
    @discardableResult
    mutating func loadShuffled(_ songs: [Song], startingAt index: Int) -> Bool {
        guard songs.indices.contains(index) else { return false }

        shuffleEnabled = true
        self.songs = songs
        rebuildOrder(startingAt: index)
        return true
    }

    // MARK: - Modes

    mutating func toggleShuffle() {
        shuffleEnabled.toggle()

        // Rebâtir autour du morceau courant : basculer l'aléatoire ne doit
        // jamais interrompre ce qui joue.
        guard let index = currentIndex else { return }
        rebuildOrder(startingAt: index)
    }

    mutating func cycleRepeatMode() { repeatMode = repeatMode.next }

    // MARK: - Déplacements

    /// Passe au morceau suivant.
    ///
    /// - Parameter userInitiated: un appui sur « suivant » ignore le mode
    ///   « répéter le morceau » — sinon le bouton ne ferait rien. La fin
    ///   naturelle d'un morceau, elle, le respecte.
    mutating func next(userInitiated: Bool) -> PlaybackStep? {
        advance(by: 1, userInitiated: userInitiated)
    }

    /// Recule d'un morceau, ou rembobine le morceau courant si `elapsed` a
    /// dépassé [restartThreshold].
    ///
    /// Le morceau courant est cherché avant le seuil : sans rien qui joue, il
    /// n'y a pas plus à rembobiner qu'à reculer.
    mutating func previous(elapsed: TimeInterval) -> PlaybackStep? {
        guard currentIndex != nil else { return nil }
        guard elapsed <= Self.restartThreshold else { return .rewind }

        return advance(by: -1, userInitiated: true)
    }

    /// - Returns: `nil` quand la file est vide ou sans morceau courant — il n'y
    ///   a alors rien à demander au lecteur.
    private mutating func advance(by step: Int, userInitiated: Bool) -> PlaybackStep? {
        guard let cursor, !order.isEmpty else { return nil }

        if repeatMode == .one && !userInitiated { return .restart }

        let target = cursor + step
        switch target {
        case order.indices:
            self.cursor = target
            return .play

        case _ where repeatMode == .all:
            self.cursor = target < 0 ? order.count - 1 : 0
            return .play

        case _ where target < 0:
            // Avant le premier morceau sans répétition : on rembobine.
            return .rewind

        default:
            // Fin de file sans répétition : on s'arrête sur le dernier morceau.
            return .stop
        }
    }

    private mutating func rebuildOrder(startingAt index: Int) {
        if shuffleEnabled {
            var rest = Array(songs.indices)
            rest.remove(at: index)
            order = [index] + rest.shuffled()
            cursor = 0
        } else {
            order = Array(songs.indices)
            cursor = index
        }
    }
}
