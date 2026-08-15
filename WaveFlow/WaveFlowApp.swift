//
//  WaveFlowApp.swift
//  WaveFlow
//
//  Created by Nayeon Im on 09.08.2026.
//

import SwiftUI

@main
struct WaveFlowApp: App {

    /// Conteneur d'injection manuel, comme l'`AppContainer` d'Android : la
    /// bibliothèque, le lecteur et les playlists vivent aussi longtemps que
    /// l'app, pas le temps d'un écran. Un vrai conteneur (Swinject, Factory…)
    /// plus tard, si le graphe le justifie.
    @State private var libraryStore = LibraryStore(repository: DocumentsMusicRepository())
    @State private var player = PlaybackController()
    @State private var playlistStore = PlaylistStore(repository: makePlaylistRepository())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(libraryStore)
                .environment(player)
                .environment(playlistStore)
        }
    }

    /// Le stockage des playlists, ouvert au démarrage.
    ///
    /// L'échec est fatal, et volontairement : les playlists sont la seule
    /// donnée dont l'application est propriétaire — se rabattre en silence sur
    /// un dépôt en mémoire ferait disparaître celles de l'utilisateur à la
    /// fermeture, sans que rien ne l'en avertisse. Même parti pris que
    /// `AppPaths.documents`.
    private static func makePlaylistRepository() -> PlaylistRepository {
        do {
            return SwiftDataPlaylistRepository(
                container: try SwiftDataPlaylistRepository.makeContainer(),
            )
        } catch {
            preconditionFailure("Stockage des playlists inouvrable : \(error)")
        }
    }
}
