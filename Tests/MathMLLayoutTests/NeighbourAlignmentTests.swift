import CoreGraphics
import CoreText
@testable import MathMLLayout
import XCTest

final class NeighbourAlignmentTests: XCTestCase {
    private let forced = "<mspace linebreak='newline' indentalign='left' indentshift='0px'/>"
    private func space(_ width: Int, _ color: String) -> String {
        "<mspace width='\(width)em' height='1em' mathbackground='\(color)'/>"
    }
    private func row(_ body: String) -> String { "<mtr><mtd>\(body)</mtd></mtr>" }
    private func table(_ a: String, _ b: String, direction: String) -> String {
        "<mtable dir='\(direction)' columnalign='left'>\(row(a))\(row(b))</mtable>"
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

    private func glyphs(_ box: MathBox, at origin: CGPoint = .zero) -> [(GlyphRun, CGPoint)] {
        box.items.flatMap { item -> [(GlyphRun, CGPoint)] in
            switch item {
            case .glyphs(let run): [(run, origin)]
            case .box(let child, let p): glyphs(child, at: CGPoint(x: origin.x + p.x, y: origin.y + p.y))
            default: []
            }
        }
    }

    func testMarkFollowsANestedRowsDrawnEdgeAfterFenceShrinkage() throws {
        for direction in ["ltr", "rtl"] {
            for edge in ["left", "right"] {
                let mark = "<malignmark edge='\(edge)'/>"
                let opening = "<mrow><mrow><mo mathbackground='red'>(</mo><mspace width='0px'/></mrow></mrow>"
                let prefix = (edge == "left") == (direction == "ltr") ? mark + opening : opening + mark
                let a = "<maligngroup/>" + prefix + "<mn>1</mn><mo>)</mo>" + forced
                    + "<mfrac><mn>2</mn><mfrac><mn>3</mn><mn>4</mn></mfrac></mfrac>"
                let b = "<maligngroup/>" + space(3, "lime")
                    + "<malignmark edge='\(direction == "ltr" ? "right" : "left")'/>"
                let drawn = rectangles(try innerBox(table(a, b, direction: direction)))
                let fence = try XCTUnwrap(drawn.first), other = try XCTUnwrap(drawn.last)
                XCTAssertEqual(edge == "right" ? fence.maxX : fence.minX,
                               direction == "ltr" ? other.maxX : other.minX, accuracy: 0.001)
            }
        }
    }

    func testMarkUsesTheFullRenderedBoundsOfANeighbourBrokenAcrossLines() throws {
        for direction in ["ltr", "rtl"] {
            for edge in ["left", "right"] {
                let mark = "<malignmark edge='\(edge)'/>"
                let content = "<mrow>" + space(1, "red") + forced + space(2, "blue") + "</mrow>"
                let marked = (edge == "left") == (direction == "ltr") ? mark + content : content + mark
                let other = "<maligngroup/>" + space(3, "lime")
                    + "<malignmark edge='\(direction == "ltr" ? "right" : "left")'/>"
                let drawn = rectangles(try innerBox(table("<maligngroup/>" + marked, other, direction: direction)))
                XCTAssertEqual(drawn.count, 3)
                let actual = edge == "right" ? max(drawn[0].maxX, drawn[1].maxX) : min(drawn[0].minX, drawn[1].minX)
                XCTAssertEqual(actual, direction == "ltr" ? drawn[2].maxX : drawn[2].minX, accuracy: 0.001)
            }
        }
    }

    func testRowMarksFollowAutomaticallyWrappedTextFragments() throws {
        let style = MathStyle(fontSize: em, color: black)
        for direction in ["ltr", "rtl"] {
            for text in ["a longest", "אב אבגדה", "بت بتبتبت"] {
                for edge in ["left", "right"] {
                    let token = "<mtext>\(text)</mtext>", mark = "<malignmark edge='\(edge)'/>"
                    let marked = (edge == "left") == (direction == "ltr") ? mark + token : token + mark
                    let peer = "<maligngroup/>" + space(1, "lime")
                        + "<malignmark edge='\(direction == "ltr" ? "right" : "left")'/>"
                    func layout(_ cell: String) throws -> MathLines {
                        try LayoutEngine.lines(mathML(table(cell, peer, direction: direction)), style: style,
                                               maximumWidth: 0, firstRowMaximumWidth: nil)
                    }
                    let actual = try layout("<maligngroup/>" + marked)
                    let expected = try layout("<maligngroup groupalign='\(edge)'/>" + token)
                    let drawn = glyphs(try XCTUnwrap(actual.rows.first).box)
                    let reference = glyphs(try XCTUnwrap(expected.rows.first).box)
                    XCTAssertEqual(drawn.count, reference.count)
                    XCTAssertGreaterThan(Set(drawn.map { $0.1.y }).count, 1, "text must actually wrap")
                    XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, "\(direction) \(edge) \(text)")
                    for (run, other) in zip(drawn, reference) {
                        XCTAssertEqual(run.1.x, other.1.x, accuracy: 0.001, "\(direction) \(edge) \(text)")
                        XCTAssertEqual(run.0.positions, other.0.positions)
                    }
                    let minimum = try MathLayout(mathML(table("<maligngroup/>" + marked, peer, direction: direction)),
                                                 style: style, maximumWidth: actual.widestUnbreakable)
                    XCTAssertLessThanOrEqual(minimum.width, actual.widestUnbreakable + 0.001)
                }
            }
        }
    }

    func testNestedUnscopedTableExportsTheResolvedFragmentEdge() throws {
        for direction in ["ltr", "rtl"] {
            for edge in ["left", "right"] {
                let mark = "<malignmark edge='\(edge)'/>"
                let target = "<mrow>" + space(1, "red") + forced + space(2, "blue") + "</mrow>"
                let marked = (edge == "left") == (direction == "ltr") ? mark + target : target + mark
                let nested = "<mtable alignmentscope='false' columnalign='left'>" + row(marked) + "</mtable>"
                let peer = "<maligngroup/>" + space(3, "lime")
                    + "<malignmark edge='\(direction == "ltr" ? "right" : "left")'/>"
                let drawn = rectangles(try innerBox(table("<maligngroup/>" + nested, peer, direction: direction)))
                XCTAssertEqual(drawn.count, 3)
                let edgeX = edge == "right" ? max(drawn[0].maxX, drawn[1].maxX) : min(drawn[0].minX, drawn[1].minX)
                XCTAssertEqual(edgeX, direction == "ltr" ? drawn[2].maxX : drawn[2].minX, accuracy: 0.001)
            }
        }
    }

    func testRetainedTargetsShareThePassBudgetWithoutRetainingTheEngine() throws {
        let root = try mathML(table("<maligngroup/><malignmark edge='right'/><mrow>" + space(1, "red")
                                   + forced + space(2, "blue") + "</mrow>", "<maligngroup/>" + space(3, "lime"), direction: "rtl"))
        var engine: LayoutEngine? = LayoutEngine(fontName: nil)
        weak let weakEngine = engine
        var context = engine!.rootContext(root, style: MathStyle(fontSize: em, color: black))
        context.trackAlignment = true
        // Retain a breakable row before table scopes consume the markers.
        let row = try mathML("<malignmark/><mrow>" + space(1, "red") + forced + space(2, "blue") + "</mrow>")
        let retained = try engine!.layout(row, context, depth: 0)
        let paragraph = Paragraph(retained)
        let work = engine!.textWork
        XCTAssertTrue(paragraph.units.contains { !$0.box.alignmentTargets.isEmpty })
        XCTAssertFalse(paragraph.textWorkExceeded)
        engine = nil
        withExtendedLifetime(retained) { XCTAssertNil(weakEngine) }
        XCTAssertTrue(work.consume(TextShapingWork.limit - work.spent))
        _ = paragraph.rows(limit: 0, first: 0, auto: (.left, 0))
        XCTAssertTrue(work.exhausted)
        XCTAssertTrue(paragraph.textWorkExceeded, "formula-only alignment fragments must report budget exhaustion")
        let bounded = LayoutEngine(fontName: nil)
        XCTAssertTrue(bounded.textWork.consume(TextShapingWork.limit - 1))
        XCTAssertThrowsError(try bounded.layoutRoot(root, style: MathStyle(fontSize: em, color: black))) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
        XCTAssertTrue(bounded.textWork.exhausted)
    }
}
