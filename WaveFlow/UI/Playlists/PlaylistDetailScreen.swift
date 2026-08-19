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

    /// Ordre affiché tant que le stockage n'a pas rendu le même.
    ///
    /// Une liste qu'on réordonne doit suivre le doigt : le déposé est rendu
    /// avant l'aller-retour d'écriture, sinon la ligne lâchée revient à sa
    /// place le temps que le flux réémette. Même rôle que le `working`
    /// d'Android.
    ///
    /// Il tombe quand le stockage a répondu la même chose, et quand il a refusé
    /// d'écrire. Il cesse aussi de s'appliquer si le contenu de la playlist
    /// bouge — voir [displayedSongs(of:)].
    @State private var reordered: [Song]?

    private var playlist: Playlist? { store.playlist(playlistId) }

    var body: some View {
        Group {
            if let playlist {
                // Résolu une fois par rendu et passé aux vues filles : chaque
                // accès parcourt toute la playlist contre l'index de la
                // bibliothèque, et l'en-tête, la liste et le pied en avaient
                // besoin séparément.
                content(for: playlist, songs: displayedSongs(of: playlist))
            } else {
                // La playlist vient d'être supprimée — depuis cet écran ou un
                // autre. On le dit plutôt que d'afficher une coquille vide.
                ContentUnavailableView("Playlist introuvable", systemImage: "music.note.list")
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        // Deux façons pour l'ordre optimiste de cesser d'avoir cours.
        //
        // Le stockage a rendu celui qui était demandé : il n'y a plus rien à
        // devancer. `starts(with:)` plutôt qu'une égalité — la normalisation
        // range à la suite les morceaux introuvables sur l'appareil, que
        // l'écran n'a pas listés et n'a donc pas pu demander.
        //
        // Ou le contenu a bougé : l'ordre mémorisé décrit alors une playlist
        // qui n'existe plus, et aucune émission ultérieure ne le validera.
        // Sans ce second cas il resterait indéfiniment en place — inoffensif
        // aujourd'hui, [displayedSongs(of:)] refusant de l'appliquer, mais
        // c'est un état périmé qui n'attend qu'un second réordonnancement
        // venu d'ailleurs pour se remettre à mentir.
        //
        // Une émission qui ne relève ni de l'un ni de l'autre vient d'une
        // écriture plus ancienne — deux glissés rapprochés partent dans deux
        // écritures sérialisées — et l'abandonner là ramènerait l'ordre
        // intermédiaire sous le doigt.
        .onChange(of: playlist?.songIds) { before, stored in
            guard let requested = reordered?.map(\.id) else { return }

            let carriesTheRequest = stored?.starts(with: requested) == true
            let contentChanged = Set(before ?? []) != Set(stored ?? [])

            if carriesTheRequest || contentChanged { reordered = nil }
        }
        .toolbar {
            if let playlist {
                // iOS ne réordonne pas une liste hors du mode édition, là où
                // Android donne une poignée permanente à chaque ligne. Masqué
                // sur une playlist vide : il n'y aurait rien à déplacer ni à
                // retirer. `songIds` plutôt que les morceaux résolus, pour ne
                // pas refaire la jointure ici.
                if !playlist.songIds.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
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

    /// Morceaux à afficher, l'ordre optimiste appliqué tant qu'il tient.
    ///
    /// Il cesse de tenir dès que le contenu bouge — un retrait par balayage,
    /// un ajout depuis un autre écran : il décrit alors une playlist qui
    /// n'existe plus, et l'appliquer afficherait un titre qui n'en fait plus
    /// partie. Comparer les ensembles suffit, les identifiants d'une playlist
    /// étant uniques.
    private func displayedSongs(of playlist: Playlist) -> [Song] {
        let stored = playlist.songs(in: libraryStore.library)

        guard let reordered,
              Set(reordered.map(\.id)) == Set(stored.map(\.id))
        else { return stored }

        return reordered
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
                .onMove { source, destination in
                    move(from: source, to: destination, within: songs)
                }
                // Le retrait du mode édition. Le balayage garde son propre
                // libellé : « Retirer » dit ce que « Supprimer » laisserait
                // craindre — le fichier, lui, reste sur l'appareil.
                .onDelete { offsets in
                    for song in offsets.map({ songs[$0] }) {
                        store.remove(song.id, from: playlistId)
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

    /// Applique le déplacement à l'affichage, puis l'envoie au stockage.
    ///
    /// L'ordre complet part, pas le couple (morceau, destination) : c'est ce
    /// que l'écran connaît, et `Playlist.reorder(to:at:)` s'occupe du reste —
    /// notamment de replacer à la suite les morceaux dont le fichier a quitté
    /// `Documents`, absents d'ici sans l'être de la playlist. Les recalculer
    /// ici reviendrait à tenir deux fois la même règle.
    private func move(from source: IndexSet, to destination: Int, within songs: [Song]) {
        var moved = songs
        moved.move(fromOffsets: source, toOffset: destination)
        reordered = moved

        let requested = moved.map(\.id)
        store.reorder(playlistId, to: requested) {
            // Seulement si l'affichage porte encore cette demande-là. Les
            // écritures sont sérialisées : l'échec de l'une arrive parfois
            // alors qu'un glissé plus récent occupe déjà l'écran, et son ordre
            // à lui reste attendu — il part complet, donc le stockage le
            // retiendra tel quel, échec antérieur ou non.
            guard reordered?.map(\.id) == requested else { return }
            reordered = nil
        }
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
