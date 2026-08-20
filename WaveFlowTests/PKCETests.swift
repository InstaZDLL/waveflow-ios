import Foundation
import Testing
@testable import WaveFlow

/// Le secret de l'échange Authorization Code.
///
/// - Note: exclue du harnais Linux, CryptoKit n'y existant pas.
struct PKCETests {

    /// Le vecteur d'essai de la RFC 7636, annexe B.
    ///
    /// Une valeur publiée plutôt qu'une de mon cru : un défi que je calculerais
    /// moi-même pour le comparer à lui-même ne prouverait que ma cohérence,
    /// pas ma conformité — et c'est le serveur qui tranche.
    @Test func matchesTheReferenceVector() {
        let pkce = PKCE(
            verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
            state: "peu importe",
        )

        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    /// Le serveur refuse un défi qui ne fait pas exactement 43 caractères :
    /// c'est la longueur d'une empreinte de 32 octets en base64url, et le
    /// remplissage la ferait dépasser.
    @Test func producesAChallengeTheServerWillAccept() {
        let pkce = PKCE()

        #expect(pkce.challenge.count == 43)
        #expect(pkce.challenge.contains("=") == false)
        #expect(pkce.challenge.contains("+") == false)
        #expect(pkce.challenge.contains("/") == false)
    }

    /// Le vérificateur doit tenir dans les bornes de la spécification, et
    /// l'état être imprévisible.
    @Test func drawsAFreshSecretEachTime() {
        let first = PKCE()
        let second = PKCE()

        #expect((43...128).contains(first.verifier.count))
        #expect(first.verifier != second.verifier)
        #expect(first.state != second.state)
    }
}
