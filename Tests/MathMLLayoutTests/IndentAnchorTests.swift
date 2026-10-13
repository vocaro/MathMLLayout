import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

/// Coordinate examples for MathML 3 §3.2.5.2.3. Fixed-size rectangles make the expected
/// coordinates independent of the renderer's operator spacing and glyph metrics.
final class IndentAnchorTests: MathTestCase {
    private func lines(_ body: String, direction: String = "ltr", width: CGFloat = 100,
                       first: CGFloat? = nil, display: Bool = false) throws -> MathLayout {
        let root = try MathMLNode.parse(xml: Data("<math dir='\(direction)' display='\(display ? "block" : "inline")'>\(body)</math>".utf8))
        return try MathLayout(root, style: MathStyle(fontSize: 20, color: black), maximumWidth: width,
                              firstRowMaximumWidth: first)
    }

    private let continuation = "<mspace linebreak='newline' indentalign='id' indenttarget='target'/>"
        + "<mspace width='5px' height='4px' mathbackground='lime'/>"

    func testOppositeDirectionWrappedTargetsUseFinalPhysicalFirstLineAlignment() throws {
        for direction in ["ltr", "rtl"] {
            let inner = direction == "ltr" ? "rtl" : "ltr"
            for (align, offset) in [("left", CGFloat(0)), ("center", 5), ("right", 10)] {
                let body = "<mstyle indentalignfirst='right'><mspace width='20px'/>"
                    + "<mrow dir='\(inner)'><mstyle indentalignfirst='\(align)'>"
                    + "<mspace width='3px'/><mspace id='target' width='7px' height='4px' mathbackground='red'/>"
                    + "<mspace linebreak='newline'/><mspace width='20px' height='4px'/>"
                    + "</mstyle></mrow></mstyle>" + continuation
                let result = try lines(body, direction: direction, first: 80)
                XCTAssertEqual(result.rows.count, 2)
                // The outer 40-point first line starts at 40 in its 80-point budget.
                // Its nested 10-point first line aligns within the nested 20-point frame.
                let expected = 40 + offset + (direction == "ltr" ? 20 : 3)
                XCTAssertEqual(result.rows[1].origin.x, expected, accuracy: 0.001, "\(direction), \(align)")
                let rendering = Rendering(result)
                XCTAssertEqual(try XCTUnwrap(rendering.bounds(.red)).minX, expected, accuracy: 0.25)
                XCTAssertEqual(try XCTUnwrap(rendering.bounds(.green)).minX, expected, accuracy: 0.25)
                assertBoxCoversInk(result, body, rendering: rendering)
            }
        }
    }

    func testLaterNestedBaselineIsStillBeforeTheFollowingHostOutputLine() throws {
        let body = "<mspace width='20px'/><mrow dir='rtl'>"
            + "<mspace width='20px' height='4px'/><mspace linebreak='newline' indentshiftlast='6px'/>"
            + "<mspace width='3px'/><mspace id='target' width='7px' height='4px' mathbackground='red'/>"
            + "</mrow>" + continuation
        let result = try lines(body)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows[1].origin.x, 26, accuracy: 0.001)
        let rendering = Rendering(result)
        let target = try XCTUnwrap(rendering.bounds(.red)), below = try XCTUnwrap(rendering.bounds(.green))
        XCTAssertGreaterThan(target.minY, below.maxY)
        XCTAssertEqual(target.minX, 26, accuracy: 0.25)
        XCTAssertEqual(below.minX, 26, accuracy: 0.25)
    }

    func testUnselectedAndDuplicateWrappedTargetsFallBackToAuto() throws {
        let wrapped = "<mrow dir='rtl'><mspace width='20px'/><mspace linebreak='newline'/>"
            + "<mspace id='target' width='7px' height='4px'/></mrow>"
        for body in [
            "<maction selection='1'><mspace width='20px'/>\(wrapped)</maction>" + continuation,
            wrapped + continuation + "<mspace id='target' width='3px'/>",
            "<mspace width='20px'/>" + continuation + wrapped,
        ] {
            let result = try lines(body, display: true)
            XCTAssertEqual(result.rows[1].origin.x, 20, accuracy: 0.001)
        }
    }

    func testAutomaticIndependentTextWrappingExportsFinalAnchor() throws {
        let nested = "<mrow dir='rtl'><mtext>one two three four five six seven eight nine ten</mtext>"
            + "<mspace id='target' width='7px' height='4px' mathbackground='red'/></mrow>"
        let body = "<mspace width='12px'/>" + nested + continuation
        let result = try lines(body, width: 100)
        XCTAssertEqual(result.rows.count, 2)
        // The final source item in the internally RTL row is at its physical left edge.
        // It remains attached to the last text line, even though the text wrapped earlier.
        XCTAssertEqual(result.rows[1].origin.x, 12, accuracy: 0.001)
        let rendering = Rendering(result)
        XCTAssertEqual(try XCTUnwrap(rendering.bounds(.red)).minX, 12, accuracy: 0.25)
        XCTAssertEqual(try XCTUnwrap(rendering.bounds(.green)).minX, 12, accuracy: 0.25)
        assertBoxCoversInk(result, body, rendering: rendering)
    }

    func testEarlierSourceTargetBelowReceivingBaselineFallsBackToAuto() throws {
        let body = "<mspace width='9px'/><mpadded height='0px' depth='0px' voffset='-100px'>"
            + "<mspace id='target' width='7px'/></mpadded>" + continuation
        let result = try lines(body, display: true)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertGreaterThan(result.rows[1].origin.y, -100)
        // Source order says this target came first; its deliberately displaced final baseline
        // is below the receiving row, so its 9-point horizontal coordinate is inadmissible.
        XCTAssertEqual(result.rows[1].origin.x, 20, accuracy: 0.001)
    }

    func testRebuiltPaddingWrapperIDKeepsWrapperOriginInsteadOfChildOffset() throws {
        let body = "<mspace width='9px'/><mpadded id='target' width='+4px' lspace='0.5width'>"
            + "<mspace width='10px' height='4px' mathbackground='red'/><mspace linebreak='newline'/>"
            + "<mspace width='30px' height='4px'/></mpadded>" + continuation
        let result = try lines(body)
        XCTAssertEqual(result.rows.count, 3)
        // First-fragment padding is half of 10, so the child starts at 9 + 5. The
        // referenced wrapper starts at 9 regardless of its changing fragment padding.
        XCTAssertEqual(try XCTUnwrap(Rendering(result).bounds(.red)).minX, 14, accuracy: 0.25)
        XCTAssertEqual(result.rows[2].origin.x, 9, accuracy: 0.001)
    }

    func testRetainedMetadataTranslationsAndTraversalStayBoundedForWideRows() {
        var box = MathBox()
        for index in 0..<20_000 {
            var child = MathBox()
            child.retainIndentAnchor("t\(index)", at: CGPoint(x: -2, y: -3))
            box.add(child, at: CGPoint(x: CGFloat(index), y: 4))
        }
        var count = 0
        box.indentAnchors?.forEach { id, point in
            XCTAssertEqual(id, "t\(count)")
            XCTAssertEqual(point, CGPoint(x: CGFloat(count) - 2, y: 1))
            count += 1
        }
        XCTAssertEqual(count, 20_000)
    }
}
