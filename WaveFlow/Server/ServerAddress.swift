import Foundation

/// L'adresse d'une instance WaveFlow, ramenée à son origine.
///
/// Le guide d'intégration est explicite : ce qu'on enregistre est l'origine,
/// jamais `…/api/v2`. C'est une erreur naturelle — l'utilisateur copie l'URL
/// qu'il avait sous les yeux — et elle produirait des requêtes vers
/// `/api/v2/api/v2/…`, donc des 404 qui ne désignent pas leur cause.
///
/// Ce type existe pour que la faute soit corrigée une fois, à la saisie, plutôt
/// que rattrapée à chaque appel.
nonisolated struct ServerAddress: Hashable, Sendable, Codable {

    /// Origine normalisée : schéma, hôte, port. Sans chemin ni barre finale.
    let origin: URL

    /// Lit ce que l'utilisateur a tapé.
    ///
    /// Le schéma est facultatif — on écrit rarement `https://` de mémoire — et
    /// vaut alors HTTPS : proposer HTTP par défaut ferait passer un jeton en
    /// clair sur le réseau.
    ///
    /// Le chemin est retiré plutôt que refusé. Un serveur WaveFlow se sert
    /// depuis une origine ; tout ce qui suit est soit le `/api/v2` de trop,
    /// soit une page de l'interface web dont l'utilisateur a copié l'URL. Dans
    /// les deux cas l'origine est la bonne réponse, et un refus n'apprendrait
    /// rien de plus à quelqu'un qui vient de coller une adresse valide.
    init?(_ typed: String) {
        guard let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines).nonBlank else {
            return nil
        }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"

        guard var components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host?.nonBlank,
              // `URLComponents` accepte « https://:8080 » sans hôte utile, et
              // un hôte à espaces échapperait au contrôle ci-dessus.
              !host.contains(" ")
        else { return nil }

        components.scheme = scheme
        components.host = host.lowercased()
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil

        guard let origin = components.url else { return nil }
        self.origin = origin
    }

    /// Chemin absolu de l'API, `/api/v2` compris.
    ///
    /// Les appelants nomment la route telle qu'elle apparaît dans le guide —
    /// Builds a URL for a path under the server's versioned API endpoint.
    /// - Parameter path: The path to append under `/api/v2`.
    /// - Returns: The resulting API URL.
    func api(_ path: String) -> URL {
        origin.appending(path: "api/v2").appending(path: path)
    }

    /// Chemin absolu hors API : les sondes et l'écran d'autorisation, qui ne
    /// Builds a URL for a path relative to the server origin.
    /// - Parameter path: The path to append to the server origin.
    /// - Returns: The resulting URL.
    func root(_ path: String) -> URL {
        origin.appending(path: path)
    }
}
