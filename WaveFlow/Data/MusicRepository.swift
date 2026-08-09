import Foundation

/// Accès à la bibliothèque musicale, vu par le reste de l'application.
///
/// L'abstraction est volontairement minimale : l'UI ne sait pas d'où viennent
/// les morceaux (fichiers importés aujourd'hui, serveur WaveFlow demain), et
/// les vues peuvent être testées avec une fausse implémentation.
nonisolated protocol MusicRepository: Sendable {

    /// Flux des morceaux disponibles, ré-émis quand la source change.
    ///
    /// Le flux peut échouer (dossier illisible, fichier corrompu en cours de
    /// scan) : l'appelant est responsable de la gestion d'erreur.
    func songs() -> AsyncThrowingStream<[Song], Error>

    /// Force une relecture de la source, sans attendre un événement système.
    func refresh()
}
