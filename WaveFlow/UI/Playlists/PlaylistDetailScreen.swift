import SwiftUI

/// Détail d'une playlist : en-tête et contenu.
///
/// Comme les écrans d'album et d'artiste, il ne reçoit que l'identifiant et
/// relit le store : une playlist renommée ou vidée depuis ailleurs se reflète
/// ici au lieu de laisser un instantané périmé.
struct PlaylistDetailScreen: View {

    let playlistId: Playlist.ID

    @Environment(PlaylistStore.self) private var store
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(PlaybackController.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var renaming = false
    @State private var renamedName = ""
    @State private var deleting = false

    private var playlist: Playlist? { store.playlist(playlistId) }

    var body: some View {
        Group {
            if let playlist {
                // Résolu une fois par rendu et passé aux vues filles : chaque
                // accès parcourt toute la playlist contre l'index de la
                // bibliothèque, et l'en-tête, la liste et le pied en avaient
                // besoin séparément.
                content(for: playlist, songs: playlist.songs(in: libraryStore.library))
            } else {
                // La playlist vient d'être supprimée — depuis cet écran ou un
                // autre. On le dit plutôt que d'afficher une coquille vide.
                ContentUnavailableView("Playlist introuvable", systemImage: "music.note.list")
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let playlist {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Options de la playlist", systemImage: "ellipsis.circle") {
                        Button("Renommer", systemImage: "pencil") {
                            renamedName = playlist.name
                            renaming = true
                        }
                        Button("Supprimer", systemImage: "trash", role: .destructive) {
                            deleting = true
                        }
                    }
                }
            }
        }
        .playlistNameAlert(
            "Renommer la playlist",
            confirmLabel: "Renommer",
            isPresented: $renaming,
            name: $renamedName,
            onConfirm: { store.rename(playlistId, to: $0) },
        )
        .confirmationDialog(
            "Supprimer « \(playlist?.name ?? "") » ?",
            isPresented: $deleting,
            titleVisibility: .visible,
        ) {
            Button("Supprimer", role: .destructive) {
                store.delete(playlistId)
                // On quitte tout de suite : rester afficherait « playlist
                // introuvable » le temps que le flux réémette.
                dismiss()
            }
        } message: {
            Text("Les morceaux restent sur l'appareil.")
        }
    }

    private func content(for playlist: Playlist, songs: [Song]) -> some View {
        List {
            Section {
                ForEach(songs) { song in
                    Button {
                        player.play(song, in: songs)
                    } label: {
                        SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("Retirer", systemImage: "minus.circle", role: .destructive) {
                            store.remove(song.id, from: playlistId)
                        }
                    }
                }
            } header: {
                header(for: playlist, songs: songs)
                    .textCase(nil)
            } footer: {
                missingFilesNotice(for: playlist, songs: songs)
            }
        }
        .listStyle(.plain)
    }

    private func header(for playlist: Playlist, songs: [Song]) -> some View {
        DetailHeader(
            artworkURL: songs.first?.artworkURL,
            title: playlist.name,
            subtitle: "\(trackCountLabel(songs.count)) · \(formatTotalDuration(songs.reduce(0) { $0 + $1.duration }))",
            songs: songs,
        )
    }

    /// Des identifiants sans morceau correspondant : les fichiers ont été
    /// retirés de `Documents`.
    ///
    /// Dit plutôt que taire : sans ça, une playlist de dix titres qui n'en affiche
    /// que trois passerait pour un bug. Rien n'est retiré de la playlist — le
    /// fichier peut être réimporté.
    @ViewBuilder
    private func missingFilesNotice(for playlist: Playlist, songs: [Song]) -> some View {
        let missing = playlist.songIds.count - songs.count
        if missing > 0 {
            Text("\(trackCountLabel(missing)) introuvable\(missing > 1 ? "s" : "") sur l'appareil. Réimporte le fichier pour le retrouver ici.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
