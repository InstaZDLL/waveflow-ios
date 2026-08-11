import Foundation
import Testing
@testable import WaveFlow

/// Le dépôt en mémoire, qui sert de double aux écrans tant que le stockage
/// SwiftData n'existe pas.
///
/// Ce qui est vérifié ici, c'est le contrat de [PlaylistRepository] — ce que
/// voit un appelant : ce qui est émis, dans quel ordre, et ce qui échoue. La
/// logique de contenu appartient à `Playlist` et vit dans `PlaylistTests`.
struct InMemoryPlaylistRepositoryTests {

    private let creation = Date(timeIntervalSince1970: 1_000)

    // MARK: - Flux

    @Test func emitsTheCurrentStateOnSubscription() async throws {
        let repository = makeRepository(playlists: [makePlaylist(name: "Été")])

        let first = try await firstEmission(from: repository)

        #expect(first.map(\.name) == ["Été"])
    }

    @Test func emitsAnEmptyListWhenThereIsNothing() async throws {
        let first = try await firstEmission(from: makeRepository())

        #expect(first.isEmpty)
    }

    @Test func emitsAgainAfterACreation() async throws {
        let repository = makeRepository()
        var emissions = repository.playlists().makeAsyncIterator()

        _ = try await emissions.next()
        try await repository.create(name: "Hiver")

        let second = try await emissions.next()
        #expect(second?.map(\.name) == ["Hiver"])
    }

    /// Le tri est celui des albums et des artistes : insensible à la casse. Il
    /// est appliqué à l'émission, pas au stockage — renommer ne doit pas
    /// dépendre de l'ordre d'insertion.
    @Test func emitsPlaylistsSortedByNameIgnoringCase() async throws {
        let repository = makeRepository()
        try await repository.create(name: "zebra")
        try await repository.create(name: "Alpha")
        try await repository.create(name: "beta")

        let names = try await firstEmission(from: repository).map(\.name)

        #expect(names == ["Alpha", "beta", "zebra"])
    }

    // MARK: - Création

    @Test func createsAnEmptyPlaylist() async throws {
        let repository = makeRepository()

        let created = try await repository.create(name: "Hiver")

        #expect(created.name == "Hiver")
        #expect(created.songIds.isEmpty)
        #expect(created.createdAt == creation)
    }

    /// Le morceau arrive avec la playlist plutôt qu'en un second appel : une
    /// interruption ne peut pas laisser une playlist vide derrière elle.
    @Test func createsAPlaylistAlreadyHoldingItsFirstSong() async throws {
        let repository = makeRepository()

        let created = try await repository.create(name: "Hiver", containing: "a")

        #expect(created.songIds == ["a"])
        let stored = try await firstEmission(from: repository)
        #expect(stored.first?.songIds == ["a"])
    }

    @Test func rejectsABlankName() async throws {
        let repository = makeRepository()

        await #expect(throws: PlaylistError.invalidName) {
            try await repository.create(name: "   ")
        }
        #expect(try await firstEmission(from: repository).isEmpty)
    }

    @Test func trimsTheNameOnCreation() async throws {
        let repository = makeRepository()

        let created = try await repository.create(name: "  Hiver  ")

        #expect(created.name == "Hiver")
    }

    // MARK: - Modification

    @Test func renamesAPlaylist() async throws {
        let playlist = makePlaylist(name: "Été")
        let repository = makeRepository(playlists: [playlist])

        try await repository.rename(playlist.id, to: "Hiver")

        #expect(try await firstEmission(from: repository).map(\.name) == ["Hiver"])
    }

    @Test func renamingRejectsABlankName() async throws {
        let playlist = makePlaylist(name: "Été")
        let repository = makeRepository(playlists: [playlist])

        await #expect(throws: PlaylistError.invalidName) {
            try await repository.rename(playlist.id, to: " ")
        }
        #expect(try await firstEmission(from: repository).map(\.name) == ["Été"])
    }

    @Test func addsAndRemovesSongs() async throws {
        let playlist = makePlaylist(name: "Été")
        let repository = makeRepository(playlists: [playlist])

        try await repository.add("a", to: playlist.id)
        try await repository.add("b", to: playlist.id)
        try await repository.remove("a", from: playlist.id)

        #expect(try await firstEmission(from: repository).first?.songIds == ["b"])
    }

    @Test func reordersAPlaylist() async throws {
        let playlist = makePlaylist(name: "Été", songIds: ["a", "b", "c"])
        let repository = makeRepository(playlists: [playlist])

        try await repository.reorder(playlist.id, to: ["c", "a", "b"])

        #expect(try await firstEmission(from: repository).first?.songIds == ["c", "a", "b"])
    }

    @Test func deletesAPlaylist() async throws {
        let playlist = makePlaylist(name: "Été")
        let repository = makeRepository(playlists: [playlist, makePlaylist(name: "Hiver")])

        try await repository.delete(playlist.id)

        #expect(try await firstEmission(from: repository).map(\.name) == ["Hiver"])
    }

    // MARK: - Playlist inconnue

    /// Une playlist supprimée depuis un autre écran ne doit pas faire échouer
    /// silencieusement : l'appelant a besoin de savoir que sa cible n'existe
    /// plus.
    @Test func everyMutationRejectsAnUnknownPlaylist() async throws {
        let repository = makeRepository()
        let absent = UUID()

        await #expect(throws: PlaylistError.unknownPlaylist(absent)) {
            try await repository.rename(absent, to: "Hiver")
        }
        await #expect(throws: PlaylistError.unknownPlaylist(absent)) {
            try await repository.delete(absent)
        }
        await #expect(throws: PlaylistError.unknownPlaylist(absent)) {
            try await repository.add("a", to: absent)
        }
        await #expect(throws: PlaylistError.unknownPlaylist(absent)) {
            try await repository.remove("a", from: absent)
        }
        await #expect(throws: PlaylistError.unknownPlaylist(absent)) {
            try await repository.reorder(absent, to: [])
        }
    }

    /// Le cas de la course, rejoué en séquence : une playlist supprimée entre
    /// la validation et la mutation doit lever, pas rendre la main en silence.
    @Test func mutatingAPlaylistDeletedInTheMeantimeThrows() async throws {
        let playlist = makePlaylist(name: "Été")
        let repository = makeRepository(playlists: [playlist])

        try await repository.delete(playlist.id)

        await #expect(throws: PlaylistError.unknownPlaylist(playlist.id)) {
            try await repository.add("a", to: playlist.id)
        }
    }

    // MARK: - Concurrence

    /// Cinquante ajouts concurrents : aucun ne doit se perdre, et aucun ne doit
    /// compter double. C'est ce que garantit la mutation sous verrou, là où un
    /// lire-modifier-écrire non protégé perdrait des écritures.
    @Test func concurrentAdditionsAreAllRecorded() async throws {
        let playlist = makePlaylist(name: "Été")
        let repository = makeRepository(playlists: [playlist])

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask { try? await repository.add("song-\(index)", to: playlist.id) }
            }
        }

        let stored = try await firstEmission(from: repository).first
        #expect(stored?.songIds.count == 50)
        #expect(Set(stored?.songIds ?? []).count == 50)
    }

    /// Un abonné voit les états dans l'ordre où ils ont été produits — y
    /// compris le tout premier, celui de son inscription.
    @Test func emissionsReachASubscriberInOrder() async throws {
        let repository = makeRepository()
        var emissions = repository.playlists().makeAsyncIterator()

        try await repository.create(name: "A")
        try await repository.create(name: "B")

        #expect(try await emissions.next()?.isEmpty == true)
        #expect(try await emissions.next()?.map(\.name) == ["A"])
        #expect(try await emissions.next()?.map(\.name) == ["A", "B"])
    }

    // MARK: - Horodatage

    /// L'horloge est injectée : le dépôt est la couche qui la lit, `Playlist`
    /// ne reçoit que des dates. C'est ce qui rend l'horodatage observable.
    @Test func stampsModificationsWithTheInjectedClock() async throws {
        let modification = Date(timeIntervalSince1970: 5_000)
        let clock = MutableClock(creation)
        let playlist = makePlaylist(name: "Été")
        let repository = InMemoryPlaylistRepository(playlists: [playlist], now: clock.read)

        clock.set(modification)
        try await repository.add("a", to: playlist.id)

        let stored = try await firstEmission(from: repository).first
        #expect(stored?.updatedAt == modification)
        #expect(stored?.createdAt == creation)
    }

    // MARK: - Fixtures

    private func makeRepository(playlists: [Playlist] = []) -> InMemoryPlaylistRepository {
        let date = creation
        return InMemoryPlaylistRepository(playlists: playlists, now: { date })
    }

    private func makePlaylist(name: String, songIds: [String] = []) -> Playlist {
        Playlist(name: name, songIds: songIds, createdAt: creation)
    }

    /// Premier état émis par le flux — l'instantané que reçoit un écran qui
    /// s'abonne.
    private func firstEmission(from repository: some PlaylistRepository) async throws -> [Playlist] {
        var iterator = repository.playlists().makeAsyncIterator()
        return try await iterator.next() ?? []
    }
}

/// Horloge réglable, pour observer un horodatage qu'on choisit plutôt que
/// l'heure qu'il est.
private final class MutableClock: @unchecked Sendable {

    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) { self.date = date }

    func set(_ date: Date) { lock.withLock { self.date = date } }

    var read: @Sendable () -> Date {
        { [self] in lock.withLock { date } }
    }
}
