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
    @Environment(PlaylistStore.self) private var playlistStore

    @State private var selectedTab = Tabs.songs

    // Les piles de navigation vivent ici, pas dans les écrans : poser
    // l'accessoire au premier morceau lancé change l'identité du `TabView` et
    // jetterait l'état des vues filles — on se retrouverait ramené à la grille
    // d'albums en appuyant sur « Lecture » depuis un album.
    @State private var albumsPath = NavigationPath()
    @State private var artistsPath = NavigationPath()
    @State private var searchPath = NavigationPath()

    @State private var showPlayer = false
    @State private var importing = false
    @State private var importReport: String?

    private enum Tabs { case songs, albums, artists, search }

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
        // Les deux liaisons effacent leur message à la fermeture plutôt que
        // d'être `.constant` : avec une liaison constante, seul le bouton
        // remettrait l'état à zéro, et toute autre fermeture laisserait
        // l'alerte se rouvrir aussitôt.
        .alert("Import", isPresented: Binding(
            get: { importReport != nil },
            set: { if !$0 { importReport = nil } },
        )) {
            Button("OK") { importReport = nil }
        } message: {
            Text(importReport ?? "")
        }
        // Le stockage des playlists n'a pas pu être ouvert normalement. Dit une
        // fois, au démarrage : l'application fonctionne, mais l'utilisateur doit
        // savoir ce qu'il a perdu — et ce qu'il n'a pas perdu.
        .alert("Playlists", isPresented: Binding(
            get: { playlistStore.storageNotice != nil },
            set: { if !$0 { playlistStore.dismissStorageNotice() } },
        )) {
            Button("OK") { playlistStore.dismissStorageNotice() }
        } message: {
            Text(playlistStore.storageNotice ?? "")
        }
        // Les deux observations démarrent ici, une fois : les écrans lisent les
        // stores, ils n'ouvrent jamais leur propre flux.
        .task {
            store.load()
            playlistStore.load()
        }
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
            // `role: .search` plutôt qu'un quatrième onglet ordinaire : iOS 26
            // le détache des autres et le laisse se réduire en champ quand la
            // barre se minimise au défilement.
            Tab("Recherche", systemImage: "magnifyingglass", value: Tabs.search, role: .search) {
                SearchScreen(path: $searchPath)
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
