import CoreGraphics
import CoreText
@testable import MathMLLayout
import XCTest

final class HorizontalArrowRegressionTests: XCTestCase {
    private let singleArrows: [(long: Unicode.Scalar, short: Unicode.Scalar)] = [
        ("⟵", "←"), ("⟶", "→"), ("⟷", "↔"),
    ]

    private func context(size: CGFloat) -> LayoutContext {
        LayoutContext(fontSize: size, unclampedSize: size, minSize: min(size, 8), display: false, color: black)
    }

    private func stretched(_ arrow: Unicode.Scalar, width: CGFloat, size: CGFloat = em,
                           font: String? = nil) throws -> MathBox {
        try LayoutEngine(fontName: font).layout(mo(String(arrow)), context(size: size),
                                               Embellishment(stretch: .horizontal(width: width)), depth: 0)
    }

    func testLongSingleArrowsUseTheirShortFormsAssembly() throws {
        let font = MathFont.named(nil)
        XCTAssertEqual(CTFontCopyPostScriptName(font.base) as String, "STIXTwoMath-Regular")
        let table = try XCTUnwrap(font.table)
        for (long, short) in singleArrows {
            let longGlyph = try XCTUnwrap(font.glyph(for: long)), shortGlyph = try XCTUnwrap(font.glyph(for: short))
            XCTAssertNil(table.construction(longGlyph, vertical: false), "\(long) needs its short form")
            XCTAssertFalse(try XCTUnwrap(table.construction(shortGlyph, vertical: false)).parts.isEmpty, "\(short)")
            for width: CGFloat in [80, 200] {
                let actual = try stretched(long, width: width), expected = try stretched(short, width: width)
                guard actual.items.count == 1, expected.items.count == 1,
                      case .glyphs(let longRun) = actual.items[0], case .glyphs(let shortRun) = expected.items[0] else {
                    return XCTFail("\(long) and \(short) must be glyph assemblies")
                }
                XCTAssertGreaterThan(longRun.glyphs.count, 1, "\(long)")
                XCTAssertEqual(longRun.glyphs, shortRun.glyphs, "\(long)")
                XCTAssertEqual(longRun.positions, shortRun.positions, "\(long)")
                XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, "\(long)")
                // Connector limits can make a font assembly exceed the requested width.
                XCTAssertGreaterThanOrEqual(actual.width, width - 0.001, "\(long)")
                XCTAssertLessThan(actual.width, width + em, "\(long)")
                XCTAssertEqual(actual.inkBounds, expected.inkBounds, "\(long)")
                XCTAssertEqual(actual.ascent, expected.ascent, "\(long)")
                XCTAssertEqual(actual.descent, expected.descent, "\(long)")
            }
            // Asking for less than the natural width retains the long glyph.
            let engine = LayoutEngine(fontName: nil), natural = engine.glyphBox(longGlyph, context(size: em))
            XCTAssertNil(engine.stretchHorizontally(glyph: longGlyph, scalar: long, natural: natural,
                                                   width: natural.width, context(size: em)))
        }
    }

    func testLongSingleArrowsDrawWithoutAMathTableAtTheRuleWeight() throws {
        let font = MathFont.named("Helvetica")
        XCTAssertNil(font.table)
        for size: CGFloat in [4, 20, 72] {
            let rule = max(font.constants.fractionRuleThickness * size, 0.5)
            for (long, short) in singleArrows {
                let box = try stretched(long, width: size * 4, size: size, font: "Helvetica")
                guard box.items.count == 1, case .path(_, let stroke, _, let fill) = box.items[0] else {
                    return XCTFail("\(long) must draw without MATH")
                }
                XCTAssertFalse(fill, "\(long)")
                XCTAssertEqual(stroke, rule, accuracy: 0.001, "\(long) at \(size)")
                XCTAssertEqual(box.width, size * 4, accuracy: 0.001, "\(long)")
                let ink = try XCTUnwrap(box.inkBounds)
                XCTAssertGreaterThanOrEqual(ink.minX, 0, "\(long)")
                XCTAssertLessThanOrEqual(ink.maxX, box.width, "\(long)")
                XCTAssertLessThanOrEqual(ink.maxY, box.ascent, "\(long)")
                XCTAssertGreaterThanOrEqual(ink.minY, -box.descent, "\(long)")
                let shortBox = try stretched(short, width: size * 4, size: size, font: "Helvetica")
                XCTAssertEqual(ink.width, try XCTUnwrap(shortBox.inkBounds).width, accuracy: 0.001, "\(long)")
                XCTAssertEqual(ink.height, try XCTUnwrap(shortBox.inkBounds).height, accuracy: 0.001, "\(long)")
            }
        }
    }

    func testDrawnArrowWeightLeavesDelimiterWeightUnchanged() throws {
        for fontName in [nil, "Helvetica"] as [String?] {
            let engine = LayoutEngine(fontName: fontName), font = MathFont.named(fontName)
            for size: CGFloat in [4, 20, 72] {
                let box = try stretched("⇌", width: size * 4, size: size, font: fontName)
                guard box.items.count == 1, case .path(_, let arrowStroke, _, _) = box.items[0] else {
                    return XCTFail("⇌ should exercise the drawn fallback")
                }
                let delimiter = try XCTUnwrap(engine.drawnDelimiter("[", height: size * 4, context(size: size)))
                guard delimiter.items.count == 1, case .path(_, let delimiterStroke, _, _) = delimiter.items[0] else {
                    return XCTFail("the bracket must be a drawn delimiter")
                }
                let rule = font.constants.fractionRuleThickness * size
                XCTAssertEqual(arrowStroke, max(rule, 0.5), accuracy: 0.001)
                XCTAssertEqual(delimiterStroke, max(rule * 1.2, 0.5), accuracy: 0.001)
                if size == 4 { XCTAssertEqual(arrowStroke, 0.5) }
            }
        }
    }

    func testRenderedLongArrowsMatchShortArrowsAndDrawnShaftsMatchRuleWeight() throws {
        let size: CGFloat = 72, width = size * 4
        func rendering(_ arrow: Unicode.Scalar, font: String? = nil) throws -> Rendering {
            Rendering(try typeset("<munder><mo>\(arrow)</mo><mspace width=\"\(width)px\"/></munder>", size: size, font: font))
        }
        for (long, short) in singleArrows {
            let actual = try rendering(long), expected = try rendering(short)
            XCTAssertEqual(actual.bounds(), expected.bounds(), "\(long) must render its short form's ink")
            assertBoxCoversInk(actual.layout, "\(long)", rendering: actual)
        }
        // Integrated alpha through the middle of the arrow measures shaft weight without
        // including its heads or depending on where antialiasing places the outermost pixel.
        func shaftWeight(_ rendering: Rendering) -> CGFloat {
            let step = 1 / rendering.scale
            return stride(from: -rendering.layout.descent - 1 + step / 2,
                          to: rendering.layout.ascent + 1, by: step).reduce(0) {
                $0 + rendering.color(at: CGPoint(x: width / 2, y: $1)).alpha * step
            }
        }
        let mathRule = MathFont.named(nil).constants.fractionRuleThickness * size
        // STIX's shaft outline is slightly heavier than its fraction rule; both are close
        // enough that the former 1.2 multiplier would produce visibly heavier drawn shafts.
        XCTAssertEqual(shaftWeight(try rendering("→")), mathRule, accuracy: 0.25, "assembled font shaft")
        XCTAssertEqual(shaftWeight(try rendering("⇌")), 2 * mathRule, accuracy: 0.1, "two drawn shafts")
        let textRule = MathFont.named("Helvetica").constants.fractionRuleThickness * size
        for (long, _) in singleArrows {
            let drawn = try rendering(long, font: "Helvetica")
            XCTAssertEqual(shaftWeight(drawn), textRule, accuracy: 0.1, "\(long) drawn shaft")
            assertBoxCoversInk(drawn.layout, "\(long) in Helvetica", rendering: drawn)
        }
    }
}
