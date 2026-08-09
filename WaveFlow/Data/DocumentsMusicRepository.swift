import Foundation

/// Bibliothèque adossée au dossier `Documents` de l'application.
///
/// Équivalent iOS du `MediaStoreMusicRepository` d'Android. Le `ContentObserver`
/// y est remplacé par une surveillance `DispatchSource` du dossier : iOS ne
/// notifie pas les changements de médias, seulement ceux du système de
/// fichiers.
nonisolated final class DocumentsMusicRepository: MusicRepository, @unchecked Sendable {

    private let root: URL
    private let artworkDirectory: URL

    /// Protège tout l'état mutable ci-dessous. Les appels arrivent du main
    /// actor (l'UI), de la file du `DispatchSource`, et des tâches de scan.
    private let lock = NSLock()

    private var continuations: [UUID: AsyncThrowingStream<[Song], Error>.Continuation] = [:]
    private var monitor: DispatchSourceFileSystemObject?
    private var scanning = false

    /// Un changement est arrivé pendant un scan : il faut recommencer une fois
    /// celui-ci terminé, sinon la modification passe à la trappe.
    private var rescanRequested = false

    init(root: URL = AppPaths.documents, artworkDirectory: URL = AppPaths.artworkCache) {
        self.root = root
        self.artworkDirectory = artworkDirectory
    }

    deinit { monitor?.cancel() }

    func songs() -> AsyncThrowingStream<[Song], Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()

            lock.withLock { continuations[id] = continuation }

            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.continuations[id] = nil }
            }

            startMonitoring()
            scheduleScan()
        }
    }

    func refresh() { scheduleScan() }

    // MARK: - Scan

    private func scheduleScan() {
        // Un scan qui tourne déjà est laissé finir, puis relancé. Deux scans
        // concurrents pourraient publier leurs résultats dans le désordre et
        // laisser le plus ancien avoir le dernier mot.
        let shouldStart = lock.withLock {
            if scanning {
                rescanRequested = true
                return false
            }
            scanning = true
            return true
        }
        guard shouldStart else { return }

        Task.detached(priority: .userInitiated) { [self] in
            let songs = await LibraryScanner.scan(root: root, artworkDirectory: artworkDirectory)

            let (listeners, again) = lock.withLock {
                scanning = false
                defer { rescanRequested = false }
                return (Array(continuations.values), rescanRequested)
            }

            for listener in listeners { listener.yield(songs) }
            if again { scheduleScan() }
        }
    }

    // MARK: - Surveillance du dossier

    private func startMonitoring() {
        lock.lock()
        defer { lock.unlock() }
        guard monitor == nil else { return }

        let descriptor = open(root.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility),
        )

        // Copier un album entier depuis l'app Fichiers déclenche un événement
        // par fichier : on attend que ça se calme avant de relire le dossier.
        source.setEventHandler { [weak self] in
            guard let self else { return }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + debounce) {
                self.scheduleScan()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()

        monitor = source
    }

    private let debounce: DispatchTimeInterval = .milliseconds(600)
}
