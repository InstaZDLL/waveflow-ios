import Foundation
import Testing
@testable import WaveFlow

/// L'ouverture du stockage des playlists, et sa dégradation par paliers.
///
/// Ce qui est vérifié ici est une garantie produit, pas un détail technique :
/// l'application démarre quoi qu'il arrive. Refuser de démarrer forcerait
/// l'utilisateur à désinstaller — donc à perdre `Documents`, et avec lui toute
/// sa musique importée, pour réparer une base de playlists.
///
/// - Note: exclue du harnais Linux, SwiftData n'y existant pas.
struct PlaylistPersistenceTests {

    /// Dossier neuf par test, effacé derrière : aucune dépendance à l'ordre
    /// d'exécution, et rien ne traîne dans le conteneur de l'hôte de tests.
    private let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)

    private func removeDirectory() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Cas nominal

    @Test func opensAStoreOnAFreshInstall() async throws {
        defer { removeDirectory() }

        let opening = PlaylistPersistence.open(in: directory)

        #expect(opening.outcome == .opened)
        #expect(opening.outcome.notice == nil)

        // Le dépôt rendu doit être utilisable, pas seulement construit.
        try await opening.repository.create(name: "Été")
        var emissions = opening.repository.playlists().makeAsyncIterator()
        #expect(try #require(await emissions.next()).map(\.name) == ["Été"])
    }

    // MARK: - Base illisible

    @Test func resetsAnUnreadableStoreInsteadOfRefusingToStart() async throws {
        defer { removeDirectory() }
        try writeUnreadableStore()

        let opening = PlaylistPersistence.open(in: directory)

        guard case .reset(let displacedTo) = opening.outcome else {
            Issue.record("attendu une remise à neuf, obtenu \(opening.outcome)")
            return
        }

        // La base neuve est ouverte et fonctionne.
        try await opening.repository.create(name: "Hiver")
        var emissions = opening.repository.playlists().makeAsyncIterator()
        #expect(try #require(await emissions.next()).map(\.name) == ["Hiver"])

        // L'ancienne est écartée, pas détruite : elle contient les playlists de
        // l'utilisateur, et peut rester récupérable autrement.
        let displaced = displacedTo.appending(path: "Playlists.store")
        #expect(FileManager.default.fileExists(atPath: displaced.path))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "Playlists.store").path))
    }

    /// Le message doit nommer ce qui est perdu *et* ce qui ne l'est pas : la
    /// panne touche les playlists, jamais la musique importée.
    @Test func explainsWhatWasLostAndWhatWasNot() throws {
        defer { removeDirectory() }
        try writeUnreadableStore()

        let notice = try #require(PlaylistPersistence.open(in: directory).outcome.notice)

        #expect(notice.contains("playlists"))
        #expect(notice.lowercased().contains("musique"))
    }

    // MARK: - Aucun stockage possible

    /// Dernier palier : les playlists ne survivront pas à la session, mais
    /// l'application démarre et la musique reste jouable.
    @Test func fallsBackToMemoryWhenNothingCanBeOpened() async throws {
        // Un fichier ordinaire là où un dossier est attendu : ni la création du
        // dossier ni l'écartement ne peuvent aboutir.
        let blocked = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("pas un dossier".utf8).write(to: blocked)
        defer { try? FileManager.default.removeItem(at: blocked) }

        let opening = PlaylistPersistence.open(in: blocked)

        #expect(opening.outcome == .unavailable)
        #expect(opening.outcome.notice != nil)

        // Utilisable malgré tout, le temps de la session.
        try await opening.repository.create(name: "Été")
        var emissions = opening.repository.playlists().makeAsyncIterator()
        #expect(try #require(await emissions.next()).map(\.name) == ["Été"])
    }

    // MARK: - Fixtures

    /// Une base que SwiftData ne saura pas ouvrir : le fichier existe mais n'est
    /// pas une base SQLite.
    private func writeUnreadableStore() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("ceci n'est pas une base".utf8)
            .write(to: directory.appending(path: "Playlists.store"))
    }
}
