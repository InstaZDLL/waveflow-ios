import Foundation
import Testing
@testable import WaveFlow

/// Sans équivalent Android, dont le `PlayerViewModelTest` ne couvre que le
/// choix de la file : la traversée y appartient à ExoPlayer. Ici elle est
/// tenue à la main — `AVQueuePlayer` n'expose pas l'ordre dont l'aléatoire, la
/// répétition et le « précédent » ont besoin — donc elle se teste.
struct PlaybackQueueTests {

    // MARK: - Chargement

    @Test func loadsAndStartsAtTheRequestedIndex() {
        var queue = PlaybackQueue()
        queue.load(songs(3), startingAt: 1)

        #expect(queue.current?.id == "2")
        #expect(queue.currentIndex == 1)
    }

    /// La file est laissée intacte plutôt que vidée : un appel douteux ne doit
    /// pas interrompre ce qui joue.
    @Test func anOutOfBoundsIndexLeavesTheQueueUntouched() {
        var queue = PlaybackQueue()
        queue.load(songs(2), startingAt: 0)

        #expect(queue.load(songs(5), startingAt: 9) == false)
        #expect(queue.songs.count == 2)
        #expect(queue.current?.id == "1")
    }

    @Test func loadsStartingAtASongFoundByIdentifier() {
        let list = songs(3)
        var queue = PlaybackQueue()
        queue.load(list, startingAt: list[2])

        #expect(queue.current?.id == "3")
    }

    @Test func loadingOnASongAbsentFromTheListIsRejected() {
        var queue = PlaybackQueue()

        #expect(queue.load(songs(3), startingAt: song("absent")) == false)
        #expect(queue.isEmpty)
    }

    // MARK: - Suivant

    @Test func nextMovesForward() {
        var queue = PlaybackQueue()
        queue.load(songs(3), startingAt: 0)

        #expect(queue.next(userInitiated: true) == .play)
        #expect(queue.current?.id == "2")
    }

    @Test func nextAtTheEndWithoutRepeatStops() {
        var queue = PlaybackQueue()
        queue.load(songs(2), startingAt: 1)

        #expect(queue.next(userInitiated: true) == .stop)
        // Le morceau courant ne bouge pas : on s'arrête *sur* le dernier.
        #expect(queue.current?.id == "2")
    }

    @Test func nextAtTheEndWithRepeatAllWrapsToTheFirst() {
        var queue = PlaybackQueue()
        queue.load(songs(3), startingAt: 2)
        queue.repeatMode = .all

        #expect(queue.next(userInitiated: true) == .play)
        #expect(queue.current?.id == "1")
    }

    /// La fin naturelle d'un morceau respecte « répéter le morceau » : elle le
    /// rejoue sans changer de piste.
    @Test func aTrackEndingUnderRepeatOneRestartsTheSameSong() {
        var queue = PlaybackQueue()
        queue.load(songs(3), startingAt: 0)
        queue.repeatMode = .one

        #expect(queue.next(userInitiated: false) == .restart)
        #expect(queue.current?.id == "1")
    }

    /// Le bouton « suivant », lui, l'ignore — sinon il ne ferait rien.
    @Test func theNextButtonOverridesRepeatOne() {
        var queue = PlaybackQueue()
        queue.load(songs(3), startingAt: 0)
        queue.repeatMode = .one

        #expect(queue.next(userInitiated: true) == .play)
        #expect(queue.current?.id == "2")
    }

    // MARK: - Précédent

    @Test func previousMovesBackWithinTheThreshold() {
        var queue = PlaybackQueue()
        queue.load(songs(3), startingAt: 2)

        #expect(queue.previous(elapsed: 1) == .play)
        #expect(queue.current?.id == "2")
    }

    /// Convention iOS : passé le seuil, « précédent » rembobine le morceau
    /// courant au lieu de revenir en arrière.
    @Test func previousBeyondTheThresholdRewindsInPlace() {
        var queue = PlaybackQueue()
        queue.load(songs(3), startingAt: 2)

        #expect(queue.previous(elapsed: PlaybackQueue.restartThreshold + 0.1) == .rewind)
        #expect(queue.current?.id == "3")
    }

    /// La borne elle-même recule encore — c'est « au-delà » qui rembobine.
    @Test func previousExactlyAtTheThresholdStillMovesBack() {
        var queue = PlaybackQueue()
        queue.load(songs(3), startingAt: 2)

        #expect(queue.previous(elapsed: PlaybackQueue.restartThreshold) == .play)
        #expect(queue.current?.id == "2")
    }

    @Test func previousBeforeTheFirstSongRewindsRatherThanLeavingTheQueue() {
        var queue = PlaybackQueue()
        queue.load(songs(3), startingAt: 0)

        #expect(queue.previous(elapsed: 0) == .rewind)
        #expect(queue.current?.id == "1")
    }

    @Test func previousBeforeTheFirstSongWithRepeatAllWrapsToTheLast() {
        var queue = PlaybackQueue()
        queue.load(songs(3), startingAt: 0)
        queue.repeatMode = .all

        #expect(queue.previous(elapsed: 0) == .play)
        #expect(queue.current?.id == "3")
    }

    // MARK: - Aléatoire

    @Test func loadShuffledEnablesShuffleAndStartsAtTheGivenIndex() {
        var queue = PlaybackQueue()
        queue.loadShuffled(songs(4), startingAt: 2)

        #expect(queue.shuffleEnabled)
        #expect(queue.current?.id == "3")
    }

    /// L'invariant qui compte : l'ordre aléatoire est une permutation, pas un
    /// tirage avec remise — chaque morceau passe une fois et une seule.
    @Test func shuffleTraversesEverySongExactlyOnce() {
        var queue = PlaybackQueue()
        queue.loadShuffled(songs(5), startingAt: 0)

        var visited = [queue.current?.id]
        for _ in 1..<5 {
            #expect(queue.next(userInitiated: true) == .play)
            visited.append(queue.current?.id)
        }

        #expect(Set(visited.compactMap { $0 }).count == 5)
        // La file est épuisée : le sixième appel ne trouve plus rien.
        #expect(queue.next(userInitiated: true) == .stop)
    }

    /// Basculer l'aléatoire ne doit jamais interrompre ce qui joue.
    @Test func togglingShuffleKeepsTheCurrentSong() {
        var queue = PlaybackQueue()
        queue.load(songs(5), startingAt: 3)

        queue.toggleShuffle()

        #expect(queue.shuffleEnabled)
        #expect(queue.current?.id == "4")
    }

    @Test func turningShuffleOffRestoresTheNaturalOrder() {
        var queue = PlaybackQueue()
        queue.loadShuffled(songs(4), startingAt: 1)

        queue.toggleShuffle()

        #expect(queue.shuffleEnabled == false)
        #expect(queue.current?.id == "2")
        // L'ordre naturel est repris à partir du morceau courant.
        #expect(queue.next(userInitiated: true) == .play)
        #expect(queue.current?.id == "3")
    }

    // MARK: - File vide

    @Test func anEmptyQueueHasNothingToPlay() {
        var queue = PlaybackQueue()

        #expect(queue.current == nil)
        #expect(queue.isEmpty)
        #expect(queue.next(userInitiated: true) == nil)
        #expect(queue.previous(elapsed: 0) == nil)
        // Au-delà du seuil aussi : sans rien qui joue, il n'y a pas plus à
        // rembobiner qu'à reculer.
        #expect(queue.previous(elapsed: PlaybackQueue.restartThreshold + 1) == nil)
    }

    // MARK: - Modes

    @Test func repeatModeCyclesOffAllOne() {
        var queue = PlaybackQueue()

        #expect(queue.repeatMode == .off)
        queue.cycleRepeatMode()
        #expect(queue.repeatMode == .all)
        queue.cycleRepeatMode()
        #expect(queue.repeatMode == .one)
        queue.cycleRepeatMode()
        #expect(queue.repeatMode == .off)
    }

    // MARK: - Fixtures

    private func songs(_ count: Int) -> [Song] {
        (1...count).map { song("\($0)") }
    }

    private func song(_ id: String) -> Song {
        Song(
            id: id,
            url: URL(fileURLWithPath: "/tmp/\(id)"),
            title: "Morceau \(id)",
            artist: "Artiste",
            artistId: "artist:defaut",
            album: "Album",
            albumId: "album:defaut",
            collectionArtist: "Artiste",
            duration: 0,
            artworkURL: nil,
        )
    }
}
