import CoreGraphics
@testable import MathMLLayout
import XCTest

final class NegativeSpaceRegressionTests: MathTestCase {
    func testNonmonotonicInkDoesNotReduceEarlierRowsToSingleTerms() throws {
        let term = "<mi>x</mi>", plus = "<mo>+</mo>"
        let terms = [String](repeating: term, count: 220)
        let plain = terms.joined(separator: plus)
        let style = MathStyle(fontSize: 20, color: black)
        let limit: CGFloat = 3000
        let reference = try MathLayout(node(plain), style: style, maximumWidth: limit)
        // A normal row holds more than the 48 endpoints considered by the candidate window.
        let windowWidth = try layout(terms.prefix(Paragraph.window).joined(separator: plus)).width
        XCTAssertGreaterThan(reference.rows[0].width, windowWidth)
        for distance in [-10000, 10000] {
            var shifted = terms
            shifted[20] += "<mspace width=\"\(distance)px\"/><mi>z</mi><mspace width=\"\(-distance)px\"/>"
            let result = try MathLayout(node(shifted.joined(separator: plus)), style: style, maximumWidth: limit)
            // The excursion cannot share a row with a neighbour. Force just those necessary
            // breaks to make a reference whose search cannot skip the fitting earlier prefix.
            let forcedPlus = "<mo linebreak=\"newline\">+</mo>"
            let forcedBody = shifted.prefix(20).joined(separator: plus) + forcedPlus + shifted[20]
                + forcedPlus + shifted.dropFirst(21).joined(separator: plus)
            let forced = try MathLayout(node(forcedBody), style: style, maximumWidth: limit)
            XCTAssertEqual(result.rows.count, 5, "distance \(distance)")
            XCTAssertEqual(result.rows.count, forced.rows.count)
            for (row, expected) in zip(result.rows, forced.rows) {
                XCTAssertEqual(row.width, expected.width, accuracy: 0.001, "distance \(distance)")
            }
            XCTAssertEqual(result.rows.filter { $0.width > limit }.count, 1)
            for row in result.rows where row.width <= limit {
                XCTAssertLessThanOrEqual(row.origin.x + row.width, limit + 0.001)
            }
            XCTAssertEqual(result.widestUnbreakableWidth, result.rows[1].width, accuracy: 0.001)
        }
    }
}
