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
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var heldPath: String?
    private var heldDeliveries: [@Sendable () -> Void] = []

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

    /// Retient la réponse aux requêtes de `path` jusqu'à [releaseHeld].
    ///
    /// Ce qu'il faut pour agir *pendant* un appel et non juste après : savoir
    /// que la requête est partie ne suffit pas si la réponse la suit aussitôt.
    /// Le chemin est nommé plutôt que tout retenu en bloc — le test qui se
    /// déconnecte pendant un rafraîchissement a besoin que la déconnexion,
    /// elle, passe.
    ///
    /// C'est la **livraison** qui est mise de côté, jamais le fil qui la
    /// porte. Bloquer celui d'`URLSession` fige la file que tous les tests
    /// réseau du processus partagent : la première version le faisait, et
    /// l'hôte de test entier expirait, y compris sur des suites qui ne
    /// touchaient à rien.
    func hold(path: String) {
        lock.withLock { heldPath = path }
    }

    func releaseHeld() {
        let deliveries = lock.withLock {
            defer {
                heldPath = nil
                heldDeliveries = []
            }
            return heldDeliveries
        }
        deliveries.forEach { $0() }
    }

    /// Attend qu'une requête soit parvenue jusqu'ici.
    ///
    /// Ce qu'il faut à un test qui veut agir *pendant* un appel : sans ce
    /// point de rendez-vous, il agirait peut-être avant que l'appel ait
    /// commencé, et vérifierait alors tout autre chose que ce qu'il annonce.
    /// Rend la main tout de suite si une requête est déjà arrivée.
    func requestReceived() async {
        await withCheckedContinuation { continuation in
            let alreadyServed = lock.withLock {
                guard requests.isEmpty else { return true }
                waiters.append(continuation)
                return false
            }
            if alreadyServed { continuation.resume() }
        }
    }

    /// Sert `request` : la réponse part par `deliver`, tout de suite ou au
    /// prochain [releaseHeld]. Rend `false` si aucune réponse n'est installée.
    fileprivate func serve(
        _ request: URLRequest,
        deliver: @escaping @Sendable (Int, Data) -> Void,
    ) throws -> Bool {
        let body = try request.readBody()
        let served = ServedRequest(
            url: request.url,
            method: request.httpMethod,
            headers: request.allHTTPHeaderFields ?? [:],
            body: body,
        )

        // Enregistrée et signalée même sans réponse installée : sinon un test
        // qui aurait oublié la sienne resterait pendu sur [requestReceived]
        // jusqu'à expiration, au lieu d'échouer en montrant ce qu'il a reçu.
        let handler = lock.withLock { self.handler }
        guard let handler else {
            wake(with: served, held: false)
            return false
        }

        // Le corps est reposé dans la requête transmise : `URLProtocol` ne
        // laisse qu'un flux, qui vient d'être lu et ne se relit pas. Un
        // gestionnaire qui inspecterait `httpBody` n'y trouverait rien, sans
        // rien pour le lui dire.
        //
        // Le flux d'abord : poser `httpBody` alors qu'un flux est encore là ne
        // le remplace pas, et le gestionnaire relirait un flux épuisé.
        var forwarded = request
        forwarded.httpBodyStream = nil
        forwarded.httpBody = body

        let (status, response) = handler(forwarded)

        let isHeld = wake(with: served, held: heldPath == request.url?.path) {
            deliver(status, response)
        }

        if !isHeld { deliver(status, response) }
        return true
    }

    /// Enregistre la requête, met la livraison de côté si elle est retenue,
    /// puis réveille ceux qui l'attendaient — dans cet ordre : le test qui
    /// reprend s'attend à ce que la retenue soit déjà en place.
    @discardableResult
    private func wake(
        with served: ServedRequest,
        held: Bool,
        deliver: (@Sendable () -> Void)? = nil,
    ) -> Bool {
        let waiting = lock.withLock {
            requests.append(served)
            defer { waiters = [] }

            if held, let deliver { heldDeliveries.append(deliver) }
            return waiters
        }
        waiting.forEach { $0.resume() }

        return held
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

    /// Une livraison retenue peut être lâchée après l'abandon de la requête —
    /// une annulation, par exemple. Rien à remettre à un client qui n'écoute
    /// plus.
    private let stopLock = NSLock()
    private var stopped = false
    fileprivate var isStopped: Bool { stopLock.withLock { stopped } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func stopLoading() {
        stopLock.withLock { stopped = true }
    }

    override func startLoading() {
        let stub = request.value(forHTTPHeaderField: StubServer.header).flatMap { id in
            StubServer.registryLock.withLock { StubServer.registry[id]?.stub }
        }

        do {
            let url = request.url!
            let deliver: @Sendable (Int, Data) -> Void = { [weak self] status, body in
                guard let self, !self.isStopped else { return }

                let response = HTTPURLResponse(
                    url: url,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"],
                )!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: body)
                self.client?.urlProtocolDidFinishLoading(self)
            }

            guard let stub, try stub.serve(request, deliver: deliver) else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }
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
