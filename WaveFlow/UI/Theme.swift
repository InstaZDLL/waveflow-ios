import SwiftUI

/// Palette WaveFlow — accent émeraude, le preset par défaut du desktop.
///
/// Android redéfinit tout le `ColorScheme` Material ; ici on se contente de
/// l'accent et de quelques teintes de fond, et on laisse les couleurs
/// sémantiques d'iOS (`.primary`, `.secondary`, `.background`) faire le reste :
/// elles suivent déjà le mode clair/sombre et les réglages d'accessibilité.
nonisolated extension Color {

    static let waveEmerald = Color(red: 0x10 / 255, green: 0xB9 / 255, blue: 0x81 / 255)
    static let waveEmeraldDark = Color(red: 0x05 / 255, green: 0x96 / 255, blue: 0x69 / 255)
    static let waveEmeraldLight = Color(red: 0x6E / 255, green: 0xE7 / 255, blue: 0xB7 / 255)
}
