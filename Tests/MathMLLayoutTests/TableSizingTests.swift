import CoreGraphics
@testable import MathMLLayout
import XCTest

final class TableSizingTests: XCTestCase {
    private func cell(_ width: CGFloat, _ height: CGFloat = 10, _ depth: CGFloat = 0,
                      color: String = "red", attributes: String = "") -> String {
        "<mtd \(attributes)><mspace width=\"\(width)px\" height=\"\(height)px\" depth=\"\(depth)px\" mathbackground=\"\(color)\"/></mtd>"
    }
    private func layout(_ body: String, _ width: CGFloat, maxwidth: String? = nil) throws -> MathLayout {
        try MathLayout(mathML(body, attributes: maxwidth.map { "maxwidth=\"\($0)\"" } ?? ""),
                       style: MathStyle(fontSize: em, color: black), maximumWidth: width)
    }

    func testEqualColumnsSolveSpanningConstraintIncludingInternalGap() throws {
        for direction in ["ltr", "rtl"] {
            let body = "<mtable dir=\"\(direction)\" equalcolumns=\"true\" columnspacing=\"4px\" rowspacing=\"0\"><mtr>"
                + cell(64, attributes: "columnspan=\"2\"") + "</mtr><mtr>"
                + cell(10, color: "blue") + cell(20, color: "lime") + "</mtr></mtable>"
            XCTAssertEqual(try innerBox(body).width, 64, accuracy: 0.001)
            let found = try inks(body)
            let blue = try XCTUnwrap(found[.blue]), green = try XCTUnwrap(found[.green])
            XCTAssertEqual(abs(blue.midX - green.midX), 34, accuracy: 0.6)
            assertBoxCoversInk(try typeset(body), body)
        }
    }

    func testEqualRowsPreserveBaselineOffsetsAndExcludeInterRowGaps() throws {
        let body = "<mtable equalrows=\"true\" columnspacing=\"0\" rowspacing=\"5px\"><mtr>"
            + cell(10, 20, 10) + cell(10, 10, 5, color: "blue") + "</mtr><mtr>"
            + cell(10, 10, 0, color: "lime") + "</mtr></mtable>"
        let box = try innerBox(body), found = try inks(body)
        XCTAssertEqual(box.height, 65, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(found[.red]).maxY - XCTUnwrap(found[.blue]).maxY, 10, accuracy: 0.6)
        XCTAssertEqual(try XCTUnwrap(found[.green]).maxY, box.ascent - 45, accuracy: 0.6)
        assertBoxCoversInk(try typeset(body), body)
    }

    func testAbsoluteRelativePercentageAndFitWidthsHaveIndependentGeometry() throws {
        let row = "<mtr>" + cell(10) + cell(10, color: "blue") + cell(10, color: "lime") + "</mtr>"
        let body = "<mtable width=\"200px\" columnwidth=\"2em 25% fit\" columnspacing=\"5px\" columnalign=\"left\">" + row + "</mtable>"
        let box = try innerBox(body), found = try inks(body)
        XCTAssertEqual(box.width, 200, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(found[.blue]).minX, 45, accuracy: 0.6)
        XCTAssertEqual(try XCTUnwrap(found[.green]).minX, 100, accuracy: 0.6)
        let half = "<mtable width=\"50%\" columnwidth=\"auto fit\" columnspacing=\"0\"><mtr>" + cell(20) + cell(20) + "</mtr></mtable>"
        XCTAssertEqual(try layout(half, 200).width, 100, accuracy: 0.001)
        XCTAssertEqual(try layout(half.replacingOccurrences(of: "50%", with: "0.5"), 200).width, 100, accuracy: 0.001)
        XCTAssertEqual(try innerBox(half).width, 40, accuracy: 0.001, "no finite host means an unresolved relative table width is auto")
    }

    func testFixedColumnListRepeatsAndContentMinimaBeatHostAndAuthoredWidths() throws {
        let body = "<mtable width=\"200px\" columnwidth=\"25px 35px\" columnspacing=\"4px\"><mtr>"
            + cell(10) + cell(10) + cell(10) + "</mtr></mtable>"
        // Three fixed columns total 95px, plus two gaps. A desired width distributes excess.
        XCTAssertEqual(try innerBox(body).width, 200, accuracy: 0.001)
        let narrow = try layout(body, 20)
        XCTAssertEqual(narrow.width, 103, accuracy: 0.001)
        XCTAssertEqual(narrow.widestUnbreakableWidth, 103, accuracy: 0.001)
        XCTAssertEqual(try layout(body, narrow.widestUnbreakableWidth).width, 103, accuracy: 0.001)
        let content = "<mtable width=\"10px\" columnwidth=\"5px\" columnspacing=\"0\"><mtr>" + cell(30) + "</mtr></mtable>"
        XCTAssertEqual(try layout(content, 1).width, 30, accuracy: 0.001)
        XCTAssertEqual(try layout(body, 300, maxwidth: "120px").width, 120, accuracy: 0.001)
    }

    func testExplicitColumnWidthWrapsWithoutHostAndHandlesNestedTablesAndForcedBreaks() throws {
        let text = "<mtext>alpha beta gamma delta epsilon zeta eta</mtext>"
        let table = "<mtable columnwidth=\"70px\" columnspacing=\"0\" frame=\"solid\" framespacing=\"2px 2px\"><mtr><mtd>" + text + "</mtd></mtr></mtable>"
        XCTAssertEqual(try innerBox(table).width, 74, accuracy: 0.01)
        XCTAssertGreaterThan(try innerBox(table).height, try innerBox(text).height * 2)
        assertBoxCoversInk(try typeset(table), table)
        let nested = "<mtable width=\"110px\" columnwidth=\"fit\"><mtr><mtd>" + table + "</mtd></mtr></mtable>"
        XCTAssertEqual(try layout(nested, 100).width, 100, accuracy: 0.01)
        assertBoxCoversInk(try layout(nested, 100), nested)
        let forced = "<mtable equalcolumns=\"true\" columnwidth=\"40px\" columnspacing=\"4px\"><mtr><mtd><mi>a</mi><mspace linebreak=\"newline\"/><mi>b</mi></mtd>" + cell(20) + "</mtr></mtable>"
        XCTAssertEqual(try innerBox(forced).width, 84, accuracy: 0.01)
        assertBoxCoversInk(try layout(forced, 84), forced)
    }

    func testOverlapLabelsReserveNoGutterAndKeepDrawingInsideReportedBounds() throws {
        for direction in ["ltr", "rtl"] {
            for side in ["leftoverlap", "rightoverlap"] {
                for alignment in ["top", "baseline"] {
                    let body = "<mtable dir=\"\(direction)\" side=\"\(side)\" minlabelspacing=\"3px\" rowalign=\"\(alignment)\" columnspacing=\"0\"><mlabeledtr>"
                        + cell(6, color: "blue", attributes: "columnspan=\"4\"") + cell(40) + "</mlabeledtr></mtable>"
                    let box = try innerBox(body), found = try inks(body)
                    let red = try XCTUnwrap(found[.red]), label = try XCTUnwrap(found[.blue])
                    XCTAssertEqual(box.width, 40, accuracy: 0.01)
                    XCTAssertEqual(label.minX, side == "leftoverlap" ? 0 : 34, accuracy: 0.6)
                    if alignment == "top" { XCTAssertGreaterThan(label.minY, red.maxY + 2) }
                    else { XCTAssertLessThan(label.maxY, red.minY - 2) }
                    assertBoxCoversInk(try layout(body, 40), body)
                }
            }
        }
        let wide = "<mtable side=\"rightoverlap\" columnspacing=\"0\"><mlabeledtr>" + cell(80, color: "blue") + cell(40) + "</mlabeledtr></mtable>"
        let layout = try layout(wide, 1)
        XCTAssertEqual(layout.width, 80, accuracy: 0.01)
        XCTAssertEqual(layout.widestUnbreakableWidth, 80, accuracy: 0.01)
        assertBoxCoversInk(layout, wide)
    }

    func testAuthoredTableWidthAndColumnPercentagesExcludeIndependentLabelGutter() throws {
        let body = "<mtable width=\"100px\" columnwidth=\"50% fit\" side=\"left\" columnspacing=\"0\" minlabelspacing=\"3px\" columnalign=\"left\"><mlabeledtr>"
            + cell(6, color: "black") + cell(10) + cell(10, color: "blue") + "</mlabeledtr></mtable>"
        let found = try inks(body)
        XCTAssertEqual(try innerBox(body).width, 109, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(found[.red]).minX, 9, accuracy: 0.6)
        XCTAssertEqual(try XCTUnwrap(found[.blue]).minX, 59, accuracy: 0.6)
        XCTAssertEqual(try layout(body, 100).width, 100, accuracy: 0.01)
        assertBoxCoversInk(try layout(body, 100), body)
    }

    func testOversubscribedAndMalformedSizingStayBoundedAndRepeatable() throws {
        for values in ["80% 80%", "100000000% fit", "-20px nonsense", "1width auto", "nanpx inf%"] {
            let body = "<mtable width=\"100px\" columnwidth=\"\(values)\" columnspacing=\"4px\" equalrows=\"true\"><mtr>" + cell(20) + cell(20) + "</mtr></mtable>"
            let first = try layout(body, 100), second = try layout(body, 100)
            XCTAssertLessThanOrEqual(first.width, 100.01)
            XCTAssertEqual(first.width, second.width, accuracy: 0.001)
            XCTAssertEqual(height(first), height(second), accuracy: 0.001)
            assertBoxCoversInk(first, body)
        }
    }

    func testSizedGroupedColumnsKeepSharedMarkGeometryInBothDirections() throws {
        for direction in ["ltr", "rtl"] {
            let first = cell(10) + "<malignmark/>" + cell(20, color: "blue")
            let second = cell(30, color: "lime") + "<malignmark/>" + cell(10, color: "black")
            // Use the coloured struts themselves as group children, rather than nested cells.
            let a = first.replacingOccurrences(of: "<mtd >", with: "").replacingOccurrences(of: "</mtd>", with: "")
            let b = second.replacingOccurrences(of: "<mtd >", with: "").replacingOccurrences(of: "</mtd>", with: "")
            let body = "<mtable dir=\"\(direction)\" columnwidth=\"70px\" columnspacing=\"0\"><mtr><mtd><maligngroup/>" + a
                + "</mtd></mtr><mtr><mtd><maligngroup/>" + b + "</mtd></mtr></mtable>"
            let found = try inks(body)
            let red = try XCTUnwrap(found[.red]), green = try XCTUnwrap(found[.green]), blue = try XCTUnwrap(found[.blue])
            XCTAssertEqual(try innerBox(body).width, 70, accuracy: 0.01)
            if direction == "ltr" {
                XCTAssertEqual(red.maxX, 40, accuracy: 0.6)
                XCTAssertEqual(green.maxX, red.maxX, accuracy: 0.6)
                XCTAssertEqual(blue.minX, red.maxX, accuracy: 0.6)
            } else {
                XCTAssertEqual(red.minX, green.minX, accuracy: 0.6)
                XCTAssertEqual(blue.maxX, red.minX, accuracy: 0.6)
            }
            let narrow = try layout(body, 1)
            XCTAssertEqual(narrow.widestUnbreakableWidth, 70, accuracy: 0.01)
            assertBoxCoversInk(narrow, body)
        }
    }

    func testEqualTracksWithCombinedSpansFramesAndRulesKeepExactWidth() throws {
        for direction in ["ltr", "rtl"] {
            let body = "<mtable dir=\"\(direction)\" width=\"160px\" equalcolumns=\"true\" equalrows=\"true\" frame=\"solid\" framespacing=\"2px 2px\" rowlines=\"solid\" columnlines=\"dashed\" columnspacing=\"4px\" rowspacing=\"5px\"><mtr>"
                + cell(90, 10, 40, attributes: "rowspan=\"2\" columnspan=\"2\"") + cell(10, color: "blue")
                + "</mtr><mtr>" + cell(10, color: "lime") + "</mtr></mtable>"
            let first = try layout(body, 160), again = try layout(body, 160)
            XCTAssertEqual(first.width, 160, accuracy: 0.01)
            XCTAssertEqual(first.width, again.width, accuracy: 0.01)
            XCTAssertEqual(height(first), height(again), accuracy: 0.01)
            let minimum = try layout(body, 1)
            XCTAssertLessThanOrEqual(try layout(body, minimum.widestUnbreakableWidth).width,
                                     minimum.widestUnbreakableWidth + 0.01)
            assertBoxCoversInk(first, body)
            assertBoxCoversInk(minimum, body)
        }
        XCTAssertEqual(try innerBox("<mtable width=\"100px\"/>").width, 100, accuracy: 0.01)
    }

    func testAuthoredSizingRetainsOccupancyAndStretchWorkLimits() throws {
        let huge = "<mtable equalcolumns=\"true\" width=\"100%\"><mtr>" + cell(1, attributes: "columnspan=\"20001\"") + "</mtr></mtable>"
        XCTAssertThrowsError(try layout(huge, 100)) { error in
            guard case MathLayoutError.limitExceeded = error else { return XCTFail("unexpected \(error)") }
        }
        let many = "<mtable columnwidth=\"fit\"><mtr>" + String(repeating: "<mtd><mo>(</mo></mtd>", count: 500) + "</mtr></mtable>"
        XCTAssertThrowsError(try layout(many, 100)) { error in
            guard case MathLayoutError.limitExceeded = error else { return XCTFail("unexpected \(error)") }
        }
    }
}
