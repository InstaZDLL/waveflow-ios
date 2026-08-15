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
    @State private var playlistStore = makePlaylistStore()

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
    /// L'ouverture ne peut pas échouer : [PlaylistPersistence] dégrade par
    /// paliers plutôt que d'empêcher le démarrage, et rédige ce qu'il faut en
    /// dire à l'utilisateur. Refuser de démarrer le forcerait à désinstaller —
    /// donc à perdre `Documents`, et avec lui toute sa musique importée.
    private static func makePlaylistStore() -> PlaylistStore {
        let opening = PlaylistPersistence.open()
        return PlaylistStore(repository: opening.repository, storageNotice: opening.outcome.notice)
    }
}
