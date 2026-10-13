import CoreGraphics
@testable import MathMLLayout
import XCTest

final class TableIntegrationTests: MathTestCase {
    private func space(_ width: Int, _ height: Int, _ depth: Int, _ color: String) -> String {
        "<mspace width='\(width)px' height='\(height)px' depth='\(depth)px' mathbackground='\(color)'/>"
    }

    private func rectangles(_ box: MathBox, at origin: CGPoint = .zero) -> [CGRect] {
        box.items.flatMap { item -> [CGRect] in
            switch item {
            case .rect(let rect, _): return [rect.offsetBy(dx: origin.x, dy: origin.y)]
            case .box(let child, let point): return rectangles(child, at: CGPoint(x: origin.x + point.x, y: origin.y + point.y))
            default: return []
            }
        }
    }

    func testSpanningCellsUseTheirFullRectangleForVerticalAlignment() throws {
        for alignment in ["top", "bottom", "center"] {
            let body = "<mstyle rowalign='\(alignment)'><mtable rowspacing='0px' columnspacing='0px'>"
                + "<mtr><mtd rowspan='2'>\(space(10, 30, 10, "red"))</mtd><mtd>\(space(10, 25, 5, "lime"))</mtd></mtr>"
                + "<mtr><mtd>\(space(10, 15, 5, "blue"))</mtd></mtr></mtable></mstyle>"
            let box = try innerBox(body)
            let rects = rectangles(box)
            XCTAssertEqual(rects.count, 3)
            XCTAssertEqual(box.height, 50, accuracy: 0.001)
            switch alignment {
            case "top": XCTAssertEqual(rects[0].maxY, box.ascent, accuracy: 0.001)
            case "bottom": XCTAssertEqual(rects[0].minY, -box.descent, accuracy: 0.001)
            default: XCTAssertEqual(rects[0].midY, (box.ascent - box.descent) / 2, accuracy: 0.001)
            }
        }
    }

    func testSpanningAxisCellsRetainTheirOwnFontAxis() throws {
        let body = "<mtable rowalign='axis' rowspacing='0px'><mtr><mtd rowspan='2' mathsize='40px'>"
            + space(10, 30, 10, "red") + "</mtd><mtd>" + space(10, 10, 5, "lime")
            + "</mtd></mtr><mtr><mtd>" + space(10, 10, 5, "blue") + "</mtd></mtr></mtable>"
        let box = try innerBox(body, size: 20)
        let rects = rectangles(box)
        let firstBaseline = rects[0].minY + 10, secondBaseline = rects[1].minY + 5
        XCTAssertEqual(firstBaseline + constant(\.axisHeight, size: 40),
                       secondBaseline + constant(\.axisHeight, size: 20), accuracy: 0.001)
        for rect in rects {
            XCTAssertLessThanOrEqual(rect.maxY, box.ascent + 0.001)
            XCTAssertGreaterThanOrEqual(rect.minY, -box.descent - 0.001)
        }
    }

    func testGroupsAndInheritedListsAddressOccupiedGridColumns() throws {
        let body = "<mstyle rowalign='top' groupalign='{left} {right}'><mtable columnspacing='0px' rowspacing='0px'>"
            + "<mtr><mtd rowspan='2'>" + space(10, 30, 10, "red") + "</mtd><mtd><maligngroup/>"
            + space(10, 8, 2, "lime") + "</mtd></mtr><mtr><mtd><maligngroup/>"
            + space(30, 8, 2, "blue") + "</mtd></mtr></mtable></mstyle>"
        let rects = rectangles(try innerBox(body))
        XCTAssertEqual(rects.count, 3)
        XCTAssertEqual(rects[1].maxX, rects[2].maxX, accuracy: 0.001)
        XCTAssertEqual(rects[1].maxY, rects[0].maxY, accuracy: 0.001)
        XCTAssertGreaterThan(rects[1].minX, rects[2].minX)
    }

    func testNestedTableWrappingInsideSpansKeepsFramesLabelsAndGroupWidths() throws {
        let text = "<mtext>alpha beta gamma delta epsilon zeta eta theta</mtext>"
        let inner = "<mtable frame='solid'><mtr><mtd><maligngroup/><mn>1.5</mn></mtd><mtd>\(text)</mtd></mtr>"
            + "<mtr><mtd><maligngroup/><mn>12.75</mn></mtd><mtd>\(text)</mtd></mtr></mtable>"
        let body = "<mstyle rowalign='top' groupalign='{decimalpoint}'><mtable frame='dashed' side='left' rowlines='solid'>"
            + "<mlabeledtr><mtd rowspan='2' rowalign='center'><mi>L</mi></mtd><mtd columnspan='2'>\(inner)</mtd><mtd>\(text)</mtd></mlabeledtr>"
            + "<mtr><mtd><mi>x</mi></mtd><mtd><mi>y</mi></mtd><mtd>\(text)</mtd></mtr></mtable></mstyle>"
        let natural = try MathLayout(node(body), style: MathStyle(fontSize: 20, color: black))
        let tiny = try MathLayout(node(body), style: MathStyle(fontSize: 20, color: black), maximumWidth: 0)
        XCTAssertLessThan(tiny.width, natural.width * 0.8)
        for width in [(natural.width + tiny.width) / 2, tiny.widestUnbreakableWidth] {
            let fitted = try MathLayout(node(body), style: MathStyle(fontSize: 20, color: black), maximumWidth: width)
            XCTAssertLessThanOrEqual(fitted.width, width + 0.001)
            XCTAssertGreaterThan(height(fitted), height(natural))
            let bounds = try XCTUnwrap(ink(fitted))
            XCTAssertGreaterThanOrEqual(bounds.minX, -0.5)
            XCTAssertLessThanOrEqual(bounds.maxX, fitted.width + 0.5)
            XCTAssertGreaterThanOrEqual(bounds.minY, -fitted.descent - 0.5)
            XCTAssertLessThanOrEqual(bounds.maxY, fitted.ascent + 0.5)
        }
    }

    func testRepeatedCachedScopesRetainDistinctSourceMarkPriorities() throws {
        let table = try XCTUnwrap(node("<mtable alignmentscope='false'><mtr><mtd><malignmark/><mi>x</mi></mtd></mtr></mtable>").children.first)
        let engine = LayoutEngine(fontName: nil)
        var context = LayoutContext(fontSize: 20, unclampedSize: 20, minSize: 12, display: false, color: black)
        context.trackAlignment = true
        _ = try engine.layout(table, context, depth: 0)
        let row = MathMLNode(name: "mtd", children: [table, table])
        let rebuilt = try engine.relayoutCell(TableCellSource(node: row, context: context, depth: 0), width: 100)
        let priorities = rebuilt.alignment.compactMap { event -> Int? in
            if case .mark = event.kind { return event.order }
            return nil
        }
        XCTAssertEqual(priorities.count, 2)
        XCTAssertEqual(Set(priorities).count, 2)
        XCTAssertLessThan(priorities[0], priorities[1])
    }

    func testCachedRelayoutChargesSharedTableWork() throws {
        let table = try XCTUnwrap(node("<mtable><mtr><mtd columnspan='2'><mi>x</mi></mtd></mtr></mtable>").children.first)
        let engine = LayoutEngine(fontName: nil)
        let context = LayoutContext(fontSize: 20, unclampedSize: 20, minSize: 12, display: false, color: black)
        _ = try engine.layout(table, context, depth: 0)
        let cached = try XCTUnwrap(engine.tableMeasurements.lookup(table, context))
        XCTAssertEqual(cached.tableWork, 2)
        let source = TableCellSource(node: table, context: context, depth: 0)
        _ = try engine.relayoutCell(source, width: 100)
        XCTAssertEqual(engine.tableMeasurements.rebuildTableWork, 2)
        engine.tableMeasurements.rebuildTableWork = MathLimits.tableWork - 1
        XCTAssertThrowsError(try engine.relayoutCell(source, width: 100)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
    }
}
