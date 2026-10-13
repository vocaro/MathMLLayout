import CoreGraphics
@testable import MathMLLayout
import XCTest

final class NestedTableWrappingTests: MathTestCase {
    private let text = "<mtext>alpha beta gamma delta epsilon zeta eta theta</mtext>"

    private func table(_ content: String, neighbor: String = "", attributes: String = "") -> String {
        let second = neighbor.isEmpty ? "" : "<mtd>\(neighbor)</mtd>"
        return "<mtable \(attributes)><mtr><mtd>\(content)</mtd>\(second)</mtr></mtable>"
    }

    private func broken(_ body: String, width: CGFloat) throws -> MathLayout {
        try MathLayout(node(body), style: MathStyle(fontSize: 20, color: black), maximumWidth: width)
    }

    private func assertInk(_ layout: MathLayout, _ message: String) throws {
        let bounds = try XCTUnwrap(ink(layout), message)
        XCTAssertGreaterThanOrEqual(bounds.minX, -0.5, message)
        XCTAssertLessThanOrEqual(bounds.maxX, layout.width + 0.5, message)
        XCTAssertGreaterThanOrEqual(bounds.minY, -layout.descent - 0.5, message)
        XCTAssertLessThanOrEqual(bounds.maxY, layout.ascent + 0.5, message)
    }

    func testNestedTablesNarrowAtAssignedCellWidth() throws {
        let inner = table(text, attributes: "frame=\"solid\"")
        let bodies = [table(inner, neighbor: text),
                      table(table(inner, neighbor: "<mi>x</mi>"), neighbor: text),
                      table(inner + "<mo>+</mo>" + inner, neighbor: text),
                      table(inner, neighbor: table(text)),
                      table(inner + "<mspace linebreak=\"newline\"/>" + text, neighbor: text)]
        for body in bodies {
            let natural = try broken(body, width: .infinity)
            let minimum = try broken(body, width: 0)
            XCTAssertLessThan(minimum.width, natural.width * 0.8, body)
            XCTAssertGreaterThan(height(minimum), height(natural), body)
            let intermediate = (natural.width + minimum.width) / 2
            for width in [natural.width, intermediate, minimum.widestUnbreakableWidth] {
                let fitted = try broken(body, width: width)
                XCTAssertLessThanOrEqual(fitted.width, width + 0.001, body)
                if width == intermediate { XCTAssertGreaterThan(height(fitted), height(natural), body) }
                try assertInk(fitted, body)
            }
        }
    }

    func testNestedFramesLabelsAndForcedBreaksRecomputeOuterRows() throws {
        let forced = "<mi>alpha</mi><mspace linebreak=\"newline\"/><mtext>beta gamma delta epsilon</mtext>"
        let labeled = "<mtable frame=\"dashed\" side=\"left\"><mlabeledtr><mtd><mtext>(1)</mtext></mtd><mtd>\(text)</mtd><mtd>\(forced)</mtd></mlabeledtr></mtable>"
        let body = "<mtable frame=\"solid\" rowlines=\"solid\"><mtr><mtd>\(labeled)</mtd><mtd>\(text)</mtd></mtr><mtr><mtd><mi>x</mi></mtd><mtd><mi>y</mi></mtd></mtr></mtable>"
        let natural = try broken(body, width: .infinity)
        let tiny = try broken(body, width: 0)
        for width in [natural.width, (natural.width + tiny.width) / 2, tiny.widestUnbreakableWidth] {
            let fitted = try broken(body, width: width)
            XCTAssertLessThanOrEqual(fitted.width, width + 0.001)
            try assertInk(fitted, body)
        }
        XCTAssertGreaterThan(height(tiny), height(natural))
    }

    func testGenuinelyUnbreakableNestedTableKeepsItsWidth() throws {
        let fixed = "<mspace width=\"120px\" height=\"20px\" mathbackground=\"red\"/>"
        let body = table(table(fixed, attributes: "frame=\"solid\""), neighbor: text)
        let fitted = try broken(body, width: 40)
        XCTAssertGreaterThan(fitted.width, 120)
        XCTAssertGreaterThan(fitted.widestUnbreakableWidth, 120)
        let exact = try broken(body, width: fitted.widestUnbreakableWidth)
        XCTAssertLessThanOrEqual(exact.width, fitted.widestUnbreakableWidth + 0.001)
        try assertInk(fitted, body)
        try assertInk(exact, body)
    }

    func testSharedTableChildrenRetainInputAndContextChecks() throws {
        let shared = MathMLNode(name: "mtable", children: [
            MathMLNode(name: "mtr", children: [MathMLNode(name: "mtd", children: [
                MathMLNode(name: "mi", text: "x"), MathMLNode(name: "mi", text: "y")])])])
        let oversized = MathMLNode(name: "math", children: Array(repeating: shared, count: 4_001))
        XCTAssertThrowsError(try MathLayout(oversized, style: MathStyle(fontSize: 20, color: black))) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
        let small = MathMLNode(name: "mstyle", attributes: ["mathsize": "10px"], children: [shared])
        let large = MathMLNode(name: "mstyle", attributes: ["mathsize": "30px"], children: [shared])
        let engine = LayoutEngine(fontName: nil)
        engine.lineWidth = 0; engine.wrapWidth = 0
        let root = MathMLNode(name: "math", children: [small, large])
        _ = try engine.layoutRoot(root, style: MathStyle(fontSize: 20, color: black))
        let base = LayoutContext(fontSize: 20, unclampedSize: 20, minSize: 12, display: false, color: black)
        let first = engine.inherit(small, base), second = engine.inherit(large, base)
        XCTAssertNotEqual(first, second)
        let smallBox = try XCTUnwrap(engine.tableMeasurements.lookup(shared, first))
        let largeBox = try XCTUnwrap(engine.tableMeasurements.lookup(shared, second))
        XCTAssertEqual(largeBox.cells.rows[0][0].box.width, smallBox.cells.rows[0][0].box.width * 3, accuracy: 0.001)
    }

    func testNestedWrappingRetainsCompletePassBound() throws {
        var body = text
        for _ in 0..<5 { body = table(body, neighbor: text) }
        let root = try node(body)
        let fitted = try LayoutEngine.lines(root, style: MathStyle(fontSize: 20, color: black),
                                            maximumWidth: 120, firstRowMaximumWidth: nil)
        XCTAssertLessThanOrEqual(fitted.layoutPasses, LayoutEngine.maximumWrappingPasses)
        let engine = LayoutEngine(fontName: nil)
        engine.lineWidth = 200; engine.wrapWidth = 200
        let allocated = try node(table(table(text), neighbor: text))
        _ = try engine.layoutRoot(allocated, style: MathStyle(fontSize: 20, color: black))
        XCTAssertLessThanOrEqual(engine.tableMeasurements.rebuildNodes, LayoutEngine.maximumCellRebuildNodes)
        XCTAssertGreaterThan(engine.tableMeasurements.rebuildNodes, 0)
    }
}
