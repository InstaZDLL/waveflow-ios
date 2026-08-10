import Foundation

/// Recherche dans la bibliothèque déjà chargée.
///
/// Tout se fait en mémoire, contre le `Library` du store partagé : aucun scan
/// supplémentaire du dossier `Documents`, et les résultats suivent d'eux-mêmes
/// un rechargement de la bibliothèque.

/// Résultats groupés par type, dans l'ordre où l'écran les présente.
nonisolated struct SearchResults: Sendable {

    var songs: [Song] = []
    var albums: [Album] = []
    var artists: [Artist] = []

    var isEmpty: Bool { songs.isEmpty && albums.isEmpty && artists.isEmpty }
}

nonisolated extension Library {

    /// Filtre la bibliothèque sur `query`.
    ///
    /// Une requête vide ne renvoie rien plutôt que tout : l'écran affiche
    /// alors son invite, il n'a pas à recopier l'onglet Titres.
    ///
    /// Un morceau ressort par son titre, son artiste ou son album, pour que
    /// chercher « nuit » trouve aussi les pistes de l'album Nuit.
    func search(_ query: String) -> SearchResults {
        let key = query.groupingKey
        guard !key.isEmpty else { return SearchResults() }

        return SearchResults(
            songs: songs.ranked(matching: key) { [$0.title, $0.displayArtist, $0.displayAlbum] },
            albums: albums.ranked(matching: key) { [$0.title, $0.displayArtist] },
            artists: artists.ranked(matching: key) { [$0.name] },
        )
    }
}

nonisolated private extension Array {

    /// Garde les éléments dont l'un des `fields` contient `key`, les préfixes
    /// d'abord.
    ///
    /// `sorted(by:)` n'est pas stable en Swift, contrairement au `sortedBy` de
    /// Kotlin dont vient ce code : l'indice d'origine sert donc de second
    /// critère explicite, sans quoi deux éléments de même rang pourraient
    /// permuter et l'ordre alphabétique de la bibliothèque serait perdu.
    func ranked(matching key: String, fields: (Element) -> [String]) -> [Element] {
        enumerated()
            .compactMap { index, element -> (element: Element, rank: Int, index: Int)? in
                guard let rank = fields(element).compactMap({ $0.matchRank(key) }).min() else { return nil }
                return (element, rank, index)
            }
            .sorted { $0.rank == $1.rank ? $0.index < $1.index : $0.rank < $1.rank }
            .map(\.element)
    }
}

nonisolated private extension String {

    /// Rang de correspondance du texte face à `key`, `nil` s'il n'y en a
    /// aucune. Un préfixe est un meilleur résultat qu'une occurrence au milieu
    /// du texte.
    ///
    /// La comparaison passe par `groupingKey`, la même forme repliée que celle
    /// des identifiants de regroupement : chercher « bjork » doit trouver
    /// l'artiste que le scanner a rangé sous cette clé, accent compris.
    func matchRank(_ key: String) -> Int? {
        let text = groupingKey

        if text.hasPrefix(key) { return 0 }
        if text.contains(key) { return 1 }
        return nil
    }
}
