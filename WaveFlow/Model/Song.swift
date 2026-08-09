import Foundation

/// Un morceau audio, indépendant de sa provenance (fichiers importés
/// aujourd'hui, serveur WaveFlow demain).
///
/// - Note: là où Android reçoit du `MediaStore` des identifiants numériques
///   pour le morceau, l'album et l'artiste, iOS ne fournit rien de tel : on ne
///   dispose que d'un fichier et de ses tags. Les identifiants sont donc
///   dérivés — le chemin pour le morceau, les tags normalisés pour les
///   regroupements.
nonisolated struct Song: Identifiable, Hashable, Sendable {

    /// Chemin relatif au dossier `Documents`. Stable tant que le fichier n'est
    /// pas déplacé, contrairement à l'URL absolue : le conteneur de l'app
    /// change d'UUID à chaque réinstallation.
    let id: String

    /// URL du fichier, passée telle quelle à `AVPlayer`.
    let url: URL

    /// Titre affiché — retombe sur le nom de fichier si le tag manque.
    let title: String

    let artist: String?

    /// Clé de regroupement par artiste, dérivée du tag normalisé.
    let artistId: String

    let album: String?

    /// Clé de regroupement par album. Combine le titre de l'album *et*
    /// [collectionArtist] : deux « Greatest Hits » d'artistes différents ne
    /// doivent pas fusionner.
    let albumId: String

    /// Artiste retenu pour les regroupements — le tag `albumArtist` s'il
    /// existe, sinon l'artiste principal déduit de [artist].
    ///
    /// Distinct de [artist], qui reste le crédit complet affiché sur la ligne
    /// du morceau : « NO PROBLEM » se crédite « NAYEON, Felix of Stray Kids »
    /// mais appartient bien à l'album de NAYEON.
    let collectionArtist: String?

    /// Durée en secondes (0 si indéterminable).
    let duration: TimeInterval

    /// Pochette extraite du fichier et mise en cache sur disque, `nil` si le
    /// fichier n'en embarque pas.
    let artworkURL: URL?

    var displayArtist: String { artist.orUnknownArtist }

    var displayCollectionArtist: String { collectionArtist.orUnknownArtist }

    var displayAlbum: String { album?.nonBlank ?? "Album inconnu" }
}

nonisolated extension Optional where Wrapped == String {
    /// Nom d'artiste affichable, quand le tag est absent ou vide.
    var orUnknownArtist: String { self?.nonBlank ?? "Artiste inconnu" }
}

nonisolated extension String {
    /// `nil` plutôt qu'une chaîne blanche : un tag présent mais vide ne vaut
    /// pas mieux qu'un tag absent.
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Clé de regroupement insensible à la casse et aux accents : « Björk » et
    /// « bjork » désignent le même artiste.
    var groupingKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Artiste principal d'un crédit qui en mentionne plusieurs.
    ///
    /// Beaucoup de fichiers m4a n'ont pas de tag `albumArtist` (`aART`) et
    /// entassent tous les invités dans `artist` : « NAYEON, Felix of Stray
    /// Kids ». Sans découpe, chaque featuring devient un artiste — et un
    /// album — de plus, et un EP se retrouve éclaté en trois.
    ///
    /// On ne coupe que sur la virgule, le point-virgule et les marqueurs de
    /// featuring. Pas sur « & » ni « / », qui appartiennent souvent au nom
    /// lui-même : Simon & Garfunkel, AC/DC.
    var primaryArtist: String {
        let separators = [",", ";", " feat.", " feat ", " ft.", " ft ", " featuring ", " with "]

        var trimmed = self
        for separator in separators {
            if let range = trimmed.range(of: separator, options: .caseInsensitive) {
                trimmed = String(trimmed[..<range.lowerBound])
            }
        }

        // Un crédit qui *commence* par un séparateur ne laisserait rien :
        // mieux vaut le tag brut qu'une chaîne vide.
        return trimmed.nonBlank ?? self
    }
}
