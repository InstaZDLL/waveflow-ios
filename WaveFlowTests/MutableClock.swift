import Foundation

/// Horloge réglable, pour observer un horodatage qu'on choisit plutôt que
/// l'heure qu'il est.
///
/// Partagée par les suites des deux dépôts de playlists : les horodatages sont
/// une garantie du contrat de `PlaylistRepository`, pas d'une implémentation,
/// et chacune doit pouvoir les vérifier.
final class MutableClock: @unchecked Sendable {

    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) { self.date = date }

    func set(_ date: Date) { lock.withLock { self.date = date } }

    var read: @Sendable () -> Date {
        { [self] in lock.withLock { date } }
    }
}
