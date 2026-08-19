import SwiftUI

nonisolated extension View {

    /// Menu d'appui long sur une ligne de morceau : « ajouter à une playlist ».
    ///
    /// L'appui long est le geste d'Android ; sur iOS c'est un menu contextuel,
    /// et il ouvre la même feuille. Posé partout où l'application liste des
    /// morceaux, sauf dans le détail d'une playlist, où le geste sert déjà à en
    /// retirer — c'est le partage qu'Android a retenu.
    ///
    /// La sélection appartient à l'écran, pas à la ligne : une seule feuille
    /// pour toute la liste. Une feuille par ligne serait attachée à une vue que
    /// la liste peut recycler en défilant.
    func addToPlaylistMenu(for song: Song, selection: Binding<Song?>) -> some View {
        contextMenu {
            Button("Ajouter à une playlist…", systemImage: "text.badge.plus") {
                selection.wrappedValue = song
            }
        }
    }
}
