import Foundation
import Testing
@testable import WaveFlow

/// La connexion au serveur : sa reprise, son ouverture, son rafraîchissement.
///
/// - Note: exclue du harnais Linux — elle passe par CryptoKit et par
///   l'interception d'`URLProtocol`.
struct ServerConnectionTests {

    private let address = ServerAddress("https://music.example.com")!

    // MARK: - Reprise

    @Test func restoresTheStoredConnection() {
        let storage = InMemorySessionStorage(stored())
        let connection = make(storage: storage)

        connection.restore()

        #expect(connection.isConnected)
        #expect(connection.connection?.session.username == "listener")
    }

    /// Un trousseau illisible laisse démarrer déconnecté : la musique locale
    /// n'a que faire du serveur, et se reconnecter reste possible.
    @Test func startsDisconnectedWhenStorageCannotBeRead() {
        let connection = make(storage: InMemorySessionStorage(failing: KeychainError(status: -25300)))

        connection.restore()

        #expect(connection.isConnected == false)
    }

    // MARK: - Ouverture

    @Test func opensTheAuthorizationPageWithAFreshSecretEachTime() {
        let connection = make()

        let first = connection.beginSignIn(to: address, deviceName: "iPhone")
        let second = connection.beginSignIn(to: address, deviceName: "iPhone")

        #expect(first.path() == "/authorize")
        // Rouvrir le navigateur après un abandon ne doit pas rejouer l'état de
        // la tentative précédente, qu'une redirection tardive rapporterait.
        #expect(first.query() != second.query())
    }

    @Test func exchangesTheCodeAndKeepsTheConnection() async throws {
        let stub = StubServer()
        stub.respond(status: 200, body: Self.tokens)
        let storage = InMemorySessionStorage()
        let connection = make(storage: storage, stub: stub)

        let state = try #require(stateParameter(of: connection.beginSignIn(to: address, deviceName: "iPhone")))
        await connection.completeSignIn(callback: callback(code: "un-code", state: state))

        #expect(connection.connection?.session.accessToken == "wfa_abc")
        #expect(connection.connection?.address == address)
        #expect(connection.failure == nil)
        // Enregistrée, pas seulement affichée : sinon elle disparaîtrait au
        // prochain démarrage sans que personne ne sache pourquoi.
        #expect(try storage.load()?.session.accessToken == "wfa_abc")
    }

    @Test func refusesACallbackThatDoesNotAnswerTheRequest() async throws {
        let connection = make()
        _ = connection.beginSignIn(to: address, deviceName: "iPhone")

        await connection.completeSignIn(callback: callback(code: "un-code", state: "autre-chose"))

        #expect(connection.isConnected == false)
        #expect(connection.failure != nil)
    }

    /// Le code est consommé par sa première requête, même ratée : le secret
    /// tombe dès l'entrée, et un second retour n'a plus rien à échanger.
    @Test func forgetsTheSecretAfterOneAttempt() async throws {
        let stub = StubServer()
        stub.respond(status: 401, body: Data())
        let connection = make(stub: stub)

        let state = try #require(stateParameter(of: connection.beginSignIn(to: address, deviceName: "iPhone")))
        let callback = callback(code: "un-code", state: state)

        await connection.completeSignIn(callback: callback)
        #expect(connection.failure == "Le serveur a refusé la connexion.")

        connection.dismissFailure()
        await connection.completeSignIn(callback: callback)

        #expect(connection.failure == "Aucune connexion n'était en cours.")
        // Le second retour n'a pas été jusqu'au serveur.
        #expect(stub.served.count == 1)
    }

    /// Un échange abandonné — navigateur refermé — ne doit pas rester ouvert :
    /// une redirection tardive n'aurait plus à être honorée.
    @Test func forgetsAnAbandonedSignIn() async throws {
        let stub = StubServer()
        stub.respond(status: 200, body: Self.tokens)
        let connection = make(stub: stub)

        let state = try #require(stateParameter(of: connection.beginSignIn(to: address, deviceName: "iPhone")))
        connection.cancelSignIn()

        await connection.completeSignIn(callback: callback(code: "un-code", state: state))

        #expect(connection.isConnected == false)
        #expect(connection.failure == "Aucune connexion n'était en cours.")
        #expect(stub.served.isEmpty)
    }

    // MARK: - Déconnexion

    /// L'oubli local ne dépend pas de la réponse du serveur : l'utilisateur a
    /// demandé que cet appareil n'ait plus accès.
    @Test func signsOutEvenWhenTheServerRefuses() async throws {
        let stub = StubServer()
        stub.respond(status: 503)
        let storage = InMemorySessionStorage(stored())
        let connection = make(storage: storage, stub: stub)
        connection.restore()

        await connection.signOut()

        #expect(connection.isConnected == false)
        #expect(try storage.load() == nil)
        // La révocation a tout de même été tentée.
        #expect(stub.served.first?.url?.path == "/api/v2/auth/logout")
    }

    // MARK: - Rafraîchissement

    @Test func usesAValidSessionWithoutTouchingTheNetwork() async throws {
        let stub = StubServer()
        let connection = make(storage: InMemorySessionStorage(stored()), stub: stub, now: expiry - 60)
        connection.restore()

        let session = try await connection.validSession()

        #expect(session.accessToken == "wfa_stocke")
        #expect(stub.served.isEmpty)
    }

    /// La marge : un jeton valable encore quelques secondes arriverait périmé,
    /// et le 401 qui suivrait coûterait un aller-retour de plus.
    @Test func refreshesAndPersistsTheRotatedPair() async throws {
        let stub = StubServer()
        stub.respond(status: 200, body: Self.tokens)
        let storage = InMemorySessionStorage(stored())
        let connection = make(storage: storage, stub: stub, now: expiry - 5)
        connection.restore()

        let session = try await connection.validSession()

        #expect(session.accessToken == "wfa_abc")
        #expect(try storage.load()?.session.refreshToken == "wfr_def")
    }

    /// Le jeton tourne : deux rafraîchissements concurrents en échangeraient
    /// deux, et le second invaliderait le premier.
    @Test func refreshesOnlyOnceForConcurrentCallers() async throws {
        let stub = StubServer()
        stub.respond(status: 200, body: Self.tokens)
        let connection = make(storage: InMemorySessionStorage(stored()), stub: stub, now: expiry)
        connection.restore()

        async let first = connection.validSession()
        async let second = connection.validSession()
        let sessions = try await [first, second]

        #expect(sessions.map(\.accessToken) == ["wfa_abc", "wfa_abc"])
        #expect(stub.served.count == 1)
    }

    /// Le trousseau peut refuser au pire moment : l'ancien jeton vient d'être
    /// dépensé, et le nouveau est la seule chose qui vaille. Le garder en
    /// mémoire quand même — sans quoi le prochain appel présenterait un jeton
    /// mort et se ferait déconnecter. Au pire, la connexion ne survivra pas au
    /// prochain démarrage.
    @Test func keepsARefreshedSessionTheKeychainRefused() async throws {
        let stub = StubServer()
        stub.respond(status: 200, body: Self.tokens)
        let storage = InMemorySessionStorage(stored(), failingWrites: KeychainError(status: -34018))
        let connection = make(storage: storage, stub: stub, now: expiry)
        connection.restore()

        let session = try await connection.validSession()

        #expect(session.accessToken == "wfa_abc")
        #expect(connection.connection?.session.refreshToken == "wfr_def")
        // Sur disque, c'est bien l'ancienne qui est restée.
        #expect(try storage.load()?.session.accessToken == "wfa_stocke")
    }

    /// Une déconnexion demandée pendant un rafraîchissement l'emporte.
    ///
    /// Ce test emprunte le chemin de l'annulation : la tâche est encore en vol
    /// quand la déconnexion l'annule. L'autre entrelacement — la tâche
    /// terminée, sa reprise en attente derrière la déconnexion — est celui que
    /// garde `validSession`, et je ne sais pas le forcer depuis un test : rien
    /// ne permet d'ordonner la fin d'une requête et la reprise de son
    /// appelant. La garde reste donc défensive, et c'est dit là-bas.
    @Test func signsOutWhileARefreshIsInFlight() async throws {
        let stub = StubServer()
        stub.respond(status: 200, body: Self.tokens)
        let storage = InMemorySessionStorage(stored())
        let connection = make(storage: storage, stub: stub, now: expiry)
        connection.restore()

        async let refreshed: ServerSession = connection.validSession()
        await connection.signOut()

        _ = try? await refreshed

        #expect(connection.isConnected == false)
        #expect(try storage.load() == nil)
    }

    /// Un jeton de rafraîchissement refusé est mort — révoqué, ou déjà échangé.
    /// Garder la connexion ferait boucler chaque appel sur le même refus.
    @Test func dropsTheConnectionWhenTheRefreshTokenIsRejected() async throws {
        let stub = StubServer()
        stub.respond(status: 401, body: Data())
        let storage = InMemorySessionStorage(stored())
        let connection = make(storage: storage, stub: stub, now: expiry)
        connection.restore()

        await #expect(throws: ServerError.unauthorized) {
            try await connection.validSession()
        }

        #expect(connection.isConnected == false)
        #expect(try storage.load() == nil)
    }

    /// Une panne de réseau n'est pas un refus : la session reste, et le
    /// prochain appel réessaiera.
    @Test func keepsTheConnectionWhenTheRefreshCannotReachTheServer() async throws {
        let stub = StubServer()
        stub.respond(status: 503)
        let connection = make(storage: InMemorySessionStorage(stored()), stub: stub, now: expiry)
        connection.restore()

        await #expect(throws: ServerError.unavailable) {
            try await connection.validSession()
        }

        #expect(connection.isConnected)
    }

    // MARK: - Fixtures

    private let expiry = Date(timeIntervalSince1970: 10_000)

    private static let tokens = Data("""
        {
          "access_token": "wfa_abc",
          "refresh_token": "wfr_def",
          "token_type": "Bearer",
          "expires_in": 900,
          "user": {
            "id": "6BA7B810-9DAD-11D1-80B4-00C04FD430C8",
            "username": "listener",
            "role": "user"
          },
          "device_id": "6BA7B811-9DAD-11D1-80B4-00C04FD430C8"
        }
        """.utf8)

    private func stored() -> StoredConnection {
        StoredConnection(
            address: address,
            session: ServerSession(
                accessToken: "wfa_stocke",
                refreshToken: "wfr_stocke",
                expiresAt: expiry,
                deviceId: UUID(),
                userId: UUID(),
                username: "listener",
            ),
        )
    }

    private func make(
        storage: SessionStorage = InMemorySessionStorage(),
        stub: StubServer = StubServer(),
        now: Date = Date(timeIntervalSince1970: 0),
    ) -> ServerConnection {
        let session = stub.session
        return ServerConnection(
            storage: storage,
            now: { now },
            makeClient: { AuthClient(server: $0, session: session, now: { now }) },
        )
    }

    private func callback(code: String, state: String) -> URL {
        URL(string: "app.waveflow.ios://auth?code=\(code)&state=\(state)")!
    }

    private func stateParameter(of authorization: URL) -> String? {
        URLComponents(url: authorization, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "state" }?.value
    }
}
