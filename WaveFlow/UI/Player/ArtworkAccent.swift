import SwiftUI
import UIKit

/// Couleur dominante d'une pochette, utilisée pour teinter le lecteur.
///
/// Android passe par `Palette` (AndroidX) ; iOS n'a pas d'équivalent, alors on
/// réduit l'image à un pixel — la moyenne pondérée que fait le rééchantillonnage
/// est une approximation suffisante pour un fond.
nonisolated enum ArtworkAccent {

    /// Teinte de repli quand le morceau n'a pas de pochette.
    static let fallback = Color.waveEmeraldDark

    static func color(for url: URL?) async -> Color {
        guard let url else { return fallback }

        return await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data),
                  let averaged = image.averageColor
            else { return fallback }
            return Color(averaged.readableAsBackground)
        }.value
    }
}

private nonisolated extension UIImage {

    /// Moyenne des pixels, obtenue en dessinant l'image dans un contexte 1×1.
    var averageColor: UIColor? {
        guard let cgImage else { return nil }

        var pixel: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        return UIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1,
        )
    }
}

private nonisolated extension UIColor {

    /// Ravive la teinte et borne la luminosité.
    ///
    /// La moyenne d'une pochette tire vers le gris terne, et une pochette très
    /// claire donnerait un fond sur lequel le texte blanc disparaît.
    var readableAsBackground: UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }

        return UIColor(
            hue: hue,
            saturation: min(saturation * 1.4, 0.7),
            brightness: min(max(brightness, 0.18), 0.45),
            alpha: 1,
        )
    }
}
