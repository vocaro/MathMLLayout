import CoreGraphics
import CoreText
@testable import MathMLLayout
import XCTest

final class WrappedAlignmentTests: XCTestCase {
    private func space(_ width: Int, _ color: String) -> String {
        "<mspace width='\(width)em' height='1em' mathbackground='\(color)'/>"
    }
    private func row(_ content: String, _ attributes: String = "") -> String {
        "<mtr><mtd \(attributes)>\(content)</mtd></mtr>"
    }
    private func table(_ a: String, _ b: String, direction: String, attributes: String = "") -> String {
        "<mtable dir='\(direction)' columnalign='left' \(attributes)>\(row(a))\(row(b))</mtable>"
    }
    private func rectangles(_ box: MathBox, at origin: CGPoint = .zero) -> [CGRect] {
        box.items.flatMap { item -> [CGRect] in
            switch item {
            case .rect(let rect, _): [rect.offsetBy(dx: origin.x, dy: origin.y)]
            case .box(let child, let p): rectangles(child, at: CGPoint(x: origin.x + p.x, y: origin.y + p.y))
            default: []
            }
        }
    }
    private func runs(_ box: MathBox, at origin: CGPoint = .zero) -> [(GlyphRun, CGPoint)] {
        box.items.flatMap { item -> [(GlyphRun, CGPoint)] in
            switch item {
            case .glyphs(let run): [(run, origin)]
            case .box(let child, let p): runs(child, at: CGPoint(x: origin.x + p.x, y: origin.y + p.y))
            default: []
            }
        }
    }
    private let forced = "<mspace linebreak='newline' indentalign='left' indentshift='0px'/>"
    private let automatic = "<mspace linebreak='goodbreak' indentalign='left' indentshift='0px'/>"

    func testForcedGroupFragmentsUseSharedSideWidthsInBothDirections() throws {
        let a = "<maligngroup/>" + space(1, "red") + forced + space(2, "blue")
        let b = "<maligngroup/>" + space(3, "lime")
        for direction in ["ltr", "rtl"] {
            for (mode, x) in [("left", 0.0), ("right", 1.0), ("center", 0.5)] {
                let box = try innerBox(table(a, b, direction: direction, attributes: "groupalign='{\(mode)}'"))
                let drawn = rectangles(box)
                XCTAssertEqual(drawn.count, 3)
                XCTAssertEqual(box.width, 3 * em, accuracy: 0.001)
                XCTAssertEqual(drawn[0].minX, x * em, accuracy: 0.001)
                XCTAssertEqual(drawn[1].minX, x * em, accuracy: 0.001)
                XCTAssertEqual(drawn[2].minX, 0, accuracy: 0.001)
                XCTAssertGreaterThan(drawn[0].minY, drawn[1].maxY)
            }
        }
    }

    func testAutomaticGroupWrappingFitsAndReproducesItsMinimum() throws {
        let a = "<maligngroup/>" + space(2, "red") + automatic + space(2, "blue")
        let b = "<maligngroup/>" + space(3, "lime") + automatic + space(1, "black")
        for direction in ["ltr", "rtl"] {
            let root = try mathML(table(a, b, direction: direction, attributes: "groupalign='{right}'"))
            let style = MathStyle(fontSize: em, color: black)
            let natural = try MathLayout(root, style: style)
            let narrow = try LayoutEngine.lines(root, style: style, maximumWidth: 3 * em, firstRowMaximumWidth: nil)
            XCTAssertEqual(natural.width, 4 * em, accuracy: 0.001)
            XCTAssertEqual(narrow.width, 3 * em, accuracy: 0.001)
            XCTAssertEqual(narrow.widestUnbreakable, 3 * em, accuracy: 0.001)
            XCTAssertGreaterThan(narrow.ascent + narrow.descent, natural.ascent + natural.descent)
            let drawn = rectangles(try XCTUnwrap(narrow.rows.first).box)
            XCTAssertEqual(drawn.map(\.minX), [em, em, 0, 0])
            let exact = try MathLayout(root, style: style, maximumWidth: narrow.widestUnbreakable)
            XCTAssertLessThanOrEqual(exact.width, narrow.widestUnbreakable + 0.001)
            XCTAssertLessThan(narrow.layoutPasses, 20)
        }
    }

    func testMultipleGroupsKeepSourceIndicesAcrossForcedLines() throws {
        let a = "<maligngroup/>" + space(2, "red") + forced + space(2, "blue") + "<maligngroup/>" + space(1, "orange")
        let b = "<maligngroup/>" + space(3, "lime") + forced + space(1, "black") + "<maligngroup/>" + space(2, "purple")
        for direction in ["ltr", "rtl"] {
            let box = try innerBox(table(a, b, direction: direction))
            let drawn = rectangles(box)
            XCTAssertEqual(box.width, 5 * em, accuracy: 0.001)
            XCTAssertEqual(drawn.count, 6)
            XCTAssertEqual(drawn[2].minX, drawn[5].minX, accuracy: 0.001)
            XCTAssertEqual(drawn[2].minX, direction == "ltr" ? 3 * em : 0, accuracy: 0.001)
            XCTAssertGreaterThan(drawn[0].minY, drawn[1].maxY)
        }
    }

    func testRowSpanningGroupsAlignWithOrdinaryCellsInTheirColumn() throws {
        let a = "<maligngroup/>" + space(1, "red") + "<maligngroup/>" + space(2, "blue")
        let b = "<maligngroup/>" + space(3, "lime") + "<maligngroup/>" + space(1, "black")
        for direction in ["ltr", "rtl"] {
            let body = "<mtable dir='\(direction)' columnalign='left'>" + row(a, "rowspan='2'") + "<mtr/>" + row(b) + "</mtable>"
            let box = try innerBox(body), drawn = rectangles(box)
            XCTAssertEqual(box.width, 5 * em, accuracy: 0.001)
            XCTAssertEqual(drawn[1].minX, drawn[3].minX, accuracy: 0.001)
            XCTAssertEqual(drawn[0].minX, direction == "ltr" ? 0 : 2 * em, accuracy: 0.001)
        }
    }

    func testColumnSpanningGroupsShareOnlyAnIdenticalColumnInterval() throws {
        let a = "<maligngroup/>" + space(1, "red") + "<maligngroup/>" + space(2, "blue")
        let b = "<maligngroup/>" + space(3, "lime") + "<maligngroup/>" + space(1, "black")
        for direction in ["ltr", "rtl"] {
            let body = "<mtable dir='\(direction)' columnspacing='1em' columnalign='left'>"
                + row(a, "columnspan='2'") + row(b, "columnspan='2'")
                + "<mtr><mtd>\(space(10, "orange"))</mtd><mtd>\(space(1, "purple"))</mtd></mtr></mtable>"
            let box = try innerBox(body), drawn = rectangles(box)
            XCTAssertEqual(box.width, 12 * em, accuracy: 0.001)
            XCTAssertEqual(drawn[1].minX, drawn[3].minX, accuracy: 0.001)
            let separate = try innerBox("<mtable dir='\(direction)' columnalign='left' columnspacing='0'>"
                + row(a, "columnspan='2'") + row(b) + "</mtable>")
            let independent = rectangles(separate)
            if direction == "ltr" {
                XCTAssertEqual(independent[1].minX, em, accuracy: 0.001)
                XCTAssertEqual(independent[3].minX, 3 * em, accuracy: 0.001)
            } else {
                XCTAssertEqual(independent[0].minX, 2 * em, accuracy: 0.001)
                XCTAssertEqual(independent[2].minX, em, accuracy: 0.001)
            }
        }
    }

    func testSpanScopeListsConsumeLocalMarksAndExportOnlyEntirelyUnscopedSpans() throws {
        let a = "<maligngroup/>" + space(1, "red") + "<malignmark/>" + forced + space(2, "blue")
        for direction in ["ltr", "rtl"] {
            for (scopes, count) in [("true true", 0), ("false false", 1), ("true false", 0), ("false true", 0)] {
                let node = try mathML("<mtable dir='\(direction)' alignmentscope='\(scopes)'>"
                    + row(a, "columnspan='2'") + "</mtable>").children[0]
                let context = LayoutContext(fontSize: em, unclampedSize: em, minSize: 8, display: false,
                                            color: black, trackAlignment: true)
                let box = try LayoutEngine(fontName: nil).layout(node, context, depth: 0)
                XCTAssertEqual(box.alignment.filter { if case .mark = $0.kind { return true }; return false }.count, count)
                XCTAssertFalse(box.alignment.contains { if case .group = $0.kind { return true }; return false })
            }
        }
    }

    func testWrappedNestedUnscopedMarksKeepTheirRenderedCoordinates() throws {
        let inner = "<mtable alignmentscope='false' columnalign='left'>"
            + row("<mn>1<malignmark/>.2</mn>" + forced + "<mn>123</mn>") + "</mtable>"
        let other = "<maligngroup/><mn>123<malignmark/>.4</mn>"
        for direction in ["ltr", "rtl"] {
            let box = try innerBox(table("<maligngroup/>" + inner, other, direction: direction))
            let drawn = runs(box)
            XCTAssertEqual(drawn.count, 3)
            XCTAssertEqual(drawn[0].1.x + drawn[0].0.positions[1].x,
                           drawn[2].1.x + drawn[2].0.positions[3].x, accuracy: 0.001)
        }
    }

    func testEmbeddedTextMarksSurviveWordSplittingAndContextualShaping() throws {
        for direction in ["ltr", "rtl"] {
            for text in ["alpha beta", "אב גד"] {
                let first = text.split(separator: " ")[0]
                let second = text.split(separator: " ")[1]
                let a = "<maligngroup/><mtext mathcolor='red'>\(first) <malignmark/>\(second)</mtext>"
                let b = "<maligngroup/><mtext mathcolor='lime'><malignmark/>\(second)</mtext>"
                let root = try mathML(table(a, b, direction: direction))
                let style = MathStyle(fontSize: em, color: black)
                let result = try LayoutEngine.lines(root, style: style, maximumWidth: 0, firstRowMaximumWidth: nil)
                XCTAssertGreaterThan(result.width, 0)
                let drawn = runs(try XCTUnwrap(result.rows.first).box)
                XCTAssertEqual(drawn.count, 3)
                XCTAssertEqual(drawn[1].1.x + drawn[1].0.positions[0].x,
                               drawn[2].1.x + drawn[2].0.positions[0].x, accuracy: 0.001, "\(direction): \(text)")
                let exact = try MathLayout(root, style: style, maximumWidth: result.widestUnbreakable)
                XCTAssertLessThanOrEqual(exact.width, result.widestUnbreakable + 0.001)
            }
        }
    }

    func testFirstSourceMarkWinsAfterDeferredOperatorAndTextWrapping() throws {
        let a = "<maligngroup/><mo mathbackground='red'>(<malignmark/></mo>"
            + "<mtext>alpha <malignmark/>beta</mtext>" + forced + "<mfrac><mn>1</mn><mn>2</mn></mfrac>"
        let b = "<maligngroup/>" + space(3, "lime") + "<malignmark edge='right'/>"
        for direction in ["ltr", "rtl"] {
            let box = try innerBox(table(a, b, direction: direction))
            let drawn = rectangles(box)
            let fence = try XCTUnwrap(drawn.first)
            let other = try XCTUnwrap(drawn.last)
            XCTAssertEqual(direction == "ltr" ? fence.maxX : fence.minX,
                           direction == "ltr" ? other.maxX : other.minX, accuracy: 0.001)
        }
    }

    func testCachedCellsKeepMarkPriorityWhenNestedTablesAreNarrowed() throws {
        let a = "<maligngroup/><mo mathbackground='red'>(<malignmark/></mo>"
            + "<mtext>alpha <malignmark/>beta gamma delta</mtext>" + forced + "<mfrac><mn>1</mn><mn>2</mn></mfrac>"
        let b = "<maligngroup/>" + space(3, "lime") + "<malignmark edge='right'/>"
        for direction in ["ltr", "rtl"] {
            let body = "<mtable><mtr><mtd>" + table(a, b, direction: direction)
                + "</mtd><mtd><mtext>one two three four five six</mtext></mtd></mtr></mtable>"
            let root = try mathML(body), style = MathStyle(fontSize: em, color: black)
            let natural = try MathLayout(root, style: style)
            let lines = try LayoutEngine.lines(root, style: style, maximumWidth: natural.width / 2, firstRowMaximumWidth: nil)
            let drawn = rectangles(try XCTUnwrap(lines.rows.first).box)
            let fence = try XCTUnwrap(drawn.first), other = try XCTUnwrap(drawn.last)
            XCTAssertEqual(direction == "ltr" ? fence.maxX : fence.minX,
                           direction == "ltr" ? other.maxX : other.minX, accuracy: 0.001)
            let exact = try MathLayout(root, style: style, maximumWidth: lines.widestUnbreakable)
            XCTAssertLessThanOrEqual(exact.width, lines.widestUnbreakable + 0.001)
        }
    }

    func testWrappedColumnSpansRetainDecorationImagesAndPhantomGeometry() throws {
        let image = CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 80,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let provider = MathImageProvider { _ in image }
        let a = "<maligngroup/><mtext>alpha <mglyph src='g' width='1em'/> beta</mtext>"
        let b = "<maligngroup/><mtext>longer words</mtext>"
        for direction in ["ltr", "rtl"] {
            // Explicit LTR text permits attachment segmentation inside an RTL formula.
            let content = a.replacingOccurrences(of: "<mtext>", with: "<mtext dir='ltr'>")
            func formula(_ hidden: Bool) throws -> MathMLNode {
                try mathML("<mtable dir='\(direction)' frame='solid' columnspacing='0'>"
                    + row(hidden ? "<mphantom>\(content)</mphantom>" : content, "columnspan='2' mathbackground='red'")
                    + row(b, "columnspan='2'") + "</mtable>")
            }
            let style = MathStyle(fontSize: em, color: black, imageProvider: provider)
            let visible = try MathLayout(formula(false), style: style, maximumWidth: 0)
            let hidden = try MathLayout(formula(true), style: style, maximumWidth: 0)
            XCTAssertEqual(hidden.width, visible.width, accuracy: 0.001)
            XCTAssertEqual(hidden.ascent, visible.ascent, accuracy: 0.001)
            XCTAssertEqual(hidden.descent, visible.descent, accuracy: 0.001)
            XCTAssertGreaterThan(height(visible), 3 * em)
            XCTAssertNotNil(Rendering(visible).bounds(.red))
            XCTAssertNotNil(Rendering(hidden).bounds(.red))
            assertBoxCoversInk(visible, "wrapped decorated span \(direction)")
            assertBoxCoversInk(hidden, "wrapped phantom span \(direction)")
            let exact = try MathLayout(formula(false), style: style, maximumWidth: visible.widestUnbreakableWidth)
            XCTAssertLessThanOrEqual(exact.width, visible.widestUnbreakableWidth + 0.001)
        }
    }

    func testGroupedMinimumMeasurementsShareTheRTLTextWorkBudget() throws {
        let root = try mathML(table("<maligngroup/><mtext dir='ltr'>alpha beta</mtext>",
                                    "<maligngroup/><mtext dir='ltr'>longer word</mtext>", direction: "rtl"))
        let engine = LayoutEngine(fontName: nil)
        XCTAssertTrue(engine.textWork.consume(TextShapingWork.limit - 1))
        XCTAssertThrowsError(try engine.layoutRoot(root, style: MathStyle(fontSize: em, color: black))) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
        XCTAssertTrue(engine.textWork.exhausted)
    }
}
