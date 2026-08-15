import Foundation
import SwiftData

/// Playlists persistées par SwiftData.
///
/// Pendant de `InMemoryPlaylistRepository`, dont elle doit reproduire le
/// contrat au détail près : état courant émis dès l'abonnement, tri par nom,
/// création atomique, et `PlaylistError.unknownPlaylist` plutôt qu'un échec
/// silencieux sur un identifiant inconnu.
///
/// Là où le dépôt en mémoire sérialise tout sous `NSLock`, celui-ci s'appuie
/// sur [PlaylistStorage] : un `ModelContext` n'est pas `Sendable` et ne se
/// partage pas entre threads, c'est donc un acteur qui le détient et qui rend
/// l'exclusion mutuelle.
nonisolated final class SwiftDataPlaylistRepository: PlaylistRepository {

    private let storage: PlaylistStorage

    /// Lecture de l'horloge, injectable pour les tests.
    ///
    /// Elle est lue ici et la date descend en paramètre jusqu'au modèle, comme
    /// le veut la convention de [Playlist] : ni le stockage ni le domaine ne
    /// consultent l'horloge, seul le bord le fait.
    private let now: @Sendable () -> Date

    init(container: ModelContainer, now: @escaping @Sendable () -> Date = { Date() }) {
        self.storage = PlaylistStorage(modelContainer: container)
        self.now = now
    }

    /// Conteneur sur disque.
    ///
    /// - Parameter directory: dossier du fichier de stockage, créé s'il manque.
    ///
    /// Le dossier est créé explicitement : `Application Support` n'existe pas
    /// dans le conteneur d'une application fraîchement installée, contrairement
    /// à `Documents` et `Library/Caches`. SwiftData y dépose son fichier par
    /// défaut mais ne crée pas le chemin — sans cette ligne, la toute première
    /// ouverture échoue, et l'application ne démarre pas.
    static func makeContainer(in directory: URL = .applicationSupportDirectory) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return try ModelContainer(
            for: PlaylistEntity.self,
            configurations: ModelConfiguration(url: directory.appending(path: storeName)),
        )
    }

    /// Conteneur sans fichier — ce que veulent les tests, chacun partant d'une
    /// base vierge sans avoir à nettoyer derrière lui.
    static func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: PlaylistEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true),
        )
    }

    /// Nommé plutôt que laissé au défaut de SwiftData (`default.store`) : le
    /// jour où une seconde base arrive, deux fichiers « default » ne se
    /// distingueraient pas.
    private static let storeName = "Playlists.store"

    /// La base et ses annexes SQLite, dans l'ordre où elles se déplacent.
    ///
    /// Exposé pour [PlaylistPersistence], qui doit pouvoir écarter l'ensemble :
    /// laisser un `-wal` derrière ferait reprendre un journal périmé à la base
    /// recréée.
    static var storeFileNames: [String] {
        [storeName, "\(storeName)-wal", "\(storeName)-shm"]
    }

    // MARK: - Lecture

    func playlists() -> AsyncThrowingStream<[Playlist], Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()

            continuation.onTermination = { [storage] _ in
                Task { await storage.unsubscribe(id) }
            }

            // Contrairement au dépôt en mémoire, le premier envoi ne peut pas
            // être synchrone : lire la base demande de rejoindre l'acteur. Ce
            // qui compte est préservé — inscription et premier envoi ont lieu
            // dans le même appel d'acteur, donc une mutation concurrente ne
            // peut pas s'y glisser et livrer un état plus récent avant
            // l'instantané destiné à ce nouvel abonné.
            Task { [storage] in await storage.subscribe(id, continuation) }
        }
    }

    // MARK: - Écriture

    @discardableResult
    func create(name: String, containing songId: String?) async throws -> Playlist {
        try await storage.create(name: name, containing: songId, at: now())
    }

    func rename(_ id: Playlist.ID, to name: String) async throws {
        try await storage.rename(id, to: name, at: now())
    }

    func delete(_ id: Playlist.ID) async throws {
        try await storage.delete(id)
    }

    func add(_ songId: String, to id: Playlist.ID) async throws {
        try await storage.add(songId, to: id, at: now())
    }

    func remove(_ songId: String, from id: Playlist.ID) async throws {
        try await storage.remove(songId, from: id, at: now())
    }

    func reorder(_ id: Playlist.ID, to orderedSongIds: [String]) async throws {
        try await storage.reorder(id, to: orderedSongIds, at: now())
    }
}

/// Le `ModelContext` et les abonnés, tenus par un acteur.
///
/// `@ModelActor` lie le contexte à l'exécuteur de l'acteur : il n'est touché
/// que d'ici, ce qu'exige un type non `Sendable`.
///
/// **Aucune méthode ne suspend.** Les appels SwiftData (`fetch`, `save`) sont
/// synchrones, et c'est ce qui rend l'exclusion mutuelle réelle : un acteur est
/// réentrant, un `await` au milieu d'une mutation rouvrirait la porte aux deux
/// courses que le dépôt en mémoire a dû corriger — un abonné servi dans le
/// désordre, et une validation d'existence séparée de la mutation qu'elle
/// protège. Ne pas introduire d'`await` dans ce type sans reconsidérer les deux.
@ModelActor
actor PlaylistStorage {

    private var continuations: [UUID: AsyncThrowingStream<[Playlist], Error>.Continuation] = [:]

    /// Flux terminés avant que leur inscription ait pu être traitée.
    ///
    /// `playlists()` inscrit depuis une tâche et `onTermination` désinscrit
    /// depuis une autre : rien n'ordonne les deux. Un consommateur qui
    /// abandonne aussitôt peut donc faire arriver la désinscription en
    /// premier — et sans cette trace, l'inscription qui la suit entrerait dans
    /// `continuations` sans que personne ne vienne jamais l'en retirer. Le flux
    /// y resterait jusqu'à la fin du processus, recevant des états que plus
    /// personne ne lit.
    private var terminatedBeforeSubscribing: Set<UUID> = []

    deinit {
        for continuation in continuations.values { continuation.finish() }
    }

    // MARK: - Abonnements

    func subscribe(_ id: UUID, _ continuation: AsyncThrowingStream<[Playlist], Error>.Continuation) {
        // La terminaison a devancé l'inscription : il n'y a plus personne à
        // servir. `remove` consomme la marque au passage, l'ensemble ne grossit
        // donc pas.
        guard terminatedBeforeSubscribing.remove(id) == nil else { return }

        // Inscrit avant de lire : si l'instantané échoue, `finish` déclenche
        // `onTermination`, et `unsubscribe` doit retrouver l'entrée pour la
        // retirer. Inscrire seulement en cas de succès la lui ferait manquer,
        // et il prendrait cette terminaison pour une course.
        continuations[id] = continuation

        do {
            continuation.yield(try snapshot())
        } catch {
            continuation.finish(throwing: error)
        }
    }

    func unsubscribe(_ id: UUID) {
        guard continuations.removeValue(forKey: id) == nil else { return }

        // Rien à retirer : l'inscription n'est pas encore passée. On laisse la
        // marque pour qu'elle se sache caduque en arrivant.
        terminatedBeforeSubscribing.insert(id)
    }

    // MARK: - Écriture

    func create(name: String, containing songId: String?, at date: Date) throws -> Playlist {
        guard let trimmed = name.nonBlank else { throw PlaylistError.invalidName }

        var playlist = Playlist(name: trimmed, createdAt: date)
        if let songId { playlist.add(songId, at: date) }

        // Insertion et enregistrement dans le même appel : une interruption ne
        // peut pas laisser derrière elle une playlist créée mais vide.
        modelContext.insert(PlaylistEntity(playlist))
        try modelContext.save()
        publish()

        return playlist
    }

    func rename(_ id: Playlist.ID, to name: String, at date: Date) throws {
        // Le nom est validé avant de chercher la playlist : un nom blanc est
        // invalide même si l'identifiant l'est aussi, et c'est l'erreur la plus
        // utile à remonter à l'écran de renommage.
        guard name.nonBlank != nil else { throw PlaylistError.invalidName }
        try mutate(id) { $0.rename(to: name, at: date) }
    }

    func delete(_ id: Playlist.ID) throws {
        guard let entity = try entity(id) else { throw PlaylistError.unknownPlaylist(id) }

        modelContext.delete(entity)
        try modelContext.save()
        publish()
    }

    func add(_ songId: String, to id: Playlist.ID, at date: Date) throws {
        try mutate(id) { $0.add(songId, at: date) }
    }

    func remove(_ songId: String, from id: Playlist.ID, at date: Date) throws {
        try mutate(id) { $0.remove(songId, at: date) }
    }

    func reorder(_ id: Playlist.ID, to orderedSongIds: [String], at date: Date) throws {
        try mutate(id) { $0.reorder(to: orderedSongIds, at: date) }
    }

    // MARK: - Interne

    /// Applique `change` à la playlist désignée, puis publie.
    ///
    /// Privée, et prenant une closure non `Sendable` : c'est justement ce qui
    /// interdit de la faire traverser la frontière d'acteur depuis le dépôt.
    /// Les mutations sont donc exposées une par une, chacune recevant sa date —
    /// la même convention que [Playlist], où le modèle ne lit jamais l'horloge.
    ///
    /// Comme dans le dépôt en mémoire, c'est le modèle qui décide si quelque
    /// chose a réellement changé et s'il faut redater : le stockage se contente
    /// de retrouver l'entité, de recopier le résultat et de diffuser.
    private func mutate(_ id: Playlist.ID, _ change: (inout Playlist) -> Void) throws {
        guard let entity = try entity(id) else { throw PlaylistError.unknownPlaylist(id) }

        var playlist = entity.asPlaylist
        change(&playlist)
        entity.apply(playlist)

        try modelContext.save()
        publish()
    }

    private func entity(_ id: Playlist.ID) throws -> PlaylistEntity? {
        var descriptor = FetchDescriptor<PlaylistEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Le tri est fait en Swift plutôt que par le `FetchDescriptor` : les tris
    /// SwiftData s'appuient sur la comparaison du stockage, pas sur
    /// `localizedCaseInsensitiveCompare`. Le passer ici garantit le même ordre
    /// que le dépôt en mémoire, et que les albums et artistes.
    private func snapshot() throws -> [Playlist] {
        try modelContext.fetch(FetchDescriptor<PlaylistEntity>())
            .map(\.asPlaylist)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Publie l'état courant à tous les abonnés.
    ///
    /// Ne lève pas. La mutation qui l'appelle est déjà enregistrée : lui rendre
    /// une erreur de *lecture* lui ferait croire qu'elle a échoué, et un
    /// appelant qui rejoue une création déjà persistée en produirait une
    /// seconde. L'échec d'écriture, lui, reste remonté — `save()` lève avant
    /// qu'on arrive ici.
    ///
    /// Un instantané illisible est en revanche fatal pour les abonnés, qui
    /// n'ont plus rien de juste à afficher : leur flux se termine sur l'erreur,
    /// à charge de la couche au-dessus de se réabonner.
    private func publish() {
        do {
            let snapshot = try snapshot()
            for listener in continuations.values { listener.yield(snapshot) }
        } catch {
            // Les entrées ne sont pas retirées ici : `finish` déclenche
            // `onTermination`, donc `unsubscribe` viendra les retirer par le
            // chemin normal. Les retirer sur place les lui ferait manquer, et
            // il les prendrait pour des terminaisons arrivées avant leur
            // inscription. Un `yield` sur un flux terminé est sans effet.
            for listener in continuations.values { listener.finish(throwing: error) }
        }
    }
}
