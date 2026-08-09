import Foundation

/// Libellé de comptage de morceaux, partagé par les écrans de navigation.
nonisolated func trackCountLabel(_ count: Int) -> String {
    count <= 1 ? "\(count) titre" : "\(count) titres"
}

/// Libellé de comptage d'albums, affiché sous un artiste.
nonisolated func albumCountLabel(_ count: Int) -> String {
    count <= 1 ? "\(count) album" : "\(count) albums"
}
