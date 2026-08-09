import Foundation

/// Un artiste, tel que déduit des morceaux de la bibliothèque.
nonisolated struct Artist: Identifiable, Hashable, Sendable {

    let id: String

    let name: String

    let albumCount: Int

    let trackCount: Int

    /// Pochette d'un de ses albums, faute d'image d'artiste dans les tags.
    let artworkURL: URL?
}
