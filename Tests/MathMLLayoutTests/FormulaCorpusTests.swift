import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

/// Functional coverage: every formula of `FormulaCorpus` must lay out properly. Each is
/// checked against its own expectations and against the invariants any formula must keep.
final class FormulaCorpusTests: XCTestCase {
    private func layout(_ formula: Formula, display: Bool = true, size: CGFloat = em, font: String? = nil) throws -> MathLayout {
        do { return try typeset(formula.markup, size: size, display: display, font: font) } catch {
            XCTFail("\(formula.name): \(error)")
            throw error
        }
    }

    private func ink(_ part: Formula.Part) -> Rendering.Ink {
        switch part {
        case .red: .red
        case .green: .green
        case .blue: .blue
        case .rest: .black
        }
    }

    /// The reasons `rendering` does not meet `expectation`; empty when it does.
    private func failures(_ expectation: Formula.Expectation, in rendering: Rendering) -> [String] {
        func bounds(_ part: Formula.Part) -> CGRect? { rendering.bounds(ink(part)) }
        func both(_ a: Formula.Part, _ b: Formula.Part, _ check: (CGRect, CGRect) -> String?) -> [String] {
            guard let first = bounds(a) else { return ["no \(a) ink"] }
            guard let second = bounds(b) else { return ["no \(b) ink"] }
            return check(first, second).map { ["\($0): \(a) \(first.integralDescription), \(b) \(second.integralDescription)"] } ?? []
        }
        switch expectation {
        case .leftOf(let a, let b): return both(a, b) { $0.maxX <= $1.minX + 1 ? nil : "\(a) is not left of \(b)" }
        case .above(let a, let b): return both(a, b) { $0.minY >= $1.maxY - 0.5 ? nil : "\(a) is not above \(b)" }
        case .raised(let a, let b): return both(a, b) { $0.minY > $1.midY ? nil : "\(a) is not raised over \(b)" }
        case .lowered(let a, let b): return both(a, b) { $0.maxY < $1.midY ? nil : "\(a) is not lowered under \(b)" }
        case .centred(let a, let b): return both(a, b) { abs($0.midX - $1.midX) <= 0.25 * em ? nil : "\(a) is not centred on \(b)" }
        case .coversVertically(let a, let b):
            return both(a, b) { $0.maxY >= $1.maxY - em / 2 - 0.5 && $0.minY <= $1.minY + em / 2 + 0.5 ? nil : "\(a) does not cover \(b) vertically" }
        case .coversHorizontally(let a, let b):
            return both(a, b) {
                let slack = 0.1 * $1.width + 1
                return $0.width >= 0.9 * $1.width && $0.minX <= $1.minX + slack && $0.maxX >= $1.maxX - slack ? nil : "\(a) does not cover \(b) horizontally"
            }
        case .sameBaseline(let a, let b): return both(a, b) { abs($0.minY - $1.minY) <= 0.75 ? nil : "\(a) and \(b) are not on one baseline" }
        case .inside(let a, let b): return both(a, b) { $1.insetBy(dx: -0.5, dy: -0.5).contains($0) ? nil : "\(a) is not inside \(b)" }
        case .smaller(let a, let b): return both(a, b) { $0.height < 0.9 * $1.height ? nil : "\(a) is not smaller than \(b)" }
        }
    }

    // MARK: The corpus itself

    func testTheCorpusIsWellFormed() throws {
        XCTAssertGreaterThanOrEqual(FormulaCorpus.all.count, 50)
        XCTAssertEqual(Set(FormulaCorpus.all.map(\.name)).count, FormulaCorpus.all.count, "names are unique")
        var elements = Set<String>()
        func collect(_ node: MathMLNode) { elements.insert(node.name); node.children.forEach(collect) }
        for formula in FormulaCorpus.all {
            let parsed = try mathML(formula.markup)
            XCTAssertFalse(parsed.children.isEmpty, formula.name)
            collect(parsed)
            XCTAssertFalse(formula.expectations.isEmpty, "\(formula.name) states what its layout must show")
        }
        // Together the formulas use every presentation element the README lists as supported.
        let supported = ["mi", "mn", "mo", "mtext", "ms", "mspace", "math", "mrow", "mstyle", "mpadded", "mphantom", "semantics", "maction", "merror",
                         "msup", "msub", "msubsup", "mmultiscripts", "mprescripts", "none", "mover", "munder", "munderover", "mfrac", "msqrt", "mroot",
                         "mfenced", "menclose", "mtable", "mtr", "mtd", "mlabeledtr"]
        XCTAssertEqual(supported.filter { !elements.contains($0) }, [], "elements the corpus does not exercise")
    }

    // MARK: Each formula's own expectations

    func testEveryFormulaMeetsItsExpectations() throws {
        for formula in FormulaCorpus.all {
            let rendering = Rendering(try layout(formula))
            for expectation in formula.expectations {
                for failure in failures(expectation, in: rendering) { XCTFail("\(formula.name): \(failure)") }
            }
        }
    }

    func testExpectationsHoldAtOtherSizes() throws {
        // The same relations at a small and a large size (tolerances are in the 20-point em, so
        // only relations that do not depend on it are checked).
        for formula in FormulaCorpus.all {
            for size in [CGFloat(11), 34] {
                let rendering = Rendering(try layout(formula, size: size), scale: size < 20 ? 8 : 3)
                for expectation in formula.expectations {
                    switch expectation {
                    case .leftOf, .above, .raised, .lowered, .inside, .smaller:
                        for failure in failures(expectation, in: rendering) { XCTFail("\(formula.name) at \(size)pt: \(failure)") }
                    default: break
                    }
                }
            }
        }
    }

    func testExpectationsHoldWithoutAMathFont() throws {
        // Helvetica has no MATH table: fallback constants, system fallback glyphs, drawn stretchy
        // operators. Positions change; the relations between the parts must not.
        for formula in FormulaCorpus.all {
            let rendering = Rendering(try layout(formula, font: "Helvetica"))
            for expectation in formula.expectations {
                if case .smaller = expectation { continue }
                for failure in failures(expectation, in: rendering) { XCTFail("\(formula.name) in Helvetica: \(failure)") }
            }
        }
    }

    // MARK: Invariants

    func testEveryFormulaLaysOutInBothStylesAtEverySize() throws {
        for formula in FormulaCorpus.all {
            for display in [false, true] {
                for size in [CGFloat(1), 9, 12, 17, 20, 48, 200] {
                    let result = try layout(formula, display: display, size: size)
                    let label = "\(formula.name), display \(display), \(size)pt"
                    XCTAssertGreaterThan(result.width, 0, label)
                    XCTAssertGreaterThan(result.ascent + result.descent, 0, label)
                    XCTAssertTrue(result.width.isFinite && result.ascent.isFinite && result.descent.isFinite, label)
                    XCTAssertGreaterThanOrEqual(result.ascent, 0, label); XCTAssertGreaterThanOrEqual(result.descent, 0, label)
                }
            }
        }
    }

    func testEveryFormulaIsInsideItsBoxAndFillsIt() throws {
        for formula in FormulaCorpus.all {
            for display in [false, true] {
                for font in [nil, "Helvetica"] {
                    let result = try layout(formula, display: display, font: font)
                    let label = "\(formula.name), display \(display), font \(font ?? "default")"
                    let rendering = Rendering(result, scale: 3)
                    assertBoxCoversInk(result, label, rendering: rendering)
                    let ink = try XCTUnwrap(rendering.bounds(), label)
                    // The box is no looser than the formula needs: nothing is displaced or oversized.
                    XCTAssertGreaterThanOrEqual(ink.width, 0.85 * result.width, "ink width: \(label)")
                    XCTAssertGreaterThanOrEqual(ink.height, 0.85 * height(result), "ink height: \(label)")
                }
            }
        }
    }

    func testDisplayStyleIsNeverShorterThanTextStyle() throws {
        for formula in FormulaCorpus.all {
            let display = try layout(formula, display: true), text = try layout(formula, display: false)
            XCTAssertGreaterThanOrEqual(height(display), height(text) - 0.5, formula.name)
        }
    }

    func testEveryFormulaScalesWithTheFontSize() throws {
        for formula in FormulaCorpus.all {
            for display in [false, true] {
                let small = try layout(formula, display: display, size: 20), large = try layout(formula, display: display, size: 40)
                let label = "\(formula.name), display \(display)"
                XCTAssertEqual(large.width, 2 * small.width, accuracy: 0.015 * large.width, "width: \(label)")
                XCTAssertEqual(large.ascent, 2 * small.ascent, accuracy: 0.015 * height(large), "ascent: \(label)")
                XCTAssertEqual(large.descent, 2 * small.descent, accuracy: 0.015 * height(large), "descent: \(label)")
            }
        }
    }

    func testEveryFormulaIsDeterministic() throws {
        for formula in FormulaCorpus.all {
            let first = try layout(formula), second = try layout(formula)
            XCTAssertEqual([first.width, first.ascent, first.descent], [second.width, second.ascent, second.descent], formula.name)
            XCTAssertEqual(Rendering(first).bounds(), Rendering(second).bounds(), formula.name)
            // The same tree reached through a namespace prefix, and built by hand, lays out the same.
            let prefixed = formula.markup.replacingOccurrences(of: "</", with: "</m:").replacingOccurrences(of: "<(?=[a-z])", with: "<m:", options: .regularExpression)
            let viaPrefix = try MathMLNode.parse(xml: Data("<m:math xmlns:m=\"http://www.w3.org/1998/Math/MathML\" display=\"block\">\(prefixed)</m:math>".utf8))
            XCTAssertEqual(viaPrefix, try mathML(formula.markup, display: true), formula.name)
        }
    }

    /// Every box in a formula's tree, not only the root, reaches as high and as low as what it
    /// draws: that is what keeps neighbours, bars and limits clear of it.
    func testEveryInnerBoxCoversItsInkVertically() throws {
        func violations(_ box: MathBox, _ path: String) -> [String] {
            var result: [String] = []
            if let ink = box.inkBounds, ink.maxY > box.ascent + 0.05 || ink.minY < -box.descent - 0.05 {
                result.append(String(format: "%@: ink %.2f…%.2f outside %.2f…%.2f", path, ink.minY, ink.maxY, -box.descent, box.ascent))
            }
            for (index, item) in box.items.enumerated() {
                if case .box(let child, _) = item { result += violations(child, "\(path)/\(index)") }
            }
            return result
        }
        for formula in FormulaCorpus.all {
            for display in [false, true] {
                for found in violations(try innerBox(formula.markup, display: display), formula.name).prefix(3) { XCTFail("display \(display): \(found)") }
            }
        }
    }

    func testEveryFormulaHasASpokenReading() throws {
        for formula in FormulaCorpus.all {
            let reading = try mathML(formula.markup).accessibilityDescription
            XCTAssertFalse(reading.trimmingCharacters(in: .whitespaces).isEmpty, formula.name)
            XCTAssertLessThan(reading.count, 2000, formula.name)
        }
    }

    func testFormulasLayOutConcurrently() throws {
        let nodes = try FormulaCorpus.all.map { try mathML($0.markup, display: true) }
        let style = MathStyle(fontSize: em, color: black, isDisplay: true)
        let expected = try nodes.map { try MathLayout($0, style: style).width }
        let results = UnsafeMutableBufferPointer<CGFloat>.allocate(capacity: nodes.count * 4)
        defer { results.deallocate() }
        let shared = Results(buffer: results)
        DispatchQueue.concurrentPerform(iterations: nodes.count * 4) { index in
            shared.buffer[index] = (try? MathLayout(nodes[index % nodes.count], style: style))?.width ?? -1
        }
        for index in 0..<nodes.count * 4 { XCTAssertEqual(results[index], expected[index % nodes.count], FormulaCorpus.all[index % nodes.count].name) }
    }
}

private struct Results: @unchecked Sendable {
    let buffer: UnsafeMutableBufferPointer<CGFloat>
}

private extension CGRect {
    var integralDescription: String { String(format: "(x %.1f…%.1f, y %.1f…%.1f)", minX, maxX, minY, maxY) }
}
