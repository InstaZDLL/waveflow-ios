import SwiftUI
import UniformTypeIdentifiers

/// Ouvre le sélecteur de fichiers. Porté par l'environnement plutôt que passé
/// de vue en vue : n'importe quel écran vide doit pouvoir proposer l'import.
extension EnvironmentValues {
    @Entry var requestImport: () -> Void = {}
}

/// Racine de l'application : les onglets, le mini-lecteur et le lecteur plein
/// écran. Équivalent du `Scaffold` + `NavHost` d'Android.
struct RootView: View {

    @Environment(LibraryStore.self) private var store
    @Environment(PlaybackController.self) private var player

    @State private var selectedTab = Tabs.songs

    // Les piles de navigation vivent ici, pas dans les écrans : poser
    // l'accessoire au premier morceau lancé change l'identité du `TabView` et
    // jetterait l'état des vues filles — on se retrouverait ramené à la grille
    // d'albums en appuyant sur « Lecture » depuis un album.
    @State private var albumsPath = NavigationPath()
    @State private var artistsPath = NavigationPath()

    @State private var showPlayer = false
    @State private var importing = false
    @State private var importReport: String?

    private enum Tabs { case songs, albums, artists }

    var body: some View {
        Group {
            // Le modificateur est posé — et retiré — plutôt que de laisser le
            // mini-lecteur se vider : un accessoire au contenu vide réserve
            // quand même sa capsule au-dessus de la barre d'onglets.
            if player.currentSong == nil {
                tabs
            } else {
                tabs.tabViewBottomAccessory {
                    MiniPlayer { showPlayer = true }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Color.waveEmerald)
        .environment(\.requestImport) { importing = true }
        .fullScreenCover(isPresented: $showPlayer) {
            NowPlayingScreen()
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true,
            onCompletion: handleImport,
        )
        .alert("Import", isPresented: .constant(importReport != nil)) {
            Button("OK") { importReport = nil }
        } message: {
            Text(importReport ?? "")
        }
        .task { store.load() }
    }

    /// Les onglets, extraits pour être posés à l'identique dans les deux
    /// branches ci-dessus. La sélection est ancrée dans l'état : le
    /// changement d'identité provoqué par l'ajout de l'accessoire la
    /// réinitialiserait sinon au premier morceau lancé.
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Titres", systemImage: "music.note", value: Tabs.songs) {
                LibraryScreen()
            }
            Tab("Albums", systemImage: "square.stack", value: Tabs.albums) {
                AlbumsScreen(path: $albumsPath)
            }
            Tab("Artistes", systemImage: "music.microphone", value: Tabs.artists) {
                ArtistsScreen(path: $artistsPath)
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let outcome = MusicImporter.copy(urls)
            // La surveillance du dossier finirait par le voir, mais un rescan
            // immédiat évite la seconde d'attente après un import manuel.
            store.refresh()

            importReport = outcome.failed == 0
                ? "\(trackCountLabel(outcome.imported)) importé\(outcome.imported > 1 ? "s" : "")."
                : "\(outcome.imported) importé(s), \(outcome.failed) en échec."

        case .failure(let error):
            importReport = error.localizedDescription
        }
    }
}
