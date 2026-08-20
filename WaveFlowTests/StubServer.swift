import Foundation

/// Un serveur simulé, branché sous `URLSession`.
///
/// Chaque instance a son identité et sa `URLSession` : deux suites peuvent s'en
/// servir en parallèle sans se voir. C'est ce qui remplace la sérialisation —
/// un emplacement unique partagé obligeait les tests à passer chacun leur tour,
/// et laissait celui qui aurait oublié d'installer sa réponse s'exécuter contre
/// celle du précédent.
///
/// - Note: exclue du harnais Linux : elle intercepte les requêtes par
///   `URLProtocol`, dont le comportement diffère hors plateformes Apple.
nonisolated final class StubServer: @unchecked Sendable {

    /// L'en-tête qui rattache une requête à son serveur simulé.
    fileprivate static let header = "X-Stub-Server"

    /// Références faibles : un registre qui retient ses entrées empêcherait
    /// `deinit` de s'exécuter, donc l'entrée d'être retirée — chaque serveur
    /// simulé survivrait à son test, avec sa `URLSession` et ses requêtes.
    fileprivate nonisolated(unsafe) static var registry: [String: WeakStub] = [:]
    fileprivate static let registryLock = NSLock()

    private let id = UUID().uuidString
    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) -> (Int, Data))?
    private var requests: [ServedRequest] = []

    /// Les requêtes reçues, dans l'ordre.
    var served: [ServedRequest] { lock.withLock { requests } }

    /// Une session dont toutes les requêtes arrivent ici.
    let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServerProtocol.self]
        configuration.httpAdditionalHeaders = [Self.header: id]
        session = URLSession(configuration: configuration)

        Self.registryLock.withLock { Self.registry[id] = WeakStub(self) }
    }

    deinit {
        Self.registryLock.withLock { Self.registry.removeValue(forKey: id) }
    }

    /// Installe la réponse à rendre. Sans elle, une requête échoue franchement
    /// plutôt que de tomber sur celle d'un autre test.
    func respond(_ handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        lock.withLock { self.handler = handler }
    }

    /// Rend `status` et `body` à chaque requête.
    func respond(status: Int, body: Data = Data()) {
        respond { _ in (status, body) }
    }

    fileprivate func serve(_ request: URLRequest) throws -> (Int, Data)? {
        let handler = lock.withLock { self.handler }
        guard let handler else { return nil }

        let served = ServedRequest(
            url: request.url,
            method: request.httpMethod,
            headers: request.allHTTPHeaderFields ?? [:],
            body: try request.readBody(),
        )
        lock.withLock { requests.append(served) }

        return handler(request)
    }
}

/// Une requête interceptée, corps déjà lu.
///
/// `URLProtocol` vide `httpBody` et ne laisse qu'un flux, qui ne se lit qu'une
/// fois : le retenir dans la requête elle-même rendrait `nil` à qui la relit.
nonisolated struct ServedRequest: Sendable {
    let url: URL?
    let method: String?
    let headers: [String: String]
    let body: Data?
}

/// Un `Dictionary` ne sait pas tenir ses valeurs faiblement ; cette boîte, si.
fileprivate nonisolated final class WeakStub: @unchecked Sendable {
    weak var stub: StubServer?
    init(_ stub: StubServer) { self.stub = stub }
}

private nonisolated final class StubServerProtocol: URLProtocol, @unchecked Sendable {

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let stub = request.value(forHTTPHeaderField: StubServer.header).flatMap { id in
            StubServer.registryLock.withLock { StubServer.registry[id]?.stub }
        }

        do {
            guard let stub, let (status, body) = try stub.serve(request) else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }

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
    /// Une lecture négative est une panne du flux, pas une fin : la confondre
    /// avec `0` rendrait un corps tronqué, et l'appelant verrait un échec de
    /// décodage à la place de la cause.
    func readBody() throws -> Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        // Lire jusqu'à zéro, sans consulter `hasBytesAvailable` : celui-ci
        // n'est pas une fin de flux mais une indication, fausse tant que la
        // première lecture n'a pas eu lieu sur certains flux. S'y fier rendait
        // un corps vide qui passait pour un corps.
        while true {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read < 0 { throw stream.streamError ?? URLError(.cannotParseResponse) }
            if read == 0 { return data }
            data.append(buffer, count: read)
        }
    }
}
