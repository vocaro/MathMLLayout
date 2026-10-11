import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

/// What every test class shares: parsing a `math` body, laying it out, and measuring its ink.
class MathTestCase: XCTestCase {
    let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

    func node(_ body: String, display: Bool = false) throws -> MathMLNode {
        let attribute = display ? " display=\"block\"" : ""
        return try MathMLNode.parse(xml: Data("<math xmlns=\"http://www.w3.org/1998/Math/MathML\"\(attribute)>\(body)</math>".utf8))
    }

    func layout(_ body: String, size: CGFloat = 20, display: Bool = false, font: String? = nil) throws -> MathLayout {
        try MathLayout(node(body, display: display), style: MathStyle(fontSize: size, color: black, fontName: font))
    }

    func height(_ layout: MathLayout) -> CGFloat { layout.ascent + layout.descent }

    /// Draws `layout` into a bitmap with a margin and returns the bounds of its ink, in
    /// points relative to the baseline origin (y up).
    func ink(_ layout: MathLayout, margin: CGFloat = 20) -> CGRect? {
        let scale: CGFloat = 2
        let width = Int((layout.width + 2 * margin) * scale), height = Int((self.height(layout) + 2 * margin) * scale)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        layout.draw(in: context, baselineOrigin: CGPoint(x: margin, y: margin + layout.descent))
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for row in 0..<height {
            for column in 0..<width where pixels[(row * width + column) * 4 + 3] > 24 {
                minX = min(minX, column); maxX = max(maxX, column); minY = min(minY, row); maxY = max(maxY, row)
            }
        }
        guard maxX >= 0 else { return nil }
        // Bitmap rows run top-down.
        let top = CGFloat(height - minY) / scale, bottom = CGFloat(height - maxY - 1) / scale
        return CGRect(x: CGFloat(minX) / scale - margin, y: bottom - margin - layout.descent,
                      width: CGFloat(maxX - minX + 1) / scale, height: top - bottom)
    }
}
