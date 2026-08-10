import SwiftUI

/// Ligne d'album ou d'artiste : pochette, titre, sous-titre.
///
/// Pendant de `SongRow` pour les regroupements — la liste d'artistes et les
/// sections de la recherche s'en servent, avec pour seule différence la forme
/// de la pochette : ronde pour un artiste, arrondie pour un album.
struct MediaRow: View {

    let artworkURL: URL?
    let title: String
    let subtitle: String

    var artworkCornerRadius: CGFloat = 6

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: artworkURL, cornerRadius: artworkCornerRadius)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
