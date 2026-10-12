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

    func testPositionalScriptIncludesLastAllowedNodeAndOmitsBoundedLabels() {
        for prescript in [false, true] {
            for superscript in [false, true] {
                // math, multiscripts, base, silent slots/marker, then last and past.
                let marker = prescript ? [MathMLNode(name: "mprescripts")] : []
                let slots = MathLimits.nodes - 4 - marker.count
                // Choose slot parity for the last token, adding one empty row outside
                // the multiscripts when necessary so the total budget stays identical.
                let extra = (slots % 2 == 1) == superscript ? 0 : 1
                let placeholders = Array(repeating: MathMLNode(name: "none"), count: slots - extra)
                let children = [base] + marker + placeholders + [MathMLNode(name: "mi", text: "last"), MathMLNode(name: "mi", text: "past")]
                let parent = MathMLNode(name: "mmultiscripts", children: children)
                let root = MathMLNode(name: "math", children: Array(repeating: MathMLNode(name: "mrow"), count: extra) + [parent])
                let side = prescript ? "left" : "right", kind = superscript ? "superscript" : "subscript"
                XCTAssertEqual(root.accessibilityDescription, "x \(side) \(kind) last")
                for language in MathReading.languages {
                    let text = root.accessibilityDescription(locale: Locale(identifier: language)).text
                    XCTAssertTrue(text.hasSuffix(" last"), language)
                    XCTAssertFalse(text.contains("past"), language)
                }
            }
        }
    }

    func testMultiscriptDepthBoundLeavesNoDanglingScriptLabels() {
        let token = MathMLNode(name: "mi", text: "last")
        for extra in [0, 1] {
            let script = (0..<(MathLimits.depth - 3 + extra)).reduce(token) { inner, _ in
                MathMLNode(name: "mrow", children: [inner])
            }
            let parent = MathMLNode(name: "mmultiscripts", children: [base, script, MathMLNode(name: "none")])
            let root = MathMLNode(name: "math", children: [parent])
            XCTAssertEqual(root.accessibilityDescription, extra == 0 ? "x right subscript last" : "x")
            for language in MathReading.languages {
                let text = root.accessibilityDescription(locale: Locale(identifier: language)).text
                if extra == 0 { XCTAssertTrue(text.hasSuffix(" last"), language) }
                else { XCTAssertEqual(text, "x", language) }
            }
        }
    }

    func testMultiscriptTextBoundCountsUTF16AndLeavesNoDanglingLabels() {
        for text in [String(repeating: "a", count: MathLimits.textLength - 1),
                     String(repeating: "𝑥", count: (MathLimits.textLength - 2) / 2)] {
            // The base spends one UTF-16 unit; the script fills or nearly fills the remaining budget.
            let script = MathMLNode(name: "mi", text: text)
            let parent = MathMLNode(name: "mmultiscripts", children: [base, script, MathMLNode(name: "mi", text: "past")])
            let root = MathMLNode(name: "math", children: [parent])
            XCTAssertEqual(root.accessibilityDescription, "x right subscript \(text)")
            for language in MathReading.languages {
                let reading = root.accessibilityDescription(locale: Locale(identifier: language)).text
                XCTAssertTrue(reading.hasSuffix(text), language)
                XCTAssertFalse(reading.contains("past"), language)
            }
        }
        let script = MathMLNode(name: "mi", text: String(repeating: "a", count: MathLimits.textLength))
        let parent = MathMLNode(name: "mmultiscripts", children: [base, script, MathMLNode(name: "mi", text: "past")])
        let root = MathMLNode(name: "math", children: [parent])
        for language in MathReading.languages {
            XCTAssertEqual(root.accessibilityDescription(locale: Locale(identifier: language)).text, "x", language)
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
