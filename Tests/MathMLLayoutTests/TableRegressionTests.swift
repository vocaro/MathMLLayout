import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

final class TableRegressionTests: XCTestCase {
    func testFramesAreOmittedWhenEitherDimensionCannotHoldTheirRule() throws {
        let stroke = constant(\.fractionRuleThickness)
        for frame in ["solid", "dashed"] {
            for (width, height) in [(CGFloat(0), CGFloat(0)), (stroke / 2, stroke / 2),
                                    (stroke / 2, stroke * 2), (stroke * 2, stroke / 2)] {
                for content in ["", "<mtr><mtd><mspace width=\"\(width)px\" height=\"\(height)px\"/></mtd></mtr>"] {
                    let body = "<mtable frame=\"\(frame)\" framespacing=\"0 0\">\(content)</mtable>"
                    let box = try innerBox(body)
                    XCTAssertNil(box.inkBounds, body)
                    XCTAssertNil(Rendering(try typeset(body)).bounds(), body)
                    XCTAssertEqual(box.width, content.isEmpty ? 0 : width, accuracy: 0.001, body)
                    XCTAssertEqual(box.height, content.isEmpty ? 0 : height, accuracy: 0.001, body)
                }
            }
        }
    }

    func testSmallFramesWithRoomKeepTheirStrokesInsideTheBox() throws {
        let stroke = constant(\.fractionRuleThickness), size = stroke * 2
        for frame in ["solid", "dashed"] {
            let body = "<mtable frame=\"\(frame)\" framespacing=\"0 0\"><mtr><mtd><mspace width=\"\(size)px\" height=\"\(size)px\"/></mtd></mtr></mtable>"
            let box = try innerBox(body)
            let ink = try XCTUnwrap(box.inkBounds, body)
            XCTAssertEqual(ink.minX, 0, accuracy: 0.001, body)
            XCTAssertEqual(ink.maxX, box.width, accuracy: 0.001, body)
            XCTAssertEqual(ink.minY, -box.descent, accuracy: 0.001, body)
            XCTAssertEqual(ink.maxY, box.ascent, accuracy: 0.001, body)
            let rendering = Rendering(try typeset(body), scale: 16)
            XCTAssertNotNil(rendering.bounds(), body)
            assertBoxCoversInk(rendering.layout, body, tolerance: 0.1, rendering: rendering)
        }
    }

    func testBareRowsInheritRelativeStyleOnceLikeRowsInTables() throws {
        for name in ["mtr", "mlabeledtr"] {
            for attributes in ["scriptlevel=\"+1\"", "scriptlevel=\"-1\"", "mathsize=\"150%\"",
                               "mathsize=\"0.5em\"", "mathsize=\"big\"", "fontsize=\"150%\"",
                               "scriptlevel=\"+1\" mathsize=\"150%\"", "scriptlevel=\"1\"", "mathsize=\"30px\""] {
                let label = name == "mlabeledtr" ? "<mtd><mspace width=\"2em\" height=\"1em\" mathbackground=\"red\"/></mtd>" : ""
                let row = "<\(name) \(attributes)>\(label)<mtd><mspace width=\"1em\" height=\"1em\" depth=\"0.5em\" mathbackground=\"blue\"/></mtd></\(name)>"
                for outer in ["", "scriptlevel=\"2\" scriptminsize=\"1px\"", "mathsize=\"30px\""] {
                    for display in [false, true] {
                        let bare = try innerBox("<mstyle \(outer)>\(row)</mstyle>", display: display)
                        let table = try innerBox("<mstyle \(outer)><mtable>\(row)</mtable></mstyle>", display: display)
                        let message = "\(name): \(attributes), outer \(outer), display \(display)"
                        XCTAssertEqual(bare.width, table.width, accuracy: 0.001, message)
                        XCTAssertEqual(bare.ascent, table.ascent, accuracy: 0.001, message)
                        XCTAssertEqual(bare.descent, table.descent, accuracy: 0.001, message)
                        XCTAssertEqual(bare.inkBounds, table.inkBounds, message)
                    }
                }
            }
        }
        // The em in a bare row increases or shrinks exactly once.
        XCTAssertEqual(try innerBox("<mtr scriptlevel=\"+1\"><mtd><mspace width=\"1em\"/></mtd></mtr>").width,
                       try innerBox("<mstyle scriptlevel=\"+1\"><mspace width=\"1em\"/></mstyle>").width, accuracy: 0.001)
        XCTAssertEqual(try innerBox("<mtr mathsize=\"150%\"><mtd><mspace width=\"1em\"/></mtd></mtr>").width, 1.5 * em, accuracy: 0.001)
    }
}
