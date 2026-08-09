import SwiftUI

/// Pochette d'album, avec repli sur une note de musique.
///
/// Les pochettes sont des fichiers du cache disque, pas des URL réseau :
/// `AsyncImage` sait les charger et garde le décodage hors du thread principal.
struct ArtworkView: View {

    let url: URL?
    var cornerRadius: CGFloat = 6

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: "music.note")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        }
    }
}
