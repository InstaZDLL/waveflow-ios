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
    /// bibliothèque et le lecteur vivent aussi longtemps que l'app, pas le
    /// temps d'un écran. Un vrai conteneur (Swinject, Factory…) plus tard, si
    /// le graphe le justifie.
    @State private var libraryStore = LibraryStore(repository: DocumentsMusicRepository())
    @State private var player = PlaybackController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(libraryStore)
                .environment(player)
        }
    }
}
