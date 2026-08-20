import Foundation
import Security

/// Où la connexion au serveur survit entre deux lancements.
///
/// Une abstraction pour que les tests ne touchent pas le trousseau : sur
/// simulateur il existe, mais partagé entre les cibles et persistant d'un test
/// à l'autre — deux raisons de ne pas l'y mêler.
nonisolated protocol SessionStorage: Sendable {
    func load() throws -> StoredConnection?
    func save(_ connection: StoredConnection) throws
    func clear() throws
}

/// L'adresse et la session, gardées ensemble.
///
/// Séparées, elles pourraient se désaccorder : des jetons d'un serveur à côté
/// de l'adresse d'un autre ouvriraient des requêtes authentifiées vers une
/// machine qui ne les a jamais émis.
nonisolated struct StoredConnection: Hashable, Sendable, Codable {
    let address: ServerAddress
    let session: ServerSession
}

/// Le trousseau, seul endroit acceptable pour ces jetons.
///
/// `kSecAttrAccessibleAfterFirstUnlock` plutôt que `WhenUnlocked` : la lecture
/// continue en arrière-plan, et un rafraîchissement de jeton pendant que
/// l'appareil est verrouillé échouerait sinon en plein morceau. Pas
/// `ThisDeviceOnly` non plus — l'utilisateur qui restaure une sauvegarde sur un
/// nouvel iPhone s'attend à y retrouver sa connexion, et le serveur sait
/// révoquer un appareil qu'il ne reconnaît plus.
nonisolated struct KeychainSessionStorage: SessionStorage {

    /// Un seul serveur à la fois : le compte est fixe, et enregistrer une
    /// connexion remplace la précédente.
    private let account = "server-connection"
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "app.waveflow.ios") {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() throws -> StoredConnection? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return try JSONDecoder().decode(StoredConnection.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func save(_ connection: StoredConnection) throws {
        let data = try JSONEncoder().encode(connection)

        // Mise à jour d'abord, ajout ensuite : `SecItemAdd` sur un élément
        // existant rend `errSecDuplicateItem`, et effacer avant d'ajouter
        // laisserait une fenêtre sans jeton si l'ajout échouait.
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError(status: update) }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let add = SecItemAdd(item as CFDictionary, nil)
        guard add == errSecSuccess else { throw KeychainError(status: add) }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        // Absent, c'est déjà l'état demandé.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

nonisolated struct KeychainError: Error, Equatable {
    let status: OSStatus
}

/// Le trousseau des tests. Neuf à chaque instance, effacé avec elle.
nonisolated final class InMemorySessionStorage: SessionStorage, @unchecked Sendable {

    private let lock = NSLock()
    private var stored: StoredConnection?

    /// Panne à simuler, pour vérifier qu'un stockage inaccessible ne fait pas
    /// tomber l'application.
    private let failure: Error?

    init(_ stored: StoredConnection? = nil, failing failure: Error? = nil) {
        self.stored = stored
        self.failure = failure
    }

    func load() throws -> StoredConnection? {
        if let failure { throw failure }
        return lock.withLock { stored }
    }

    func save(_ connection: StoredConnection) throws {
        if let failure { throw failure }
        lock.withLock { stored = connection }
    }

    func clear() throws {
        if let failure { throw failure }
        lock.withLock { stored = nil }
    }
}
