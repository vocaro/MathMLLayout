import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

/// The oracle is direct CoreText lookup and drawing in an explicitly named real font, rather
/// than Unicode shaping. Font updates do not change the expected relationship to that font.
final class LegacyGlyphTests: MathTestCase {
    private let fontName = "TimesNewRomanPSMT"

    private func selected(size: CGFloat = 20) throws -> CTFont {
        let font = CTFontCreateWithName(fontName as CFString, size, nil)
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, fontName)
        return font
    }

    private func id(_ character: UniChar = 65, in font: CTFont) throws -> CGGlyph {
        var character = character, glyph: CGGlyph = 0
        XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &character, &glyph, 1))
        return try XCTUnwrap(glyph == 0 ? nil : glyph)
    }

    private func box(_ body: String, size: CGFloat = 20, images: MathImageProvider? = nil) throws -> MathBox {
        let engine = LayoutEngine(fontName: "STIXTwoMath-Regular")
        engine.imageProvider = images
        return try engine.layout(node(body), LayoutContext(fontSize: size, unclampedSize: size,
                                 minSize: 8, display: false, color: black), depth: 0)
    }

    private func markup(_ index: CGGlyph, attributes: String = "") -> String {
        "<mglyph fontfamily=\"\(fontName)\" index=\"\(index)\" alt=\"fallback\" \(attributes)/>"
    }

    private func runs(_ box: MathBox) -> [GlyphRun] {
        box.items.flatMap { item -> [GlyphRun] in
            switch item {
            case .glyphs(let run): [run]
            case .box(let inner, _): runs(inner)
            default: []
            }
        }
    }

    private func raster(_ draw: (CGContext) -> Void) -> [UInt8] {
        let context = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 512,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(context)
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: 128 * 512))
    }

    func testActualIndexGeometryAndDrawing() throws {
        let font = try selected(), glyph = try id(in: font)
        XCTAssertNotEqual(glyph, 65, "The fixture must distinguish glyph ID from Unicode A")
        let actual = try box("<mi>\(markup(glyph))</mi>")
        let run = try XCTUnwrap(runs(actual).first)
        XCTAssertEqual(runs(actual).count, 1)
        XCTAssertEqual(CTFontCopyPostScriptName(run.font) as String, fontName)
        XCTAssertEqual(run.glyphs, [glyph])
        XCTAssertEqual(run.positions, [.zero])
        var expectedGlyph = glyph, rect = CGRect.zero, advance = CGSize.zero
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &expectedGlyph, &rect, 1)
        CTFontGetAdvancesForGlyphs(font, .horizontal, &expectedGlyph, &advance, 1)
        XCTAssertEqual(actual.width, advance.width, accuracy: 1e-8)
        XCTAssertEqual(actual.ascent, rect.maxY, accuracy: 1e-8)
        XCTAssertEqual(actual.descent, -rect.minY, accuracy: 1e-8)
        XCTAssertEqual(actual.inkBounds, rect)
        let origin = CGPoint(x: 32, y: 32)
        let actualPixels = raster { actual.draw(in: $0, at: origin) }
        let expectedPixels = raster {
            $0.setFillColor(black)
            CTFontDrawGlyphs(font, [glyph], [origin], 1, $0)
        }
        XCTAssertEqual(actualPixels, expectedPixels)
        XCTAssertTrue(actualPixels.contains { $0 > 0 })
    }

    func testFamilyFullNameQuotesAndSignedDecimal() throws {
        let font = try selected(), glyph = try id(in: font)
        for name in [fontName, CTFontCopyFamilyName(font) as String, CTFontCopyFullName(font) as String,
                     "'\(fontName)'"] {
            let actual = try box("<mtext><mglyph fontfamily=\"\(name)\" index=\" +00\(glyph) \" alt=\"fallback\"/></mtext>")
            let run = try XCTUnwrap(runs(actual).first)
            XCTAssertEqual(run.glyphs, [glyph])
            XCTAssertEqual(CTFontCopyFamilyName(run.font), CTFontCopyFamilyName(font))
        }
    }

    func testInheritedStylesAndOwnAttributes() throws {
        let font = try selected(), glyph = try id(in: font)
        let own = markup(glyph, attributes: "mathsize=\"99px\" mathcolor=\"blue\" mathvariant=\"double-struck\"")
        for variant in ["normal", "bold", "italic", "bold-italic"] {
            let actual = try box("<mstyle mathsize=\"32px\" mathcolor=\"red\" mathvariant=\"\(variant)\"><mi>\(own)</mi></mstyle>")
            let run = try XCTUnwrap(runs(actual).first)
            XCTAssertEqual(CTFontGetSize(run.font), 32)
            XCTAssertEqual(run.glyphs, [glyph])
            XCTAssertEqual(CTFontCopyFamilyName(run.font), CTFontCopyFamilyName(font))
            XCTAssertEqual(run.color.components, [1, 0, 0, 1])
            let traits = CTFontGetSymbolicTraits(run.font)
            if variant.contains("bold") { XCTAssertTrue(traits.contains(.traitBold)) }
            if variant.contains("italic") { XCTAssertTrue(traits.contains(.traitItalic)) }
        }
        let script = try box("<msup><mi>x</mi><mi>\(markup(glyph))</mi></msup>")
        let legacy = try XCTUnwrap(runs(script).first { CTFontCopyFamilyName($0.font) == CTFontCopyFamilyName(font) })
        XCTAssertLessThan(CTFontGetSize(legacy.font), 20)
        XCTAssertGreaterThanOrEqual(CTFontGetSize(legacy.font), 8)
        // STIX Two Math has no bold face: inherited bold may use the explicitly named face.
        let fallbackFace = try XCTUnwrap(LegacyGlyphFonts().font(name: "STIXTwoMath-Regular", variant: .bold, size: 20))
        XCTAssertEqual(CTFontCopyPostScriptName(fallbackFace) as String, "STIXTwoMath-Regular")
        let rowLevel = try box(own), tokenLevel = try box("<mtext>\(own)</mtext>")
        XCTAssertEqual(rowLevel.width, tokenLevel.width)
        XCTAssertEqual(runs(rowLevel).map(\.glyphs), runs(tokenLevel).map(\.glyphs))
    }

    func testInvalidAndUnsupportedFormsUseAlt() throws {
        let font = try selected(), glyph = try id(in: font)
        let fallback = try box("<mtext>fallback</mtext>")
        let badIndices = ["", "0", "-1", "1.5", "0x24", "65536", "999999999999999999999999", "١", String(repeating: " ", count: 65) + String(glyph), String(CTFontGetGlyphCount(font))]
        for index in badIndices {
            let actual = try box("<mi><mglyph fontfamily=\"\(fontName)\" index=\"\(index)\" alt=\"fallback\"/></mi>")
            XCTAssertEqual(actual.width, fallback.width, index)
            XCTAssertEqual(runs(actual).map(\.glyphs), runs(fallback).map(\.glyphs), index)
        }
        for name in ["NotAnInstalledMathFont-79", "serif", "\(fontName), serif", String(repeating: "a", count: 257)] {
            let actual = try box("<mi><mglyph fontfamily=\"\(name)\" index=\"\(glyph)\" alt=\"fallback\"/></mi>")
            XCTAssertEqual(actual.width, fallback.width, name)
        }
        for attributes in ["width=\"2em\"", "height=\"2em\"", "valign=\"0\"", "src=\"\"", "src=\"missing\""] {
            XCTAssertEqual(try box("<mi>\(markup(glyph, attributes: attributes))</mi>").width, fallback.width, attributes)
        }
        for variant in ["script", "double-struck", "sans-serif", "monospace"] {
            let actual = try box("<mi mathvariant=\"\(variant)\">\(markup(glyph))</mi>")
            let expected = try box("<mtext mathvariant=\"\(variant)\">fallback</mtext>")
            XCTAssertEqual(actual.width, expected.width, variant)
        }
        XCTAssertEqual(try box("<mi><mglyph fontfamily=\"\(fontName)\"/></mi>").width, try box("<mtext>▯</mtext>").width)
    }

    func testSourcePrecedenceEvenWhenProviderCannotResolveIt() throws {
        let font = try selected(), glyph = try id(in: font)
        let context = CGContext(data: nil, width: 7, height: 11, bitsPerComponent: 8, bytesPerRow: 28,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = try XCTUnwrap(context.makeImage())
        let provider = MathImageProvider { $0 == "image" ? image : nil }
        let found = try box("<mi>\(markup(glyph, attributes: "src=\"image\""))</mi>", images: provider)
        XCTAssertEqual(found.width, 7)
        XCTAssertEqual(found.ascent, 11)
        XCTAssertTrue(runs(found).isEmpty)
        for src in ["", "missing"] {
            let missing = try box("<mi>\(markup(glyph, attributes: "src=\"\(src)\""))</mi>", images: provider)
            XCTAssertEqual(missing.width, try box("<mtext>fallback</mtext>").width)
        }
    }

    func testMixedTextBackgroundAndRootInk() throws {
        let font = try selected(), glyph = try id(106, in: font) // j has descent and may overhang.
        let legacy = markup(glyph, attributes: "mathbackground=\"yellow\"")
        let actual = try box("<mtext>a\(legacy)b</mtext>")
        let parts = try [box("<mtext>a</mtext>"), box("<mtext>\(legacy)</mtext>"), box("<mtext>b</mtext>")]
        XCTAssertEqual(actual.width, parts.reduce(0) { $0 + $1.width }, accuracy: 1e-8)
        XCTAssertEqual(runs(actual).count, 3)
        let drawn = try layout("<mi>\(legacy)</mi>")
        let ink = try XCTUnwrap(ink(drawn))
        XCTAssertGreaterThan(ink.width, 0)
        XCTAssertGreaterThan(ink.height, 0)
        XCTAssertGreaterThanOrEqual(ink.minX, -0.5)
        XCTAssertLessThanOrEqual(ink.maxX, drawn.width + 0.5)
        XCTAssertLessThanOrEqual(ink.maxY, drawn.ascent + 0.5)
        XCTAssertGreaterThanOrEqual(ink.minY, -drawn.descent - 0.5)
    }

    func testZeroAdvanceCombiningGlyphAndOperatorSize() throws {
        let name = "STIXTwoMath-Regular"
        let font = CTFontCreateWithName(name as CFString, 20, nil)
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, name)
        let glyph = try id(0x302, in: font)
        var rawGlyph = glyph, rect = CGRect.zero, advance = CGSize.zero
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &rawGlyph, &rect, 1)
        CTFontGetAdvancesForGlyphs(font, .horizontal, &rawGlyph, &advance, 1)
        XCTAssertEqual(advance.width, 0)
        let mark = "<mglyph fontfamily=\"\(name)\" index=\"\(glyph)\" alt=\"fallback\"/>"
        let actual = try box("<mi>\(mark)</mi>")
        XCTAssertEqual(actual.width, rect.width)
        XCTAssertEqual(try XCTUnwrap(actual.inkBounds).minX, 0, accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(runs(actual).first).positions, [CGPoint(x: -rect.minX, y: 0)])
        let rawFont = try selected(), ordinary = try id(in: rawFont)
        let tokenBox = try box("<mtext>\(markup(ordinary))</mtext>")
        for attributes in ["", "stretchy=\"false\" largeop=\"false\""] {
            let authored = try box("<mo displaystyle=\"true\" \(attributes)>\(markup(ordinary))</mo>")
            XCTAssertEqual(authored.width, tokenBox.width)
            XCTAssertEqual(authored.height, tokenBox.height)
            XCTAssertEqual(runs(authored).map(\.glyphs), runs(tokenBox).map(\.glyphs))
        }
        // Explicit #80 opt-ins apply to legacy glyphs too, preserving their actual ID while
        // changing whole-token geometry through the font matrix rather than Unicode shaping.
        let enlarged = try box("<mo stretchy=\"true\" largeop=\"true\" displaystyle=\"true\">\(markup(ordinary))</mo>")
        XCTAssertGreaterThan(enlarged.height, tokenBox.height)
        XCTAssertGreaterThan(enlarged.width, tokenBox.width)
        XCTAssertEqual(runs(enlarged).map(\.glyphs), runs(tokenBox).map(\.glyphs))
        XCTAssertNotEqual(CTFontGetMatrix(try XCTUnwrap(runs(enlarged).first).font), CGAffineTransform.identity)
    }

    func testNestedGlyphsShareTheFormulaNodeBudget() throws {
        let font = try selected(), glyph = try id(in: font)
        let leaf = MathMLNode(name: "mglyph", attributes: ["fontfamily": fontName, "index": String(glyph)])
        func root(_ first: Int, _ second: Int) -> MathMLNode {
            MathMLNode(name: "math", children: [
                MathMLNode(name: "mtext", children: Array(repeating: leaf, count: first)),
                MathMLNode(name: "mtext", children: Array(repeating: leaf, count: second)),
            ])
        }
        let style = MathStyle(fontSize: 1, color: black)
        // Three containers plus these glyphs: exactly 20,000 source nodes, then one more.
        XCTAssertNoThrow(try LayoutEngine(fontName: nil).layoutRoot(root(9_998, 9_999), style: style))
        XCTAssertThrowsError(try LayoutEngine(fontName: nil).layoutRoot(root(9_999, 9_999), style: style)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
        // Each token is below its local glyph bound; the formula's combined count still applies.
        XCTAssertThrowsError(try LayoutEngine(fontName: nil).layoutRoot(root(10_001, 10_001), style: style)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
    }

    func testTraversalAndTextBudgets() throws {
        let font = try selected(), glyph = try id(in: font)
        let leaf = MathMLNode(name: "mglyph", attributes: ["fontfamily": fontName, "index": String(glyph)])
        let engine = LayoutEngine(fontName: nil)
        XCTAssertThrowsError(try engine.layoutRoot(MathMLNode(name: "math", children: Array(repeating: leaf, count: MathLimits.nodes)),
                                                  style: MathStyle(fontSize: 1, color: black))) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
        let body = "<mtext>\(String(repeating: "a", count: MathLimits.textLength))\(markup(glyph))</mtext>"
        XCTAssertThrowsError(try box(body)) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded) }
    }
}
