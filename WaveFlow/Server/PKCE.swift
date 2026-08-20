import CryptoKit
import Foundation

/// Le secret d'un échange Authorization Code + PKCE.
///
/// L'application ne voit jamais le mot de passe : l'utilisateur s'authentifie
/// dans le navigateur système, et l'application ne récupère qu'un code, sans
/// valeur sans le vérificateur qu'elle a gardé pour elle.
///
/// `state` accompagne le vérificateur parce qu'il joue le même rôle à l'autre
/// bout : la redirection le rapporte, et une valeur qui ne correspond pas
/// signale une réponse qu'on n'a pas demandée.
nonisolated struct PKCE: Sendable {

    /// 32 octets tirés au sort, en base64url : 43 caractères, le minimum que la
    /// spécification autorise et ce que le serveur attend d'un défi S256.
    let verifier: String

    let state: String

    /// `base64url(sha256(verifier))`, sans remplissage. Seul S256 est accepté ;
    /// `plain` ne protège de rien quand le défi est observable, ce qui est
    /// exactement la menace que PKCE existe pour fermer.
    var challenge: String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    init() {
        verifier = Self.randomToken()
        state = Self.randomToken()
    }

    /// Pour les tests, qui ont besoin de valeurs connues.
    init(verifier: String, state: String) {
        self.verifier = verifier
        self.state = state
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        // `SystemRandomNumberGenerator` puise à la même source que
        // `SecRandomCopyBytes` sans en ramener le code d'erreur.
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64URLEncodedString()
    }
}

nonisolated extension Data {

    /// Base64 pour URL : `+` et `/` remplacés, remplissage retiré.
    ///
    /// C'est la forme qu'exige PKCE, et le serveur refuse un défi qui n'a pas
    /// Encodes the data as an unpadded Base64URL string.
    /// - Returns: The Base64URL-encoded string.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
