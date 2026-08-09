import Foundation
import Testing
@testable import WaveFlow

/// Normalisation des tags — les helpers de `Song.swift` sur lesquels reposent
/// les identifiants de regroupement.
///
/// Sans équivalent Android, où le `MediaStore` fournit des identifiants tout
/// faits. Ici ils sont dérivés des tags, et les tags du monde réel sont sales :
/// c'est la première source de bugs du projet.
struct TagNormalizationTests {

    // MARK: - primaryArtist

    /// Le cas nominal : pas d'`albumArtist` (`aART`), tous les invités entassés
    /// dans `artist`. Sans découpe, chaque featuring ouvrirait son propre
    /// album.
    @Test func retientLArtistePrincipalDUnCreditMultiple() {
        #expect("NAYEON, Felix of Stray Kids".primaryArtist == "NAYEON")
        #expect("Artiste; Autre".primaryArtist == "Artiste")
    }

    @Test(arguments: [
        "Artiste feat. Autre",
        "Artiste feat Autre",
        "Artiste ft. Autre",
        "Artiste ft Autre",
        "Artiste featuring Autre",
        "Artiste with Autre",
    ])
    func reconnaitLesMarqueursDeFeaturing(_ credit: String) {
        #expect(credit.primaryArtist == "Artiste")
    }

    @Test func reconnaitLesMarqueursQuelleQueSoitLaCasse() {
        #expect("Artiste FEAT. Autre".primaryArtist == "Artiste")
        #expect("Artiste Featuring Autre".primaryArtist == "Artiste")
    }

    /// « & » et « / » appartiennent souvent au nom lui-même : les couper
    /// casserait plus d'albums qu'il n'en réunirait.
    @Test func neCoupePasLesNomsQuiContiennentUnSeparateurLegitime() {
        #expect("Simon & Garfunkel".primaryArtist == "Simon & Garfunkel")
        #expect("AC/DC".primaryArtist == "AC/DC")
        #expect("Earth, Wind & Fire".primaryArtist == "Earth")
    }

    /// Un crédit qui *commence* par un séparateur ne laisserait rien : mieux
    /// vaut le tag brut qu'une chaîne vide, qui fusionnerait tous ces morceaux
    /// sous un même artiste fantôme.
    @Test func renvoieLeTagBrutPlutotQuUneChaineVide() {
        #expect(", Autre".primaryArtist == ", Autre")
        #expect("feat. Autre".primaryArtist == "feat. Autre")
    }

    @Test func laisseIntactUnCreditSimple() {
        #expect("Björk".primaryArtist == "Björk")
    }

    // MARK: - groupingKey

    /// Deux graphies du même artiste doivent tomber sur la même clé, sans quoi
    /// la bibliothèque affiche deux entrées pour une seule personne.
    @Test func ignoreLaCasseEtLesAccents() {
        #expect("Björk".groupingKey == "bjork".groupingKey)
        #expect("NAYEON".groupingKey == "nayeon".groupingKey)
        #expect("Céline".groupingKey == "celine".groupingKey)
    }

    @Test func ignoreLesEspacesDeBordure() {
        #expect("  Artiste  ".groupingKey == "Artiste".groupingKey)
    }

    @Test func distingueDeuxArtistesDifferents() {
        #expect("Artiste".groupingKey != "Autre".groupingKey)
    }

    // MARK: - nonBlank

    /// Un tag présent mais vide ne vaut pas mieux qu'un tag absent — sinon les
    /// écrans afficheraient une ligne blanche au lieu du repli.
    @Test func traiteUnTagBlancCommeAbsent() {
        #expect("".nonBlank == nil)
        #expect("   ".nonBlank == nil)
        #expect("\n\t".nonBlank == nil)
    }

    @Test func rogneLesEspacesDUnTagRenseigne() {
        #expect("  Artiste ".nonBlank == "Artiste")
    }

    @Test func replieSurArtisteInconnu() {
        let absent: String? = nil
        #expect(absent.orUnknownArtist == "Artiste inconnu")
        #expect(String?("  ").orUnknownArtist == "Artiste inconnu")
        #expect(String?("Artiste").orUnknownArtist == "Artiste")
    }
}
