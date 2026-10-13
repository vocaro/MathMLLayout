import CoreGraphics
@testable import MathMLLayout
import XCTest

final class TableWrappingIntegrationTests: MathTestCase {
    private let text = "<mtext>alpha beta gamma delta epsilon zeta eta theta</mtext>"

    private func fitted(_ body: String, width: CGFloat = .infinity) throws -> MathLayout {
        try MathLayout(node(body), style: MathStyle(fontSize: 20, color: black), maximumWidth: width)
    }

    private func assertContainsInk(_ layout: MathLayout) throws {
        let bounds = try XCTUnwrap(ink(layout))
        XCTAssertGreaterThanOrEqual(bounds.minX, -0.5)
        XCTAssertLessThanOrEqual(bounds.maxX, layout.width + 0.5)
        XCTAssertGreaterThanOrEqual(bounds.minY, -layout.descent - 0.5)
        XCTAssertLessThanOrEqual(bounds.maxY, layout.ascent + 0.5)
    }

    func testGroupedPhantomsKeepGeometryWithoutRevealingTheirInk() throws {
        let number = "<maligngroup/><mn mathcolor='red'>1.25</mn>"
        func table(_ first: String) -> String {
            "<mtable frame='solid' groupalign='{decimalpoint}'><mtr><mtd>\(first)</mtd></mtr>"
                + "<mtr><mtd><maligngroup/><mn mathcolor='lime'>12.5</mn></mtd></mtr></mtable>"
        }
        let visible = try fitted(table(number))
        let hidden = try fitted(table("<mphantom>\(number)</mphantom>"))
        XCTAssertEqual(hidden.width, visible.width, accuracy: 0.001)
        XCTAssertEqual(hidden.ascent, visible.ascent, accuracy: 0.001)
        XCTAssertEqual(hidden.descent, visible.descent, accuracy: 0.001)
        XCTAssertNotNil(Rendering(visible).bounds(.red))
        XCTAssertNil(Rendering(hidden).bounds(.red), "aligning groups must preserve phantom visibility")
        XCTAssertNotNil(Rendering(hidden).bounds(.green))
    }

    func testNestedTablesNarrowThroughDefaultPaddingAndPhantomRows() throws {
        let inner = "<mtable frame='solid'><mtr><mtd>\(text)</mtd></mtr></mtable>"
        func table(_ content: String) -> String {
            "<mtable frame='dashed' rowalign='top'><mtr><mtd columnspan='2'>\(content)</mtd><mtd>\(text)</mtd></mtr>"
                + "<mtr><mtd><mi>x</mi></mtd><mtd><mi>y</mi></mtd><mtd><mi>z</mi></mtd></mtr></mtable>"
        }
        let natural = try fitted(table(inner))
        let minimum = try fitted(table(inner), width: 0)
        for width in [(natural.width + minimum.width) / 2, minimum.widestUnbreakableWidth] {
            let visible = try fitted(table(inner), width: width)
            for wrapper in ["mpadded", "mphantom"] {
                let result = try fitted(table("<\(wrapper)>\(inner)</\(wrapper)>"), width: width)
                XCTAssertLessThanOrEqual(result.width, width + 0.001)
                XCTAssertEqual(result.width, visible.width, accuracy: 0.001)
                XCTAssertEqual(height(result), height(visible), accuracy: 0.001)
                try assertContainsInk(result)
            }
        }
    }

    func testCellRebuildTextSourcesShareTheCompletePassShapingBudget() throws {
        let engine = LayoutEngine(fontName: nil)
        let context = LayoutContext(fontSize: 20, unclampedSize: 20, minSize: 12, display: false, color: black)
        let words = MathMLNode(name: "mtext", text: "alpha beta")
        let rebuilt = try engine.relayoutCell(TableCellSource(node: words, context: context, depth: 0), width: 100)
        let source = try XCTUnwrap(rebuilt.textSlice?.source)
        XCTAssertTrue(source.work === engine.textWork)
        _ = source.box(source.words[0])
        XCTAssertGreaterThan(engine.textWork.spent, 0)
        XCTAssertTrue(engine.textWork.consume(TextShapingWork.limit - engine.textWork.spent))
        _ = source.box(source.words[1])
        XCTAssertTrue(engine.textWork.exhausted)
        XCTAssertThrowsError(try engine.layoutRoot(MathMLNode(name: "math", children: [words]),
                                                   style: MathStyle(fontSize: 20, color: black))) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
    }

    func testDecoratedCellsReproduceTheirFeasibleWidthAfterWrapping() throws {
        let content = text + "<mspace linebreak='newline'/>" + text
        for (opening, closing) in [("merror", "merror"), ("mrow mathbackground='blue'", "mrow")] {
            let body = "<mtable frame='solid' rowalign='bottom'><mtr><mtd><\(opening)>\(content)</\(closing)></mtd>"
                + "<mtd>\(text)</mtd></mtr><mtr><mtd><mi>x</mi></mtd><mtd><mi>y</mi></mtd></mtr></mtable>"
            let natural = try fitted(body)
            let minimum = try fitted(body, width: 0)
            XCTAssertLessThan(minimum.width, natural.width)
            let exact = try fitted(body, width: minimum.widestUnbreakableWidth)
            XCTAssertLessThanOrEqual(exact.width, minimum.widestUnbreakableWidth + 0.001)
            XCTAssertGreaterThan(height(exact), height(natural))
            XCTAssertEqual(exact.rows.count, 1, "the table remains one outer row")
            try assertContainsInk(exact)
            let drawn = Rendering(exact)
            XCTAssertNotNil(drawn.bounds(closing == "merror" ? .red : .blue), "decoration remains intact")
        }
    }
}
