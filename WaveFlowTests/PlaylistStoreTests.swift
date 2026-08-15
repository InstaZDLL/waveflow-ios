import Foundation
import Testing
@testable import WaveFlow

/// Le store des playlists : ce qu'il expose aux écrans, et ce qu'il fait des
/// échecs.
///
/// Le contrat du dépôt est vérifié ailleurs (`InMemoryPlaylistRepositoryTests`,
/// `SwiftDataPlaylistRepositoryTests`). Ce qui se joue ici, c'est la couche
/// au-dessus : chargement, confinement des erreurs d'écriture, et ordre des
/// écritures.
struct PlaylistStoreTests {

    private let creation = Date(timeIntervalSince1970: 1_000)

    // MARK: - Lecture

    @Test func exposesTheCurrentPlaylistsOnceLoaded() async throws {
        let store = makeStore(playlists: [makePlaylist(name: "Été")])

        store.load()
        await settle { !store.isLoading }

        #expect(store.playlists.map(\.name) == ["Été"])
        #expect(store.isLoading == false)
        #expect(store.errorMessage == nil)
    }

    @Test func startsLoading() {
        #expect(makeStore().isLoading)
    }

    @Test func reflectsACreation() async throws {
        let repository = makeRepository()
        let store = PlaylistStore(repository: repository)
        store.load()
        await settle { !store.isLoading }

        store.create(name: "Hiver")
        await store.waitForWrites()
        await settle { !store.playlists.isEmpty }

        #expect(store.playlists.map(\.name) == ["Hiver"])
    }

    /// Le bouton de création est déjà désactivé sur un champ vide : un nom
    /// blanc ne doit rien tenter, pas produire une erreur.
    @Test func ignoresABlankName() async throws {
        let repository = makeRepository()
        let store = PlaylistStore(repository: repository)
        store.load()
        await settle { !store.isLoading }

        store.create(name: "   ")
        await store.waitForWrites()

        #expect(store.playlists.isEmpty)
        #expect(store.writeFailure == nil)
    }

    @Test func findsAPlaylistByIdentifier() async throws {
        let playlist = makePlaylist(name: "Été")
        let store = makeStore(playlists: [playlist])

        store.load()
        await settle { !store.isLoading }

        #expect(store.playlist(playlist.id)?.name == "Été")
        #expect(store.playlist(UUID()) == nil)
    }

    /// `isEmpty` ne doit pas être vrai pendant le chargement : l'écran
    /// afficherait « aucune playlist » avant d'en savoir quoi que ce soit.
    @Test func isNotEmptyWhileLoading() async throws {
        let store = makeStore()
        #expect(store.isEmpty == false)

        store.load()
        await settle { !store.isLoading }

        #expect(store.isEmpty)
    }

    // MARK: - Échec de lecture

    @Test func surfacesAReadFailure() async throws {
        let store = PlaylistStore(repository: StubPlaylistRepository(streamFailures: 1))

        store.load()
        await settle { store.errorMessage != nil }

        #expect(store.errorMessage != nil)
        #expect(store.isLoading == false)
    }

    /// Après un échec, `retry()` doit rouvrir un flux — sans quoi l'écran
    /// resterait bloqué sur son message d'erreur.
    @Test func retryResumesAfterAReadFailure() async throws {
        let repository = StubPlaylistRepository(streamFailures: 1)
        let store = PlaylistStore(repository: repository)

        store.load()
        await settle { store.errorMessage != nil }
        #expect(store.errorMessage != nil)

        store.retry()
        await settle { store.errorMessage == nil && !store.isLoading }

        #expect(store.errorMessage == nil)
        #expect(store.isLoading == false)
    }

    // MARK: - Échec d'écriture

    /// Une écriture ratée est un événement, pas un état : la liste reste
    /// affichée, seule une alerte s'ajoute.
    @Test func reportsAWriteFailureWithoutReplacingTheList() async throws {
        let repository = StubPlaylistRepository(
            playlists: [makePlaylist(name: "Été")],
            writeError: StubPlaylistRepository.Failure.boom,
        )
        let store = PlaylistStore(repository: repository)
        store.load()
        await settle { !store.isLoading }

        store.delete(UUID())
        await store.waitForWrites()

        #expect(store.writeFailure?.message == "Impossible de supprimer la playlist.")
        #expect(store.playlists.map(\.name) == ["Été"])
        #expect(store.errorMessage == nil)
    }

    /// Le message nomme l'action, pas la cause technique — mais la cause reste
    /// attachée, sans quoi un échec ne laisserait aucune trace exploitable.
    @Test func keepsTheCauseOfAWriteFailure() async throws {
        let store = PlaylistStore(
            repository: StubPlaylistRepository(writeError: StubPlaylistRepository.Failure.boom),
        )

        store.create(name: "Hiver")
        await store.waitForWrites()

        let failure = try #require(store.writeFailure)
        #expect(failure.underlying as? StubPlaylistRepository.Failure == .boom)
    }

    @Test func dismissesAWriteFailure() async throws {
        let store = PlaylistStore(
            repository: StubPlaylistRepository(writeError: StubPlaylistRepository.Failure.boom),
        )

        store.create(name: "Hiver")
        await store.waitForWrites()
        #expect(store.writeFailure != nil)

        store.dismissWriteFailure()

        #expect(store.writeFailure == nil)
    }

    /// Chaque échec porte une identité neuve : deux échecs successifs
    /// identiques doivent rouvrir l'alerte plutôt que passer inaperçus.
    @Test func givesEachFailureItsOwnIdentity() async throws {
        let store = PlaylistStore(
            repository: StubPlaylistRepository(writeError: StubPlaylistRepository.Failure.boom),
        )

        store.create(name: "Hiver")
        await store.waitForWrites()
        let first = try #require(store.writeFailure?.id)

        store.create(name: "Été")
        await store.waitForWrites()

        #expect(store.writeFailure?.id != first)
    }

    // MARK: - Ordre des écritures

    /// Deux glissers rapprochés partent dans deux tâches : c'est l'ordre des
    /// gestes qui doit décider de l'ordre final, pas celui de leur arrivée au
    /// stockage. La première écriture est retenue par une barrière que le test
    /// lève après avoir lancé la seconde — sans sérialisation, la seconde
    /// s'enregistrerait en premier.
    @Test func serializesWritesInCallOrder() async throws {
        let gate = Gate()
        let repository = StubPlaylistRepository(holdFirstWriteAt: gate)
        let store = PlaylistStore(repository: repository)
        let id = UUID()

        store.reorder(id, to: ["a"])
        store.reorder(id, to: ["b"])

        await gate.open()
        await store.waitForWrites()

        #expect(repository.reorders == [["a"], ["b"]])
    }

    // MARK: - Fixtures

    /// Dépôt réel, horloge figée.
    ///
    /// La fermeture est bâtie ici plutôt que rendue par une propriété : la
    /// suite est isolée au main actor, et une fermeture qui en sort héritait de
    /// cette isolation — le dépôt, lui, n'est isolé nulle part et attend du
    /// `@Sendable`.
    private func makeRepository(playlists: [Playlist] = []) -> InMemoryPlaylistRepository {
        let date = creation
        return InMemoryPlaylistRepository(playlists: playlists, now: { @Sendable in date })
    }

    private func makeStore(playlists: [Playlist] = []) -> PlaylistStore {
        PlaylistStore(repository: makeRepository(playlists: playlists))
    }

    private func makePlaylist(name: String, songIds: [String] = []) -> Playlist {
        Playlist(name: name, songIds: songIds, createdAt: creation)
    }

    /// Cède la main jusqu'à ce que `condition` soit vraie.
    ///
    /// Le store consomme son flux dans une tâche : rien ne permet de l'attendre
    /// depuis l'extérieur, contrairement aux écritures. Attendre la condition
    /// plutôt qu'un nombre fixe de tours évite qu'une machine chargée ne fasse
    /// échouer le test — et la borne empêche une attente infinie si elle ne
    /// devient jamais vraie.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
    }
}

/// Barrière à une passe, pour retenir une écriture le temps d'en lancer une
/// seconde.
private actor Gate {

    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { self.continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

/// Dépôt de complaisance : il n'implémente que ce dont ces tests ont besoin —
/// échouer sur commande, retenir la première écriture, et noter les ordres
/// reçus.
private nonisolated final class StubPlaylistRepository: PlaylistRepository, @unchecked Sendable {

    enum Failure: Error, Equatable { case boom }

    private let lock = NSLock()
    private var recordedReorders: [[String]] = []
    private var remainingStreamFailures: Int
    private var firstWriteHeld = false

    private let storedPlaylists: [Playlist]
    private let writeError: Error?
    private let gate: Gate?

    var reorders: [[String]] { lock.withLock { recordedReorders } }

    init(
        playlists: [Playlist] = [],
        writeError: Error? = nil,
        streamFailures: Int = 0,
        holdFirstWriteAt gate: Gate? = nil,
    ) {
        self.storedPlaylists = playlists
        self.writeError = writeError
        self.remainingStreamFailures = streamFailures
        self.gate = gate
    }

    func playlists() -> AsyncThrowingStream<[Playlist], Error> {
        AsyncThrowingStream { continuation in
            // Les échecs sont consommés un par un : `retry()` doit pouvoir
            // repartir sur un flux sain.
            let shouldFail = lock.withLock {
                guard remainingStreamFailures > 0 else { return false }
                remainingStreamFailures -= 1
                return true
            }

            if shouldFail {
                continuation.finish(throwing: Failure.boom)
            } else {
                continuation.yield(storedPlaylists)
            }
        }
    }

    @discardableResult
    func create(name: String, containing songId: String?) async throws -> Playlist {
        try await perform()
        return Playlist(name: name, createdAt: Date(timeIntervalSince1970: 0))
    }

    func rename(_ id: Playlist.ID, to name: String) async throws { try await perform() }

    func delete(_ id: Playlist.ID) async throws { try await perform() }

    func add(_ songId: String, to id: Playlist.ID) async throws { try await perform() }

    func remove(_ songId: String, from id: Playlist.ID) async throws { try await perform() }

    func reorder(_ id: Playlist.ID, to orderedSongIds: [String]) async throws {
        try await perform()
        lock.withLock { recordedReorders.append(orderedSongIds) }
    }

    /// Retient la toute première écriture si une barrière a été fournie, puis
    /// échoue si on le lui a demandé.
    private func perform() async throws {
        let shouldHold = lock.withLock {
            guard gate != nil, !firstWriteHeld else { return false }
            firstWriteHeld = true
            return true
        }
        if shouldHold { await gate?.wait() }

        if let writeError { throw writeError }
    }
}
