import Foundation

/// Une réponse d'erreur de l'API, lue selon les règles du contrat.
///
/// Le guide insiste sur un point : **ne jamais brancher sur le statut 409
/// seul**. Il porte deux codes qui demandent des reprises opposées —
/// `conflict` veut un nouvel identifiant d'opération, `cursor_expired` veut
/// jeter la projection locale et repartir d'un instantané complet. Réagir à
/// l'un comme à l'autre perd une écriture ou efface un état sain.
///
/// D'où ce type : la distinction est faite une fois, à la lecture de la
/// réponse, et aucun appelant n'a l'occasion de l'oublier.
nonisolated enum ServerError: Error, Equatable {

    /// 401 — se réauthentifier. Ne jamais en déduire qu'un compte existe.
    case unauthorized

    /// 403 — s'arrêter, ou demander le rôle manquant.
    case forbidden

    /// 404 — la ressource est absente **ou** inaccessible. Le serveur ne
    /// distingue pas les deux, pour ne pas révéler ce qu'on n'a pas le droit
    /// de voir.
    case notFound

    /// 409 `conflict` — l'identifiant d'opération a servi à autre chose.
    case operationConflict

    /// 409 `cursor_expired` — la projection locale est à jeter.
    case cursorExpired

    /// 422 — la requête est fautive ; la rejouer telle quelle ne peut pas
    /// aboutir.
    case validation(message: String?)

    /// 429 — limite de transcodage atteinte.
    case rateLimited

    /// 503 — réessayer avec un délai exponentiel borné.
    case unavailable

    /// Tout le reste, y compris un 409 portant un code inconnu : le contrat
    /// dit d'ignorer ce qu'on ne sait pas lire, pas de le deviner.
    case unexpected(status: Int, code: String?)

    /// Lit le statut et, quand il en faut un, le code du corps.
    ///
    /// `body` est le corps brut plutôt qu'un code déjà extrait : seul 409 en a
    /// Classifies an HTTP response as a server error.
    /// - Parameters:
    ///   - status: The HTTP status code.
    ///   - body: The response body containing optional error details.
    /// - Returns: The corresponding `ServerError`, or `nil` for successful 2xx responses.
    static func from(status: Int, body: Data) -> ServerError? {
        guard !(200..<300).contains(status) else { return nil }

        let payload = try? JSONDecoder().decode(Payload.self, from: body)

        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 409:
            switch payload?.code {
            case "conflict": return .operationConflict
            case "cursor_expired": return .cursorExpired
            case let code: return .unexpected(status: status, code: code)
            }
        case 422: return .validation(message: payload?.message)
        case 429: return .rateLimited
        case 503: return .unavailable
        default: return .unexpected(status: status, code: payload?.code)
        }
    }

    /// Vrai quand rejouer la même requête peut aboutir.
    ///
    /// Ni `validation` ni `operationConflict` n'en sont : la première est
    /// fautive, la seconde exige un identifiant d'opération neuf — donc une
    /// autre requête, pas la même.
    ///
    /// 502 et 504 s'y ajoutent bien qu'absents du contrat, et c'est justement
    /// pourquoi : l'API native n'a aucun moyen de les produire — son type
    /// d'erreur ne connaît que les sept statuts documentés, et « réessayer
    /// plus tard » s'y dit 503. Les recevoir signifie qu'un intermédiaire a
    /// répondu à la place du serveur, sans l'avoir joint ou sans l'avoir
    /// attendu assez. C'est transitoire par nature.
    ///
    /// 500 n'y est pas, pour la même raison lue à l'envers : il ne peut venir
    /// que d'une panne que le serveur n'a pas su nommer, et la rejouer telle
    /// quelle la reproduit.
    var isRetriable: Bool {
        switch self {
        case .rateLimited, .unavailable: true
        case .unexpected(let status, _): status == 502 || status == 504
        default: false
        }
    }

    private struct Payload: Decodable {
        let code: String?
        let message: String?
    }
}
