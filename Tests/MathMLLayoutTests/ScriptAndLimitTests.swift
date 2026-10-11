import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

/// Scripts and limits (MathML 3, 3.4; MathML Core 3.4): `msub`, `msup`, `msubsup`,
/// `mmultiscripts`, `munder`, `mover` and `munderover`, measured from their ink.
final class ScriptAndLimitTests: XCTestCase {
    private let pixel: CGFloat = 0.6
    private let scriptScale = constant(\.scriptPercentScaleDown, size: 1) / 100

    private func assertSameBox(_ a: String, _ b: String, display: Bool = false, _ message: String = "",
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let first = try innerBox(a, display: display), second = try innerBox(b, display: display)
        let label = message.isEmpty ? "\(a) vs \(b)" : message
        XCTAssertEqual(first.width, second.width, accuracy: 0.01, "width: \(label)", file: file, line: line)
        XCTAssertEqual(first.ascent, second.ascent, accuracy: 0.01, "ascent: \(label)", file: file, line: line)
        XCTAssertEqual(first.descent, second.descent, accuracy: 0.01, "descent: \(label)", file: file, line: line)
    }

    // MARK: Sub- and superscripts

    func testScriptsAreAScriptLevelSmaller() throws {
        let digit = try XCTUnwrap(Rendering(try typeset("<mn>2</mn>")).bounds())
        for body in ["<msup><mi>x</mi><mn mathcolor=\"red\">2</mn></msup>", "<msub><mi>x</mi><mn mathcolor=\"red\">2</mn></msub>",
                     "<msubsup><mi>x</mi><mn mathcolor=\"red\">2</mn><mi>n</mi></msubsup>", "<msubsup><mi>x</mi><mi>n</mi><mn mathcolor=\"red\">2</mn></msubsup>",
                     "<mmultiscripts><mi>x</mi><mprescripts/><mn mathcolor=\"red\">2</mn><none/></mmultiscripts>"] {
            let script = try XCTUnwrap(try inks(body)[.red], body)
            XCTAssertEqual(script.height / digit.height, scriptScale, accuracy: 0.08, body)
        }
        // A script's own em shrinks with it.
        let space = try XCTUnwrap(try inks("<msup><mi>x</mi><mspace width=\"1em\" height=\"1ex\" mathbackground=\"red\"/></msup>")[.red])
        XCTAssertEqual(space.width, scriptScale * em, accuracy: pixel)
    }

    func testScriptLevelsStopShrinkingAtTheMinimumSize() throws {
        // x^(y^(z^w)): 70%, then the 60% floor rather than 55% and 39%.
        func width(_ levels: Int) throws -> CGFloat {
            var script = "<mspace width=\"1em\" height=\"1ex\" mathbackground=\"red\"/>"
            for _ in 0..<levels { script = "<msup><mi>x</mi>\(script)</msup>" }
            return try XCTUnwrap(try inks(script)[.red]).width
        }
        XCTAssertEqual(try width(1), 0.7 * em, accuracy: pixel)
        XCTAssertEqual(try width(2), 0.6 * em, accuracy: pixel)
        XCTAssertEqual(try width(3), 0.6 * em, accuracy: pixel)
        // Small text does not shrink below 8 points; text already smaller does not shrink at all.
        func scriptEm(size: CGFloat) throws -> CGFloat {
            try innerBox("<msup><mi>x</mi><msup><mi>x</mi><mspace width=\"1em\"/></msup></msup>", size: size).width
                - (try innerBox("<msup><mi>x</mi><msup><mi>x</mi><mspace width=\"0em\"/></msup></msup>", size: size).width)
        }
        XCTAssertEqual(try scriptEm(size: 10), 8, accuracy: 0.01)
        XCTAssertEqual(try scriptEm(size: 6), 6, accuracy: 0.01)
    }

    func testScriptSizeAttributes() throws {
        func scriptEm(_ attributes: String, levels: Int = 1) throws -> CGFloat {
            var script = "<mspace width=\"1em\" height=\"1ex\" mathbackground=\"red\"/>"
            for _ in 0..<levels { script = "<msup><mi>x</mi>\(script)</msup>" }
            return try XCTUnwrap(try inks("<mstyle \(attributes)>\(script)</mstyle>")[.red]).width
        }
        XCTAssertEqual(try scriptEm("scriptminsize=\"18px\""), 18, accuracy: pixel, "the minimum stops the shrink")
        XCTAssertEqual(try scriptEm("scriptminsize=\"1px\"", levels: 2), constant(\.scriptScriptPercentScaleDown) / 100, accuracy: pixel,
                       "without the floor, level 2 uses the font's ScriptScriptPercentScaleDown")
        XCTAssertEqual(try scriptEm("scriptsizemultiplier=\"0.5\" scriptminsize=\"1px\""), 0.5 * em, accuracy: pixel)
        XCTAssertEqual(try scriptEm("scriptsizemultiplier=\"0.5\" scriptminsize=\"1px\"", levels: 2), 0.25 * em, accuracy: pixel)
        XCTAssertEqual(try scriptEm("scriptsizemultiplier=\"0.9\""), 0.9 * em, accuracy: pixel)
        for ignored in ["scriptsizemultiplier=\"0\"", "scriptsizemultiplier=\"-1\"", "scriptsizemultiplier=\"bogus\"", "scriptminsize=\"bogus\""] {
            XCTAssertEqual(try scriptEm(ignored), 0.7 * em, accuracy: pixel, ignored)
        }
        // scriptlevel, absolute and relative.
        XCTAssertEqual(try innerBox("<mstyle scriptlevel=\"1\"><mspace width=\"1em\"/></mstyle>").width, 0.7 * em, accuracy: 0.01)
        XCTAssertEqual(try innerBox("<mstyle scriptlevel=\"+1\"><mstyle scriptlevel=\"+1\"><mspace width=\"1em\"/></mstyle></mstyle>").width, 0.6 * em, accuracy: 0.01)
        XCTAssertEqual(try innerBox("<mstyle scriptlevel=\"2\"><mstyle scriptlevel=\"-2\"><mspace width=\"1em\"/></mstyle></mstyle>").width, em, accuracy: 0.01,
                       "back to level 0 is back to the full size, not the clamped size scaled up")
        XCTAssertEqual(try innerBox("<msup><mi>x</mi><mstyle scriptlevel=\"0\"><mspace width=\"1em\"/></mstyle></msup>").width
                       - (try innerBox("<msup><mi>x</mi><mspace width=\"0em\"/></msup>").width), em, accuracy: 0.01, "scriptlevel=0 in a script is full size")
        XCTAssertEqual(try innerBox("<mstyle scriptlevel=\"bogus\"><mspace width=\"1em\"/></mstyle>").width, em, accuracy: 0.01)
        XCTAssertEqual(try innerBox("<mstyle scriptlevel=\"-1\"><mspace width=\"1em\"/></mstyle>").width, em / 0.71, accuracy: 0.01,
                       "a negative level enlarges, as MathML's math-depth does")
    }

    func testScriptsSitAtTheFontsShifts() throws {
        // A digit's ink starts at its baseline, so its bottom shows the shift.
        let base = try innerBox("<mi>x</mi>")
        let superShift = max(constant(\.superscriptShiftUp), base.ascent - constant(\.superscriptBaselineDropMax), constant(\.superscriptBottomMin))
        let power = try XCTUnwrap(try inks("<msup><mi>x</mi><mn mathcolor=\"red\">1</mn></msup>")[.red])
        XCTAssertEqual(power.minY, superShift, accuracy: 0.75)
        let digit = try innerBox("<mstyle scriptlevel=\"1\"><mn>1</mn></mstyle>")
        let subShift = max(constant(\.subscriptShiftDown), base.descent + constant(\.subscriptBaselineDropMin), digit.ascent - constant(\.subscriptTopMax))
        let index = try XCTUnwrap(try inks("<msub><mi>x</mi><mn mathcolor=\"red\">1</mn></msub>")[.red])
        XCTAssertEqual(index.minY, -subShift, accuracy: 0.75)
        // The limits the font sets on any script.
        for script in ["<mn>1</mn>", "<mi>g</mi>", "<mi>f</mi>", "<mi>j</mi>", "<mfrac><mi>a</mi><mi>b</mi></mfrac>", "<mo>′</mo>"] {
            let raised = try XCTUnwrap(try inks("<msup><mi>x</mi><mrow mathcolor=\"red\">\(script)</mrow></msup>")[.red], script)
            XCTAssertGreaterThanOrEqual(raised.minY, constant(\.superscriptBottomMin) - pixel, "superscript \(script) keeps SuperscriptBottomMin")
            let lowered = try XCTUnwrap(try inks("<msub><mi>x</mi><mrow mathcolor=\"red\">\(script)</mrow></msub>")[.red], script)
            XCTAssertLessThanOrEqual(lowered.maxY, constant(\.subscriptTopMax) + pixel, "subscript \(script) keeps SubscriptTopMax")
        }
    }

    func testScriptsFollowATallOrDeepBase() throws {
        let tall = "<mspace width=\"1em\" height=\"3em\" depth=\"2em\"/>"
        let power = try XCTUnwrap(try inks("<msup>\(tall)<mn mathcolor=\"red\">1</mn></msup>")[.red])
        XCTAssertEqual(power.minY, 3 * em - constant(\.superscriptBaselineDropMax), accuracy: 0.75)
        let index = try XCTUnwrap(try inks("<msub>\(tall)<mn mathcolor=\"red\">1</mn></msub>")[.red])
        XCTAssertEqual(index.minY, -(2 * em + constant(\.subscriptBaselineDropMin)), accuracy: 0.75)
        // On a stretched fence: (…)² puts the 2 at the top of the parenthesis.
        let found = try inks("<msup><mrow><mo>(</mo><mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mi>c</mi></mfrac><mo>)</mo></mrow><mn mathcolor=\"red\">2</mn></msup>",
                             display: true)
        let fences = try XCTUnwrap(found[.black]), two = try XCTUnwrap(found[.red])
        XCTAssertGreaterThan(two.minY, fences.maxY - constant(\.superscriptBaselineDropMax) - 0.4 * em)
        XCTAssertGreaterThan(two.minX, fences.maxX - 2)
    }

    func testSubAndSuperscriptKeepTheMinimumGap() throws {
        let minimum = constant(\.subSuperscriptGapMin)
        for (sub, sup) in [("<mn>1</mn>", "<mn>2</mn>"), ("<mi>f</mi>", "<mi>g</mi>"), ("<mi>b</mi>", "<mi>j</mi>"),
                           ("<mfrac><mi>a</mi><mi>b</mi></mfrac>", "<mfrac><mi>c</mi><mi>d</mi></mfrac>")] {
            for element in ["msubsup", "mmultiscripts"] {
                let found = try inks("<\(element)><mi>x</mi><mrow mathcolor=\"blue\">\(sub)</mrow><mrow mathcolor=\"red\">\(sup)</mrow></\(element)>")
                let lower = try XCTUnwrap(found[.blue]), upper = try XCTUnwrap(found[.red])
                XCTAssertGreaterThanOrEqual(upper.minY - lower.maxY, minimum - pixel, "\(element): \(sub) and \(sup)")
            }
        }
        // Scripts that would collide end exactly the minimum apart.
        let high = "<mspace width=\"1em\" height=\"2em\" mathbackground=\"blue\"/>", deep = "<mspace width=\"1em\" depth=\"2em\" height=\"1ex\" mathbackground=\"red\"/>"
        let forced = try inks("<msubsup><mi>x</mi>\(high)\(deep)</msubsup>")
        XCTAssertEqual(try XCTUnwrap(forced[.red]).minY - (try XCTUnwrap(forced[.blue])).maxY, minimum, accuracy: pixel)
        // With both scripts neither sits higher or lower than it would alone.
        let both = try inks("<msubsup><mi>x</mi><mn mathcolor=\"blue\">1</mn><mn mathcolor=\"red\">2</mn></msubsup>")
        let power = try XCTUnwrap(try inks("<msup><mi>x</mi><mn mathcolor=\"red\">2</mn></msup>")[.red])
        let index = try XCTUnwrap(try inks("<msub><mi>x</mi><mn mathcolor=\"blue\">1</mn></msub>")[.blue])
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(both[.red]).minY, power.minY - 0.01)
        XCTAssertLessThanOrEqual(try XCTUnwrap(both[.blue]).minY, index.minY + 0.01)
    }

    func testScriptsFollowTheBaseWithItsItalicCorrection() throws {
        // An upright base: both scripts start where it ends.
        let upright = try inks("<msubsup><mi mathvariant=\"normal\">H</mi><mn mathcolor=\"blue\">1</mn><mn mathcolor=\"red\">1</mn></msubsup>")
        XCTAssertEqual(try XCTUnwrap(upright[.blue]).minX, try XCTUnwrap(upright[.red]).minX, accuracy: 0.3)
        XCTAssertGreaterThan(try XCTUnwrap(upright[.blue]).minX, try XCTUnwrap(upright[.black]).maxX - 0.3)
        // A slanted base: the subscript tucks in by the italic correction, the superscript does not.
        for base in ["<mi>f</mi>", "<mi>V</mi>", "<mi>T</mi>", "<mrow><mi>f</mi></mrow>"] {
            let found = try inks("<msubsup>\(base)<mn mathcolor=\"blue\">1</mn><mn mathcolor=\"red\">1</mn></msubsup>")
            let correction = try innerBox(base).italicCorrection
            XCTAssertGreaterThan(correction, 0.2, base)
            XCTAssertEqual(try XCTUnwrap(found[.red]).minX - (try XCTUnwrap(found[.blue])).minX, correction, accuracy: 0.3, base)
        }
        // An integral's limits as scripts lean with it.
        for display in [false, true] {
            let integral = try inks("<msubsup><mo>∫</mo><mn mathcolor=\"blue\">0</mn><mn mathcolor=\"red\">1</mn></msubsup>", display: display)
            XCTAssertGreaterThan(try XCTUnwrap(integral[.red]).minX, try XCTUnwrap(integral[.blue]).minX + 1, "display \(display)")
        }
    }

    func testAScriptedBoxIsItsPartsPlusTheSpaceAfterAScript() throws {
        let x = try innerBox("<mi mathvariant=\"normal\">x</mi>").width
        let two = try innerBox("<mstyle scriptlevel=\"1\"><mn>2</mn></mstyle>").width, wide = try innerBox("<mstyle scriptlevel=\"1\"><mn>1000</mn></mstyle>").width
        let space = constant(\.spaceAfterScript)
        let base = "<mi mathvariant=\"normal\">x</mi>"
        XCTAssertEqual(try innerBox("<msup>\(base)<mn>2</mn></msup>").width, x + two + space, accuracy: 0.01)
        XCTAssertEqual(try innerBox("<msub>\(base)<mn>2</mn></msub>").width, x + two + space, accuracy: 0.01)
        XCTAssertEqual(try innerBox("<msubsup>\(base)<mn>2</mn><mn>1000</mn></msubsup>").width, x + wide + space, accuracy: 0.01, "the wider script")
        XCTAssertEqual(try innerBox("<msubsup>\(base)<mn>1000</mn><mn>2</mn></msubsup>").width, x + wide + space, accuracy: 0.01)
    }

    // MARK: Multiscripts

    func testMultiscriptsAbbreviateTheOtherScriptElements() throws {
        let base = "<mi>f</mi>", sub = "<mi>i</mi>", sup = "<mn>2</mn>"
        for display in [false, true] {
            try assertSameBox("<mmultiscripts>\(base)\(sub)\(sup)</mmultiscripts>", "<msubsup>\(base)\(sub)\(sup)</msubsup>", display: display)
            try assertSameBox("<mmultiscripts>\(base)\(sub)<none/></mmultiscripts>", "<msub>\(base)\(sub)</msub>", display: display)
            try assertSameBox("<mmultiscripts>\(base)<none/>\(sup)</mmultiscripts>", "<msup>\(base)\(sup)</msup>", display: display)
            try assertSameBox("<mmultiscripts>\(base)</mmultiscripts>", base, display: display, "a base alone")
            try assertSameBox("<mmultiscripts>\(base)<mprescripts/></mmultiscripts>", base, display: display)
        }
    }

    func testPrescriptsGoBeforeTheBaseAndAlignRight() throws {
        // Carbon-14: a wide presuperscript over a narrow presubscript.
        let found = try inks("<mmultiscripts><mi mathvariant=\"normal\">C</mi><mprescripts/><mn mathcolor=\"blue\">6</mn><mn mathcolor=\"red\">14</mn></mmultiscripts>")
        let base = try XCTUnwrap(found[.black]), lower = try XCTUnwrap(found[.blue]), upper = try XCTUnwrap(found[.red])
        XCTAssertLessThan(upper.maxX, base.minX + pixel)
        XCTAssertLessThan(lower.maxX, base.minX + pixel)
        XCTAssertEqual(lower.maxX, upper.maxX, accuracy: 0.75, "prescripts are right-aligned, against the base")
        XCTAssertGreaterThan(upper.minY, lower.maxY)
        XCTAssertGreaterThan(upper.width, lower.width * 1.5)
        // The same scripts sit at the same heights before the base as after it.
        let after = try inks("<mmultiscripts><mi mathvariant=\"normal\">C</mi><mn mathcolor=\"blue\">6</mn><mn mathcolor=\"red\">14</mn></mmultiscripts>")
        XCTAssertEqual(try XCTUnwrap(after[.blue]).minY, lower.minY, accuracy: 0.3)
        XCTAssertEqual(try XCTUnwrap(after[.red]).minY, upper.minY, accuracy: 0.3)
        XCTAssertGreaterThan(try XCTUnwrap(after[.blue]).minX, try XCTUnwrap(after[.black]).maxX - pixel)
    }

    func testTensorIndicesKeepTheirOrder() throws {
        // R with a lower i, then an upper j, then a lower k: each pair after the last.
        let found = try inks("<mmultiscripts><mi>R</mi><mi mathcolor=\"blue\">i</mi><none/><none/><mi mathcolor=\"red\">j</mi><mi mathcolor=\"lime\">k</mi><none/></mmultiscripts>")
        let first = try XCTUnwrap(found[.blue]), second = try XCTUnwrap(found[.red]), third = try XCTUnwrap(found[.green])
        XCTAssertGreaterThanOrEqual(second.minX, first.maxX - pixel)
        XCTAssertGreaterThanOrEqual(third.minX, second.maxX - pixel)
        XCTAssertGreaterThan(second.midY, first.midY + 0.3 * em, "the upper index is above the lower ones")
        XCTAssertEqual(third.minY, first.minY, accuracy: 1.5, "both subscripts on one line")
        // Scripts on both sides at once.
        let both = try inks("<mmultiscripts><mi mathvariant=\"normal\">X</mi><mn mathcolor=\"red\">1</mn><mn mathcolor=\"red\">2</mn><mprescripts/><mn mathcolor=\"blue\">3</mn><mn mathcolor=\"blue\">4</mn></mmultiscripts>")
        XCTAssertLessThan(try XCTUnwrap(both[.blue]).maxX, try XCTUnwrap(both[.black]).minX + pixel)
        XCTAssertGreaterThan(try XCTUnwrap(both[.red]).minX, try XCTUnwrap(both[.black]).maxX - 3)
    }

    func testScriptElementsNeedTheRightNumberOfChildren() {
        let invalid: [(String, String)] = [
            ("<msub/>", "msub"), ("<msub><mi>x</mi></msub>", "msub"), ("<msub><mi>x</mi><mn>1</mn><mn>2</mn></msub>", "msub"),
            ("<msup><mi>x</mi></msup>", "msup"), ("<msup><mi>x</mi><mn>1</mn><mn>2</mn></msup>", "msup"),
            ("<msubsup><mi>x</mi><mn>1</mn></msubsup>", "msubsup"), ("<msubsup><mi>x</mi><mn>1</mn><mn>2</mn><mn>3</mn></msubsup>", "msubsup"),
            ("<mmultiscripts/>", "mmultiscripts"), ("<mmultiscripts><mi>x</mi><mn>1</mn></mmultiscripts>", "mmultiscripts"),
            ("<mmultiscripts><mi>x</mi><mn>1</mn><mn>2</mn><mprescripts/><mn>3</mn></mmultiscripts>", "mmultiscripts"),
            ("<munder><mi>x</mi></munder>", "munder"), ("<munder><mi>x</mi><mi>y</mi><mi>z</mi></munder>", "munder"),
            ("<mover/>", "mover"), ("<mover><mi>x</mi><mi>y</mi><mi>z</mi></mover>", "mover"),
            ("<munderover><mi>x</mi><mi>y</mi></munderover>", "munderover"), ("<munderover><mi>x</mi><mi>y</mi><mi>z</mi><mi>w</mi></munderover>", "munderover"),
        ]
        for (body, element) in invalid {
            XCTAssertThrowsError(try typeset(body), body) { XCTAssertEqual($0 as? MathLayoutError, .invalidMarkup(element), body) }
        }
    }

    // MARK: Limits

    private func limits(_ op: String, attributes: String = "", display: Bool) throws -> (op: CGRect, under: CGRect, over: CGRect) {
        let found = try inks("<munderover><mo \(attributes)>\(op)</mo><mrow mathcolor=\"blue\"><mi>i</mi><mo>=</mo><mn>1</mn></mrow><mi mathcolor=\"red\">n</mi></munderover>",
                             display: display)
        return (try XCTUnwrap(found[.black]), try XCTUnwrap(found[.blue]), try XCTUnwrap(found[.red]))
    }

    func testLimitsStackOnLargeOperatorsInDisplayStyle() throws {
        for op in ["∑", "∏", "⋃", "⋂", "⨁"] {
            let found = try limits(op, display: true)
            XCTAssertGreaterThanOrEqual(found.over.minY, found.op.maxY + constant(\.upperLimitGapMin) - pixel, "\(op) upper gap")
            XCTAssertLessThanOrEqual(found.under.maxY, found.op.minY - constant(\.lowerLimitGapMin) + pixel, "\(op) lower gap")
            XCTAssertLessThan(found.over.minY, found.op.maxY + em, "\(op): the limit stays near its operator")
            XCTAssertGreaterThan(found.under.maxY, found.op.minY - em, op)
            XCTAssertEqual(found.over.midX, found.op.midX, accuracy: 1.5, "\(op) upper limit centred")
            XCTAssertEqual(found.under.midX, found.op.midX, accuracy: 1.5, "\(op) lower limit centred")
        }
        // The limits are script-sized, and their operators keep no spacing.
        let n = try XCTUnwrap(Rendering(try typeset("<mi>n</mi>")).bounds())
        let found = try limits("∑", display: true)
        XCTAssertEqual(found.over.height / n.height, scriptScale, accuracy: 0.08)
        let unspaced = try innerBox("<mstyle scriptlevel=\"1\"><mi>i</mi><mo lspace=\"0\" rspace=\"0\">=</mo><mn>1</mn></mstyle>").width
        XCTAssertEqual(found.under.width, unspaced, accuracy: 2)
    }

    func testMovableLimitsBecomeScriptsInTextStyle() throws {
        for op in ["∑", "∏", "⋃"] {
            let found = try limits(op, display: false)
            XCTAssertGreaterThan(found.over.minX, found.op.maxX - 2, "\(op): the upper limit moves beside the operator")
            XCTAssertGreaterThan(found.under.minX, found.op.maxX - 2, op)
            XCTAssertGreaterThan(found.over.minY, found.under.maxY, op)
            // The same layout as msubsup.
            let limits = "<mrow><mi>i</mi><mo>=</mo><mn>1</mn></mrow><mi>n</mi>"
            try assertSameBox("<munderover><mo>\(op)</mo>\(limits)</munderover>", "<msubsup><mo>\(op)</mo>\(limits)</msubsup>")
            try assertSameBox("<munder><mo>\(op)</mo><mi>i</mi></munder>", "<msub><mo>\(op)</mo><mi>i</mi></msub>")
            try assertSameBox("<mover><mo>\(op)</mo><mi>n</mi></mover>", "<msup><mo>\(op)</mo><mi>n</mi></msup>")
        }
        // displaystyle decides, wherever it is set.
        let stacked = try innerBox("<munderover><mo>∑</mo><mi>i</mi><mi>n</mi></munderover>", display: true)
        let beside = try innerBox("<munderover><mo>∑</mo><mi>i</mi><mi>n</mi></munderover>")
        XCTAssertGreaterThan(stacked.height, beside.height + 0.5 * em)
        XCTAssertEqual(try innerBox("<mstyle displaystyle=\"true\"><munderover><mo>∑</mo><mi>i</mi><mi>n</mi></munderover></mstyle>").height, stacked.height, accuracy: 0.01)
        XCTAssertEqual(try innerBox("<mstyle displaystyle=\"false\"><munderover><mo>∑</mo><mi>i</mi><mi>n</mi></munderover></mstyle>", display: true).height,
                       beside.height, accuracy: 0.01)
        XCTAssertEqual(try innerBox("<mfrac><munderover><mo>∑</mo><mi>i</mi><mi>n</mi></munderover><mn>2</mn></mfrac>", display: true).width,
                       try innerBox("<mfrac><msubsup><mo>∑</mo><mi>i</mi><mi>n</mi></msubsup><mn>2</mn></mfrac>", display: true).width, accuracy: 0.01,
                       "a display fraction's parts are in text style")
    }

    func testMovableLimitsCanBeTurnedOffAndOn() throws {
        let fixed = try limits("∑", attributes: "movablelimits=\"false\"", display: false)
        XCTAssertGreaterThan(fixed.over.minY, fixed.op.maxY, "movablelimits=false keeps the limits above and below in text style")
        XCTAssertLessThan(fixed.under.maxY, fixed.op.minY)
        XCTAssertEqual(fixed.over.midX, fixed.op.midX, accuracy: 1.5)
        // Integrals do not move their limits in either style.
        for display in [false, true] {
            let integral = try limits("∫", display: display)
            XCTAssertGreaterThan(integral.over.minY, integral.op.maxY, "display \(display)")
            XCTAssertLessThan(integral.under.maxY, integral.op.minY, "display \(display)")
            XCTAssertGreaterThanOrEqual(integral.over.midX, integral.under.midX - 0.5, "an integral's limits lean with it")
        }
        let moved = try limits("∫", attributes: "movablelimits=\"true\"", display: false)
        XCTAssertGreaterThan(moved.under.minX, moved.op.maxX - 4, "movablelimits=true moves an integral's limits too")
    }

    func testNamedLimitOperators() throws {
        for name in ["lim", "max", "min", "sup", "inf", "det", "gcd"] {
            let body = "<munder><mo>\(name)</mo><mrow mathcolor=\"blue\"><mi>x</mi><mo>→</mo><mn>0</mn></mrow></munder>"
            let below = try inks(body, display: true)
            let word = try XCTUnwrap(below[.black]), under = try XCTUnwrap(below[.blue])
            XCTAssertLessThan(under.maxY, word.minY, "\(name): the limit goes underneath in display style")
            XCTAssertEqual(under.midX, word.midX, accuracy: 1.5, name)
            let beside = try inks(body)
            XCTAssertGreaterThan(try XCTUnwrap(beside[.blue]).minX, try XCTUnwrap(beside[.black]).maxX - 2, "\(name): a subscript in text style")
        }
        // An identifier is not an operator: its underscript stays underneath.
        let identifier = try inks("<munder><mi>lim</mi><mi mathcolor=\"blue\">x</mi></munder>")
        XCTAssertLessThan(try XCTUnwrap(identifier[.blue]).maxY, try XCTUnwrap(identifier[.black]).minY)
    }

    // MARK: Under and over

    func testUnderAndOverScriptsAreCentredWithTheFontsGaps() throws {
        for base in ["<mi>x</mi>", "<mi>A</mi><mi>B</mi><mi>C</mi>", "<mi>g</mi><mi>f</mi>"] {
            for display in [false, true] {
                let found = try inks("<munderover><mrow>\(base)</mrow><mi mathcolor=\"blue\">b</mi><mi mathcolor=\"red\">a</mi></munderover>", display: display)
                let middle = try XCTUnwrap(found[.black]), under = try XCTUnwrap(found[.blue]), over = try XCTUnwrap(found[.red])
                XCTAssertEqual(over.minY, middle.maxY + constant(\.overbarVerticalGap), accuracy: 0.75, "\(base) over gap")
                XCTAssertEqual(under.maxY, middle.minY - constant(\.underbarVerticalGap), accuracy: 0.75, "\(base) under gap")
                XCTAssertEqual(over.midX, middle.midX, accuracy: 0.15 * em, "\(base) over centred")
                XCTAssertEqual(under.midX, middle.midX, accuracy: 0.15 * em, "\(base) under centred")
            }
        }
        // munder and mover place their one script where munderover does.
        let both = try inks("<munderover><mi>x</mi><mi mathcolor=\"blue\">b</mi><mi mathcolor=\"red\">a</mi></munderover>")
        XCTAssertEqual(try XCTUnwrap(try inks("<mover><mi>x</mi><mi mathcolor=\"red\">a</mi></mover>")[.red]).minY, try XCTUnwrap(both[.red]).minY, accuracy: 0.3)
        XCTAssertEqual(try XCTUnwrap(try inks("<munder><mi>x</mi><mi mathcolor=\"blue\">b</mi></munder>")[.blue]).maxY, try XCTUnwrap(both[.blue]).maxY, accuracy: 0.3)
        // A script wider than its base widens the box, and the base stays centred under it.
        let wide = try inks("<mover><mi>x</mi><mtext mathcolor=\"red\">a wide label</mtext></mover>")
        XCTAssertEqual(try XCTUnwrap(wide[.black]).midX, try XCTUnwrap(wide[.red]).midX, accuracy: 0.15 * em)
        XCTAssertGreaterThan(try XCTUnwrap(wide[.black]).minX, em)
    }

    func testUnderAndOverScriptsAreScriptSizedUnlessAccents() throws {
        let letter = try XCTUnwrap(Rendering(try typeset("<mi mathvariant=\"normal\">o</mi>")).bounds())
        let script = "<mi mathvariant=\"normal\" mathcolor=\"red\">o</mi>"
        XCTAssertEqual(try XCTUnwrap(try inks("<mover><mi>x</mi>\(script)</mover>")[.red]).height / letter.height, scriptScale, accuracy: 0.08)
        XCTAssertEqual(try XCTUnwrap(try inks("<munder><mi>x</mi>\(script)</munder>")[.red]).height / letter.height, scriptScale, accuracy: 0.08)
        XCTAssertEqual(try XCTUnwrap(try inks("<mover accent=\"true\"><mi>x</mi>\(script)</mover>")[.red]).height, letter.height, accuracy: pixel)
        XCTAssertEqual(try XCTUnwrap(try inks("<munder accentunder=\"true\"><mi>x</mi>\(script)</munder>")[.red]).height, letter.height, accuracy: pixel)
        XCTAssertEqual(try XCTUnwrap(try inks("<munderover accent=\"true\"><mi>x</mi><mi>b</mi>\(script)</munderover>")[.red]).height, letter.height, accuracy: pixel)
        XCTAssertEqual(try XCTUnwrap(try inks("<munderover accentunder=\" TRUE \"><mi>x</mi>\(script)<mi>a</mi></munderover>")[.red]).height, letter.height,
                       accuracy: pixel)
    }

    // MARK: Accents

    func testAccentsSitJustAboveTheirBase() throws {
        for accent in ["^", "~", "¯", "˙", "¨", "ˇ", "˘", "´", "`", "˚"] {
            for base in ["<mi mathvariant=\"normal\">x</mi>", "<mi mathvariant=\"normal\">A</mi>", "<mi mathvariant=\"normal\">b</mi>", "<mi>x</mi>", "<mi>f</mi>"] {
                let found = try inks("<mover>\(base)<mo mathcolor=\"red\">\(accent)</mo></mover>")
                let letter = try XCTUnwrap(found[.black]), mark = try XCTUnwrap(found[.red], "\(accent) over \(base)"), label = "\(accent) over \(base)"
                XCTAssertGreaterThanOrEqual(mark.minY, letter.maxY - 0.75, "the accent clears its base: \(label)")
                XCTAssertLessThan(mark.minY, letter.maxY + 0.3 * em, "and stays close to it: \(label)")
                XCTAssertGreaterThan(mark.midX, letter.minX, "over the base: \(label)")
                XCTAssertLessThan(mark.midX, letter.maxX + 0.1 * em, "over the base: \(label)")
            }
            // Over an upright symmetric letter the accent is centred.
            let centred = try inks("<mover><mi mathvariant=\"normal\">o</mi><mo mathcolor=\"red\">\(accent)</mo></mover>")
            XCTAssertEqual(try XCTUnwrap(centred[.red]).midX, try XCTUnwrap(centred[.black]).midX, accuracy: 0.08 * em, "\(accent) over o")
        }
    }

    func testTheAccentAttributeOverridesTheDictionary() throws {
        // A hat is an accent by the dictionary. accent="false" makes it an ordinary, script-sized overscript.
        let natural = try inks("<mover><mi>x</mi><mo mathcolor=\"red\">^</mo></mover>")
        let explicit = try inks("<mover accent=\"true\"><mi>x</mi><mo mathcolor=\"red\">^</mo></mover>")
        let script = try inks("<mover accent=\"false\"><mi>x</mi><mo mathcolor=\"red\">^</mo></mover>")
        XCTAssertEqual(try XCTUnwrap(natural[.red]), try XCTUnwrap(explicit[.red]))
        XCTAssertLessThan(try XCTUnwrap(script[.red]).height, try XCTUnwrap(natural[.red]).height, "a script-sized hat is thinner")
        // The operator's own accent attribute counts when the mover has none, and the mover's wins.
        let viaOperator = try inks("<mover><mi>x</mi><mo accent=\"false\" mathcolor=\"red\">^</mo></mover>")
        XCTAssertEqual(try XCTUnwrap(viaOperator[.red]), try XCTUnwrap(script[.red]))
        let overridden = try inks("<mover accent=\"true\"><mi>x</mi><mo accent=\"false\" mathcolor=\"red\">^</mo></mover>")
        XCTAssertEqual(try XCTUnwrap(overridden[.red]), try XCTUnwrap(natural[.red]))
        // An identifier made an accent keeps its size and sits on the base.
        let letter = try inks("<mover accent=\"true\"><mi>x</mi><mi mathcolor=\"red\">a</mi></mover>")
        let ordinary = try inks("<mover><mi>x</mi><mi mathcolor=\"red\">a</mi></mover>")
        XCTAssertGreaterThan(try XCTUnwrap(letter[.red]).height, try XCTUnwrap(ordinary[.red]).height * 1.2)
    }

    // MARK: Horizontal stretching

    private let wideBase = "<mrow><mi>a</mi><mo>+</mo><mi>b</mi><mo>+</mo><mi>c</mi><mo>+</mo><mi>d</mi></mrow>"

    func testStretchyScriptsCoverAWideBase() throws {
        // Bars, arrows and braces have assemblies, so they span the whole base.
        for (element, script) in [("mover", "¯"), ("mover", "‾"), ("mover", "→"), ("mover", "←"), ("mover", "↔"), ("mover", "⏞"), ("mover", "⇒"),
                                  ("munder", "_"), ("munder", "⏟"), ("munder", "→"), ("munder", "‾")] {
            let found = try inks("<\(element)>\(wideBase)<mo mathcolor=\"red\">\(script)</mo></\(element)>")
            let base = try XCTUnwrap(found[.black]), stretched = try XCTUnwrap(found[.red], script), label = "\(script) in \(element)"
            XCTAssertGreaterThanOrEqual(stretched.width, base.width * 0.92, label)
            XCTAssertLessThanOrEqual(stretched.width, base.width * 1.15 + 2, "not overstretched: \(label)")
            XCTAssertEqual(stretched.midX, base.midX, accuracy: 0.1 * em, label)
            if element == "mover" { XCTAssertGreaterThan(stretched.minY, base.maxY - pixel, label) } else { XCTAssertLessThan(stretched.maxY, base.minY + pixel, label) }
        }
        // Hats and tildes have a few wider forms: wider than over one letter, as far as the font goes.
        for accent in ["^", "~", "ˇ"] {
            let narrow = try XCTUnwrap(try inks("<mover><mi>x</mi><mo mathcolor=\"red\">\(accent)</mo></mover>")[.red])
            let wide = try XCTUnwrap(try inks("<mover><mrow><mi>x</mi><mi>y</mi><mi>z</mi></mrow><mo mathcolor=\"red\">\(accent)</mo></mover>")[.red])
            XCTAssertGreaterThan(wide.width, narrow.width * 1.5, accent)
        }
        // stretchy="false" keeps the natural glyph.
        let fixed = try XCTUnwrap(try inks("<mover>\(wideBase)<mo stretchy=\"false\" mathcolor=\"red\">→</mo></mover>")[.red])
        XCTAssertLessThan(fixed.width, 1.5 * em)
    }

    func testAStretchyBaseCoversItsScripts() throws {
        for arrow in ["→", "←", "↔", "⇒", "⟶", "↦"] {
            for body in ["<mover><mo>\(arrow)</mo><mtext mathcolor=\"red\">a long label</mtext></mover>",
                         "<munder><mo>\(arrow)</mo><mtext mathcolor=\"red\">a long label</mtext></munder>",
                         "<munderover><mo>\(arrow)</mo><mtext mathcolor=\"red\">a long label</mtext><mi mathcolor=\"red\">k</mi></munderover>"] {
                let found = try inks(body)
                let stretched = try XCTUnwrap(found[.black]), label = try XCTUnwrap(found[.red])
                XCTAssertGreaterThanOrEqual(stretched.width, label.width * 0.95, body)
                XCTAssertEqual(stretched.midX, label.midX, accuracy: 0.15 * em, body)
            }
        }
        // In a row, the arrow keeps its relation spacing around the whole stack.
        let a = try innerBox("<mi>A</mi>").width, b = try innerBox("<mi>B</mi>").width
        let stack = "<mover><mo>→</mo><mtext>f</mtext></mover>"
        XCTAssertEqual(try innerBox("<mi>A</mi>\(stack)<mi>B</mi>").width - a - b - (try innerBox(stack).width), 10 * em / 18, accuracy: 0.05)
    }

    /// The operator dictionary marks these arrows stretchy. Each should cover a long label,
    /// from the font's glyph assembly where it has one and drawn where it does not, as the
    /// single-shafted long arrows already are.
    func testEveryStretchyArrowInTheDictionaryCoversItsLabel() throws {
        // Fails until https://github.com/vocaro/MathMLLayout/issues/13 is fixed.
        var short: [String] = []
        for arrow in "←→↔↤↦↩↪↼↽⇀⇁⇐⇒⇔⇚⇛⟵⟶⟷⟸⟹⟺⟼⇋⇌⇄⇆↠↣".unicodeScalars {
            let found = try inks("<mover><mo>\(arrow)</mo><mtext mathcolor=\"red\">a long label</mtext></mover>")
            let stretched = try XCTUnwrap(found[.black]), label = try XCTUnwrap(found[.red])
            if stretched.width < label.width * 0.95 { short.append("\(arrow) U+\(String(arrow.value, radix: 16, uppercase: true))") }
        }
        XCTAssertEqual(short, [], "arrows that stay at their natural width under a long label")
    }

    func testBracesTakeLabels() throws {
        // An underbrace with a label beneath it.
        let found = try inks("<munder><munder>\(wideBase)<mo mathcolor=\"red\">⏟</mo></munder><mtext mathcolor=\"blue\">four terms</mtext></munder>")
        let base = try XCTUnwrap(found[.black]), brace = try XCTUnwrap(found[.red]), label = try XCTUnwrap(found[.blue])
        XCTAssertLessThan(brace.maxY, base.minY + pixel)
        XCTAssertLessThan(label.maxY, brace.minY + pixel)
        XCTAssertGreaterThanOrEqual(brace.width, base.width * 0.92)
        XCTAssertEqual(label.midX, brace.midX, accuracy: 0.15 * em)
        let over = try inks("<mover><mover>\(wideBase)<mo mathcolor=\"red\">⏞</mo></mover><mi mathcolor=\"blue\">n</mi></mover>")
        XCTAssertGreaterThan(try XCTUnwrap(over[.blue]).minY, try XCTUnwrap(over[.red]).maxY - pixel)
        XCTAssertGreaterThan(try XCTUnwrap(over[.red]).minY, try XCTUnwrap(over[.black]).maxY - pixel)
    }

    func testStretchingIsDrawnWithoutAMathFont() throws {
        // Helvetica has no MATH table: bars, arrows and braces are drawn to the base's width.
        for (element, script) in [("mover", "¯"), ("mover", "→"), ("mover", "←"), ("mover", "↔"), ("mover", "⏞"), ("munder", "_"), ("munder", "⏟")] {
            let layout = try typeset("<\(element)>\(wideBase)<mo mathcolor=\"red\">\(script)</mo></\(element)>", font: "Helvetica")
            let rendering = Rendering(layout), label = "\(script) in \(element) with Helvetica"
            let base = try XCTUnwrap(rendering.bounds(.black), label), stretched = try XCTUnwrap(rendering.bounds(.red), label)
            XCTAssertGreaterThanOrEqual(stretched.width, base.width * 0.9, label)
            XCTAssertLessThanOrEqual(stretched.width, base.width * 1.1 + 2, label)
            if element == "mover" { XCTAssertGreaterThan(stretched.minY, base.maxY - 1, label) } else { XCTAssertLessThan(stretched.maxY, base.minY + 1, label) }
            assertBoxCoversInk(layout, label)
        }
        // And every kind of fence is drawn to its content's height.
        let tall = "<mrow mathcolor=\"red\"><mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mfrac><mi>c</mi><mi>d</mi></mfrac></mfrac></mrow>"
        for (open, close) in [("(", ")"), ("[", "]"), ("{", "}"), ("|", "|"), ("‖", "‖"), ("⌈", "⌉"), ("⌊", "⌋"), ("⟨", "⟩")] {
            let layout = try typeset("<mo>\(open)</mo>\(tall)<mo>\(close)</mo>", display: true, font: "Helvetica")
            let rendering = Rendering(layout), label = "\(open) \(close) with Helvetica"
            let fences = try XCTUnwrap(rendering.bounds(.black), label), content = try XCTUnwrap(rendering.bounds(.red), label)
            XCTAssertGreaterThanOrEqual(fences.height, content.height - em / 2 - 1, label)
            XCTAssertLessThan(fences.minX, content.minX, label)
            XCTAssertGreaterThan(fences.maxX, content.maxX, label)
            assertBoxCoversInk(layout, label)
        }
    }

    // MARK: Embellished operators

    func testScriptedOperatorsKeepTheirSpacing() throws {
        // An operator with scripts or limits is still that operator to the row around it.
        let a = try innerBox("<mi>a</mi>").width, b = try innerBox("<mi>b</mi>").width
        for (embellished, expected) in [("<msub><mo>+</mo><mn>2</mn></msub>", 8.0), ("<msup><mo>=</mo><mo>*</mo></msup>", 10),
                                        ("<mover><mo>=</mo><mtext>def</mtext></mover>", 10), ("<munder><mo>=</mo><mi>k</mi></munder>", 10),
                                        ("<munderover><mo>→</mo><mi>u</mi><mi>v</mi></munderover>", 10), ("<mrow><mo>+</mo></mrow>", 8),
                                        ("<mstyle mathcolor=\"red\"><mo>+</mo></mstyle>", 8), ("<mphantom><mo>+</mo></mphantom>", 8),
                                        ("<mpadded><mo>+</mo></mpadded>", 8), ("<mrow><mspace width=\"0\"/><mo>=</mo></mrow>", 10),
                                        ("<mmultiscripts><mo>+</mo><mn>1</mn><mn>2</mn></mmultiscripts>", 8), ("<semantics><mo>=</mo></semantics>", 10)] {
            let alone = try innerBox(embellished).width
            let spacing = (try innerBox("<mi>a</mi>\(embellished)<mi>b</mi>").width - a - b - alone) * 18 / em
            XCTAssertEqual(spacing, CGFloat(expected), accuracy: 0.05, embellished)
        }
    }
}
