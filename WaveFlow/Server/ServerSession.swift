import Foundation

/// Une session ouverte sur un serveur WaveFlow.
///
/// Le jeton d'accès est court — un quart d'heure par défaut — et le jeton de
/// rafraîchissement **tourne** : chaque rafraîchissement en rend un nouveau et
/// invalide l'ancien. D'où une valeur unique plutôt que deux champs séparés :
/// remplacer la paire d'un bloc est la seule façon de ne jamais garder un
/// jeton d'accès neuf à côté d'un jeton de rafraîchissement déjà consommé.
///
/// - Important: cette valeur est `Codable` pour aller **au trousseau**, et pour
///   rien d'autre. Ni `UserDefaults`, ni fichier, ni journal : le jeton de
///   rafraîchissement ouvre des sessions jusqu'à sa révocation, et une
///   sauvegarde d'appareil non chiffrée l'emporterait avec elle. `Codable`
///   n'interdit rien tout seul — c'est écrit ici parce que rien d'autre ne le
///   dira au moment de choisir où l'écrire.
nonisolated struct ServerSession: Hashable, Sendable, Codable {

    let accessToken: String
    let refreshToken: String

    /// Fin de validité du jeton d'accès, calculée à la réception.
    ///
    /// Le serveur rend une durée ; on la date tout de suite, parce qu'une durée
    /// stockée telle quelle ne veut plus rien dire au démarrage suivant.
    let expiresAt: Date

    /// L'appareil créé par cette session. Voyage en `X-WaveFlow-Device-Id` sur
    /// les écritures, et sert à acquitter le curseur de synchronisation.
    let deviceId: UUID

    let userId: UUID
    let username: String

    /// Vrai quand le jeton d'accès est expiré, ou sur le point de l'être.
    ///
    /// La marge couvre le trajet de la requête : un jeton valable encore deux
    /// secondes au moment du test peut arriver périmé, et le 401 qui s'ensuit
    /// coûte un aller-retour de plus que de l'avoir rafraîchi d'emblée.
    func isExpired(at date: Date, margin: TimeInterval = 30) -> Bool {
        date.addingTimeInterval(margin) >= expiresAt
    }
}

/// La réponse d'authentification du serveur, telle qu'elle arrive.
///
/// Distincte de [ServerSession] : celle-ci porte une durée relative, et des
/// champs que l'application ignore. Les décoder ici plutôt que de faire porter
/// à la session un `expires_in` qu'elle devrait redater elle-même.
nonisolated struct AuthTokensPayload: Decodable, Sendable {

    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let deviceId: UUID
    let user: User

    struct User: Decodable, Sendable {
        let id: UUID
        let username: String
    }

    /// Date la durée reçue et laisse tomber le reste.
    func session(receivedAt now: Date) -> ServerSession {
        ServerSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(expiresIn),
            deviceId: deviceId,
            userId: user.id,
            username: user.username,
        )
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case deviceId = "device_id"
        case user
    }
}
