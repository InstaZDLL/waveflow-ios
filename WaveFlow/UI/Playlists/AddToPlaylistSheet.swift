import SwiftUI

/// Feuille d'ajout d'un morceau à une playlist, ouverte par appui long depuis
/// n'importe quelle liste de morceaux.
///
/// L'appui long est le geste d'Android ; sur iOS c'est un menu contextuel, mais
/// la feuille qu'il ouvre est la même.
struct AddToPlaylistSheet: View {

    let song: Song

    @Environment(PlaylistStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Nouvelle playlist", systemImage: "plus") {
                        newName = ""
                        creating = true
                    }
                }

                // Les états vides et en erreur sont des lignes de la liste, pas
                // un `overlay` : superposer une vue pleine hauteur au-dessus de
                // « Nouvelle playlist » reviendrait à parier sur son
                // comportement au toucher, alors que c'est la seule action
                // encore utile quand il n'y a rien à afficher.
                if let message = store.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                        Button("Réessayer") { store.retry() }
                    }
                } else if store.isEmpty {
                    Section {
                        Text("Aucune playlist. Crée-en une pour y ranger « \(song.title) ».")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(store.playlists) { playlist in
                            row(for: playlist)
                        }
                    }
                }
            }
            .navigationTitle("Ajouter à…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .playlistNameAlert(
            "Nouvelle playlist",
            confirmLabel: "Créer",
            isPresented: $creating,
            name: $newName,
            onConfirm: { name in
                // Créée avec le morceau dedans, en une seule opération : c'est
                // le contrat de `create(name:containing:)`, et une interruption
                // ne peut pas laisser une playlist vide derrière elle.
                store.create(name: name, containing: song.id)
                dismiss()
            },
        )
    }

    private func row(for playlist: Playlist) -> some View {
        // Le modèle ignore un ajout en double ; le dire évite un appui qui
        // semblerait sans effet.
        let alreadyThere = playlist.songIds.contains(song.id)

        return Button {
            store.add(song.id, to: playlist.id)
            dismiss()
        } label: {
            HStack {
                Text(playlist.name)
                    .foregroundStyle(.primary)
                Spacer()
                if alreadyThere {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Déjà dans cette playlist")
                }
            }
        }
        .disabled(alreadyThere)
    }
}
