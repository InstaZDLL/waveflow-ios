import SwiftUI

/// Enveloppe les écrans qui dépendent de la bibliothèque : chargement, erreur
/// et bibliothèque vide sont traités une seule fois, ici.
struct LibraryStateContainer<Content: View>: View {

    let library: Library
    var onRetry: () -> Void
    var onImport: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        if library.isLoading && library.songs.isEmpty {
            ProgressView("Lecture de la bibliothèque…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = library.errorMessage {
            ContentUnavailableView {
                Label("Bibliothèque illisible", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
        } else if library.isEmpty {
            emptyLibrary
        } else {
            content()
        }
    }

    /// Sur Android, l'écran vide veut dire « aucun fichier audio sur
    /// l'appareil ». Ici il faut expliquer *comment* en ajouter : rien n'entre
    /// dans le dossier de l'app tant que l'utilisateur ne l'y met pas.
    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("Aucune musique", systemImage: "music.note.list")
        } description: {
            Text("Importe des fichiers, ou dépose-les dans **Fichiers → Sur mon iPhone → WaveFlow**.")
        } actions: {
            if let onImport {
                Button("Importer des fichiers", systemImage: "square.and.arrow.down", action: onImport)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
