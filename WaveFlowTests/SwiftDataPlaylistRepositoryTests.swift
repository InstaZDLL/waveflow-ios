import Foundation
import SwiftData
import Testing
@testable import WaveFlow

/// Le dépôt SwiftData, seconde implémentation de [PlaylistRepository].
///
/// La suite reprend le contrat vérifié par `InMemoryPlaylistRepositoryTests` —
/// deux implémentations du même protocole doivent se comporter pareil — et y
/// ajoute ce qui n'a de sens qu'ici : la persistance, et le fait que la
/// normalisation reste celle du modèle plutôt qu'une seconde écrite pour la
/// base.
///
/// Chaque test part d'un conteneur en mémoire neuf : rien à nettoyer, et aucune
/// dépendance à l'ordre d'exécution.
///
/// - Note: exclue du harnais Linux (`Tools/LinuxHarness/Package.swift`),
///   SwiftData n'y existant pas.
struct SwiftDataPlaylistRepositoryTests {

    private let container: ModelContainer
    private let creation = Date(timeIntervalSince1970: 1_000)

    init() throws {
        container = try SwiftDataPlaylistRepository.makeContainer(inMemory: true)
    }

    // MARK: - Flux

    @Test func emitsAnEmptyListWhenThereIsNothing() async throws {
        #expect(try await firstEmission(from: makeRepository()).isEmpty)
    }

    @Test func emitsTheCurrentStateOnSubscription() async throws {
        let repository = makeRepository()
        try await repository.create(name: "Été")

        let first = try await firstEmission(from: repository)

        #expect(first.map(\.name) == ["Été"])
    }

    @Test func emitsAgainAfterACreation() async throws {
        let repository = makeRepository()
        var emissions = repository.playlists().makeAsyncIterator()

        // Le premier état est attendu avant de muter : l'inscription est
        // asynchrone ici, et sans cette attente la création pourrait la
        // devancer et se retrouver repliée dans l'instantané initial.
        #expect(try await emissions.next()?.isEmpty == true)

        try await repository.create(name: "Hiver")
        #expect(try await emissions.next()?.map(\.name) == ["Hiver"])
    }

    /// Même tri que le dépôt en mémoire, et que les albums et artistes : il est
    /// fait en Swift, pas par le `FetchDescriptor`, pour que la comparaison
    /// reste `localizedCaseInsensitiveCompare` et non celle du stockage.
    @Test func emitsPlaylistsSortedByNameIgnoringCase() async throws {
        let repository = makeRepository()
        try await repository.create(name: "zebra")
        try await repository.create(name: "Alpha")
        try await repository.create(name: "beta")

        let names = try await firstEmission(from: repository).map(\.name)

        #expect(names == ["Alpha", "beta", "zebra"])
    }

    /// Un abonné voit les états dans l'ordre où ils ont été produits. Ce que
    /// garantit ici la sérialisation de l'acteur, là où le dépôt en mémoire
    /// s'appuie sur son verrou.
    @Test func emissionsReachASubscriberInOrder() async throws {
        let repository = makeRepository()
        var emissions = repository.playlists().makeAsyncIterator()

        #expect(try await emissions.next()?.isEmpty == true)

        try await repository.create(name: "A")
        #expect(try await emissions.next()?.map(\.name) == ["A"])

        try await repository.create(name: "B")
        #expect(try await emissions.next()?.map(\.name) == ["A", "B"])
    }

    // MARK: - Création

    @Test func createsAnEmptyPlaylist() async throws {
        let created = try await makeRepository().create(name: "Hiver")

        #expect(created.name == "Hiver")
        #expect(created.songIds.isEmpty)
        #expect(created.createdAt == creation)
    }

    /// Le morceau arrive avec la playlist plutôt qu'en un second appel : une
    /// interruption ne peut pas laisser une playlist vide derrière elle. Ici
    /// c'est un seul `save()` qui le garantit.
    @Test func createsAPlaylistAlreadyHoldingItsFirstSong() async throws {
        let repository = makeRepository()

        let created = try await repository.create(name: "Hiver", containing: "a")

        #expect(created.songIds == ["a"])
        #expect(try await firstEmission(from: repository).first?.songIds == ["a"])
    }

    @Test func rejectsABlankName() async throws {
        let repository = makeRepository()

        await #expect(throws: PlaylistError.invalidName) {
            try await repository.create(name: "   ")
        }
        #expect(try await firstEmission(from: repository).isEmpty)
    }

    @Test func trimsTheNameOnCreation() async throws {
        let created = try await makeRepository().create(name: "  Hiver  ")

        #expect(created.name == "Hiver")
    }

    // MARK: - Modification

    @Test func renamesAPlaylist() async throws {
        let repository = makeRepository()
        let playlist = try await repository.create(name: "Été")

        try await repository.rename(playlist.id, to: "Hiver")

        #expect(try await firstEmission(from: repository).map(\.name) == ["Hiver"])
    }

    @Test func renamingRejectsABlankName() async throws {
        let repository = makeRepository()
        let playlist = try await repository.create(name: "Été")

        await #expect(throws: PlaylistError.invalidName) {
            try await repository.rename(playlist.id, to: " ")
        }
        #expect(try await firstEmission(from: repository).map(\.name) == ["Été"])
    }

    @Test func addsAndRemovesSongs() async throws {
        let repository = makeRepository()
        let playlist = try await repository.create(name: "Été")

        try await repository.add("a", to: playlist.id)
        try await repository.add("b", to: playlist.id)
        try await repository.remove("a", from: playlist.id)

        #expect(try await firstEmission(from: repository).first?.songIds == ["b"])
    }

    @Test func reordersAPlaylist() async throws {
        let repository = makeRepository()
        let playlist = try await repository.create(name: "Été")
        for songId in ["a", "b", "c"] { try await repository.add(songId, to: playlist.id) }

        try await repository.reorder(playlist.id, to: ["c", "a", "b"])

        #expect(try await firstEmission(from: repository).first?.songIds == ["c", "a", "b"])
    }

    /// La normalisation appartient à `Playlist.reorder(to:at:)` et n'est pas
    /// réécrite pour la base : un identifiant étranger est écarté, et un
    /// morceau omis par l'appelant est replacé à la suite plutôt que supprimé.
    ///
    /// Ce n'est pas un cas d'école — l'écran ne liste que les morceaux résolus
    /// contre la bibliothèque, donc un fichier disparu de `Documents` est
    /// absent de ce qu'il renvoie sans l'être de la playlist.
    @Test func normalizesTheRequestedOrderThroughTheModel() async throws {
        let repository = makeRepository()
        let playlist = try await repository.create(name: "Été")
        for songId in ["a", "b", "c"] { try await repository.add(songId, to: playlist.id) }

        try await repository.reorder(playlist.id, to: ["c", "étranger", "c"])

        #expect(try await firstEmission(from: repository).first?.songIds == ["c", "a", "b"])
    }

    @Test func deletesAPlaylist() async throws {
        let repository = makeRepository()
        let playlist = try await repository.create(name: "Été")
        try await repository.create(name: "Hiver")

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

    @Test func mutatingAPlaylistDeletedInTheMeantimeThrows() async throws {
        let repository = makeRepository()
        let playlist = try await repository.create(name: "Été")

        try await repository.delete(playlist.id)

        await #expect(throws: PlaylistError.unknownPlaylist(playlist.id)) {
            try await repository.add("a", to: playlist.id)
        }
    }

    // MARK: - Persistance

    /// Ce que le dépôt en mémoire ne peut pas offrir : l'état survit à
    /// l'instance qui l'a écrit. Un second dépôt sur le même conteneur relit ce
    /// que le premier a enregistré.
    @Test func outlivesTheRepositoryThatWroteIt() async throws {
        let playlist = try await makeRepository().create(name: "Été", containing: "a")

        let reopened = try await firstEmission(from: makeRepository())

        #expect(reopened.map(\.id) == [playlist.id])
        #expect(reopened.first?.songIds == ["a"])
        #expect(reopened.first?.createdAt == creation)
    }

    // MARK: - Concurrence

    /// Cinquante ajouts concurrents : aucun ne doit se perdre, ni compter
    /// double. C'est la sérialisation de l'acteur qui l'assure — un
    /// lire-modifier-écrire non protégé perdrait des écritures.
    @Test func concurrentAdditionsAreAllRecorded() async throws {
        let repository = makeRepository()
        let playlist = try await repository.create(name: "Été")

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask { try? await repository.add("song-\(index)", to: playlist.id) }
            }
        }

        let stored = try await firstEmission(from: repository).first
        #expect(stored?.songIds.count == 50)
        #expect(Set(stored?.songIds ?? []).count == 50)
    }

    // MARK: - Horodatage

    /// L'horloge est lue par le dépôt et la date descend en paramètre jusqu'au
    /// modèle : `Playlist` ne consulte jamais l'heure.
    @Test func stampsModificationsWithTheInjectedClock() async throws {
        let modification = Date(timeIntervalSince1970: 5_000)
        let clock = MutableClock(creation)
        let repository = SwiftDataPlaylistRepository(container: container, now: clock.read)
        let playlist = try await repository.create(name: "Été")

        clock.set(modification)
        try await repository.add("a", to: playlist.id)

        let stored = try await firstEmission(from: repository).first
        #expect(stored?.updatedAt == modification)
        #expect(stored?.createdAt == creation)
    }

    /// `updatedAt` n'est daté que si quelque chose a réellement changé : c'est
    /// un horodatage de résolution de conflits pour la future synchronisation,
    /// et un ajout sans effet ne doit pas faire croire à une modification.
    @Test func doesNotRedateAnAdditionThatChangesNothing() async throws {
        let clock = MutableClock(creation)
        let repository = SwiftDataPlaylistRepository(container: container, now: clock.read)
        let playlist = try await repository.create(name: "Été", containing: "a")

        clock.set(Date(timeIntervalSince1970: 5_000))
        try await repository.add("a", to: playlist.id)

        #expect(try await firstEmission(from: repository).first?.updatedAt == creation)
    }

    // MARK: - Fixtures

    private func makeRepository() -> SwiftDataPlaylistRepository {
        let date = creation
        return SwiftDataPlaylistRepository(container: container, now: { date })
    }

    /// Premier état émis par le flux — l'instantané que reçoit un écran qui
    /// s'abonne.
    private func firstEmission(from repository: some PlaylistRepository) async throws -> [Playlist] {
        var iterator = repository.playlists().makeAsyncIterator()
        return try await iterator.next() ?? []
    }
}
