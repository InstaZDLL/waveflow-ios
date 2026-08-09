import Foundation

/// Formate une durée en `m:ss` (ou `h:mm:ss` au-delà d'une heure).
///
/// `String(format:)` sans locale utilise la locale POSIX : ce sont des
/// chiffres et des deux-points, pas du texte à traduire, et certaines locales
/// substituent des chiffres non arabes.
nonisolated func formatDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite else { return "0:00" }

    let total = Int(max(seconds, 0))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60

    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%d:%02d", minutes, secs)
}

/// Durée cumulée d'une liste, en « 12 min » / « 1 h 04 » — pour les en-têtes
/// d'album et d'artiste, où la seconde près n'apporte rien.
nonisolated func formatTotalDuration(_ seconds: TimeInterval) -> String {
    let minutes = Int(max(seconds, 0)) / 60
    guard minutes >= 60 else { return "\(minutes) min" }
    return String(format: "%d h %02d", minutes / 60, minutes % 60)
}
