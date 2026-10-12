import Foundation
@testable import MathMLLayout
import XCTest

final class SpeechBoundsRegressionTests: XCTestCase {
    private let base = MathMLNode(name: "mi", text: "x")

    private func multiscripts(skipped name: String, count: Int) -> MathMLNode {
        MathMLNode(name: "mmultiscripts", children: [base] + Array(repeating: MathMLNode(name: name), count: count))
    }

    /// Silent script placeholders still consume the node budget, including a shared child list
    /// visited under many parents. No elapsed-time threshold is needed to detect the missing count.
    func testSilentMultiscriptChildrenCountTowardSpeechBound() {
        for name in ["none", "mprescripts"] {
            let parent = multiscripts(skipped: name, count: 10_000)
            let root = MathMLNode(name: "math", children: Array(repeating: parent, count: 9_000))
            XCTAssertEqual(root.accessibilityDescription.split(separator: " ").count, 2, name)
            for language in MathReading.languages {
                XCTAssertEqual(root.accessibilityDescription(locale: Locale(identifier: language)).text.split(separator: " ").count, 2, "\(name), \(language)")
            }
        }
    }

    func testMultiscriptSpeechIncludesLastAllowedNode() {
        for name in ["none", "mprescripts"] {
            // math, mmultiscripts, base, placeholders, then the last allowed token.
            let parent = multiscripts(skipped: name, count: MathLimits.nodes - 4)
            let root = MathMLNode(name: "math", children: [parent, MathMLNode(name: "mi", text: "last"), MathMLNode(name: "mi", text: "past")])
            XCTAssertEqual(root.accessibilityDescription, "x last", name)
        }
    }

    func testSilentMultiscriptChildrenCountTowardLayoutBound() throws {
        let style = MathStyle(fontSize: 1, color: black)
        for name in ["none", "mprescripts"] {
            // A multiscripts and its base consume two nodes; an even number of none children
            // forms complete pairs, so the first case is valid and exactly at the bound.
            _ = try MathLayout(multiscripts(skipped: name, count: MathLimits.nodes - 2), style: style)
            XCTAssertThrowsError(try MathLayout(multiscripts(skipped: name, count: MathLimits.nodes), style: style)) {
                XCTAssertEqual($0 as? MathLayoutError, .limitExceeded, name)
            }
        }
    }

    func testSharedSilentMultiscriptChildrenCountOnEveryLayoutVisit() {
        for name in ["none", "mprescripts"] {
            let parent = multiscripts(skipped: name, count: 10_000)
            let root = MathMLNode(name: "math", children: [parent, parent])
            XCTAssertThrowsError(try MathLayout(root, style: MathStyle(fontSize: 1, color: black))) {
                XCTAssertEqual($0 as? MathLayoutError, .limitExceeded, name)
            }
        }
    }

    func testIncompletePairsDiscardedByPrescriptsCountTowardLayoutBound() throws {
        let pair = [MathMLNode(name: "mi", text: "discarded"), MathMLNode(name: "mprescripts")]
        func root(_ pairs: Int) -> MathMLNode {
            MathMLNode(name: "mmultiscripts", children: [base] + Array(repeating: pair, count: pairs).flatMap { $0 })
        }
        let style = MathStyle(fontSize: 1, color: black)
        _ = try MathLayout(root((MathLimits.nodes - 2) / 2), style: style)
        XCTAssertThrowsError(try MathLayout(root(MathLimits.nodes / 2), style: style)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
    }
}
