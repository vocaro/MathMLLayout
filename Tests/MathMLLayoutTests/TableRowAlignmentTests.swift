import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

/// MathML 3 §3.5.1–3.5.4: vertical cell alignment and table/row/cell precedence.
final class TableRowAlignmentTests: XCTestCase {
    private let tolerance: CGFloat = 0.001

    private func cell(_ ascent: CGFloat, _ descent: CGFloat, _ attributes: String = "") -> String {
        "<mtd \(attributes)><mspace width=\"10px\" height=\"\(ascent)px\" depth=\"\(descent)px\" mathbackground=\"red\"/></mtd>"
    }

    private func table(_ body: String) throws -> MathBox {
        try innerBox(XCTUnwrap(try mathML(body).children.first))
    }

    /// Exact colored backgrounds, y up, independent of rasterization and font smoothing.
    private func rectangles(_ box: MathBox, at origin: CGPoint = .zero) -> [CGRect] {
        box.items.flatMap { item -> [CGRect] in
            switch item {
            case .rect(let rect, let color):
                color.components?.prefix(3).contains(where: { $0 > 0 }) == true
                    ? [rect.offsetBy(dx: origin.x, dy: origin.y)] : []
            case .box(let child, let point): rectangles(child, at: CGPoint(x: origin.x + point.x, y: origin.y + point.y))
            default: []
            }
        }
    }

    func testAllAlignmentsWithUnequalCellHeights() throws {
        for alignment in ["top", "bottom", "center", "baseline", "axis"] {
            let box = try table("<mtable align=\"baseline 1\" rowalign=\"\(alignment)\"><mtr>\(cell(30, 10))\(cell(10, 5))</mtr></mtable>")
            let rects = rectangles(box)
            XCTAssertEqual(rects.count, 2)
            XCTAssertEqual(box.height, 40, accuracy: tolerance, alignment)
            switch alignment {
            case "top": XCTAssertEqual(rects[0].maxY, rects[1].maxY, accuracy: tolerance)
            case "bottom": XCTAssertEqual(rects[0].minY, rects[1].minY, accuracy: tolerance)
            case "center": XCTAssertEqual(rects[0].midY, rects[1].midY, accuracy: tolerance)
            default: XCTAssertEqual(rects[0].minY + 10, rects[1].minY + 5, accuracy: tolerance)
            }
            XCTAssertGreaterThanOrEqual(rects[1].minY, -box.descent - tolerance)
            XCTAssertLessThanOrEqual(rects[1].maxY, box.ascent + tolerance)
        }
    }

    func testEdgeAlignmentUsesTallestHeightInsteadOfIndependentBaselineExtents() throws {
        for alignment in ["top", "bottom", "center"] {
            let box = try table("<mtable rowalign=\"\(alignment)\"><mtr>\(cell(30, 0))\(cell(0, 30))</mtr></mtable>")
            XCTAssertEqual(box.height, 30, accuracy: tolerance)
            XCTAssertEqual(rectangles(box)[0].minY, rectangles(box)[1].minY, accuracy: tolerance)
        }
        for alignment in ["", "rowalign=\"baseline\"", "rowalign=\"axis\""] {
            XCTAssertEqual(try table("<mtable \(alignment)><mtr>\(cell(30, 0))\(cell(0, 30))</mtr></mtable>").height,
                           60, accuracy: tolerance)
        }
    }

    func testTableListRepeatsLastValueAndIgnoresExcess() throws {
        let row = "<mtr>\(cell(30, 10))\(cell(10, 5))</mtr>"
        let body = "<mtable rowalign=\"top bottom\">\(row)\(row)\(row)</mtable>"
        let rects = rectangles(try table(body))
        XCTAssertEqual(rects[0].maxY, rects[1].maxY, accuracy: tolerance)
        XCTAssertEqual(rects[2].minY, rects[3].minY, accuracy: tolerance)
        XCTAssertEqual(rects[4].minY, rects[5].minY, accuracy: tolerance)
        let excess = try table("<mtable rowalign=\"top bottom bottom center\">\(row)\(row)\(row)</mtable>")
        XCTAssertEqual(rects, rectangles(excess))
    }

    func testRowAndCellOverridesIncludeMixedBaselineAndEdgeAlignment() throws {
        let box = try table("<mtable align=\"baseline 1\" rowalign=\"bottom\"><mtr rowalign=\"top\">"
            + cell(30, 10) + cell(10, 5) + cell(10, 5, "rowalign=\"bottom\"")
            + cell(10, 5, "rowalign=\"center\"") + cell(10, 5, "rowalign=\"baseline\"") + "</mtr></mtable>")
        let rects = rectangles(box)
        XCTAssertEqual(box.height, 40, accuracy: tolerance)
        XCTAssertEqual(rects[0].maxY, rects[1].maxY, accuracy: tolerance)
        XCTAssertEqual(rects[0].minY, rects[2].minY, accuracy: tolerance)
        XCTAssertEqual(rects[0].midY, rects[3].midY, accuracy: tolerance)
        XCTAssertEqual(rects[4].minY + 5, 0, accuracy: tolerance)
        // An edge-aligned cell can be taller than all baseline-aligned cells: the row grows.
        XCTAssertEqual(box.ascent, 22.5, accuracy: tolerance)
        XCTAssertEqual(box.descent, 17.5, accuracy: tolerance)
    }

    func testInvalidAndEmptyOverridesFallBackToInheritedAlignment() throws {
        let reference = try table("<mtable rowalign=\"top\"><mtr>\(cell(30, 10))\(cell(10, 5))</mtr></mtable>")
        for invalid in ["", "invalid", "top bottom"] {
            let box = try table("<mtable rowalign=\"top\"><mtr rowalign=\"\(invalid)\">\(cell(30, 10))\(cell(10, 5, "rowalign=\"\(invalid)\""))</mtr></mtable>")
            XCTAssertEqual(rectangles(box), rectangles(reference))
        }
        let normalized = try table("<mtable rowalign=\" TOP \t\"><mtr rowalign=\"\n Top \t\">\(cell(30, 10))\(cell(10, 5, "rowalign=\" Top \t\""))</mtr></mtable>")
        XCTAssertEqual(rectangles(normalized), rectangles(reference))
    }

    func testAxisAlignmentAccountsForCellAndRowFontSizes() throws {
        let axis = constant(\.axisHeight)
        for alignment in ["baseline 1", "axis 1", "axis -1"] {
            let body = "<mtable align=\"\(alignment)\" rowalign=\"axis\"><mtr mathsize=\"40px\">"
                + cell(30, 10) + cell(10, 5, "mathsize=\"20px\"") + "</mtr></mtable>"
            let box = try table(body), rects = rectangles(box)
            let firstBaseline = rects[0].minY + 10, secondBaseline = rects[1].minY + 5
            XCTAssertEqual(firstBaseline + 2 * axis, secondBaseline + axis, accuracy: tolerance)
            XCTAssertEqual(firstBaseline, alignment == "baseline 1" ? 0 : -axis, accuracy: tolerance)
            XCTAssertEqual(box.height, 40, accuracy: tolerance)
        }
        // Unlike baseline, axis aligns differently sized cells even without a row size override.
        let axisRects = rectangles(try table("<mtable align=\"axis 1\" rowalign=\"axis\"><mtr>"
            + cell(30, 10, "mathsize=\"40px\"") + cell(10, 5) + "</mtr></mtable>"))
        XCTAssertEqual(axisRects[0].minY + 10, -axis, accuracy: tolerance)
        XCTAssertEqual(axisRects[1].minY + 5, 0, accuracy: tolerance)
    }

    func testFractionsAlignByFinalCellBoxes() throws {
        let fraction = "<mfrac><mn>1</mn><mn>2</mn></mfrac>"
        for alignment in ["top", "bottom", "center"] {
            let body = "<mtable rowalign=\"\(alignment)\"><mtr><mtd mathbackground=\"red\"><mi>x</mi></mtd>"
                + "<mtd mathbackground=\"blue\">\(fraction)</mtd></mtr></mtable>"
            let box = try table(body), rects = rectangles(box)
            XCTAssertEqual(rects.count, 2)
            XCTAssertEqual(box.height, max(rects[0].height, rects[1].height), accuracy: tolerance)
            switch alignment {
            case "top": XCTAssertEqual(rects[0].maxY, rects[1].maxY, accuracy: tolerance)
            case "bottom": XCTAssertEqual(rects[0].minY, rects[1].minY, accuracy: tolerance)
            default: XCTAssertEqual(rects[0].midY, rects[1].midY, accuracy: tolerance)
            }
            assertBoxCoversInk(try typeset(body), alignment)
        }
    }

    func testLabelsInheritRowAlignmentAndAcceptCellOverrides() throws {
        for side in ["left", "right"] {
            for alignment in ["top", "bottom", "center", "baseline", "axis"] {
                let body = "<mtable side=\"\(side)\" rowalign=\"\(alignment)\"><mlabeledtr>"
                    + cell(10, 5) + cell(30, 10) + "</mlabeledtr></mtable>"
                let rects = rectangles(try table(body)) // grid cell followed by label
                switch alignment {
                case "top": XCTAssertEqual(rects[0].maxY, rects[1].maxY, accuracy: tolerance)
                case "bottom": XCTAssertEqual(rects[0].minY, rects[1].minY, accuracy: tolerance)
                case "center": XCTAssertEqual(rects[0].midY, rects[1].midY, accuracy: tolerance)
                default: XCTAssertEqual(rects[0].minY + 10, rects[1].minY + 5, accuracy: tolerance)
                }
                assertBoxCoversInk(try typeset(body), body)
            }
            let overridden = rectangles(try table("<mtable side=\"\(side)\" rowalign=\"baseline\"><mlabeledtr rowalign=\"top\">"
                + cell(10, 5, "rowalign=\"bottom\"") + cell(30, 10) + "</mlabeledtr></mtable>"))
            XCTAssertEqual(overridden[0].minY, overridden[1].minY, accuracy: tolerance)
        }
    }

    func testSpacingRulesAndFramesFollowAlignedRowHeight() throws {
        let body = "<mtable align=\"top\" rowalign=\"top bottom\" rowspacing=\"8px\" frame=\"solid\" framespacing=\"4px 6px\" rowlines=\"solid\">"
            + "<mtr>\(cell(30, 0))\(cell(0, 30))</mtr><mtr>\(cell(10, 5))\(cell(30, 0))</mtr></mtable>"
        let box = try table(body), rects = rectangles(box)
        XCTAssertEqual(box.ascent, 0, accuracy: tolerance)
        XCTAssertEqual(box.descent, 80, accuracy: tolerance)
        XCTAssertEqual(rects[0].maxY, -6, accuracy: tolerance)
        XCTAssertEqual(rects[2].minY, -74, accuracy: tolerance)
        let paths = box.items.compactMap { item -> CGPath? in
            if case .path(let path, _, _, _) = item { return path }
            return nil
        }
        XCTAssertEqual(paths.count, 1)
        var horizontal: [CGFloat] = []
        paths[0].applyWithBlock { element in
            if element.pointee.type == .addLineToPoint { horizontal.append(element.pointee.points[0].y) }
        }
        XCTAssertTrue(horizontal.contains { abs($0 + 40) < tolerance }, "rule is halfway between final rows")
        let ink = try XCTUnwrap(box.inkBounds)
        XCTAssertEqual(ink.maxY, box.ascent, accuracy: tolerance)
        XCTAssertEqual(ink.minY, -box.descent, accuracy: tolerance)
        assertBoxCoversInk(try typeset(body), body)
    }

    func testTallLabelsAndCellAxisOverridesStayInsideFramedRows() throws {
        for alignment in ["top", "bottom", "center", "baseline", "axis"] {
            let body = "<mtable rowalign=\"\(alignment)\" side=\"left\" frame=\"dashed\" rowlines=\"solid\" rowspacing=\"8px\">"
                + "<mlabeledtr>" + cell(50, 20, "mathsize=\"40px\" rowalign=\"axis\"")
                + cell(10, 5) + "</mlabeledtr><mtr>" + cell(10, 5) + "</mtr></mtable>"
            let box = try table(body), rects = rectangles(box), ink = try XCTUnwrap(box.inkBounds)
            XCTAssertGreaterThanOrEqual(rects[1].minY - rects[2].maxY, 8 - tolerance,
                                        "the tall label cannot overlap the following row")
            XCTAssertGreaterThanOrEqual(ink.minY, -box.descent - tolerance)
            XCTAssertLessThanOrEqual(ink.maxY, box.ascent + tolerance)
            assertBoxCoversInk(try typeset(body), body)
        }
    }

    func testWrappingPrecedesVerticalAlignment() throws {
        let text = "<mtext mathcolor=\"red\">alpha beta gamma delta epsilon zeta eta theta</mtext>"
        let fraction = "<mfrac mathcolor=\"blue\"><mn>1</mn><mn>2</mn></mfrac>"
        let textBox = try innerBox(text), fractionBox = try innerBox(fraction)
        let textInk = try XCTUnwrap(textBox.inkBounds), fractionInk = try XCTUnwrap(fractionBox.inkBounds)
        for alignment in ["top", "bottom", "center", "baseline", "axis"] {
            let body = "<mtable rowalign=\"\(alignment)\"><mtr><mtd>\(text)</mtd><mtd>\(fraction)</mtd></mtr></mtable>"
            let natural = try typeset(body)
            let wrapped = try MathLayout(mathML(body), style: MathStyle(fontSize: em, color: black), maximumWidth: 130)
            XCTAssertEqual(wrapped.rows.count, 1)
            XCTAssertLessThanOrEqual(wrapped.width, 130.001)
            XCTAssertGreaterThan(height(wrapped), height(natural) + em)
            let rendering = Rendering(wrapped)
            let red = try XCTUnwrap(rendering.bounds(.red)), blue = try XCTUnwrap(rendering.bounds(.blue))
            // Text line boxes follow their ink; the fraction's rule can have a small box/ink gap.
            switch alignment {
            case "top": XCTAssertEqual(red.maxY, blue.maxY + fractionBox.ascent - fractionInk.maxY, accuracy: 0.6)
            case "bottom": XCTAssertEqual(red.minY, blue.minY - fractionBox.descent - fractionInk.minY, accuracy: 0.6)
            case "center": XCTAssertEqual(red.midY, blue.midY + (fractionBox.ascent - fractionBox.descent) / 2 - fractionInk.midY, accuracy: 0.6)
            default: XCTAssertEqual(red.maxY - textInk.maxY, blue.maxY - fractionInk.maxY, accuracy: 0.6)
            }
            assertBoxCoversInk(wrapped, alignment, rendering: rendering)
        }
    }

    func testForcedBreaksUseFinalCellHeight() throws {
        let body = "<mtable rowalign=\"bottom\"><mtr><mtd><mi mathcolor=\"red\">alpha</mi><mspace linebreak=\"newline\"/><mi mathcolor=\"red\">beta</mi></mtd>"
            + "<mtd><mi mathcolor=\"blue\">x</mi></mtd></mtr></mtable>"
        let layout = try typeset(body), rendering = Rendering(layout)
        let red = try XCTUnwrap(rendering.bounds(.red)), blue = try XCTUnwrap(rendering.bounds(.blue))
        XCTAssertGreaterThan(red.height, blue.height + em * 0.8)
        XCTAssertEqual(red.minY, blue.minY, accuracy: 0.6)
        assertBoxCoversInk(layout, body, rendering: rendering)
    }
}
