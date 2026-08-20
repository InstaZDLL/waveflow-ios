import Foundation
import Testing
@testable import WaveFlow

/// Les appels d'authentification, contre un serveur simulé.
///
/// - Note: exclue du harnais Linux : elle intercepte les requêtes par
///   `URLProtocol`, dont le comportement diffère hors plateformes Apple.
struct AuthClientTests {

    private let server = ServerAddress("https://music.example.com")!
    private let pkce = PKCE(verifier: "un-verificateur", state: "un-etat")

    // MARK: - L'adresse d'autorisation

    @Test func opensTheEmbeddedAuthorizePageOutsideTheAPI() throws {
        let url = client().authorizationURL(for: pkce, deviceName: "iPhone de Nayeon")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.path == "/authorize")

        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(query["client_id"] == "app.waveflow.ios")
        #expect(query["redirect_uri"] == "app.waveflow.ios://auth")
        #expect(query["code_challenge"] == pkce.challenge)
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["state"] == "un-etat")
        #expect(query["device_name"] == "iPhone de Nayeon")

        // Le vérificateur ne sort pas de l'application : c'est tout ce qui
        // sépare un code intercepté d'une session ouverte.
        #expect(url.absoluteString.contains(pkce.verifier) == false)
    }

    // MARK: - Le retour de la redirection

    @Test func readsTheCodeFromTheCallback() {
        let callback = URL(string: "app.waveflow.ios://auth?code=un-code&state=un-etat")!

        #expect(AuthClient.authorizationCode(from: callback, matching: pkce) == "un-code")
    }

    /// Un état qui ne correspond pas désigne une réponse qu'on n'a pas
    /// demandée. Le code qui l'accompagne ne vaut rien.
    @Test func refusesACallbackWhoseStateDoesNotMatch() {
        let callback = URL(string: "app.waveflow.ios://auth?code=un-code&state=autre-chose")!

        #expect(AuthClient.authorizationCode(from: callback, matching: pkce) == nil)
    }

    @Test(arguments: [
        "app.waveflow.ios://auth?state=un-etat",
        "app.waveflow.ios://auth?code=&state=un-etat",
        "app.waveflow.ios://auth?code=un-code",
        "app.waveflow.ios://auth?error=access_denied&state=un-etat",
    ])
    func refusesACallbackWithoutAUsableCode(_ raw: String) {
        #expect(AuthClient.authorizationCode(from: URL(string: raw)!, matching: pkce) == nil)
    }

    // MARK: - L'échange

    @Test func exchangesTheCodeAndDatesTheExpiry() async throws {
        let received = Date(timeIntervalSince1970: 1_000)
        let stub = StubServer()
        stub.respond(status: 200, body: Self.tokens)

        let session = try await client(stub, now: received).exchange(code: "un-code", with: pkce)

        // Les vérifications de la requête sont ici, pas dans le gestionnaire :
        // là-bas, une requête jamais émise n'y ferait échouer personne — elles
        // ne seraient tout simplement pas atteintes.
        let request = try #require(stub.served.first)
        #expect(request.url?.path == "/api/v2/oauth/token")
        #expect(request.method == "POST")

        let sent = try JSONDecoder().decode([String: String].self, from: #require(request.body))
        #expect(sent["code"] == "un-code")
        #expect(sent["code_verifier"] == "un-verificateur")
        #expect(sent["client_id"] == "app.waveflow.ios")
        #expect(sent["redirect_uri"] == "app.waveflow.ios://auth")

        #expect(session.accessToken == "wfa_abc")
        #expect(session.refreshToken == "wfr_def")
        #expect(session.username == "listener")
        #expect(session.deviceId == UUID(uuidString: "6BA7B811-9DAD-11D1-80B4-00C04FD430C8"))
        // Une durée relative devient une date à la réception : stockée telle
        // quelle, elle ne voudrait plus rien dire au démarrage suivant.
        #expect(session.expiresAt == received.addingTimeInterval(900))
    }

    @Test func rejectsTheExchangeWithTheServersOwnError() async throws {
        let stub = StubServer()
        stub.respond(status: 401, body: Data(#"{"code":"unauthorized","message":"non"}"#.utf8))

        await #expect(throws: ServerError.unauthorized) {
            try await client(stub).exchange(code: "code-consomme", with: pkce)
        }
    }

    // MARK: - Le rafraîchissement

    @Test func sendsTheRefreshTokenAndReplacesThePair() async throws {
        let stub = StubServer()
        stub.respond(status: 200, body: Self.tokens)

        let refreshed = try await client(stub).refresh(session(refreshToken: "wfr_ancien"))

        let request = try #require(stub.served.first)
        #expect(request.url?.path == "/api/v2/auth/refresh")

        let sent = try JSONDecoder().decode([String: String].self, from: #require(request.body))
        #expect(sent["refresh_token"] == "wfr_ancien")

        // Le serveur fait tourner le jeton : celui d'avant ne resservira pas.
        #expect(refreshed.refreshToken == "wfr_def")
        #expect(refreshed.accessToken == "wfa_abc")
    }

    // MARK: - La déconnexion

    /// L'appelant efface la session quoi qu'il arrive ; lui faire garder des
    /// jetons parce que le serveur n'a pas répondu serait le contraire de ce
    /// qu'il a demandé.
    @Test func logsOutWithoutReportingAFailure() async throws {
        let stub = StubServer()
        stub.respond(status: 503)

        await client(stub).logout(session(accessToken: "wfa_courant"))

        let request = try #require(stub.served.first)
        #expect(request.url?.path == "/api/v2/auth/logout")
        #expect(request.headers["Authorization"] == "Bearer wfa_courant")
    }

    // MARK: - Fixtures

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

    private func client(
        _ stub: StubServer = StubServer(),
        now: Date = Date(timeIntervalSince1970: 0),
    ) -> AuthClient {
        AuthClient(server: server, session: stub.session, now: { now })
    }

    private func session(accessToken: String = "wfa_x", refreshToken: String = "wfr_x") -> ServerSession {
        ServerSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: 900),
            deviceId: UUID(),
            userId: UUID(),
            username: "listener",
        )
    }
}
