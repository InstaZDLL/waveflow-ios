import Foundation

/// Regroupements dérivés de la bibliothèque.
///
/// Albums et artistes sont calculés à partir de la liste de morceaux plutôt
/// que lus d'une seconde source : la bibliothèque complète est déjà en mémoire
/// (elle sert de file de lecture), un second index n'apporterait qu'un état de
/// plus à tenir synchronisé.
///
/// Le tri est insensible à la casse, comme celui de la liste des morceaux.
nonisolated extension Array where Element == Song {

    func toAlbums() -> [Album] {
        Dictionary(grouping: self, by: \.albumId)
            .map { albumId, songs in
                let first = songs[0]
                return Album(
                    id: albumId,
                    title: first.displayAlbum,
                    // L'artiste du regroupement, pas le crédit complet de la
                    // première piste : la carte d'album afficherait sinon
                    // « NAYEON, Wonstein » selon l'ordre du scan.
                    artist: first.collectionArtist,
                    artworkURL: songs.lazy.compactMap(\.artworkURL).first,
                    trackCount: songs.count,
                    duration: songs.reduce(0) { $0 + $1.duration },
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func toArtists() -> [Artist] {
        Dictionary(grouping: self, by: \.artistId)
            .map { artistId, songs in
                Artist(
                    id: artistId,
                    name: songs[0].displayCollectionArtist,
                    albumCount: Set(songs.map(\.albumId)).count,
                    trackCount: songs.count,
                    artworkURL: songs.lazy.compactMap(\.artworkURL).first,
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
