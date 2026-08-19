import SwiftUI

/// Onglet Recherche : filtre la bibliothèque déjà chargée.
///
/// Aucun état à lui au-delà de la requête — `Library.search` est une fonction
/// pure, recalculée pendant l'évaluation du corps. Là où Android a besoin d'un
/// `SearchViewModel` pour croiser deux flux, il suffit ici de lire le store :
/// un rechargement de la bibliothèque rafraîchit les résultats tout seul.
struct SearchScreen: View {

    /// Pile détenue par `RootView` — voir le commentaire là-bas.
    @Binding var path: NavigationPath

    @Environment(LibraryStore.self) private var store
    @Environment(PlaybackController.self) private var player
    @Environment(\.requestImport) private var requestImport

    @State private var query = ""

    /// Morceau dont la feuille « ajouter à une playlist » est ouverte.
    @State private var songToAdd: Song?

    var body: some View {
        // Filtré une fois par évaluation du corps, puis passé aux sections :
        // une propriété calculée relue à chaque section referait le parcours
        // de la bibliothèque pour chacune d'elles.
        let results = store.library.search(query)

        NavigationStack(path: $path) {
            LibraryStateContainer(
                library: store.library,
                onRetry: { store.retry() },
                onImport: requestImport,
            ) {
                resultList(results)
            }
            .navigationTitle("Recherche")
            .navigationDestination(for: Album.self) { album in
                AlbumDetailScreen(albumId: album.id)
            }
            .navigationDestination(for: Artist.self) { artist in
                ArtistDetailScreen(artistId: artist.id)
            }
        }
        // Posé sur la pile, pas sur le contenu : celui-ci change d'identité à
        // la première lettre frappée — l'invite laisse place à la liste — et
        // le champ perdrait le focus au premier caractère s'il lui était
        // attaché.
        .searchable(text: $query, prompt: "Titres, albums, artistes")
        .sheet(item: $songToAdd) { AddToPlaylistSheet(song: $0) }
    }

    /// Les trois sections partagent une seule liste : un album qui n'apparaît
    /// qu'après trente titres reste atteignable en continuant de faire
    /// défiler, plutôt que caché derrière un onglet de plus.
    @ViewBuilder private func resultList(_ results: SearchResults) -> some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "Rechercher",
                systemImage: "magnifyingglass",
                description: Text("Cherche un titre, un album ou un artiste."),
            )
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                if !results.songs.isEmpty {
                    Section("Titres") {
                        ForEach(results.songs) { song in
                            Button {
                                // La file démarrée depuis la recherche est la
                                // liste des résultats, pas la bibliothèque
                                // entière : ce qui suit le morceau lancé est
                                // ce que l'écran montre.
                                player.play(song, in: results.songs)
                            } label: {
                                SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                            }
                            .buttonStyle(.plain)
                            .addToPlaylistMenu(for: song, selection: $songToAdd)
                        }
                    }
                }

                if !results.albums.isEmpty {
                    Section("Albums") {
                        ForEach(results.albums) { album in
                            NavigationLink(value: album) {
                                MediaRow(
                                    artworkURL: album.artworkURL,
                                    title: album.title,
                                    subtitle: album.displayArtist,
                                )
                            }
                        }
                    }
                }

                if !results.artists.isEmpty {
                    Section("Artistes") {
                        ForEach(results.artists) { artist in
                            NavigationLink(value: artist) {
                                MediaRow(
                                    artworkURL: artist.artworkURL,
                                    title: artist.name,
                                    subtitle: "\(albumCountLabel(artist.albumCount)) · \(trackCountLabel(artist.trackCount))",
                                    artworkCornerRadius: 24,
                                )
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
