import Foundation

/// Playlists tenues en mémoire, sans persistance.
///
/// Deux usages : servir de double aux écrans et à leurs tests tant que le
/// stockage SwiftData n'existe pas, et rester ensuite le moyen de tester la
/// couche au-dessus sans base — c'est le pendant du dépôt de morceaux, où
/// `DocumentsMusicRepository` est une implémentation parmi d'autres à venir.
///
/// Même patron de concurrence que `DocumentsMusicRepository` : une classe
/// `nonisolated` dont tout l'état mutable passe par un verrou. Les appels
/// arrivent du main actor (l'UI) comme de tâches détachées, et rien ici n'est
/// assez long pour mériter un acteur.
nonisolated final class InMemoryPlaylistRepository: PlaylistRepository, @unchecked Sendable {

    /// Protège `storage` et `continuations`.
    private let lock = NSLock()

    /// Les playlists dans leur ordre de création ; le tri par nom n'est fait
    /// qu'à l'émission, pour que renommer ne réordonne pas le stockage.
    private var storage: [Playlist] = []

    private var continuations: [UUID: AsyncThrowingStream<[Playlist], Error>.Continuation] = [:]

    /// Lecture de l'horloge, injectable : les horodatages de [Playlist] sont
    /// des paramètres, et c'est ici qu'ils prennent leur valeur. Un test peut
    /// donc figer le temps plutôt que d'observer une date qu'il ne choisit pas.
    private let now: @Sendable () -> Date

    init(playlists: [Playlist] = [], now: @escaping @Sendable () -> Date = { Date() }) {
        self.storage = playlists
        self.now = now
    }

    deinit {
        for continuation in continuations.values { continuation.finish() }
    }

    // MARK: - Lecture

    func playlists() -> AsyncThrowingStream<[Playlist], Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()

            let snapshot: [Playlist] = lock.withLock {
                continuations[id] = continuation
                return sortedByName(storage)
            }

            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.continuations[id] = nil }
            }

            // L'état courant part tout de suite : un écran qui s'ouvre alors
            // que rien ne change ensuite doit quand même afficher quelque
            // chose.
            continuation.yield(snapshot)
        }
    }

    // MARK: - Écriture

    @discardableResult
    func create(name: String, containing songId: String?) async throws -> Playlist {
        guard let trimmed = name.nonBlank else { throw PlaylistError.invalidName }

        let date = now()
        var playlist = Playlist(name: trimmed, createdAt: date)
        if let songId { playlist.add(songId, at: date) }

        publish { $0.append(playlist) }
        return playlist
    }

    func rename(_ id: Playlist.ID, to name: String) async throws {
        guard name.nonBlank != nil else { throw PlaylistError.invalidName }
        try mutate(id) { $0.rename(to: name, at: now()) }
    }

    func delete(_ id: Playlist.ID) async throws {
        try withPlaylist(id) { storage in
            storage.removeAll { $0.id == id }
        }
    }

    func add(_ songId: String, to id: Playlist.ID) async throws {
        try mutate(id) { $0.add(songId, at: now()) }
    }

    func remove(_ songId: String, from id: Playlist.ID) async throws {
        try mutate(id) { $0.remove(songId, at: now()) }
    }

    func reorder(_ id: Playlist.ID, to orderedSongIds: [String]) async throws {
        try mutate(id) { $0.reorder(to: orderedSongIds, at: now()) }
    }

    // MARK: - Interne

    /// Applique `change` à la playlist désignée, puis publie.
    ///
    /// La modification passe par le modèle : c'est lui qui décide si quelque
    /// chose a réellement changé et s'il faut redater — le dépôt ne fait que
    /// retrouver la bonne playlist et diffuser le résultat.
    private func mutate(_ id: Playlist.ID, _ change: (inout Playlist) -> Void) throws {
        try withPlaylist(id) { storage in
            guard let index = storage.firstIndex(where: { $0.id == id }) else { return }
            change(&storage[index])
        }
    }

    /// Vérifie l'existence de la playlist, applique `change` au stockage sous
    /// verrou, puis diffuse hors verrou.
    private func withPlaylist(_ id: Playlist.ID, _ change: (inout [Playlist]) -> Void) throws {
        let known = lock.withLock { storage.contains { $0.id == id } }
        guard known else { throw PlaylistError.unknownPlaylist(id) }

        publish(change)
    }

    /// Modifie le stockage sous verrou, puis émet le nouvel état.
    ///
    /// Les continuations sont recopiées avant de rendre le verrou : `yield`
    /// peut réveiller un consommateur qui rappelle le dépôt, et le faire sous
    /// verrou l'interbloquerait — `NSLock` n'est pas réentrant.
    private func publish(_ change: (inout [Playlist]) -> Void) {
        let (snapshot, listeners) = lock.withLock {
            change(&storage)
            return (sortedByName(storage), Array(continuations.values))
        }

        for listener in listeners { listener.yield(snapshot) }
    }

    /// Même tri que les albums et les artistes : insensible à la casse, dans
    /// l'ordre de la langue de l'utilisateur.
    private func sortedByName(_ playlists: [Playlist]) -> [Playlist] {
        playlists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
