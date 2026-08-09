import Foundation

/// La bibliothèque chargée, partagée par toute l'application.
///
/// Portée au niveau de l'app plutôt qu'à celui d'une vue : plusieurs écrans en
/// dépendent (titres, albums, artistes, et les playlists à venir), et chacun
/// ouvrant son propre flux relancerait un scan complet du dossier. Ici la
/// lecture n'a lieu qu'une fois et survit à la recomposition des vues.
@Observable
@MainActor
final class LibraryStore {

    private(set) var library = Library()

    private let repository: MusicRepository
    private var observation: Task<Void, Never>?

    init(repository: MusicRepository) {
        self.repository = repository
    }

    // Pas de `deinit` annulant l'observation : le store vit aussi longtemps
    // que l'application, et `deinit` n'est pas isolé au main actor — il ne
    // peut donc pas toucher à `observation`.

    /// Démarre l'observation si elle ne tourne pas déjà. Idempotent : appelé à
    /// chaque apparition de la vue racine.
    func load() {
        guard observation == nil else { return }
        observe()
    }

    /// Relance après une erreur.
    func retry() { observe() }

    /// Force une relecture du dossier — après un import, sans attendre que la
    /// surveillance du système de fichiers se déclenche.
    func refresh() { repository.refresh() }

    private func observe() {
        observation?.cancel()
        library = Library(isLoading: true, songs: library.songs)

        observation = Task { [repository] in
            do {
                for try await songs in repository.songs() {
                    library = Library(isLoading: false, songs: songs)
                }
            } catch is CancellationError {
                // Remplacée par une nouvelle observation : rien à signaler.
            } catch {
                library = Library(
                    isLoading: false,
                    errorMessage: error.localizedDescription.nonBlank ?? "Impossible de lire la bibliothèque.",
                )
            }
        }
    }
}
