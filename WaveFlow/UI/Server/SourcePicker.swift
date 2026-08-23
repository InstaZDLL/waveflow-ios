import SwiftUI

/// La source affichée, portée par l'environnement.
///
/// Dans l'environnement plutôt que passée de vue en vue : le sélecteur apparaît
/// en tête de chaque écran racine, et chacun doit pouvoir le lire et le changer
/// sans que `RootView` ait à traverser cinq niveaux de vues pour le lui donner.
extension EnvironmentValues {
    @Entry var musicSource: Binding<MusicSource> = .constant(.local)
}

nonisolated extension View {

    /// Le sélecteur de source, en tête de barre de titre.
    ///
    /// Un menu et non un `Picker` segmenté : celui-ci prendrait toute la
    /// largeur de la barre sur les écrans qui ont déjà un titre, et la source
    /// change rarement — elle mérite un bouton discret qui dit où l'on est,
    /// pas un commutateur permanent.
    func sourcePicker() -> some View {
        modifier(SourcePickerModifier())
    }
}

private struct SourcePickerModifier: ViewModifier {

    @Environment(\.musicSource) private var source

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Source", selection: source) {
                        ForEach(MusicSource.allCases, id: \.self) { source in
                            Label(source.label, systemImage: source.symbol).tag(source)
                        }
                    }
                } label: {
                    Label("Source", systemImage: source.wrappedValue.symbol)
                }
            }
        }
    }
}
