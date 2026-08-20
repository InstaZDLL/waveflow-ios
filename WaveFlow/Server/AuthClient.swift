import Foundation

/// Les appels d'authentification d'un serveur WaveFlow.
///
/// Sans état : il ne garde pas la session qu'il rend. C'est au niveau
/// au-dessus de décider où elle vit et quand la rafraîchir — ici on ne fait
/// que parler au serveur.
nonisolated struct AuthClient: Sendable {

    /// Ce que l'application déclare être. Il n'existe ni registre de clients ni
    /// secret côté serveur : l'identifiant sert à retrouver le grant, et la
    /// redirection à ramener le code dans l'application qui l'a demandé.
    static let clientId = "app.waveflow.ios"

    /// Schéma en nom de domaine inversé, ce que le serveur accepte pour un
    /// client natif — un mot seul serait revendicable par une autre
    /// application. C'est aussi ce que `ASWebAuthenticationSession` intercepte,
    /// sans avoir à le déclarer dans `Info.plist`.
    static let redirectURI = "\(clientId)://auth"

    let server: ServerAddress
    let session: URLSession
    let now: @Sendable () -> Date

    init(
        server: ServerAddress,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.server = server
        self.session = session
        self.now = now
    }

    /// L'adresse à ouvrir dans le navigateur système.
    ///
    /// Sous `/authorize` et non `/api/v2` : c'est une page de l'interface
    /// Builds the authorization URL for a device authentication flow.
    /// - Parameters:
    ///   - pkce: The PKCE challenge and state used for authorization.
    ///   - deviceName: The name of the device requesting authorization.
    /// - Returns: The server authorization URL containing the client, redirect, PKCE, state, and device parameters.
    func authorizationURL(for pkce: PKCE, deviceName: String) -> URL {
        var components = URLComponents(url: server.root("authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "device_name", value: deviceName),
        ]
        return components.url!
    }

    /// Lit le code et l'état rapportés par la redirection.
    ///
    /// L'état est comparé ici plutôt que chez l'appelant : c'est la seule
    /// vérification qui distingue une réponse à notre demande d'une réponse
    /// Extracts the authorization code from a callback URL when its state matches the PKCE state.
    /// - Parameters:
    ///   - callback: The authorization callback URL.
    ///   - pkce: The PKCE state used to validate the callback.
    /// - Returns: The nonblank authorization code, or `nil` when the callback state does not match or no code is present.
    static func authorizationCode(from callback: URL, matching pkce: PKCE) -> String? {
        guard let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              let state = items.first(where: { $0.name == "state" })?.value,
              state == pkce.state,
              let code = items.first(where: { $0.name == "code" })?.value?.nonBlank
        else { return nil }

        return code
    }

    /// Échange le code contre une session.
    ///
    /// Un code expire au bout de dix minutes et **est consommé par la première
    /// requête, y compris ratée** : en cas d'échec, il faut relancer
    /// Exchanges an authorization code and PKCE verifier for a server session.
    /// - Parameters:
    ///   - code: The authorization code received from the server.
    ///   - pkce: The PKCE data used to verify the authorization request.
    /// - Returns: The authenticated server session.
    func exchange(code: String, with pkce: PKCE) async throws -> ServerSession {
        try await post(server.api("oauth/token"), body: [
            "code": code,
            "code_verifier": pkce.verifier,
            "client_id": Self.clientId,
            "redirect_uri": Self.redirectURI,
        ])
    }

    /// Rafraîchit la session.
    ///
    /// Le jeton rendu remplace l'ancien : le serveur le fait tourner, et
    /// Renews an authenticated server session using its refresh token.
    /// - Parameter session: The session whose refresh token is used.
    /// - Returns: The replacement server session.
    func refresh(_ session: ServerSession) async throws -> ServerSession {
        try await post(server.api("auth/refresh"), body: ["refresh_token": session.refreshToken])
    }

    /// Révoque la session courante.
    ///
    /// Un échec n'est pas remonté : l'appelant efface la session de toute
    /// façon, et lui faire garder des jetons parce que le serveur n'a pas
    /// Logs out the specified server session.
    ///
    /// - Parameter session: The authenticated session to terminate.
    func logout(_ session: ServerSession) async {
        var request = URLRequest(url: server.api("auth/logout"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await self.session.data(for: request)
    }

    /// Sends an authentication request and produces the resulting server session.
    /// - Parameters:
    ///   - url: The endpoint to request.
    ///   - body: The JSON fields included in the request.
    /// - Returns: The authenticated server session.
    /// - Throws: An error if the request fails, the server reports an error, or the response cannot be decoded.
    private func post(_ url: URL, body: [String: String]) async throws -> ServerSession {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if let error = ServerError.from(status: status, body: data) { throw error }

        return try JSONDecoder().decode(AuthTokensPayload.self, from: data).session(receivedAt: now())
    }
}
