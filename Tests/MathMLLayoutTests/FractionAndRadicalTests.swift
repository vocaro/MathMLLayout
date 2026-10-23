import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

/// `mfrac`, `msqrt` and `mroot` (MathML 3, 3.3.2–3.3.3; MathML Core 3.3.2–3.3.3): where the
/// bar, the parts, the radical sign and the index go, measured from their ink.
final class FractionAndRadicalTests: XCTestCase {
    private let axis = constant(\.axisHeight)
    private let rule = constant(\.fractionRuleThickness)
    /// Half a pixel of the rendering, and a little antialiasing.
    private let pixel: CGFloat = 0.6

    // MARK: The bar

    /// A fraction whose parts have no ink, so its only ink is the bar.
    private func bar(_ attributes: String = "", display: Bool = true) throws -> CGRect? {
        let body = "<mfrac \(attributes)><mspace width=\"2em\" height=\"1ex\"/><mspace width=\"1em\" height=\"1ex\"/></mfrac>"
        return Rendering(try typeset(body, display: display)).bounds()
    }

    func testTheBarLiesOnTheAxisAndSpansTheWiderPart() throws {
        for display in [false, true] {
            let fraction = try typeset("<mfrac><mspace width=\"2em\" height=\"1ex\"/><mspace width=\"1em\" height=\"1ex\"/></mfrac>", display: display)
            let bar = try XCTUnwrap(Rendering(fraction).bounds())
            XCTAssertEqual(bar.midY, axis, accuracy: 0.3, "display \(display)")
            XCTAssertEqual(bar.height, rule, accuracy: 0.5, "display \(display)")
            // In text style the parts are a script level down, so their em is smaller.
            XCTAssertEqual(bar.width, display ? 2 * em : 2 * constant(\.scriptPercentScaleDown) / 100, accuracy: pixel, "display \(display)")
            XCTAssertEqual(bar.midX, fraction.width / 2, accuracy: 0.3, "the bar is centered in the box")
            XCTAssertGreaterThan(bar.minX, 0.5, "with a little room each side")
        }
    }

    func testLineThickness() throws {
        func thickness(_ value: String) throws -> CGFloat { try XCTUnwrap(try bar("linethickness=\"\(value)\""), value).height }
        let standard = try XCTUnwrap(try bar()).height
        XCTAssertEqual(standard, rule, accuracy: 0.4)
        XCTAssertEqual(try thickness("medium"), standard, accuracy: 0.01)
        XCTAssertEqual(try thickness("thin"), rule / 2, accuracy: 0.4)
        XCTAssertEqual(try thickness("thick"), rule * 2, accuracy: 0.4)
        XCTAssertEqual(try thickness(" Thick "), rule * 2, accuracy: 0.4)
        XCTAssertEqual(try thickness("3px"), 3, accuracy: 0.4)
        XCTAssertEqual(try thickness("0.25em"), 5, accuracy: 0.4)
        XCTAssertEqual(try thickness("300%"), 3 * rule, accuracy: 0.4, "a percentage of the default")
        XCTAssertEqual(try thickness("3"), 3 * rule, accuracy: 0.4, "a bare number multiplies the default (MathML 3)")
        XCTAssertEqual(try thickness("bogus"), standard, accuracy: 0.01, "an invalid value is ignored")
        XCTAssertEqual(try thickness("50em"), em, accuracy: 0.5, "bounded by the font size")
        for value in ["thin", "thick", "5px"] {
            XCTAssertEqual(try XCTUnwrap(try bar("linethickness=\"\(value)\"")).midY, axis, accuracy: 0.3, "\(value) stays centered on the axis")
        }
        for none in ["0", "0px", "0em", "0%", "-2px"] { XCTAssertNil(try bar("linethickness=\"\(none)\""), "linethickness=\(none) draws no bar") }
    }

    // MARK: The parts

    private func parts(_ numerator: String, _ denominator: String, attributes: String = "", display: Bool)
        throws -> (numerator: CGRect, denominator: CGRect, bar: CGRect?) {
        let found = try inks("<mfrac \(attributes)><mrow mathcolor=\"red\">\(numerator)</mrow><mrow mathcolor=\"blue\">\(denominator)</mrow></mfrac>",
                             display: display)
        return (try XCTUnwrap(found[.red]), try XCTUnwrap(found[.blue]), found[.black])
    }

    func testPartsClearTheBarByTheFontsGaps() throws {
        // Deep numerators and tall denominators, the cases the minimum gaps exist for.
        let pairs = [("<mi>a</mi>", "<mi>b</mi>"), ("<mi>g</mi>", "<mi>f</mi>"), ("<mi>y</mi><mo>+</mo><mi>j</mi>", "<mi>d</mi><mi>h</mi>"),
                     ("<msub><mi>x</mi><mi>j</mi></msub>", "<msup><mi>b</mi><mi>f</mi></msup>"),
                     ("<mfrac><mi>p</mi><mi>q</mi></mfrac>", "<mfrac><mi>d</mi><mi>f</mi></mfrac>")]
        for display in [false, true] {
            let numeratorGap = display ? constant(\.fractionNumDisplayStyleGapMin) : constant(\.fractionNumeratorGapMin)
            let denominatorGap = display ? constant(\.fractionDenomDisplayStyleGapMin) : constant(\.fractionDenominatorGapMin)
            for (numerator, denominator) in pairs {
                let found = try parts(numerator, denominator, display: display)
                let label = "\(numerator) over \(denominator), display \(display)"
                XCTAssertGreaterThanOrEqual(found.numerator.minY, axis + rule / 2 + numeratorGap - pixel, "numerator gap: \(label)")
                XCTAssertLessThanOrEqual(found.denominator.maxY, axis - rule / 2 - denominatorGap + pixel, "denominator gap: \(label)")
            }
        }
    }

    func testAPartThatWouldTouchTheBarIsMovedByExactlyTheGap() throws {
        // A numerator 1em deep and a denominator 2em tall: the standard shifts are too small.
        let deep = "<mspace width=\"1em\" height=\"1ex\" depth=\"1em\" mathbackground=\"red\"/>"
        let high = "<mspace width=\"1em\" height=\"2em\" depth=\"1ex\" mathbackground=\"blue\"/>"
        for display in [false, true] {
            let found = try inks("<mfrac>\(deep)\(high)</mfrac>", display: display)
            let numerator = try XCTUnwrap(found[.red]), denominator = try XCTUnwrap(found[.blue])
            XCTAssertEqual(numerator.minY, axis + rule / 2 + (display ? constant(\.fractionNumDisplayStyleGapMin) : constant(\.fractionNumeratorGapMin)),
                           accuracy: pixel, "display \(display)")
            XCTAssertEqual(denominator.maxY, axis - rule / 2 - (display ? constant(\.fractionDenomDisplayStyleGapMin) : constant(\.fractionDenominatorGapMin)),
                           accuracy: pixel, "display \(display)")
        }
    }

    func testShortPartsUseTheFontsStandardShifts() throws {
        // Digits have no depth, so the numerator's baseline is its ink's bottom.
        for display in [false, true] {
            let found = try parts("<mn>1</mn>", "<mn>1</mn>", display: display)
            let up = display ? constant(\.fractionNumeratorDisplayStyleShiftUp) : constant(\.fractionNumeratorShiftUp)
            let down = display ? constant(\.fractionDenominatorDisplayStyleShiftDown) : constant(\.fractionDenominatorShiftDown)
            XCTAssertEqual(found.numerator.minY, up, accuracy: 1, "display \(display)")
            XCTAssertEqual(found.denominator.minY, -down, accuracy: 1, "display \(display)")
        }
    }

    func testPartsAreCenteredUnlessAligned() throws {
        let wide = "<mn>1000000</mn>", narrow = "<mn>1</mn>"
        for display in [false, true] {
            let centered = try parts(narrow, wide, display: display)
            XCTAssertEqual(centered.numerator.midX, centered.denominator.midX, accuracy: 1)
            XCTAssertEqual(try XCTUnwrap(centered.bar).midX, centered.denominator.midX, accuracy: 1)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(centered.bar).width, centered.denominator.width - pixel, "the bar spans the wider part")
            let left = try parts(narrow, wide, attributes: "numalign=\"left\"", display: display)
            XCTAssertEqual(left.numerator.minX, left.denominator.minX, accuracy: 1)
            let right = try parts(narrow, wide, attributes: "numalign=\"right\"", display: display)
            XCTAssertEqual(right.numerator.maxX, right.denominator.maxX, accuracy: 1)
            let below = try parts(wide, narrow, attributes: "denomalign=\" Right \"", display: display)
            XCTAssertEqual(below.denominator.maxX, below.numerator.maxX, accuracy: 1)
            XCTAssertEqual(try parts(wide, narrow, attributes: "denomalign=\"left\"", display: display).denominator.minX,
                           below.numerator.minX, accuracy: 1)
        }
    }

    func testPartsShrinkInTextStyleOnly() throws {
        let digit = try XCTUnwrap(Rendering(try typeset("<mn>1</mn>")).bounds()).height
        let scale = constant(\.scriptPercentScaleDown, size: 1) / 100
        XCTAssertEqual(try parts("<mn>1</mn>", "<mn>1</mn>", display: true).numerator.height, digit, accuracy: pixel)
        XCTAssertEqual(try parts("<mn>1</mn>", "<mn>1</mn>", display: false).numerator.height, digit * scale, accuracy: 1)
        XCTAssertEqual(try parts("<mn>1</mn>", "<mn>1</mn>", display: false).denominator.height, digit * scale, accuracy: 1)
        // displaystyle on the fraction itself, either way.
        XCTAssertEqual(try parts("<mn>1</mn>", "<mn>1</mn>", attributes: "displaystyle=\"true\"", display: false).numerator.height, digit, accuracy: pixel)
        XCTAssertEqual(try parts("<mn>1</mn>", "<mn>1</mn>", attributes: "displaystyle=\"false\"", display: true).numerator.height, digit * scale,
                       accuracy: 1)
        // A fraction inside a display fraction is in text style: its parts shrink.
        let nested = try parts("<mfrac><mn>1</mn><mn>1</mn></mfrac>", "<mn>1</mn>", display: true)
        XCTAssertLessThan(nested.numerator.height, 2 * digit + 4 * rule + 8, "nested parts are a script level down")
        XCTAssertEqual(nested.denominator.height, digit, accuracy: pixel)
    }

    func testNestedFractionsStopShrinkingAtTheMinimumSize() throws {
        // Script level 1 is 70%; levels 2 and 3 would be 55% and 39%, but stop at 60% of the size.
        func deepest(_ levels: Int) throws -> CGFloat {
            var body = "<mspace width=\"1em\" height=\"1ex\" mathbackground=\"red\"/>"
            for _ in 0..<levels { body = "<mfrac>\(body)<mn>1</mn></mfrac>" }
            return try XCTUnwrap(try inks(body)[.red]).width
        }
        XCTAssertEqual(try deepest(1), 0.7 * em, accuracy: pixel)
        XCTAssertEqual(try deepest(2), 0.6 * em, accuracy: pixel)
        XCTAssertEqual(try deepest(3), 0.6 * em, accuracy: pixel)
        XCTAssertEqual(try deepest(6), 0.6 * em, accuracy: pixel)
    }

    // MARK: Stacks and beveled fractions

    func testAStackWithoutABarKeepsTheMinimumGap() throws {
        for display in [false, true] {
            let minimum = display ? constant(\.stackDisplayStyleGapMin) : constant(\.stackGapMin)
            for (top, bottom) in [("<mi>n</mi>", "<mi>k</mi>"), ("<mi>g</mi>", "<mi>f</mi>"),
                                  ("<mfrac><mi>a</mi><mi>g</mi></mfrac>", "<mfrac><mi>f</mi><mi>b</mi></mfrac>")] {
                let found = try parts(top, bottom, attributes: "linethickness=\"0\"", display: display)
                XCTAssertNil(found.bar, "no bar")
                XCTAssertGreaterThanOrEqual(found.numerator.minY - found.denominator.maxY, minimum - pixel, "\(top) atop \(bottom), display \(display)")
            }
            // Parts that would collide are moved apart equally, to exactly the minimum.
            let deep = "<mspace width=\"1em\" height=\"1ex\" depth=\"1em\" mathbackground=\"red\"/>"
            let high = "<mspace width=\"1em\" height=\"1em\" depth=\"1ex\" mathbackground=\"blue\"/>"
            let forced = try inks("<mfrac linethickness=\"0\">\(deep)\(high)</mfrac>", display: display)
            let upper = try XCTUnwrap(forced[.red]), lower = try XCTUnwrap(forced[.blue])
            XCTAssertEqual(upper.minY - lower.maxY, minimum, accuracy: pixel, "display \(display)")
        }
        // A binomial coefficient: the stack between stretched parentheses.
        let binomial = try inks("<mo>(</mo><mfrac linethickness=\"0\"><mi mathcolor=\"red\">n</mi><mi mathcolor=\"blue\">k</mi></mfrac><mo>)</mo>", display: true)
        let fences = try XCTUnwrap(binomial[.black])
        XCTAssertGreaterThanOrEqual(fences.maxY, try XCTUnwrap(binomial[.red]).maxY - em / 2)
        XCTAssertLessThanOrEqual(fences.minY, try XCTUnwrap(binomial[.blue]).minY + em / 2)
    }

    func testBeveledFractionsPutTheNumeratorUpAndLeftOfASlash() throws {
        for display in [false, true] {
            for (numerator, denominator) in [("<mn>1</mn>", "<mn>2</mn>"), ("<mi>a</mi><mo>+</mo><mi>b</mi>", "<mi>c</mi>"),
                                             ("<mfrac><mi>a</mi><mi>b</mi></mfrac>", "<mfrac><mi>c</mi><mi>d</mi></mfrac>")] {
                let found = try parts(numerator, denominator, attributes: "bevelled=\"true\"", display: display)
                let slash = try XCTUnwrap(found.bar), label = "\(numerator) / \(denominator), display \(display)"
                XCTAssertLessThan(found.numerator.maxX, found.denominator.minX + pixel, "numerator left of denominator: \(label)")
                XCTAssertGreaterThan(found.numerator.midY, found.denominator.midY, "numerator raised: \(label)")
                XCTAssertGreaterThan(slash.midX, found.numerator.midX, label)
                XCTAssertLessThan(slash.midX, found.denominator.midX, label)
                XCTAssertGreaterThan(slash.height, slash.width, "a slash, not a bar: \(label)")
                XCTAssertGreaterThan(slash.maxY, found.denominator.maxY - pixel, label)
                XCTAssertLessThan(slash.minY, found.numerator.minY + pixel, label)
            }
        }
        // bevelled="false" is an ordinary fraction.
        let plain = try typeset("<mfrac><mn>1</mn><mn>2</mn></mfrac>"), unbeveled = try typeset("<mfrac bevelled=\"false\"><mn>1</mn><mn>2</mn></mfrac>")
        XCTAssertEqual(plain.width, unbeveled.width); XCTAssertEqual(height(plain), height(unbeveled))
    }

    func testAFractionBoxCoversItsPartsAndBar() throws {
        for attributes in ["", "linethickness=\"0\"", "linethickness=\"thick\"", "bevelled=\"true\"", "numalign=\"left\""] {
            for display in [false, true] {
                let box = try innerBox("<mfrac \(attributes)><mrow><mi>g</mi><mo>+</mo><mi>f</mi></mrow><mrow><mi>j</mi><mi>f</mi></mrow></mfrac>", display: display)
                let ink = try XCTUnwrap(box.inkBounds)
                XCTAssertLessThanOrEqual(ink.maxY, box.ascent + 0.01, "\(attributes) display \(display)")
                XCTAssertGreaterThanOrEqual(ink.minY, -box.descent - 0.01, "\(attributes) display \(display)")
                XCTAssertLessThanOrEqual(ink.maxX, box.width + 0.15 * em, "\(attributes) display \(display)")
                XCTAssertGreaterThanOrEqual(ink.minX, -0.15 * em, "\(attributes) display \(display)")
            }
        }
    }

    func testFractionsNeedExactlyTwoChildren() {
        for body in ["<mfrac/>", "<mfrac><mi>a</mi></mfrac>", "<mfrac><mi>a</mi><mi>b</mi><mi>c</mi></mfrac>"] {
            XCTAssertThrowsError(try typeset(body), body) { XCTAssertEqual($0 as? MathLayoutError, .invalidMarkup("mfrac")) }
        }
        for body in ["<mroot/>", "<mroot><mi>a</mi></mroot>", "<mroot><mi>a</mi><mi>b</mi><mi>c</mi></mroot>"] {
            XCTAssertThrowsError(try typeset(body), body) { XCTAssertEqual($0 as? MathLayoutError, .invalidMarkup("mroot")) }
        }
    }

    // MARK: Radicals

    private func radical(_ content: String, index: String? = nil, display: Bool, font: String? = nil)
        throws -> (sign: CGRect, radicand: CGRect, index: CGRect?, layout: MathLayout) {
        let radicand = "<mrow mathcolor=\"red\">\(content)</mrow>"
        let body = index.map { "<mroot>\(radicand)<mrow mathcolor=\"blue\">\($0)</mrow></mroot>" } ?? "<msqrt>\(radicand)</msqrt>"
        let layout = try typeset(body, display: display, font: font)
        let rendering = Rendering(layout)
        return (try XCTUnwrap(rendering.bounds(.black)), try XCTUnwrap(rendering.bounds(.red)), rendering.bounds(.blue), layout)
    }

    private let radicands = ["<mi>x</mi>", "<mi>a</mi><mo>+</mo><mi>b</mi>", "<mi>f</mi><mi>g</mi>", "<mfrac><mi>a</mi><mi>b</mi></mfrac>",
                             "<msup><mi>b</mi><mn>2</mn></msup><mo>−</mo><mn>4</mn><mi>a</mi><mi>c</mi>",
                             "<mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mfrac><mi>c</mi><mi>d</mi></mfrac></mfrac>",
                             "<mtable><mtr><mtd><mn>1</mn></mtd></mtr><mtr><mtd><mn>2</mn></mtd></mtr><mtr><mtd><mn>3</mn></mtd></mtr></mtable>"]

    func testTheSignAndOverbarCoverTheRadicand() throws {
        for display in [false, true] {
            let gap = display ? constant(\.radicalDisplayStyleVerticalGap) : constant(\.radicalVerticalGap)
            let thickness = constant(\.radicalRuleThickness)
            for content in radicands {
                let found = try radical(content, display: display), label = "√(\(content)), display \(display)"
                XCTAssertGreaterThanOrEqual(found.sign.maxY, found.radicand.maxY + gap + thickness - pixel, "the bar clears the radicand: \(label)")
                XCTAssertLessThanOrEqual(found.sign.minY, found.radicand.minY + pixel, "the sign reaches the radicand's depth: \(label)")
                XCTAssertGreaterThanOrEqual(found.sign.maxX, found.radicand.maxX - 0.15 * em, "the bar reaches the radicand's end: \(label)")
                XCTAssertLessThan(found.sign.minX, found.radicand.minX - 0.3 * em, "the sign is left of the radicand: \(label)")
                XCTAssertEqual(found.layout.ascent, found.sign.maxY + constant(\.radicalExtraAscender), accuracy: pixel, "extra ascender: \(label)")
                XCTAssertEqual(found.sign.maxX, found.layout.width, accuracy: 0.15 * em, "the bar ends the box: \(label)")
            }
        }
    }

    func testTheRadicalGrowsWithItsRadicand() throws {
        var last: CGFloat = 0
        for content in ["<mi>x</mi>", "<mfrac><mi>a</mi><mi>b</mi></mfrac>", radicands[5], "<mspace width=\"1em\" height=\"4em\" depth=\"3em\" mathbackground=\"red\"/>",
                        "<mspace width=\"1em\" height=\"9em\" depth=\"8em\" mathbackground=\"red\"/>"] {
            let found = try radical(content, display: true)
            XCTAssertGreaterThan(found.sign.height, last, content)
            XCTAssertGreaterThanOrEqual(found.sign.height, found.radicand.height, content)
            XCTAssertLessThan(found.sign.height, found.radicand.height + 1.2 * em, "no taller than it needs to be: \(content)")
            last = found.sign.height
        }
        let outer = try typeset("<msqrt><msqrt><msqrt><mi>x</mi></msqrt></msqrt></msqrt>"), inner = try typeset("<msqrt><mi>x</mi></msqrt>")
        XCTAssertGreaterThan(outer.ascent, inner.ascent + 2)
        XCTAssertGreaterThan(outer.width, inner.width + em)
    }

    func testSquareRootInfersARow() throws {
        let inferred = try innerBox("<msqrt><mi>a</mi><mo>+</mo><mi>b</mi></msqrt>")
        let explicit = try innerBox("<msqrt><mrow><mi>a</mi><mo>+</mo><mi>b</mi></mrow></msqrt>")
        XCTAssertEqual(inferred.width, explicit.width, accuracy: 0.001)
        XCTAssertEqual(inferred.ascent, explicit.ascent, accuracy: 0.001)
        XCTAssertEqual(inferred.descent, explicit.descent, accuracy: 0.001)
        // An empty square root is a sign and nothing else.
        let empty = try typeset("<msqrt/>")
        XCTAssertGreaterThan(empty.width, 0.3 * em); XCTAssertGreaterThan(empty.ascent, 0)
        // menclose's radical notation is the same drawing.
        let enclosed = try typeset("<menclose notation=\"radical\"><mi>x</mi></menclose>"), root = try typeset("<msqrt><mi>x</mi></msqrt>")
        XCTAssertEqual(enclosed.width, root.width, accuracy: 0.001); XCTAssertEqual(enclosed.ascent, root.ascent, accuracy: 0.001)
    }

    /// MathML Core's `math-shift: compact`, TeX's cramped style: a superscript sits lower under
    /// a radical, in a denominator, in a subscript and under an accent, and nowhere else.
    func testCrampedContextsLowerSuperscripts() throws {
        let power = "<msup><mi mathcolor=\"blue\">x</mi><mn mathcolor=\"red\">2</mn></msup>"
        func raise(_ body: String) throws -> CGFloat {
            let found = try inks(body, display: true)
            return try XCTUnwrap(found[.red], body).minY - (try XCTUnwrap(found[.blue], body)).minY
        }
        let delta = constant(\.superscriptShiftUp) - constant(\.superscriptShiftUpCramped)
        XCTAssertGreaterThan(delta, 0.75, "the font distinguishes the two shifts")
        let open = try raise(power)
        for cramped in ["<msqrt>\(power)</msqrt>", "<mroot>\(power)<mn>3</mn></mroot>", "<mfrac><mn>1</mn>\(power)</mfrac>",
                        "<mover accent=\"true\">\(power)<mo>¯</mo></mover>", "<msqrt><mrow><mstyle>\(power)</mstyle></mrow></msqrt>"] {
            XCTAssertEqual(open - (try raise(cramped)), delta, accuracy: 0.5, cramped)
        }
        for normal in ["<mrow>\(power)</mrow>", "<mfrac>\(power)<mn>1</mn></mfrac>", "<mover>\(power)<mi>a</mi></mover>",
                       "<munder>\(power)<mi>a</mi></munder>", "<mo>(</mo>\(power)<mo>)</mo>"] {
            XCTAssertEqual(try raise(normal), open, accuracy: 0.3, normal)
        }
        // A subscript is cramped and a superscript is not, both at script size.
        let scale = constant(\.scriptPercentScaleDown, size: 1) / 100
        let inSuperscript = try raise("<msup><mi>y</mi>\(power)</msup>"), inSubscript = try raise("<msub><mi>y</mi>\(power)</msub>")
        XCTAssertEqual(inSuperscript - inSubscript, delta * scale, accuracy: 0.5)
        // And exactly, in the engine's own terms.
        let engine = LayoutEngine(fontName: nil)
        let context = LayoutContext(fontSize: em, unclampedSize: em, minSize: 12, display: false, color: black)
        let node = try mathML("<msup><mi>x</mi><mn>2</mn></msup>").children[0]
        let plain = try engine.layout(node, context, depth: 0), cramped = try engine.layout(node, context.with(cramped: true), depth: 0)
        XCTAssertEqual(plain.ascent - cramped.ascent, delta, accuracy: 0.01)
    }

    // MARK: Indexed roots

    func testTheIndexSitsInTheCrookOfTheSign() throws {
        let digit = try XCTUnwrap(Rendering(try typeset("<mn>3</mn>")).bounds()).height
        for display in [false, true] {
            for content in ["<mi>x</mi>", "<mfrac><mi>a</mi><mi>b</mi></mfrac>", radicands[5]] {
                let found = try radical(content, index: "<mn>3</mn>", display: display), label = "∛(\(content)), display \(display)"
                let index = try XCTUnwrap(found.index)
                XCTAssertLessThan(index.maxX, found.radicand.minX, "index left of the radicand: \(label)")
                XCTAssertGreaterThanOrEqual(index.minX, -pixel, label)
                // Its bottom is raised by RadicalDegreeBottomRaisePercent of the sign's height.
                let raise = MathFont.named(nil).constants.radicalDegreeBottomRaisePercent / 100
                XCTAssertEqual(index.minY, found.sign.minY + raise * found.sign.height, accuracy: 1.5, "index height: \(label)")
                // Two script levels down, which is the minimum size here.
                XCTAssertEqual(index.height, 0.6 * digit, accuracy: 1, "index size: \(label)")
                XCTAssertLessThanOrEqual(index.maxY, found.layout.ascent + pixel, label)
            }
        }
    }

    func testIndexedRootsMatchSquareRootsApartFromTheIndex() throws {
        for content in ["<mi>x</mi>", "<mfrac><mi>a</mi><mi>b</mi></mfrac>"] {
            let square = try radical(content, display: true), cube = try radical(content, index: "<mn>3</mn>", display: true)
            XCTAssertEqual(cube.sign.height, square.sign.height, accuracy: pixel, content)
            XCTAssertEqual(cube.radicand.minY, square.radicand.minY, accuracy: 0.01, content)
            XCTAssertGreaterThanOrEqual(cube.layout.width, square.layout.width - 0.01, content)
            let wide = try radical(content, index: "<mi>n</mi><mo>+</mo><mn>1</mn>", display: true)
            XCTAssertGreaterThan(wide.layout.width, cube.layout.width + 0.5 * em, "a wide index pushes the sign right")
            XCTAssertLessThan(try XCTUnwrap(wide.index).maxX, wide.radicand.minX)
        }
        // A tall index raises the box to cover it.
        let tall = try innerBox("<mroot><mi>x</mi><mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mi>c</mi></mfrac></mroot>")
        let ink = try XCTUnwrap(tall.inkBounds)
        XCTAssertLessThanOrEqual(ink.maxY, tall.ascent + 0.01)
        XCTAssertGreaterThanOrEqual(ink.minY, -tall.descent - 0.01)
    }

    func testRadicalsAreDrawnWithoutAMathFont() throws {
        // Helvetica has no MATH table: fallback constants and a drawn sign.
        for content in ["<mi>x</mi>", "<mfrac><mi>a</mi><mi>b</mi></mfrac>", radicands[5]] {
            for index in [nil, "<mn>3</mn>"] {
                let found = try radical(content, index: index, display: true, font: "Helvetica"), label = "\(content) index \(index ?? "none")"
                XCTAssertGreaterThanOrEqual(found.sign.maxY, found.radicand.maxY + pixel, label)
                XCTAssertLessThanOrEqual(found.sign.minY, found.radicand.minY + 1, label)
                XCTAssertGreaterThanOrEqual(found.sign.maxX, found.radicand.maxX - 0.15 * em, label)
                XCTAssertLessThan(found.sign.minX, found.radicand.minX, label)
                if let index = found.index { XCTAssertLessThan(index.maxX, found.radicand.minX, label) }
                assertBoxCoversInk(found.layout, label)
            }
        }
    }
}
