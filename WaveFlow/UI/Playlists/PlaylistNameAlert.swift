import SwiftUI

nonisolated extension View {

    /// Saisie du nom d'une playlist, à la création comme au renommage.
    ///
    /// Une alerte plutôt qu'une feuille : c'est un champ unique, et iOS sait
    /// loger un `TextField` dans une alerte depuis iOS 16. Android utilise un
    /// `AlertDialog` pour la même raison.
    ///
    /// La validation est bloquée tant que le champ est blanc, ce qui évite de
    /// faire descendre un nom vide dans la chaîne — le store le refuserait en
    /// silence, sans que l'utilisateur comprenne pourquoi rien ne se passe.
    func playlistNameAlert(
        _ title: String,
        confirmLabel: String,
        isPresented: Binding<Bool>,
        name: Binding<String>,
        onConfirm: @escaping (String) -> Void,
    ) -> some View {
        alert(title, isPresented: isPresented) {
            TextField("Nom", text: name)
                .textInputAutocapitalization(.sentences)

            Button("Annuler", role: .cancel) {}

            Button(confirmLabel) { onConfirm(name.wrappedValue) }
                .disabled(name.wrappedValue.nonBlank == nil)
        }
    }
}
