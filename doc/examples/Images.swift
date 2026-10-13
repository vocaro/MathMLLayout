import CoreGraphics
import Foundation
import MathMLLayout

func style(images: [String: CGImage]) -> MathStyle {
    let provider = MathImageProvider { source in images[source] }
    return MathStyle(fontSize: 17, color: CGColor(gray: 0, alpha: 1), imageProvider: provider)
}

func retinaStyle(images: [String: CGImage]) -> MathStyle {
    let provider = MathImageProvider.resolving { source in
        images[source].map { MathImage($0, scale: 2) }
    }
    return MathStyle(fontSize: 17, color: CGColor(gray: 0, alpha: 1), imageProvider: provider)
}
