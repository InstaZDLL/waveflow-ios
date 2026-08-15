import Foundation

/// Horloge réglable, pour observer un horodatage qu'on choisit plutôt que
/// l'heure qu'il est.
///
/// Partagée par les suites des deux dépôts de playlists : les horodatages sont
/// une garantie du contrat de `PlaylistRepository`, pas d'une implémentation,
/// et chacune doit pouvoir les vérifier.
/// `nonisolated` : une horloge se lit depuis n'importe quel contexte, et la
/// cible de tests est isolée au main actor par défaut comme celle de l'app.
/// Son propre verrou la protège.
nonisolated final class MutableClock: @unchecked Sendable {

    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) { self.date = date }

    func set(_ date: Date) { lock.withLock { self.date = date } }

    var read: @Sendable () -> Date {
        { [self] in lock.withLock { date } }
    }
}
