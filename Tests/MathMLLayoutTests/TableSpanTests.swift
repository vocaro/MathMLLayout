import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

final class TableSpanTests: XCTestCase {
    private func cell(_ color: String, width: CGFloat = 20, height: CGFloat = 10,
                      descent: CGFloat = 0, attributes: String = "") -> String {
        "<mtd \(attributes)><mspace width=\"\(width)px\" height=\"\(height)px\" depth=\"\(descent)px\" mathbackground=\"\(color)\"/></mtd>"
    }

    func testCombinedSpansSkipOccupiedColumnsAndConstrainDimensions() throws {
        let body = "<mtable columnspacing=\"5px\" rowspacing=\"0\"><mtr>"
            + cell("red", width: 40, descent: 60, attributes: "rowspan=\"3\" columnspan=\"2\"")
            + cell("blue", width: 10) + "</mtr><mtr>" + cell("lime") + "</mtr><mtr>"
            + cell("black", width: 10) + "</mtr></mtable>"
        let box = try innerBox(body), found = try inks(body)
        XCTAssertEqual(box.width, 65, accuracy: 0.001)
        XCTAssertEqual(box.height, 70, accuracy: 0.001)
        let red = try XCTUnwrap(found[.red]), green = try XCTUnwrap(found[.green])
        XCTAssertEqual(red.minX, 0, accuracy: 0.6)
        XCTAssertEqual(green.minX, 45, accuracy: 0.6)
        XCTAssertEqual(try XCTUnwrap(found[.blue]).midX, green.midX, accuracy: 0.6)
        XCTAssertEqual(try XCTUnwrap(found[.black]).midX, green.midX, accuracy: 0.6)
        XCTAssertEqual(red.minY, -box.descent, accuracy: 0.6)
        assertBoxCoversInk(try typeset(body), body)
    }

    func testSparseRowsAndMixedSpacingContributeInsideSpans() throws {
        let body = "<mtable columnspacing=\"4px 6px\" rowspacing=\"2px 3px\"><mtr>"
            + cell("red", width: 60, descent: 40, attributes: "rowspan=\"3\" columnspan=\"3\"")
            + "</mtr><mtr/><mtr/></mtable>"
        let box = try innerBox(body)
        XCTAssertEqual(box.width, 60, accuracy: 0.001, "internal gaps count toward the span width")
        XCTAssertEqual(box.height, 50, accuracy: 0.001, "internal row gaps count toward the span depth")
        let ink = try XCTUnwrap(box.inkBounds)
        XCTAssertEqual(ink.width, box.width, accuracy: 0.001)
        XCTAssertEqual(ink.height, box.height, accuracy: 0.001)
    }

    func testFullRectangleSearchAvoidsPartialOverlap() throws {
        var grid = try TableGrid(rowCount: 2)
        let box = MathBox(width: 1)
        try grid.insert(box, row: 0, rowSpan: 1, columnSpan: 1, align: nil, rowAlign: nil)
        try grid.insert(box, row: 0, rowSpan: 2, columnSpan: 1, align: nil, rowAlign: nil)
        try grid.insert(box, row: 1, rowSpan: 1, columnSpan: 2, align: nil, rowAlign: nil)
        XCTAssertEqual(grid.rows[1][0].column, 2, "a free starting slot cannot overlap the occupied second slot")
        XCTAssertEqual(grid.columns, 4)
    }

    func testAlignmentUsesFullSpanAndGridColumnAfterSkip() throws {
        for align in ["left", "center", "right"] {
            let body = "<mtable columnspacing=\"4px\" columnalign=\"left \(align)\"><mtr>"
                + cell("red", width: 10, attributes: "rowspan=\"2\"") + cell("blue", width: 40)
                + "</mtr><mtr columnalign=\"left \(align)\">" + cell("lime", width: 10, attributes: "columnspan=\"2\"")
                + "</mtr><mtr>" + cell("black", width: 10) + cell("black", width: 40)
                + cell("black", width: 20) + "</mtr></mtable>"
            let found = try inks(body), green = try XCTUnwrap(found[.green])
            let expected: CGFloat = align == "left" ? 14 : align == "right" ? 68 : 41
            XCTAssertEqual(green.minX, expected, accuracy: 0.6)
        }
    }

    func testSpansAndLabelsUseSeparateColumns() throws {
        for side in ["left", "right"] {
            let body = "<mtable side=\"\(side)\" columnspacing=\"4px\" minlabelspacing=\"3px\"><mtr>"
                + cell("red", width: 30, attributes: "rowspan=\"2\" columnspan=\"2\"") + cell("blue", width: 10)
                + "</mtr><mlabeledtr>" + cell("black", width: 6) + cell("lime", width: 10)
                + "</mlabeledtr></mtable>"
            let box = try innerBox(body), found = try inks(body)
            XCTAssertEqual(box.width, 53, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(found[.blue]).minX, try XCTUnwrap(found[.green]).minX, accuracy: 0.6)
            let red = try XCTUnwrap(found[.red]), label = try XCTUnwrap(found[.black])
            if side == "left" { XCTAssertLessThan(label.maxX, red.minX) }
            else { XCTAssertGreaterThan(label.minX, try XCTUnwrap(found[.green]).maxX) }
        }
    }

    func testVerticalAlignmentUsesFullRowSpan() throws {
        for align in ["baseline", "top", "bottom", "center"] {
            let body = "<mtable rowspacing=\"5px\"><mtr>"
                + cell("red", height: 10, attributes: "rowspan=\"2\" rowalign=\" \(align) \"")
                + cell("blue", height: 10) + "</mtr><mtr>" + cell("lime", height: 30) + "</mtr></mtable>"
            let found = try inks(body), red = try XCTUnwrap(found[.red])
            let top = try XCTUnwrap(found[.blue]).maxY, bottom = try XCTUnwrap(found[.green]).minY
            switch align {
            case "bottom": XCTAssertEqual(red.minY, bottom, accuracy: 0.6)
            case "center": XCTAssertEqual(red.midY, (top + bottom) / 2, accuracy: 0.6)
            default: XCTAssertEqual(red.maxY, top, accuracy: 0.6)
            }
            assertBoxCoversInk(try typeset(body), body)
        }
    }

    func testSpanningLabelReservesHeightWithoutConsumingGridSlots() throws {
        let body = "<mtable side=\"left\" minlabelspacing=\"3px\" rowspacing=\"0\"><mlabeledtr>"
            + cell("red", width: 6, descent: 60, attributes: "rowspan=\"2\" columnspan=\"3\"")
            + cell("blue") + "</mlabeledtr><mtr>" + cell("lime") + "</mtr></mtable>"
        let box = try innerBox(body), found = try inks(body)
        XCTAssertEqual(box.width, 29, accuracy: 0.001)
        XCTAssertEqual(box.height, 70, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(found[.blue]).minX, try XCTUnwrap(found[.green]).minX, accuracy: 0.6)
        XCTAssertEqual(try XCTUnwrap(found[.red]).minY, -box.descent, accuracy: 0.6)
        assertBoxCoversInk(try typeset(body), body)
    }

    func testSpanningCellWrapsWithinAllTracksAndKeepsInkCovered() throws {
        let body = "<mtable frame=\"solid\" columnspacing=\"4px\" columnalign=\"left\"><mtr><mtd columnspan=\"2\" rowspan=\"2\">"
            + "<mtext>alpha beta gamma delta epsilon zeta eta theta iota</mtext></mtd><mtd><mi>x</mi></mtd></mtr>"
            + "<mtr><mtd><mi>y</mi></mtd></mtr><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd><mtd><mi>c</mi></mtd></mtr></mtable>"
        let natural = try typeset(body)
        for width: CGFloat in [180, 120, 100] {
            let layout = try MathLayout(mathML(body), style: MathStyle(fontSize: em, color: black), maximumWidth: width)
            XCTAssertEqual(layout.rows.count, 1)
            XCTAssertLessThanOrEqual(layout.width, width + 0.01)
            XCTAssertGreaterThan(height(layout), height(natural))
            assertBoxCoversInk(layout, body)
        }
        let tooNarrow = try MathLayout(mathML(body), style: MathStyle(fontSize: em, color: black), maximumWidth: 90)
        XCTAssertGreaterThan(tooNarrow.width, 90, "a word plus the remaining track and frame cannot fit")
        XCTAssertEqual(tooNarrow.width, tooNarrow.widestUnbreakableWidth, accuracy: 0.01)
        let atMinimum = try MathLayout(mathML(body), style: MathStyle(fontSize: em, color: black),
                                       maximumWidth: tooNarrow.widestUnbreakableWidth)
        XCTAssertLessThanOrEqual(atMinimum.width, tooNarrow.widestUnbreakableWidth + 0.01)
        let forced = "<mtable><mtr><mtd columnspan=\"2\"><mi>a</mi><mspace linebreak=\"newline\"/><mi>b</mi></mtd></mtr></mtable>"
        XCTAssertGreaterThan(try innerBox(forced).height, try innerBox("<mtable><mtr><mtd columnspan=\"2\"><mi>a</mi><mi>b</mi></mtd></mtr></mtable>").height)
    }

    private func segments(_ box: MathBox) -> [(CGPoint, CGPoint)] {
        var result: [(CGPoint, CGPoint)] = []
        for item in box.items {
            switch item {
            case .box(let child, let origin):
                result += segments(child).map { (CGPoint(x: $0.0.x + origin.x, y: $0.0.y + origin.y),
                                                CGPoint(x: $0.1.x + origin.x, y: $0.1.y + origin.y)) }
            case .path(let path, _, _, _), .dashes(let path, _, _, _):
                var previous = CGPoint.zero
                path.applyWithBlock { pointer in
                    let element = pointer.pointee
                    if element.type == .moveToPoint { previous = element.points[0] }
                    if element.type == .addLineToPoint { result.append((previous, element.points[0])); previous = element.points[0] }
                }
            default: break
            }
        }
        return result
    }

    func testRulesStopAtCombinedSpansAndFramesKeepInkInside() throws {
        for style in ["solid", "dashed"] {
            let body = "<mtable frame=\"\(style)\" rowlines=\"\(style)\" columnlines=\"\(style)\" framespacing=\"0 0\" rowspacing=\"4px\" columnspacing=\"4px\"><mtr>"
                + cell("red", width: 40, descent: 35, attributes: "rowspan=\"2\" columnspan=\"2\"")
                + cell("blue") + "</mtr><mtr>" + cell("lime") + "</mtr><mtr>"
                + cell("black") + cell("black") + cell("black") + "</mtr></mtable>"
            let box = try innerBox(body), red = try XCTUnwrap(try inks(body)[.red])
            // Frame lies on the outside edge; no segment may cross the interior of the span.
            for (a, b) in segments(box) {
                if abs(a.y - b.y) < 0.001, a.y < red.maxY - 1, a.y > red.minY + 1 {
                    XCTAssertTrue(max(a.x, b.x) <= red.minX + 0.6 || min(a.x, b.x) >= red.maxX - 0.6)
                }
                if abs(a.x - b.x) < 0.001, a.x > red.minX + 1, a.x < red.maxX - 1 {
                    XCTAssertTrue(max(a.y, b.y) <= red.minY + 0.6 || min(a.y, b.y) >= red.maxY - 0.6)
                }
            }
            assertBoxCoversInk(try typeset(body), body)
        }
    }

    func testRulesWithNegativeFrameSpacingStayWithinRuleBounds() throws {
        for style in ["solid", "dashed"] {
            var rows = ""
            for index in 0..<20 {
                rows += "<mtr>" + cell("red", height: 20, attributes: index == 1 ? "columnspan=\"2\"" : "") + "</mtr>"
            }
            let body = "<mtable framespacing=\"0 -100px\" rowspacing=\"0\" columnlines=\"\(style)\" frame=\"\(style)\">" + rows + "</mtable>"
            let box = try innerBox(body)
            for (a, b) in segments(box) {
                for point in [a, b] {
                    XCTAssertGreaterThanOrEqual(point.y, -box.descent - 0.001)
                    XCTAssertLessThanOrEqual(point.y, box.ascent + 0.001)
                    XCTAssertGreaterThanOrEqual(point.x, -0.001)
                    XCTAssertLessThanOrEqual(point.x, box.width + 0.001)
                }
            }
            assertBoxCoversInk(try typeset(body), body)
        }
    }

    func testNestedSiblingAndLabelSpansShareTheWorkBudget() throws {
        let large = "<mtable columnspacing=\"0\"><mtr><mtd columnspan=\"20000\"/></mtr></mtable>"
        for content in [String(repeating: large, count: 11),
                        "<mtable><mtr><mtd>" + String(repeating: large, count: 11) + "</mtd></mtr></mtable>"] {
            XCTAssertThrowsError(try innerBox(content)) {
                XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
            }
        }
        // A conflict search must stop at its remaining shared allowance before probing again.
        var limited = try TableGrid(rowCount: 4)
        try limited.insert(MathBox(), row: 3, rowSpan: 1, columnSpan: 1, align: nil, rowAlign: nil)
        let before = limited.work
        XCTAssertThrowsError(try limited.insert(MathBox(), row: 0, rowSpan: 4, columnSpan: 1,
                                                align: nil, rowAlign: nil, workBudget: 5))
        XCTAssertEqual(limited.work - before, 5)
        let label = "<mlabeledtr><mtd rowspan=\"1000\"><mspace/></mtd></mlabeledtr>"
        XCTAssertThrowsError(try innerBox("<mtable>" + String(repeating: label, count: 1000) + "</mtable>")) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded, "independent labels cannot multiply track work without bound")
        }
    }

    func testInvalidOversizedAndAreaLimitedSpans() throws {
        for value in ["0", "-1", "+2", "1.5", "bad", "", "NaN"] {
            XCTAssertEqual(try TableGrid.span(value), 1)
        }
        for value in ["20001", "999999999999999999999999999999999999"] {
            XCTAssertThrowsError(try innerBox("<mtable><mtr><mtd columnspan=\"\(value)\"><mi>x</mi></mtd></mtr></mtable>")) {
                XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
            }
        }
        var grid = try TableGrid(rowCount: 201)
        XCTAssertThrowsError(try grid.insert(MathBox(), row: 0, rowSpan: 201, columnSpan: 100, align: nil, rowAlign: nil))
        var busy = try TableGrid(rowCount: 2000)
        try busy.insert(MathBox(), row: 1999, rowSpan: 1, columnSpan: 101, align: nil, rowAlign: nil)
        XCTAssertThrowsError(try busy.insert(MathBox(), row: 0, rowSpan: 2000, columnSpan: 1, align: nil, rowAlign: nil)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded, "conflict searches have a work bound")
        }
        let clipped = try innerBox("<mtable rowspacing=\"0\" columnspacing=\"0\"><mtr><mtd rowspan=\"20000\" columnspan=\"20000\"/></mtr></mtable>")
        XCTAssertEqual(clipped.width, 0)
        XCTAssertEqual(clipped.height, 0)
        XCTAssertThrowsError(try typeset("<mtable columnspacing=\"3px\"><mtr><mtd columnspan=\"20000\"/></mtr></mtable>"))
    }
}
