import Foundation

/// Un album, tel que déduit des morceaux de la bibliothèque.
nonisolated struct Album: Identifiable, Hashable, Sendable {

    let id: String

    let title: String

    /// Artiste principal — celui du premier morceau ; les compilations
    /// afficheront donc l'artiste de leur première piste.
    let artist: String?

    let artworkURL: URL?

    /// Nombre de morceaux présents sur l'appareil, pas le nombre de pistes de
    /// l'album original.
    let trackCount: Int

    let duration: TimeInterval

    var displayArtist: String { artist.orUnknownArtist }
}
