import Foundation
import Testing
@testable import WaveFlow

/// Portage de `SearchTest` (Android).
///
/// La recherche ne lit que la bibliothèque déjà en mémoire : les fixtures
/// posent donc des morceaux, et les albums comme les artistes sont ceux que
/// `Library` en dérive — c'est bien le filtrage qui est testé, pas le
/// regroupement, couvert par `GroupingTests`.
struct SearchTests {

    /// Le morceau dont le titre ne contient « nuit » qu'au milieu vient en
    /// premier dans la bibliothèque : c'est ce qui rend le classement par
    /// préfixe observable, plutôt que confondu avec l'ordre d'origine.
    private var library: Library {
        Library(
            isLoading: false,
            songs: [
                song(id: "3", title: "Blanche nuit", artist: "Alba", album: "Mer"),
                song(id: "1", title: "Nuit blanche", artist: "Zoé Blanc", album: "Été"),
                song(id: "2", title: "Aube", artist: "Alba", album: "Nuit"),
            ],
        )
    }

    @Test func uneRequeteVideNeRenvoieRienPlutotQueTout() {
        #expect(library.search("").isEmpty)
    }

    @Test func uneRequeteFaiteDEspacesNeRenvoieRien() {
        #expect(library.search("   ").isEmpty)
    }

    @Test func unMorceauRessortParSonTitre() {
        #expect(library.search("aube").songs.map(\.id) == ["2"])
    }

    @Test func unMorceauRessortParSonAlbum() {
        // Le morceau 2 s'appelle « Aube » : seul son album porte « nuit ».
        #expect(library.search("nuit").songs.map(\.id).contains("2"))
    }

    @Test func unMorceauRessortParSonArtiste() {
        #expect(library.search("zoé").songs.map(\.id) == ["1"])
    }

    @Test func laRechercheIgnoreLesAccentsEtLaCasse() {
        // La requête doit dépasser l'accent : « zoe » seul correspondrait déjà
        // au préfixe de « zoé » sans qu'aucun accent ait été retiré, et le
        // test passerait pour la mauvaise raison.
        #expect(library.search("ZOE BLANC").songs.map(\.id) == ["1"])
    }

    @Test func uneRequeteAccentueeTrouveUnTexteSansAccent() {
        let sansAccent = Library(isLoading: false, songs: [song(id: "1", title: "Ete")])

        #expect(sansAccent.search("été").songs.map(\.id) == ["1"])
    }

    @Test func lesPrefixesPassentDevantLesOccurrencesAuMilieuDuTexte() {
        // 1 « Nuit blanche » et 2 (album « Nuit ») commencent par la requête ;
        // 3 « Blanche nuit » ne la contient qu'au milieu, et passe donc après
        // alors qu'il ouvre la bibliothèque.
        #expect(library.search("nuit").songs.map(\.id) == ["1", "2", "3"])
    }

    @Test func albumsEtArtistesSontFiltresEuxAussi() {
        let results = library.search("alba")

        #expect(results.artists.map(\.name) == ["Alba"])
        // Un album ressort aussi par son artiste : ce sont les deux d'Alba,
        // dans l'ordre alphabétique de la bibliothèque.
        #expect(results.albums.map(\.title) == ["Mer", "Nuit"])
    }

    @Test func uneRequeteSansCorrespondanceNeRenvoieAucuneSection() {
        #expect(library.search("xylophone").isEmpty)
    }

    /// Propre au portage iOS : un fichier sans tag n'est pas écarté de la
    /// recherche, il se cherche sous le libellé de repli que les listes
    /// affichent déjà.
    @Test func unMorceauSansTagSeTrouveSousSonLibelleDeRepli() {
        let sansTags = Library(
            isLoading: false,
            songs: [song(id: "1", title: "Piste 1", artist: nil, album: nil)],
        )

        #expect(sansTags.search("artiste inconnu").songs.map(\.id) == ["1"])
        #expect(sansTags.search("album inconnu").songs.map(\.id) == ["1"])
    }

    // MARK: - Fixture

    /// Les identifiants de regroupement sont dérivés des tags comme le fait le
    /// scanner : les albums et artistes que `Library` construit doivent se
    /// séparer d'eux-mêmes, sinon les deux titres d'Alba tomberaient dans le
    /// même album et le filtrage n'aurait rien à classer.
    private func song(
        id: String,
        title: String,
        artist: String? = "Artiste",
        album: String? = "Album",
    ) -> Song {
        Song(
            id: id,
            url: URL(fileURLWithPath: "/tmp/\(id)"),
            title: title,
            artist: artist,
            artistId: artist?.primaryArtist.groupingKey ?? "",
            album: album,
            albumId: "\(album?.groupingKey ?? "")|\(artist?.primaryArtist.groupingKey ?? "")",
            collectionArtist: artist?.primaryArtist,
            duration: 0,
            artworkURL: nil,
        )
    }
}
