import SwiftUI

/// Onglet Playlists : création et accès aux playlists locales.
struct PlaylistsScreen: View {

    /// Pile détenue par `RootView` — voir le commentaire là-bas.
    @Binding var path: NavigationPath

    @Environment(PlaylistStore.self) private var store
    @Environment(LibraryStore.self) private var libraryStore

    @State private var creating = false
    @State private var newName = ""

    /// Playlist visée par le renommage ou la suppression en cours.
    @State private var renaming: Playlist?
    @State private var renamedName = ""
    @State private var deleting: Playlist?

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Playlists")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Nouvelle playlist", systemImage: "plus", action: startCreating)
                    }
                }
                .navigationDestination(for: Playlist.self) { playlist in
                    PlaylistDetailScreen(playlistId: playlist.id)
                }
        }
        .playlistNameAlert(
            "Nouvelle playlist",
            confirmLabel: "Créer",
            isPresented: $creating,
            name: $newName,
            onConfirm: { store.create(name: $0) },
        )
        .playlistNameAlert(
            "Renommer la playlist",
            confirmLabel: "Renommer",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
            name: $renamedName,
            onConfirm: { newName in
                guard let renaming else { return }
                store.rename(renaming.id, to: newName)
            },
        )
        .confirmationDialog(
            "Supprimer « \(deleting?.name ?? "") » ?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
        ) {
            Button("Supprimer", role: .destructive) {
                guard let deleting else { return }
                store.delete(deleting.id)
            }
        } message: {
            // Le dire explicitement : supprimer une playlist ressemble assez à
            // supprimer des morceaux pour qu'on hésite sans cette phrase.
            Text("Les morceaux restent sur l'appareil.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.playlists.isEmpty {
            ProgressView("Lecture des playlists…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = store.errorMessage {
            ContentUnavailableView {
                Label("Playlists illisibles", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { store.retry() }
                    .buttonStyle(.borderedProminent)
            }
        } else if store.isEmpty {
            ContentUnavailableView {
                Label("Aucune playlist", systemImage: "music.note.list")
            } description: {
                Text("Crée-en une, puis appuie longuement sur un morceau pour l'y ajouter.")
            } actions: {
                Button("Nouvelle playlist", systemImage: "plus", action: startCreating)
                    .buttonStyle(.borderedProminent)
            }
        } else {
            list
        }
    }

    private var list: some View {
        List(store.playlists) { playlist in
            // Les morceaux résolus, pas les identifiants stockés : un fichier
            // disparu de `Documents` ne doit pas être compté, sinon le nombre
            // affiché ici ne correspond pas à ce qu'on voit en ouvrant.
            let songs = playlist.songs(in: libraryStore.library)

            NavigationLink(value: playlist) {
                MediaRow(
                    // La pochette du premier morceau tient lieu de visuel,
                    // faute d'image propre à la playlist.
                    artworkURL: songs.first?.artworkURL,
                    title: playlist.name,
                    subtitle: trackCountLabel(songs.count),
                )
            }
            // Balayage et appui long : les deux gestes iOS pour la même paire
            // d'actions, là où Android passe par un menu de barre de titre.
            .swipeActions(edge: .trailing) {
                Button("Supprimer", systemImage: "trash", role: .destructive) {
                    deleting = playlist
                }
                Button("Renommer", systemImage: "pencil") { startRenaming(playlist) }
                    .tint(.waveEmerald)
            }
            .contextMenu {
                Button("Renommer", systemImage: "pencil") { startRenaming(playlist) }
                Button("Supprimer", systemImage: "trash", role: .destructive) {
                    deleting = playlist
                }
            }
        }
        .listStyle(.plain)
    }

    private func startCreating() {
        newName = ""
        creating = true
    }

    private func startRenaming(_ playlist: Playlist) {
        renamedName = playlist.name
        renaming = playlist
    }
}
