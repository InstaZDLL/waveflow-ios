import Foundation
import Observation

/// Les playlists chargées, partagées par toute l'application.
///
/// Pendant de `LibraryStore` : porté au niveau de l'app plutôt que d'un écran,
/// parce que plusieurs le liront — la liste, le détail, et la feuille « ajouter
/// à une playlist » ouverte depuis n'importe quel morceau — et que chacun
/// ouvrant son propre flux dupliquerait l'observation du stockage.
///
/// - Note: il ne résout pas les morceaux, là où le `PlaylistsViewModel`
///   d'Android tient une `Map<Long, List<Song>>`. `Playlist.songs(in:)` le fait
///   déjà à partir de la bibliothèque, et les écrans ont les deux stores sous
///   la main : refaire cette jointure ici obligerait ce store à observer aussi
///   la bibliothèque, pour un résultat que le modèle sait produire.
@Observable
@MainActor
final class PlaylistStore {

    private(set) var playlists: [Playlist] = []

    private(set) var isLoading = true

    /// Lecture impossible — le flux a échoué. Durable : tant qu'il n'est pas
    /// effacé, l'écran n'a rien de juste à afficher.
    private(set) var errorMessage: String?

    /// Dernière écriture ratée, à montrer une fois puis à oublier.
    ///
    /// Un événement plutôt qu'un état, comme sur Android : une suppression
    /// ratée ne doit pas remplacer durablement la liste par un message
    /// d'erreur.
    private(set) var writeFailure: WriteFailure?

    /// Aucune playlist alors que le chargement s'est bien terminé.
    var isEmpty: Bool { !isLoading && errorMessage == nil && playlists.isEmpty }

    private let repository: PlaylistRepository
    private var observation: Task<Void, Never>?

    /// Dernière écriture lancée. Chaque nouvelle l'attend : voir [write].
    private var pendingWrites: Task<Void, Never>?

    init(repository: PlaylistRepository) {
        self.repository = repository
    }

    // Pas de `deinit` annulant l'observation, pour la même raison que
    // `LibraryStore` : le store vit aussi longtemps que l'application, et
    // `deinit` n'est pas isolé au main actor.

    // MARK: - Lecture

    /// Démarre l'observation si elle ne tourne pas déjà. Idempotent.
    func load() {
        guard observation == nil else { return }
        observe()
    }

    /// Relance après une erreur.
    func retry() { observe() }

    func playlist(_ id: Playlist.ID) -> Playlist? {
        playlists.first { $0.id == id }
    }

    private func observe() {
        observation?.cancel()
        isLoading = true
        errorMessage = nil

        observation = Task { [repository] in
            do {
                for try await playlists in repository.playlists() {
                    self.playlists = playlists
                    isLoading = false
                }
            } catch is CancellationError {
                // Remplacée par une nouvelle observation : rien à signaler.
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription.nonBlank
                    ?? "Impossible de lire les playlists."
            }
        }
    }

    // MARK: - Écriture

    func dismissWriteFailure() { writeFailure = nil }

    /// Crée une playlist, éventuellement pourvue de son premier morceau.
    ///
    /// Un nom blanc est ignoré sans bruit : l'écran de création désactive déjà
    /// son bouton dans ce cas, et remonter une erreur pour un champ vide
    /// n'apprendrait rien à personne.
    func create(name: String, containing songId: String? = nil) {
        guard name.nonBlank != nil else { return }
        write("Impossible de créer la playlist.") { [repository] in
            try await repository.create(name: name, containing: songId)
        }
    }

    func rename(_ id: Playlist.ID, to name: String) {
        guard name.nonBlank != nil else { return }
        write("Impossible de renommer la playlist.") { [repository] in
            try await repository.rename(id, to: name)
        }
    }

    func delete(_ id: Playlist.ID) {
        write("Impossible de supprimer la playlist.") { [repository] in
            try await repository.delete(id)
        }
    }

    func add(_ songId: String, to id: Playlist.ID) {
        write("Impossible d'ajouter le morceau à la playlist.") { [repository] in
            try await repository.add(songId, to: id)
        }
    }

    func remove(_ songId: String, from id: Playlist.ID) {
        write("Impossible de retirer le morceau de la playlist.") { [repository] in
            try await repository.remove(songId, from: id)
        }
    }

    /// Enregistre l'ordre obtenu par glisser-déposer.
    ///
    /// L'ordre complet, tel que l'écran l'affiche : la normalisation — les
    /// identifiants inconnus écartés, les morceaux absents de l'affichage
    /// replacés à la suite — appartient à `Playlist.reorder(to:at:)`.
    func reorder(_ id: Playlist.ID, to orderedSongIds: [String]) {
        write("Impossible de réordonner la playlist.") { [repository] in
            try await repository.reorder(id, to: orderedSongIds)
        }
    }

    /// Lance une écriture en confinant son échec.
    ///
    /// Deux garanties, toutes deux portées d'Android.
    ///
    /// L'échec ne remonte nulle part : une erreur qui s'échapperait d'une tâche
    /// détachée ne serait rattrapée par personne. Elle devient un message,
    /// jamais un plantage — et un message qui nomme l'action, pas la cause
    /// technique, que l'utilisateur ne saurait pas lire. La cause reste
    /// attachée à [WriteFailure] pour le débogage et les tests.
    ///
    /// Les écritures sont sérialisées dans leur ordre d'appel : deux glissers
    /// rapprochés partent dans deux tâches, et sans cette chaîne c'est leur
    /// ordre d'arrivée au stockage qui déciderait de l'ordre final, pas l'ordre
    /// des gestes.
    private func write(
        _ failureMessage: String,
        _ operation: @escaping () async throws -> Void,
    ) {
        let previous = pendingWrites

        pendingWrites = Task {
            await previous?.value

            do {
                try await operation()
            } catch is CancellationError {
                // Écriture abandonnée : rien à signaler à l'utilisateur.
            } catch {
                writeFailure = WriteFailure(message: failureMessage, underlying: error)
            }
        }
    }

    /// Attend la fin des écritures en cours.
    ///
    /// Point d'accroche pour les tests : les écritures sont volontairement sans
    /// valeur de retour — un écran ne les attend pas, il observe le flux — donc
    /// rien d'autre ne permettrait de savoir qu'elles ont abouti.
    func waitForWrites() async {
        await pendingWrites?.value
    }
}

/// Une écriture qui a échoué.
///
/// [message] nomme l'action manquée, en français, pour l'utilisateur.
/// [underlying] garde la cause : sans elle, un échec ne laisserait aucune trace
/// exploitable.
///
/// `Identifiable` avec une identité neuve à chaque échec : deux échecs
/// successifs identiques doivent rouvrir l'alerte, pas passer inaperçus.
@MainActor
struct WriteFailure: Identifiable {

    let id = UUID()
    let message: String
    let underlying: Error
}
