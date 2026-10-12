import CoreGraphics
import Foundation
import MathMLLayout

func style(images: [String: CGImage]) -> MathStyle {
    let provider = MathImageProvider { source in images[source] }
    return MathStyle(fontSize: 17, color: CGColor(gray: 0, alpha: 1), imageProvider: provider)
}
