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

    /// Change dès que la connexion cesse d'être celle qu'elle était :
    /// déconnexion, refus définitif, ou connexion à un autre serveur. Un
    /// rafraîchissement n'y touche pas — il prolonge la même connexion.
    ///
    /// Comparer la connexion elle-même ne suffirait pas : celui qui rejoint un
    /// rafraîchissement en cours la retrouve remplacée par sa version
    /// rafraîchie, qu'il n'a pourtant aucune raison de refuser.
    private var generation = 0

    /// Change à chaque tentative de connexion ouverte, abandonnée ou terminée.
    /// Un échange qui aboutit après coup n'a plus rien à installer.
    private var signInAttempt = 0

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
        signInAttempt += 1
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

        // L'échange peut durer, et la tentative être abandonnée entre-temps —
        // ou remplacée par une autre. Ce qui en revient alors n'a plus à
        // s'installer, ni même à se plaindre : le message porterait sur une
        // tentative que l'utilisateur a déjà quittée.
        let attempt = signInAttempt

        do {
            let session = try await makeClient(pending.address).exchange(code: code, with: pending.pkce)
            guard attempt == signInAttempt else { return }
            try persist(StoredConnection(address: pending.address, session: session))
        } catch {
            guard attempt == signInAttempt else { return }
            failure = Self.message(for: error)
        }
    }

    /// Abandonne un échange commencé — navigateur refermé, connexion annulée.
    func cancelSignIn() {
        pending = nil
        signInAttempt += 1
    }

    // MARK: - Déconnexion

    /// Révoque la session et l'oublie.
    ///
    /// L'oubli local ne dépend pas de la réponse du serveur : l'utilisateur a
    /// demandé que cet appareil n'ait plus accès, et lui laisser des jetons
    /// parce que le réseau manquait serait le contraire.
    func signOut() async {
        guard let connection else { return }
        self.connection = nil
        generation += 1
        signInAttempt += 1
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

        let generation = self.generation

        // Celui qui rejoint passe la même garde que celui qui a lancé : sans
        // elle, une déconnexion survenue pendant l'attente le laisserait
        // repartir avec des jetons dont plus personne ne veut.
        if let refreshing {
            let session = try await refreshing.value
            return try stillCurrent(session, from: generation)
        }

        let task = Task { [makeClient, connection] in
            try await makeClient(connection.address).refresh(connection.session)
        }
        refreshing = task
        // Seulement si c'est encore la nôtre : une déconnexion suivie d'une
        // reconnexion peut en avoir lancé une autre pendant l'attente, et
        // l'effacer laisserait le prochain appelant en démarrer une troisième
        // — deux rafraîchissements concurrents sur un jeton qui tourne.
        defer { if refreshing == task { refreshing = nil } }

        do {
            // La connexion a pu changer pendant l'attente — déconnexion, ou
            // connexion à un autre serveur. Réinstaller la session ici la
            // ressusciterait dans le premier cas, et dans le second poserait
            // les jetons d'un serveur sous l'adresse d'un autre.
            let session = try stillCurrent(await task.value, from: generation)

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
            if self.generation == generation {
                self.connection = nil
                self.generation += 1
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
        generation += 1
    }

    /// Rend la session si la connexion qu'elle prolonge est encore celle de
    /// l'application, et abandonne sinon.
    ///
    /// L'échec est une annulation et non un refus : le serveur n'a rien
    /// refusé, c'est l'état local qui est passé à autre chose.
    private func stillCurrent(_ session: ServerSession, from generation: Int) throws -> ServerSession {
        guard self.generation == generation else { throw CancellationError() }
        return session
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
