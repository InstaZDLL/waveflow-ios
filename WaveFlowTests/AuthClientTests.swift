import Foundation
import Testing
@testable import WaveFlow

/// Les appels d'authentification, contre un serveur simulé.
///
/// Sérialisée : `URLSession` instancie elle-même le protocole d'interception,
/// donc la réponse à rendre ne peut être posée que sur un emplacement statique
/// — un seul pour toute la suite. Deux tests qui s'exécuteraient en parallèle y
/// écriraient chacun la leur, et recevraient celle de l'autre.
///
/// - Note: exclue du harnais Linux : elle intercepte les requêtes par
///   `URLProtocol`, dont le comportement diffère hors plateformes Apple.
@Suite(.serialized)
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
        StubServer.respond { request in
            #expect(request.url?.path == "/api/v2/oauth/token")
            #expect(request.httpMethod == "POST")

            let body = try #require(request.bodyData)
            let sent = try #require(try JSONDecoder().decode([String: String].self, from: body))
            #expect(sent["code"] == "un-code")
            #expect(sent["code_verifier"] == "un-verificateur")
            #expect(sent["client_id"] == "app.waveflow.ios")
            #expect(sent["redirect_uri"] == "app.waveflow.ios://auth")

            return (200, Self.tokens)
        }

        let session = try await client(now: received).exchange(code: "un-code", with: pkce)

        #expect(session.accessToken == "wfa_abc")
        #expect(session.refreshToken == "wfr_def")
        #expect(session.username == "listener")
        #expect(session.deviceId == UUID(uuidString: "6BA7B811-9DAD-11D1-80B4-00C04FD430C8"))
        // Une durée relative devient une date à la réception : stockée telle
        // quelle, elle ne voudrait plus rien dire au démarrage suivant.
        #expect(session.expiresAt == received.addingTimeInterval(900))
    }

    @Test func rejectsTheExchangeWithTheServersOwnError() async throws {
        StubServer.respond { _ in (401, Data(#"{"code":"unauthorized","message":"non"}"#.utf8)) }

        await #expect(throws: ServerError.unauthorized) {
            try await client().exchange(code: "code-consomme", with: pkce)
        }
    }

    // MARK: - Le rafraîchissement

    @Test func sendsTheRefreshTokenAndReplacesThePair() async throws {
        StubServer.respond { request in
            #expect(request.url?.path == "/api/v2/auth/refresh")

            let body = try #require(request.bodyData)
            let sent = try #require(try JSONDecoder().decode([String: String].self, from: body))
            #expect(sent["refresh_token"] == "wfr_ancien")

            return (200, Self.tokens)
        }

        let refreshed = try await client().refresh(session(refreshToken: "wfr_ancien"))

        // Le serveur fait tourner le jeton : celui d'avant ne resservira pas.
        #expect(refreshed.refreshToken == "wfr_def")
        #expect(refreshed.accessToken == "wfa_abc")
    }

    // MARK: - La déconnexion

    /// L'appelant efface la session quoi qu'il arrive ; lui faire garder des
    /// jetons parce que le serveur n'a pas répondu serait le contraire de ce
    /// qu'il a demandé.
    @Test func logsOutWithoutReportingAFailure() async throws {
        StubServer.respond { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer wfa_courant")
            return (503, Data())
        }

        await client().logout(session(accessToken: "wfa_courant"))
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

    private func client(now: Date = Date(timeIntervalSince1970: 0)) -> AuthClient {
        AuthClient(server: server, session: StubServer.makeSession(), now: { now })
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

/// Un serveur simulé, branché sous `URLSession` par `URLProtocol`.
private nonisolated final class StubServer: URLProtocol, @unchecked Sendable {

    /// La réponse à rendre, posée par le test en cours.
    ///
    /// Statique parce que `URLSession` instancie le protocole elle-même : rien
    /// ne permet de lui passer une fermeture autrement. Le verrou protège la
    /// lecture faite depuis le thread de la requête — c'est la sérialisation de
    /// la suite, pas lui, qui garantit qu'un seul test s'en sert à la fois.
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    private static let lock = NSLock()

    static func respond(_ handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) {
        lock.withLock { Self.handler = handler }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let handler = Self.lock.withLock { Self.handler }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        do {
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"],
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

private nonisolated extension URLRequest {

    /// Le corps de la requête, où qu'il soit.
    ///
    /// `URLProtocol` vide `httpBody` et ne laisse qu'un flux : le lire tel quel
    /// rendrait `nil` sur toutes les requêtes interceptées.
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
