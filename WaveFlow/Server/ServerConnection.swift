import Foundation
import Observation

/// La connexion au serveur WaveFlow : ce que l'application en sait, et ce
/// qu'elle sait en faire.
///
/// Porté au niveau de l'application comme les autres stores : le catalogue
/// distant, la lecture en flux et la synchronisation liront tous la même
/// session, et chacun ouvrant la sienne multiplierait les rafraîchissements
/// concurrents d'un jeton que le serveur fait tourner.
///
/// Il ne connaît ni `ASWebAuthenticationSession` ni la moindre vue : il rend
/// l'adresse à ouvrir et lit le retour. C'est ce qui le rend vérifiable sans
/// navigateur.
@Observable
@MainActor
final class ServerConnection {

    /// La connexion en cours, si elle existe.
    private(set) var connection: StoredConnection?

    /// Dernier échec de connexion, à montrer une fois puis à oublier.
    private(set) var failure: String?

    var isConnected: Bool { connection != nil }

    /// Le secret de l'échange en cours. Retenu entre l'ouverture du navigateur
    /// et le retour de la redirection, et jamais au-delà.
    private var pending: (pkce: PKCE, address: ServerAddress)?

    /// Rafraîchissement en vol. Voir [validSession].
    private var refreshing: Task<ServerSession, Error>?

    private let storage: SessionStorage
    private let makeClient: @Sendable (ServerAddress) -> AuthClient
    private let now: @Sendable () -> Date

    init(
        storage: SessionStorage = KeychainSessionStorage(),
        now: @escaping @Sendable () -> Date = { Date() },
        makeClient: @escaping @Sendable (ServerAddress) -> AuthClient = { AuthClient(server: $0) },
    ) {
        self.storage = storage
        self.now = now
        self.makeClient = makeClient
    }

    // MARK: - Reprise

    /// Relit la connexion enregistrée. Idempotent.
    ///
    /// Un stockage illisible laisse l'application démarrer déconnectée plutôt
    /// que de la faire tomber : la musique locale n'a que faire du serveur, et
    /// se reconnecter reste possible.
    func restore() {
        guard connection == nil else { return }
        connection = try? storage.load()
    }

    func dismissFailure() { failure = nil }

    // MARK: - Connexion

    /// Prépare un échange et rend l'adresse à ouvrir dans le navigateur.
    ///
    /// Chaque appel tire un secret neuf : rouvrir le navigateur après un
    /// abandon ne doit pas rejouer l'état de la tentative précédente, qu'une
    /// redirection tardive pourrait encore rapporter.
    func beginSignIn(to address: ServerAddress, deviceName: String) -> URL {
        let pkce = PKCE()
        pending = (pkce, address)
        failure = nil

        return makeClient(address).authorizationURL(for: pkce, deviceName: deviceName)
    }

    /// Termine l'échange à partir de la redirection.
    ///
    /// Le code est consommé par cette requête, réussie ou non : en cas
    /// d'échec, il faut relancer l'autorisation, jamais rejouer le même code.
    /// D'où l'abandon du secret dès l'entrée.
    func completeSignIn(callback: URL) async {
        guard let pending else {
            failure = "Aucune connexion n'était en cours."
            return
        }
        self.pending = nil

        guard let code = AuthClient.authorizationCode(from: callback, matching: pending.pkce) else {
            failure = "La réponse du serveur ne correspond pas à la demande."
            return
        }

        do {
            let session = try await makeClient(pending.address).exchange(code: code, with: pending.pkce)
            try persist(StoredConnection(address: pending.address, session: session))
        } catch {
            failure = Self.message(for: error)
        }
    }

    /// Abandonne un échange commencé — navigateur refermé, connexion annulée.
    func cancelSignIn() { pending = nil }

    // MARK: - Déconnexion

    /// Révoque la session et l'oublie.
    ///
    /// L'oubli local ne dépend pas de la réponse du serveur : l'utilisateur a
    /// demandé que cet appareil n'ait plus accès, et lui laisser des jetons
    /// parce que le réseau manquait serait le contraire.
    func signOut() async {
        guard let connection else { return }
        self.connection = nil
        refreshing?.cancel()
        refreshing = nil
        try? storage.clear()

        await makeClient(connection.address).logout(connection.session)
    }

    // MARK: - Usage

    /// Une session utilisable, rafraîchie si besoin.
    ///
    /// Un seul rafraîchissement en vol : le jeton **tourne**, donc deux appels
    /// concurrents en échangeraient deux et le second invaliderait le premier.
    /// Les appelants qui arrivent pendant celui qui court attendent son
    /// résultat au lieu d'en lancer un autre.
    func validSession() async throws -> ServerSession {
        guard let connection else { throw ServerError.unauthorized }
        guard connection.session.isExpired(at: now()) else { return connection.session }

        if let refreshing { return try await refreshing.value }

        let task = Task { [makeClient, connection] in
            try await makeClient(connection.address).refresh(connection.session)
        }
        refreshing = task
        defer { refreshing = nil }

        do {
            let session = try await task.value

            // Une déconnexion a pu passer pendant l'attente. Réinstaller la
            // session ici la ressusciterait — et réécrirait au trousseau des
            // jetons que l'utilisateur vient de demander d'oublier.
            //
            // Défensif faute de pouvoir être éprouvé : quand la déconnexion
            // arrive assez tôt, elle annule la tâche et l'on n'atteint jamais
            // cette ligne. Elle ne compte que si la requête s'est terminée
            // avant, sa reprise attendant derrière la déconnexion — un
            // entrelacement qu'aucun test ne sait ordonner.
            //
            // L'échec est une annulation et non un refus : le serveur n'a rien
            // refusé, c'est l'état local qui est passé à autre chose.
            guard self.connection == connection else {
                throw CancellationError()
            }

            let refreshed = StoredConnection(address: connection.address, session: session)
            self.connection = refreshed

            // L'enregistrement passe après, et son échec ne fait pas échouer
            // l'appel — contrairement à la connexion initiale. À ce stade
            // l'ancien jeton de rafraîchissement est déjà consommé : refuser le
            // nouveau parce que le trousseau n'a pas voulu de lui laisserait
            // une session morte en mémoire, et le prochain appel se ferait
            // refuser pour de bon. Au pire la connexion ne survivra pas au
            // prochain démarrage.
            try? storage.save(refreshed)

            return session
        } catch ServerError.unauthorized {
            // Le jeton de rafraîchissement est mort — révoqué, ou déjà échangé.
            // Rien ne le ranimera : garder la connexion ferait boucler chaque
            // appel sur le même refus.
            //
            // À condition que le refus porte encore sur la connexion courante :
            // se déconnecter puis se reconnecter pendant l'attente ferait
            // autrement effacer la nouvelle session sur un refus adressé à
            // l'ancienne.
            if self.connection == connection {
                self.connection = nil
                try? storage.clear()
            }
            throw ServerError.unauthorized
        }
    }

    // MARK: - Interne

    /// Retient une connexion neuve, sur disque puis en mémoire.
    ///
    /// L'écriture d'abord : à la connexion, un trousseau qui refuse doit se
    /// dire tout de suite plutôt que de laisser une session qui aura disparu au
    /// prochain démarrage sans que personne ne sache pourquoi. Rien n'est perdu
    /// à recommencer — le raisonnement s'inverse au rafraîchissement, où
    /// l'ancien jeton est déjà dépensé ; voir [validSession].
    private func persist(_ connection: StoredConnection) throws {
        try storage.save(connection)
        self.connection = connection
    }

    private static func message(for error: Error) -> String {
        switch error {
        case ServerError.unauthorized:
            "Le serveur a refusé la connexion."
        case ServerError.notFound:
            "Ce serveur ne propose pas WaveFlow à cette adresse."
        case let error as ServerError where error.isRetriable:
            "Le serveur n'est pas disponible. Réessaie dans un instant."
        case is KeychainError:
            "La connexion n'a pas pu être enregistrée sur cet appareil."
        default:
            "La connexion a échoué."
        }
    }
}
