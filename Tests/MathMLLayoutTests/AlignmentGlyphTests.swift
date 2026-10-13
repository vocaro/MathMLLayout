import CoreGraphics
import CoreText
import Foundation
import Synchronization
@testable import MathMLLayout
import XCTest

final class AlignmentGlyphTests: XCTestCase {
    private var context: LayoutContext {
        LayoutContext(fontSize: em, unclampedSize: em, minSize: 8, display: false,
                      color: black, trackAlignment: true)
    }
    private func image() -> CGImage {
        CGContext(data: nil, width: 30, height: 10, bitsPerComponent: 8, bytesPerRow: 120,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
    private func engine(images: Bool = true) -> LayoutEngine {
        let engine = LayoutEngine(fontName: nil)
        if images {
            let image = image()
            engine.imageProvider = MathImageProvider { _ in image }
        }
        return engine
    }
    private func element(_ body: String) throws -> MathMLNode { try mathML(body).children[0] }
    private func mark(_ box: MathBox) throws -> AlignmentEvent {
        try XCTUnwrap(box.alignment.first { if case .mark = $0.kind { return true }; return false })
    }
    private func imageRects(_ box: MathBox, at origin: CGPoint = .zero) -> [CGRect] {
        box.items.flatMap { item -> [CGRect] in
            switch item {
            case .image(_, let rect, _): [rect.offsetBy(dx: origin.x, dy: origin.y)]
            case .box(let child, let point): imageRects(child, at: CGPoint(x: origin.x + point.x, y: origin.y + point.y))
            default: []
            }
        }
    }
    private func shapes(_ box: MathBox, at origin: CGPoint = .zero) -> [CGRect] {
        box.items.flatMap { item -> [CGRect] in
            switch item {
            case .rect(let rect, _): [rect.offsetBy(dx: origin.x, dy: origin.y)]
            case .box(let child, let point): shapes(child, at: CGPoint(x: origin.x + point.x, y: origin.y + point.y))
            default: []
            }
        }
    }

    func testImageEdgesInEveryTokenAndFirstSourceMarkWins() throws {
        for token in ["mi", "mn", "mo", "mtext", "ms"] {
            let quotes = token == "ms" ? "lquote='' rquote=''" : ""
            for (body, edge) in [("12<malignmark/><mglyph src='g'/>3<malignmark/>", false),
                                 ("12<mglyph src='g'/><malignmark/>3<malignmark/>", true)] {
                let engine = engine()
                let box = try engine.layout(element("<\(token) \(quotes)>\(body)</\(token)>"), context, depth: 0)
                let rect = try XCTUnwrap(imageRects(box).first)
                XCTAssertEqual(try mark(box).x, edge ? rect.maxX : rect.minX, accuracy: 0.001, token)
                XCTAssertEqual(box.alignment.filter { if case .mark = $0.kind { return true }; return false }.count, 1)
            }
        }
    }

    func testImageBoundaryMarksUseDrawnEdgesBesideNaturalRTLText() throws {
        for (body, after) in [
            ("אב<malignmark/><mglyph src='g'/>גד", false),
            ("אב<mglyph src='g'/><malignmark/>גד", true),
        ] {
            let box = try engine().layout(element("<mtext>\(body)</mtext>"), context, depth: 0)
            let rect = try XCTUnwrap(imageRects(box).first)
            XCTAssertEqual(try mark(box).x, after ? rect.maxX : rect.minX, accuracy: 0.001)
        }
    }

    func testInlineImageMarkAlignsTableCellsAndRetainsBounds() throws {
        let xml = "<mtable frame='solid'><mtr><mtd><maligngroup/><mtext>1<mglyph src='g' width='1em'/><malignmark/>3</mtext></mtd></mtr>"
            + "<mtr><mtd><maligngroup/><mtext>123<mglyph src='g' width='2em'/><malignmark/>4</mtext></mtd></mtr></mtable>"
        let box = try engine().layout(element(xml), context, depth: 0)
        let rects = imageRects(box)
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0].maxX, rects[1].maxX, accuracy: 0.001)
        let ink = try XCTUnwrap(box.inkBounds)
        XCTAssertGreaterThanOrEqual(ink.minX, -0.001)
        XCTAssertLessThanOrEqual(ink.maxX, box.width + 0.001)
    }

    func testUndecoratedFallbackUsesFullTokenShaping() throws {
        let engine = engine(images: false)
        let node = try element("<mtext>1<mglyph src='missing' alt='  WIDE  '/><malignmark/>.3</mtext>")
        let box = try engine.layout(node, context, depth: 0)
        let line = CTLineCreateWithAttributedString(engine.attributedText("1WIDE.3", context))
        XCTAssertEqual(try mark(box).x, CTLineGetOffsetForStringIndex(line, 5, nil), accuracy: 0.001)
        XCTAssertEqual(box.width, engine.textBox("1WIDE.3", context).width, accuracy: 0.001)
        XCTAssertTrue(imageRects(box).isEmpty)
        let before = try engine.layout(element("<mtext>1<malignmark/><mglyph src='missing' alt='  WIDE  '/>.3</mtext>"), context, depth: 0)
        XCTAssertEqual(try mark(before).x, CTLineGetOffsetForStringIndex(line, 1, nil), accuracy: 0.001)
    }

    func testDecoratedFallbackAndLegacyGlyphUseTheirBoxAdvances() throws {
        let engine = engine(images: false)
        for attributes in ["src='missing' alt='WIDE' mathbackground='red'",
                           "fontfamily='\(CTFontCopyPostScriptName(engine.font.base))' index='2'"] {
            let box = try engine.layout(element("<mtext>1<mglyph \(attributes)/><malignmark/>3</mtext>"), context, depth: 0)
            let prefix = try engine.layout(element("<mtext>1<mglyph \(attributes)/></mtext>"), context, depth: 0)
            XCTAssertEqual(try mark(box).x, prefix.width, accuracy: 0.001, attributes)
            XCTAssertGreaterThan(prefix.width, engine.textBox("1", context).width)
        }
    }

    func testParserSurrogatesWhitespaceVariantsAndStringQuotesMapToRenderedEdges() throws {
        let node = try element("<mi mathvariant='bold'> \n𝛼 \tA<mglyph src='g'/><malignmark/> B</mi>")
        XCTAssertEqual(node.children[1].tokenTextOffset, 8)
        let engine = engine()
        let box = try engine.layout(node, context, depth: 0)
        XCTAssertEqual(try mark(box).x, try XCTUnwrap(imageRects(box).first).maxX, accuracy: 0.001)
        let before = try engine.layout(element("<mi mathvariant='bold'> \n𝛼 \tA<malignmark/><mglyph src='g'/> B</mi>"), context, depth: 0)
        XCTAssertEqual(try mark(before).x, try XCTUnwrap(imageRects(before).first).minX, accuracy: 0.001)
        let quoted = try engine.layout(element("<ms lquote='&lt;&lt;' rquote='&gt;&gt;'> A<mglyph src='g'/><malignmark/> B</ms>"), context, depth: 0)
        XCTAssertEqual(try mark(quoted).x, try XCTUnwrap(imageRects(quoted).first).maxX, accuracy: 0.001)
    }

    func testHostOffsetsClampAndRoundInsideSurrogatesAndNilMeansDisplayedEnd() throws {
        for (offset, expected) in [(Int.min, 0.0), (1, 0.0), (Int.max, -1.0)] {
            let engine = engine()
            let node = MathMLNode(name: "mi", children: [MathMLNode(name: "mglyph", attributes: ["src": "g"]),
                MathMLNode(name: "malignmark", tokenTextOffset: offset)], text: "𝛼\u{FFFC}")
            let box = try engine.layout(node, context, depth: 0)
            XCTAssertEqual(try mark(box).x, expected < 0 ? box.width : expected, accuracy: 0.001)
        }
        let engine = engine()
        let host = MathMLNode(name: "mtext", children: [MathMLNode(name: "mglyph", attributes: ["src": "g"]),
            MathMLNode(name: "malignmark")], text: "12")
        let box = try engine.layout(host, context, depth: 0)
        XCTAssertEqual(try mark(box).x, box.width, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(imageRects(box).first).maxX, box.width, accuracy: 0.001)
        var explicit = host
        explicit.children[1].tokenTextOffset = Int.max
        let explicitBox = try self.engine().layout(explicit, context, depth: 0)
        XCTAssertEqual(try mark(explicitBox).x, try XCTUnwrap(imageRects(explicitBox).first).minX, accuracy: 0.001,
                       "explicit offsets address raw text, before an unmarked appended host glyph")
        let scalarOperator = MathMLNode(name: "mo", children: [MathMLNode(name: "malignmark", tokenTextOffset: 1)], text: "𝛼")
        XCTAssertEqual(try mark(self.engine().layout(scalarOperator, context, depth: 0)).x, 0, accuracy: 0.001)
    }

    func testDecimalLookupAfterImagesIncludesTheirAdvances() throws {
        let xml = "<mtable groupalign='{decimalpoint}'><mtr><mtd><maligngroup/><mn>1<mglyph src='g' width='1em'/>.3</mn></mtd></mtr>"
            + "<mtr><mtd><maligngroup/><mn>12<mglyph src='g' width='2em'/>.4</mn></mtd></mtr></mtable>"
        let rects = imageRects(try engine().layout(element(xml), context, depth: 0))
        XCTAssertEqual(rects[0].maxX, rects[1].maxX, accuracy: 0.001)
    }

    func testImageOperatorAffineScalingRetainsFirstMarkAndSourcePriority() throws {
        let engine = engine()
        let natural = try engine.layout(element("<mo stretchy='true'>→<mglyph src='g'/><malignmark/>x<malignmark/></mo>"), context, depth: 0)
        let wide = try engine.layout(element("<mover><mo stretchy='true'>→<mglyph src='g'/><malignmark/>x<malignmark/></mo><mspace width='8em'/></mover>"), context, depth: 0)
        let rect = try XCTUnwrap(imageRects(wide).first)
        XCTAssertEqual(try mark(wide).x, rect.maxX, accuracy: 0.001)
        XCTAssertGreaterThan(try mark(wide).x, try mark(natural).x)
        var display = context; display.display = true
        let large = try engine.layout(element("<mo largeop='true'><mglyph src='g'/><malignmark/>x</mo>"), display, depth: 0)
        XCTAssertEqual(try mark(large).x, try XCTUnwrap(imageRects(large).first).maxX, accuracy: 0.001)
        XCTAssertGreaterThan(try mark(large).x, 30)
        let row = try engine.layout(element("<mrow><mo largeop='true'><mglyph src='g'/><malignmark/>x</mo><mn>123<malignmark/></mn></mrow>"), display, depth: 0)
        let marks = row.alignment.filter { if case .mark = $0.kind { return true }; return false }
        XCTAssertEqual(marks.count, 2)
        XCTAssertLessThan(marks[0].order, marks[1].order)
    }

    func testRedundantLTRDeclarationsPreserveGroupsAndChangedDirectionDoesNot() throws {
        let a = "<maligngroup/><mspace width='1em' mathbackground='red' height='1em'/><maligngroup/><mspace width='2em' height='1em'/>"
        let b = "<maligngroup/><mspace width='3em' height='1em'/><maligngroup/><mspace width='1em' height='1em'/>"
        for wrapper in ["mrow", "mstyle"] {
            let xml = "<mtable><mtr><mtd><\(wrapper) dir='ltr'>\(a)</\(wrapper)></mtd></mtr><mtr><mtd>\(b)</mtd></mtr></mtable>"
            let box = try innerBox(xml)
            XCTAssertEqual(box.width, 5 * em, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(shapes(box).first).minX, 0, accuracy: 0.001)
            let changed = xml.replacingOccurrences(of: "dir='ltr'", with: "dir='rtl'")
            XCTAssertEqual(try innerBox(changed).width, 4 * em, accuracy: 0.001)
        }
    }

    func testChangedDirectionRetainsOneAtomicExtentInsideTheOuterLTRGroup() throws {
        let xml = "<mtable columnalign='left'><mtr><mtd><maligngroup/><mrow dir='rtl' mathbackground='red'><maligngroup/><mspace width='2em' height='1em'/><malignmark/></mrow><maligngroup/><mspace width='1em' height='1em' mathbackground='blue'/></mtd></mtr>"
            + "<mtr><mtd><maligngroup/><mspace width='1em' height='1em' mathbackground='lime'/><maligngroup/><mspace width='3em' height='1em' mathbackground='black'/></mtd></mtr></mtable>"
        let box = try innerBox(xml), rects = shapes(box)
        XCTAssertEqual(box.width, 5 * em, accuracy: 0.001)
        XCTAssertEqual(rects.count, 4)
        XCTAssertEqual(rects[0].minX, 0, accuracy: 0.001)
        XCTAssertEqual(rects[0].maxX, rects[1].minX, accuracy: 0.001)
        XCTAssertEqual(rects[1].minX, rects[3].minX, accuracy: 0.001)
        let directed = try engine().layout(element("<mrow dir='rtl' mathbackground='red'><maligngroup/><mspace width='2em' height='1em'/><malignmark/></mrow>"), context, depth: 0)
        XCTAssertEqual(directed.alignment.count, 1)
        guard case .extent(let width) = directed.alignment[0].kind else { return XCTFail("only one atomic extent may cross the boundary") }
        XCTAssertEqual(width, 2 * em, accuracy: 0.001)
        for backgroundAttribute in ["", "mathbackground='red'"] {
            let withSpace = try engine().layout(element("<mrow dir='rtl' \(backgroundAttribute)><mtext>x </mtext></mrow>"), context, depth: 0)
            guard case .extent(let atomicWidth) = withSpace.alignment[0].kind else { return XCTFail("missing atomic extent") }
            let painted = try XCTUnwrap(withSpace.inkBounds)
            let expected = painted.union(CGRect(x: 0, y: 0, width: withSpace.width, height: 1))
            XCTAssertEqual(withSpace.alignment[0].x, expected.minX, accuracy: 0.001)
            XCTAssertEqual(atomicWidth, expected.width, accuracy: 0.001, "the atomic extent includes advance and font overhang")
            if let background = shapes(withSpace).first {
                XCTAssertLessThanOrEqual(withSpace.alignment[0].x, background.minX)
                XCTAssertGreaterThanOrEqual(withSpace.alignment[0].x + atomicWidth, background.maxX - 0.001)
            }
        }

        // The child has a zero authored advance but visible, overhanging ink.
        let child = "<mrow dir='rtl'><mpadded width='0px' lspace='-1em'><mspace width='2em' height='1em' mathbackground='red'/></mpadded></mrow>"
        let overhang = "<mtable columnalign='left'><mtr><mtd><maligngroup/>\(child)<maligngroup/><mspace width='1em' height='1em' mathbackground='blue'/></mtd></mtr>"
            + "<mtr><mtd><maligngroup/><mspace width='1em' height='1em'/><maligngroup/><mspace width='1em' height='1em'/></mtd></mtr></mtable>"
        let overhanging = try innerBox(overhang), fills = shapes(overhanging)
        XCTAssertEqual(overhanging.width, 3 * em, accuracy: 0.001)
        XCTAssertEqual(fills[0].minX, 0, accuracy: 0.001)
        XCTAssertEqual(fills[0].maxX, fills[1].minX, accuracy: 0.001)
        let ink = try XCTUnwrap(overhanging.inkBounds)
        XCTAssertGreaterThanOrEqual(ink.minX, -0.001)
        XCTAssertLessThanOrEqual(ink.maxX, overhanging.width + 0.001)
    }

    func testMixedGlyphMarksKeepSharedNodeTextAndProviderBounds() throws {
        let engine = engine()
        let marks = Array(repeating: MathMLNode(name: "malignmark"), count: MathLimits.nodes - 1)
        let node = MathMLNode(name: "mn", children: marks + [MathMLNode(name: "mglyph", attributes: ["src": "g"])], text: "\u{FFFC}")
        XCTAssertThrowsError(try engine.layout(node, context, depth: 0)) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded) }
        let largeAlt = "<mn><mglyph src='missing' alt='\(String(repeating: "1", count: MathLimits.textLength))'/><malignmark/>2</mn>"
        XCTAssertThrowsError(try self.engine(images: false).layout(element(largeAlt), context, depth: 0)) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded) }
        let calls = Mutex(0)
        let image = image(), cached = self.engine(images: false)
        cached.imageProvider = MathImageProvider { _ in calls.withLock { $0 += 1 }; return image }
        _ = try cached.layout(element("<mn><mglyph src='g'/><malignmark/><mglyph src='g'/><malignmark/></mn>"), context, depth: 0)
        XCTAssertEqual(calls.withLock { $0 }, 1, "alignment mapping must not resolve or lay out glyph prefixes again")
    }
    func testRTLTokenMarksBesideImagesAndFallbacksRetainRenderedCoordinates() throws {
        var rtl = context
        rtl.direction = .rightToLeft
        rtl.alignmentRTL = true
        for token in ["mi", "mn", "mo", "mtext", "ms"] {
            for glyph in ["src='g'", "src='missing' alt='WIDE' mathbackground='red'",
                          "fontfamily='STIX Two Math' index='2'"] {
                let engine = engine(images: glyph == "src='g'")
                let node = try element("<\(token) lquote='' rquote=''>1<mglyph \(glyph)/><malignmark/>3</\(token)>")
                let box = try engine.layout(node, rtl, depth: 0)
                let prefix = try engine.layout(element("<\(token) lquote='' rquote=''>1<mglyph \(glyph)/></\(token)>"), rtl, depth: 0)
                XCTAssertEqual(try mark(box).x, prefix.width, accuracy: 0.001, token)
            }
        }
        let body = "<mtable dir='rtl'><mtr><mtd><maligngroup/><mtext>1<mglyph src='g' width='1em'/><malignmark/>3</mtext></mtd></mtr>"
            + "<mtr><mtd><maligngroup/><mtext>123<mglyph src='g' width='2em'/><malignmark/>4</mtext></mtd></mtr></mtable>"
        let r = imageRects(try engine().layout(element(body), context, depth: 0))
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].maxX, r[1].maxX, accuracy: 0.001)
    }

    func testRTLStretchedOperatorTokenEdgesUseDirectionAndRenderedWidth() throws {
        var rtl = context
        rtl.direction = .rightToLeft
        rtl.alignmentRTL = true
        for (text, end) in [("→<malignmark/>", true), ("<malignmark/>→", false)] {
            let box = try engine().layout(element("<mover><mo>\(text)</mo><mspace width='8em'/></mover>"), rtl, depth: 0)
            XCTAssertEqual(try mark(box).x, end ? 0 : box.width, accuracy: 0.001)
        }
    }

}
