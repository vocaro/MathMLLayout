import Foundation
@testable import MathMLLayout
import XCTest

final class SpeechLocaleBoundsTests: XCTestCase {
    private let catalog = MathVocabularyCatalog(vocabularies: [FixtureVocabulary.self, FixtureRegion.self])

    func testCustomLanguageRegionAndFallbackRetainSourceBudgets() {
        let x = MathMLNode(name: "mi", text: "x")
        let deep = (0..<10_000).reduce(x) { inner, _ in MathMLNode(name: "mrow", children: [inner]) }
        let slots = Array(repeating: MathMLNode(name: "none"), count: MathLimits.nodes - 4)
        let scripts = MathMLNode(name: "mmultiscripts", children: [x] + slots)
        let last = MathMLNode(name: "mi", text: "last"), past = MathMLNode(name: "mi", text: "past")
        let bounded = MathMLNode(name: "math", children: [scripts, last, past])
        let oversize = MathMLNode(name: "mtext", text: String(repeating: "𝑥", count: MathLimits.textLength / 2 + 1))
        let exhausted = MathMLNode(name: "math", children: [oversize, past])
        for locale in ["qaa", "qaa-ZZ", "en-GB", "ja-JP"] {
            let custom = locale.hasPrefix("qaa")
            func read(_ node: MathMLNode) -> String { node.accessibilityDescription(locale: Locale(identifier: locale), vocabularies: catalog).text }
            XCTAssertEqual(read(deep), "", locale)
            XCTAssertEqual(read(bounded), custom ? "x|last" : "x last", locale)
            XCTAssertEqual(read(exhausted), "", locale)
        }
    }

    func testStackGroupsRetainCollectionDepthAndTextBudgets() {
        let one = MathMLNode(name: "mn", text: "1")
        let deep = (0..<10_000).reduce(one) { inner, _ in MathMLNode(name: "msgroup", children: [inner]) }
        let stack = MathMLNode(name: "mstack", children: [deep])
        let wide = MathMLNode(name: "mstack", children: Array(repeating: one, count: MathLimits.nodes + 10))
        let oversize = MathMLNode(name: "mn", text: String(repeating: "9", count: MathLimits.textLength + 1))
        let exhausted = MathMLNode(name: "mstack", children: [oversize, one])
        for locale in ["qaa", "qaa-ZZ", "en-GB", "ja-JP"] {
            func read(_ node: MathMLNode) -> String { node.accessibilityDescription(locale: Locale(identifier: locale), vocabularies: catalog).text }
            XCTAssertFalse(read(stack).contains("qa-digit-1"), locale)
            XCTAssertFalse(read(exhausted).contains("qa-digit-1"), locale)
            XCTAssertLessThan(read(wide).utf16.count, MathLimits.nodes * 100, locale)
        }
    }

    func testCustomCompositionOnSmallThreadStackRemainsBounded() {
        let deep = (0..<500).reduce(MathMLNode(name: "mi", text: "x")) { inner, _ in MathMLNode(name: "msqrt", children: [inner]) }
        let catalog = catalog
        for locale in ["qaa", "qaa-ZZ", "en-GB", "ja-JP"] {
            let finished = expectation(description: "bounded custom speech on small stack: " + locale)
            let thread = Thread {
                let result = deep.accessibilityDescription(locale: Locale(identifier: locale), vocabularies: catalog)
                XCTAssertLessThan(result.text.utf16.count, MathLimits.depth * 100)
                finished.fulfill()
            }
            thread.stackSize = 256 * 1024
            thread.start()
            withExtendedLifetime(deep) { wait(for: [finished], timeout: 30) }
        }
    }
}
