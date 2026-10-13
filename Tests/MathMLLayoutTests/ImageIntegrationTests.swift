import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

/// Intersections of provider metadata, operator geometry, legacy IDs and elementary columns.
final class ImageIntegrationTests: MathTestCase {
    private func provider() -> MathImageProvider {
        let context = CGContext(data: nil, width: 24, height: 16, bitsPerComponent: 8, bytesPerRow: 96,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
        let image = context.makeImage()!
        return .resolving { $0 == "digit" ? MathImage(image, scale: 2) : nil }
    }

    private func raw(_ tree: MathMLNode, size: CGFloat = 20, images: MathImageProvider? = nil) throws -> MathBox {
        let engine = LayoutEngine(fontName: "STIXTwoMath-Regular")
        engine.imageProvider = images
        return try engine.layout(tree, LayoutContext(fontSize: size, unclampedSize: size,
                                 minSize: min(8, size), display: false, color: black), depth: 0)
    }

    private func box(_ body: String, images: MathImageProvider? = nil) throws -> MathBox {
        try raw(node(body), images: images)
    }

    private func images(_ box: MathBox, origin: CGPoint = .zero) -> [CGRect] {
        box.items.flatMap { item -> [CGRect] in
            switch item {
            case .image(_, let rect, _): [rect.offsetBy(dx: origin.x, dy: origin.y)]
            case .box(let inner, let point): images(inner, origin: CGPoint(x: origin.x + point.x, y: origin.y + point.y))
            default: []
            }
        }
    }

    private func runs(_ box: MathBox, origin: CGPoint = .zero) -> [(GlyphRun, CGPoint)] {
        box.items.flatMap { item -> [(GlyphRun, CGPoint)] in
            switch item {
            case .glyphs(let run): [(run, CGPoint(x: origin.x + (run.positions.first?.x ?? 0),
                                                y: origin.y + (run.positions.first?.y ?? 0)))]
            case .box(let inner, let point): runs(inner, origin: CGPoint(x: origin.x + point.x, y: origin.y + point.y))
            default: []
            }
        }
    }

    private func legacy() throws -> (font: CTFont, glyph: CGGlyph, markup: String) {
        let name = "TimesNewRomanPSMT", font = CTFontCreateWithName("TimesNewRomanPSMT" as CFString, 20, nil)
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, name)
        var character: UniChar = 65, glyph: CGGlyph = 0
        XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &character, &glyph, 1))
        XCTAssertNotEqual(glyph, 0)
        return (font, glyph, "<mglyph fontfamily=\"\(name)\" index=\"\(glyph)\" alt=\"A\"/>")
    }

    func testIntrinsicScalePrecedesWholeOperatorEnlargement() throws {
        let images = provider(), mark = "<mglyph src=\"digit\"/>"
        let natural = try box("<mo>\(mark)</mo>", images: images)
        XCTAssertEqual(natural.width, 12)
        XCTAssertEqual(natural.height, 8)
        let enlarged = try box("<mo largeop=\"true\" displaystyle=\"true\">\(mark)</mo>", images: images)
        let engine = LayoutEngine(fontName: "STIXTwoMath-Regular")
        let expectedHeight = max(engine.constants.displayOperatorMinHeight * 20, 8 * 2.squareRoot())
        XCTAssertEqual(enlarged.height, expectedHeight, accuracy: 1e-8)
        XCTAssertEqual(enlarged.width, 12 * expectedHeight / 8, accuracy: 1e-8)
        let rect = try XCTUnwrap(self.images(enlarged).first)
        XCTAssertEqual(rect.height, expectedHeight, accuracy: 1e-8)
        XCTAssertEqual(rect.width, enlarged.width, accuracy: 1e-8)
        let axis = engine.constants.axisHeight * 20
        XCTAssertEqual(rect.midY, axis, accuracy: 1e-8)
        let disabled = try box("<mo largeop=\"false\" displaystyle=\"true\">\(mark)</mo>", images: images)
        XCTAssertEqual(disabled.width, 12)
        XCTAssertEqual(disabled.height, 8)
    }

    func testScaledImageAndLegacyGlyphEachOccupyOneStackColumn() throws {
        let legacy = try legacy()
        let result = try box("<mstack stackalign=\"left\" charalign=\"left\" charspacing=\"0\"><mn>1<mglyph src=\"digit\"/>2\(legacy.markup)3</mn><mn>12345</mn></mstack>", images: provider())
        let rect = try XCTUnwrap(images(result).first)
        XCTAssertEqual(rect.width, 12)
        XCTAssertEqual(rect.height, 8)
        let placed = runs(result)
        let legacyRun = try XCTUnwrap(placed.first { CTFontCopyPostScriptName($0.0.font) == CTFontCopyPostScriptName(legacy.font) })
        XCTAssertEqual(legacyRun.0.glyphs, [legacy.glyph])
        let lowest = try XCTUnwrap(placed.map { $0.1.y }.min())
        let bottom = placed.filter { abs($0.1.y - lowest) < 1e-8 }.sorted { $0.1.x < $1.1.x }
        XCTAssertEqual(bottom.count, 5)
        XCTAssertEqual(rect.minX, bottom[1].1.x, accuracy: 1e-8)
        XCTAssertEqual(legacyRun.1.x, bottom[3].1.x, accuracy: 1e-8)
    }

    func testElementarySyntheticCellsDoNotChargeGlyphChildrenTwice() throws {
        let legacy = try legacy()
        let leaf = MathMLNode(name: "mglyph", attributes: ["fontfamily": "TimesNewRomanPSMT", "index": String(legacy.glyph)])
        func stack(_ count: Int) -> MathMLNode {
            MathMLNode(name: "mstack", children: [MathMLNode(name: "mn", children: Array(repeating: leaf, count: count))])
        }
        // Existing elementary accounting charges each numeric column and visited source child.
        // The synthetic token resolving a glyph must not charge that source child a second time.
        XCTAssertNoThrow(try raw(stack(9_999), size: 1))
        XCTAssertThrowsError(try raw(stack(10_000), size: 1)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
    }
}
