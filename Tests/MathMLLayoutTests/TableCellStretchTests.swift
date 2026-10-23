import CoreGraphics
@testable import MathMLLayout
import XCTest

final class TableCellStretchTests: XCTestCase {
    private func blue(_ body: String) throws -> CGRect { try XCTUnwrap(try inks(body)[.blue]) }
    private func arrow(_ attributes: String = "") -> String {
        "<mo mathcolor=\"blue\" \(attributes)>→</mo>"
    }

    func testWholeCellVerticalOperatorCoversTallRowNeighbor() throws {
        let body = "<mtable><mtr><mtd><mo mathcolor=\"blue\" symmetric=\"false\">(</mo></mtd>"
            + "<mtd><mspace height=\"60px\" depth=\"20px\" width=\"10px\"/></mtd></mtr></mtable>"
        XCTAssertGreaterThan(try blue(body).height, 70)
        assertBoxCoversInk(try typeset(body), body)
    }

    func testWholeCellHorizontalOperatorCoversColumnNeighbor() throws {
        let body = "<mtable><mtr><mtd>\(arrow())</mtd></mtr>"
            + "<mtr><mtd><mspace width=\"120px\"/></mtd></mtr></mtable>"
        XCTAssertGreaterThan(try blue(body).width, 115)
        assertBoxCoversInk(try typeset(body), body)
    }

    func testEmbellishedArrowKeepsExternalStretchWithItsLabel() throws {
        let body = "<mtable><mtr><mtd><munder>\(arrow())<mi>x</mi></munder></mtd></mtr>"
            + "<mtr><mtd><mspace width=\"120px\"/></mtd></mtr></mtable>"
        XCTAssertGreaterThan(try blue(body).width, 115)
    }

    func testDisabledStretchAndMaximumSizeAreHonored() throws {
        for attributes in ["stretchy=\"false\"", "maxsize=\"100%\""] {
            let body = "<mtable><mtr><mtd>\(arrow(attributes))</mtd></mtr>"
                + "<mtr><mtd><mspace width=\"120px\"/></mtd></mtr></mtable>"
            XCTAssertLessThan(try blue(body).width, 40)
        }
    }

    func testMultipleDirectCellExpressionsAreNotWholeCellOperators() throws {
        let body = "<mtable><mtr><mtd>\(arrow())<mi>x</mi></mtd></mtr>"
            + "<mtr><mtd><mspace width=\"120px\"/></mtd></mtr></mtable>"
        XCTAssertLessThan(try blue(body).width, 40)
    }

    func testCrossingColumnSpanDoesNotStretchAnArrow() throws {
        let body = "<mtable><mtr><mtd>\(arrow())</mtd><mtd><mi>x</mi></mtd></mtr>"
            + "<mtr><mtd columnspan=\"2\"><mspace width=\"120px\"/></mtd></mtr></mtable>"
        XCTAssertLessThan(try blue(body).width, 40)
    }

    func testCrossingRowSpanDoesNotStretchAFence() throws {
        let body = "<mtable><mtr><mtd><mo mathcolor=\"blue\">(</mo></mtd>"
            + "<mtd rowspan=\"2\"><mspace height=\"60px\" depth=\"20px\"/></mtd></mtr><mtr/></mtable>"
        XCTAssertLessThan(try blue(body).height, 40)
    }

    func testVerticalSpanCoversContainedRowsAndTheirGap() throws {
        let body = "<mtable rowspacing=\"10px\"><mtr><mtd rowspan=\"2\"><mo mathcolor=\"blue\" symmetric=\"false\">(</mo></mtd>"
            + "<mtd><mspace height=\"30px\" depth=\"5px\"/></mtd></mtr>"
            + "<mtr><mtd><mspace height=\"30px\" depth=\"5px\"/></mtd></mtr></mtable>"
        XCTAssertGreaterThan(try blue(body).height, 70)
        assertBoxCoversInk(try typeset(body), body)
    }

    func testWholeCellMinimumWidthUsesTheCoreNormalWidth() throws {
        let body = "<mtable><mtr><mtd>\(arrow("minsize=\"4\""))</mtd></mtr>"
            + "<mtr><mtd><mi>x</mi></mtd></mtr></mtable>"
        XCTAssertGreaterThan(try blue(body).width, 60)
    }

    func testLoneCellHorizontalOperatorHonorsMinimumSize() throws {
        XCTAssertGreaterThan(try blue("<mtable><mtr><mtd>\(arrow("minsize=\"4\""))</mtd></mtr></mtable>").width, 60)
    }

    func testAllStretchyRowTargetsNormalSizesBeforeMinimumBounds() throws {
        let body = "<mtable><mtr><mtd><mo mathcolor=\"blue\">(</mo></mtd>"
            + "<mtd><mo minsize=\"80px\">|</mo></mtd></mtr></mtable>"
        XCTAssertLessThan(try blue(body).height, 40,
                          "another operator's author minimum must not become this operator's target")
    }

    func testTopAlignedCellDoesNotApplySymmetricStretching() throws {
        let body = "<mtable rowalign=\"top\"><mtr><mtd><mo mathcolor=\"blue\" symmetric=\"true\">(</mo></mtd>"
            + "<mtd><mspace height=\"60px\"/></mtd></mtr></mtable>"
        XCTAssertGreaterThan(try blue(body).height, 50)
        XCTAssertLessThan(try blue(body).height, 80)
    }

    func testLoneHorizontalOperatorFillsAuthoredColumnWidth() throws {
        let body = "<mtable columnwidth=\"100px\"><mtr><mtd>\(arrow())</mtd></mtr></mtable>"
        XCTAssertGreaterThan(try blue(body).width, 95)
    }

    func testStretchRebuildKeepsLocallyScopedMarksInsideTable() throws {
        let table = try mathML("<mtable columnwidth='100px'><mtr><mtd><mo>→<malignmark/></mo></mtd></mtr></mtable>").children[0]
        let engine = LayoutEngine(fontName: nil)
        var context = LayoutContext(fontSize: em, unclampedSize: em, minSize: 8, display: false, color: black)
        context.trackAlignment = true
        let box = try engine.layout(table, context, depth: 0)
        XCTAssertFalse(box.alignment.contains { if case .mark = $0.kind { return true }; return false })
    }

    func testUnscopedStretchedOperatorsKeepUniqueSourceMarkPriorities() throws {
        let table = try mathML("<mtable alignmentscope='false' columnwidth='100px'>"
            + "<mtr><mtd><mo>→<malignmark/></mo></mtd></mtr>"
            + "<mtr><mtd><mo>→<malignmark/></mo></mtd></mtr></mtable>").children[0]
        let engine = LayoutEngine(fontName: nil)
        var context = LayoutContext(fontSize: em, unclampedSize: em, minSize: 8, display: false, color: black)
        context.trackAlignment = true
        let box = try engine.layout(table, context, depth: 0)
        let marks = box.alignment.filter { if case .mark = $0.kind { return true }; return false }
        XCTAssertEqual(marks.count, 2)
        guard marks.count == 2 else { return }
        XCTAssertLessThan(marks[0].order, marks[1].order)
    }

    func testVerticalStretchPreservesSharedGroupAlignmentAndReservedWidth() throws {
        let body = "<mtable groupalign='{right}' columnspacing='0'><mtr>"
            + "<mtd><mrow><maligngroup/><mo mathcolor='blue'>(<malignmark edge='right'/></mo></mrow></mtd>"
            + "<mtd><mspace width='10px' height='60px'/></mtd></mtr><mtr>"
            + "<mtd><mrow><maligngroup/><mspace width='80px' height='10px' mathbackground='red'/></mrow></mtd>"
            + "<mtd/></mtr></mtable>"
        let found = try inks(body), fence = try XCTUnwrap(found[.blue]), reference = try XCTUnwrap(found[.red])
        XCTAssertGreaterThan(fence.height, 50)
        XCTAssertEqual(fence.maxX, reference.maxX, accuracy: 0.75)
        XCTAssertEqual(try innerBox(body).width, 90, accuracy: 0.01)
    }
}
