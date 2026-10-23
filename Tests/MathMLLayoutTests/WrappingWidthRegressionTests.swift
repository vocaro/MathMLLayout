import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

final class WrappingWidthRegressionTests: MathTestCase {
    func testReportedWidthFitsKnownFailingSeeds() {
        for seed: UInt64 in [10154, 10910, 65766, 28706, 52442, 63] {
            for failure in LineBreakingFuzzTests.failures(seed: seed, shrinks: false) { XCTFail(failure) }
        }
    }

    func testMinimumForcedPartStillValidatesItsReportedWidth() throws {
        let xml = """
            <math linebreakmultchar='∑'><mo>+</mo><mo>)</mo>
            <mstyle indentshift='2 em'><mfrac><mn/><mfenced close='|'>
            <mspace linebreak='newline'/><mo>⁢</mo><ms>s</ms></mfenced></mfrac><mo>∫</mo></mstyle>
            <mo>+</mo><mi>alpha</mi></math>
            """
        let root = try MathMLNode.parse(xml: Data(xml.utf8))
        let style = MathStyle(fontSize: 9, color: black, isDisplay: true)
        // The forced fraction part is already at its minimum, but its measured row widths change
        // when this formula is laid out at the first reported width (fuzzer seed 52442).
        let narrow = try MathLayout(root, style: style, maximumWidth: 46)
        let exact = try MathLayout(root, style: style, maximumWidth: narrow.widestUnbreakableWidth)
        for row in exact.rows {
            XCTAssertLessThanOrEqual(row.origin.x + row.width, narrow.widestUnbreakableWidth + 0.001)
        }
    }

    func testReportedWidthAlsoRespectsHeightBounds() throws {
        let root = try node("<mstyle lineleading='99999999999999999999999999999999999999999999'><mtext>one two three</mtext></mstyle>")
        let style = MathStyle(fontSize: 40, color: black)
        let inputs = [try MathLayout(root, style: style),
                      try MathLayout(root, style: style, maximumWidth: .infinity),
                      try MathLayout(root, style: style, maximumWidth: 0, firstRowMaximumWidth: .infinity)]
        for unbroken in inputs {
            XCTAssertEqual(unbroken.rows.count, 1)
            let exact = try MathLayout(root, style: style, maximumWidth: unbroken.widestUnbreakableWidth)
            XCTAssertEqual(exact.rows.count, 1)
            XCTAssertLessThanOrEqual(exact.width, unbroken.widestUnbreakableWidth + 0.001)
        }
    }

    func testEnclosureWithNegativeSpacingFitsItsReportedWidth() throws {
        for notation in ["box", "updiagonalarrow"] {
            for trailing in ["<mi>y</mi>", ""] {
                let root = try node("""
                    <mtext>\n a\t😀 😀 principal 😀 principal</mtext><mo>⁡</mo><mi>s</mi>
                    <mo>+</mo><mi>x</mi><mo rspace='-50%'>!</mo>
                    <menclose notation='\(notation)'><mtext>é数学￼over-long-hyphenated-word</mtext>
                    <mo rspace='-5'>=</mo>\(trailing)</menclose>
                    """)
                let style = MathStyle(fontSize: 2000, color: black)
                let initial = try MathLayout(root, style: style, maximumWidth: 1726)
                let width = initial.widestUnbreakableWidth
                let exact = try MathLayout(root, style: style, maximumWidth: width)
                for row in exact.rows {
                    XCTAssertLessThanOrEqual(row.origin.x + row.width, width + 0.01, "\(notation) \(trailing)")
                }
            }
        }
    }

    func testManyWrappingNeighborsKeepRetriesBounded() throws {
        let sum = (1...12).map { "<mi>term\($0)</mi>" }.joined(separator: "<mo>+</mo>")
        let radical = "<msqrt>\(sum)</msqrt>"
        let style = MathStyle(fontSize: 20, color: black)
        for count in [16, 64] {
            let root = try node(String(repeating: radical, count: count))
            let tiny = try LayoutEngine.lines(root, style: style, maximumWidth: 0, firstRowMaximumWidth: nil)
            XCTAssertLessThanOrEqual(tiny.layoutPasses, LayoutEngine.maximumWrappingPasses)
            let exact = try LayoutEngine.lines(root, style: style, maximumWidth: tiny.widestUnbreakable, firstRowMaximumWidth: nil)
            XCTAssertLessThanOrEqual(exact.layoutPasses, LayoutEngine.maximumWrappingPasses)
            for row in exact.rows {
                XCTAssertLessThanOrEqual(row.origin.x + row.box.width, tiny.widestUnbreakable + 0.01)
            }
        }
    }

    func testFittingInputIsAnUpperBoundOnReportedMinimum() throws {
        let sum = (1...7).map { "<mi>term\($0)</mi>" }.joined(separator: "<mo>+</mo>")
        let style = MathStyle(fontSize: 20, color: black)
        for notation in ["radical", "circle", "updiagonalarrow"] {
            for count in [1, 2, 3] {
                let content = String(repeating: "<menclose notation='\(notation)'>\(sum)</menclose>", count: count)
                for padding in ["", "lspace='-2height'", "width='2height'"] {
                    let root = try node("<mpadded \(padding)>\(content)</mpadded>")
                    let natural = try MathLayout(root, style: style).width
                    for share in [0.15, 0.3, 0.5, 0.75, 1] as [CGFloat] {
                        let width = natural * share
                        let result = try MathLayout(root, style: style, maximumWidth: width)
                        if result.rows.allSatisfy({ $0.origin.x + $0.width <= width + 0.001 }) {
                            XCTAssertLessThanOrEqual(result.widestUnbreakableWidth, width + 0.001,
                                                     "\(notation), \(count), \(padding), \(share)")
                        }
                    }
                }
            }
        }
    }
}
