import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

final class RowFenceRegressionTests: MathTestCase {
    private let tall = "<mspace width=\"1em\" height=\"4em\" depth=\"2em\"/>"
    private let newline = "<mo form=\"infix\" linebreak=\"newline\">=</mo>"
    private let pair = "<mo mathcolor=\"red\">(</mo><mi>x</mi><mo mathcolor=\"red\">)</mo>"

    private func lines(_ body: String, width: CGFloat = .infinity) throws -> MathLines {
        try LayoutEngine.lines(node(body), style: MathStyle(fontSize: 20, color: black),
                               maximumWidth: width, firstRowMaximumWidth: nil)
    }

    private func coloredInk(_ box: MathBox, _ color: String, at origin: CGPoint = .zero) -> CGRect? {
        let tint = MathColor.parse(color)!
        var ink: CGRect?
        func merge(_ rect: CGRect) {
            let rect = rect.offsetBy(dx: origin.x, dy: origin.y)
            ink = ink.map { $0.union(rect) } ?? rect
        }
        for item in box.items {
            switch item {
            case .glyphs(let run): if run.color == tint, !run.ink.isNull { merge(run.ink) }
            case .rect(let rect, let color): if color == tint { merge(rect) }
            case .path(let path, let width, let color, _), .dashes(let path, let width, let color, _):
                if color == tint { merge(path.boundingBoxOfPath.insetBy(dx: -width / 2, dy: -width / 2)) }
            case .box(let child, let point):
                if let part = coloredInk(child, color, at: CGPoint(x: origin.x + point.x, y: origin.y + point.y)) {
                    ink = ink.map { $0.union(part) } ?? part
                }
            case .image: break
            }
        }
        return ink
    }

    private func assertInk(_ actual: CGRect?, _ expected: CGRect?, _ message: String = "",
                           file: StaticString = #filePath, line: UInt = #line) {
        guard let actual, let expected else {
            XCTAssertEqual(actual, expected, message, file: file, line: line)
            return
        }
        for (a, b) in zip([actual.minX, actual.minY, actual.width, actual.height],
                          [expected.minX, expected.minY, expected.width, expected.height]) {
            XCTAssertEqual(a, b, accuracy: 0.001, message, file: file, line: line)
        }
    }

    func testWholePairShrinksAndCompactsFollowingText() throws {
        let tail = "<mi mathcolor=\"blue\">tail</mi>"
        let whole = try lines(tall + "<mo form=\"infix\">=</mo>" + pair + tail)
        let broken = try lines(tall + newline + pair + tail)
        let plain = try lines("<mo form=\"infix\" lspace=\"0\">=</mo>" + pair + tail)
        XCTAssertEqual(broken.rows.count, 2)
        let large = try XCTUnwrap(coloredInk(whole.rows[0].box, "red"))
        let small = try XCTUnwrap(coloredInk(broken.rows[1].box, "red"))
        XCTAssertGreaterThan(large.height, small.height * 2)
        assertInk(small, try XCTUnwrap(coloredInk(plain.rows[0].box, "red")))
        XCTAssertEqual(broken.rows[1].box.width, plain.rows[0].box.width, accuracy: 0.001)
        assertInk(coloredInk(broken.rows[1].box, "blue"), coloredInk(plain.rows[0].box, "blue"))
    }

    func testSplitPairKeepsOriginalSize() throws {
        let body = "<mo mathcolor=\"red\">(</mo>" + tall + newline
            + "<mi>x</mi><mo mathcolor=\"blue\">)</mo>"
        let broken = try lines(body)
        let whole = try lines(body.replacingOccurrences(of: "linebreak=\"newline\"", with: ""))
        XCTAssertEqual(broken.rows.count, 2)
        for (index, tint) in [(0, "red"), (1, "blue")] {
            let original = try XCTUnwrap(coloredInk(whole.rows[0].box, tint))
            let actual = try XCTUnwrap(coloredInk(broken.rows[index].box, tint))
            XCTAssertEqual(actual.height, original.height, accuracy: 0.001)
            XCTAssertEqual(actual.midY, original.midY, accuracy: 0.001)
        }
    }

    func testNestedFencedRowsAndInheritedRelativeStyle() throws {
        let forms = [pair, "<mrow>\(pair)</mrow>",
                     "<mstyle mathcolor=\"red\"><mfenced><mi mathcolor=\"black\">x</mi></mfenced></mstyle>",
                     "<mstyle mathsize=\"150%\"><mrow>\(pair)</mrow></mstyle>",
                     "<mo mathcolor=\"red\">[</mo><mrow>\(pair)</mrow><mo mathcolor=\"red\">]</mo>"]
        for form in forms {
            let broken = try lines(tall + newline + form)
            let plain = try lines("<mo form=\"infix\" lspace=\"0\">=</mo>" + form)
            assertInk(coloredInk(broken.rows[1].box, "red"), coloredInk(plain.rows[0].box, "red"), form)
            XCTAssertEqual(broken.rows[1].box.width, plain.rows[0].box.width, accuracy: 0.001, form)
        }
    }

    func testSplitOuterPairDoesNotKeepWholeInnerPairTall() throws {
        let inner = pair.replacingOccurrences(of: "red", with: "blue")
        let body = "<mo mathcolor=\"red\">(</mo>" + tall + newline + inner
            + "<mo mathcolor=\"red\">)</mo>"
        let broken = try lines(body)
        let whole = try lines(body.replacingOccurrences(of: "linebreak=\"newline\"", with: ""))
        let local = try lines("<mo form=\"infix\" lspace=\"0\">=</mo>" + inner)
        XCTAssertEqual(broken.rows.count, 2)
        let original = try XCTUnwrap(coloredInk(whole.rows[0].box, "red"))
        for row in broken.rows {
            let outer = try XCTUnwrap(coloredInk(row.box, "red"))
            XCTAssertEqual(outer.height, original.height, accuracy: 0.001)
            XCTAssertEqual(outer.midY, original.midY, accuracy: 0.001)
        }
        assertInk(coloredInk(broken.rows[1].box, "blue"), coloredInk(local.rows[0].box, "blue"))
    }

    func testEmbellishedRowsKeepBreaksInsideSpaceLikeContent() throws {
        let opening = "<mo mathcolor=\"red\">(</mo>"
        let closing = "<mo mathcolor=\"red\">)</mo>"
        let forced = "<mi>a</mi><mrow>" + opening + "<mspace linebreak=\"newline\"/>"
            + "<mtext>label</mtext></mrow>" + closing
        let broken = try lines(forced)
        XCTAssertEqual(broken.rows.count, 2)
        XCTAssertNotNil(coloredInk(broken.rows[0].box, "red"))
        XCTAssertNotNil(coloredInk(broken.rows[1].box, "red"))

        let automatic = "<mi>a</mi><mrow>" + opening
            + "<mtext>alpha beta gamma delta epsilon</mtext></mrow>" + closing
        let wrapped = try lines(automatic, width: 80)
        XCTAssertGreaterThan(wrapped.rows.count, 2)
        for row in wrapped.rows { XCTAssertLessThanOrEqual(row.origin.x + row.box.width, 80.001) }
        // The flattened operator's source keeps its metadata; the labels remain ordinary units
        // and keep every glyph when their row is broken into words.
        let source = try LayoutEngine(fontName: nil).layoutRoot(node(automatic), style: MathStyle(fontSize: 20, color: black))
        let before = LineBreakingFuzzTests.marks([source], preservingFences: true)
        let after = LineBreakingFuzzTests.marks(wrapped.rows.map(\.box), preservingFences: true)
        XCTAssertEqual(before, after)
    }

    func testEmbellishedFencesReattachTheirScripts() throws {
        let decorated = "<msup><mo mathcolor=\"red\">(</mo><mi mathcolor=\"blue\">a</mi></msup>"
            + "<mi>x</mi><msub><mo mathcolor=\"red\">)</mo><mi mathcolor=\"blue\">b</mi></msub>"
        let broken = try lines(tall + newline + decorated)
        let plain = try lines("<mo form=\"infix\" lspace=\"0\">=</mo>" + decorated)
        assertInk(coloredInk(broken.rows[1].box, "red"), coloredInk(plain.rows[0].box, "red"))
        assertInk(coloredInk(broken.rows[1].box, "blue"), coloredInk(plain.rows[0].box, "blue"))
        XCTAssertEqual(broken.rows[1].box.width, plain.rows[0].box.width, accuracy: 0.001)
    }

    func testCompactionUpdatesIndentTargetAndCenterAlignment() throws {
        let target = "<mi id=\"target\" mathcolor=\"blue\">tail</mi>"
        let indent = "<mo linebreak=\"newline\" indentalign=\"id\" indenttarget=\"target\">+</mo><mi>z</mi>"
        let broken = try lines(tall + newline + pair + target + indent, width: 400)
        let ink = try XCTUnwrap(coloredInk(broken.rows[1].box, "blue"))
        let glyphBearing = try XCTUnwrap(coloredInk(try lines(target).rows[0].box, "blue")).minX
        XCTAssertEqual(broken.rows[2].origin.x, broken.rows[1].origin.x + ink.minX - glyphBearing, accuracy: 0.001)
        let centered = try lines(tall + newline.replacingOccurrences(of: "linebreak=", with: "indentalign=\"center\" linebreak=") + pair, width: 400)
        XCTAssertEqual(centered.rows[1].origin.x, (400 - centered.rows[1].box.width) / 2, accuracy: 0.001)
    }

    func testFenceNormalizationKeepsScriptOperatorsRulesAndBackgrounds() throws {
        let decorated = "<msup><mo mathcolor=\"red\" mathbackground=\"yellow\">(</mo>"
            + "<mfrac><mo mathcolor=\"green\">+</mo><mi mathcolor=\"blue\">a</mi></mfrac></msup>"
            + "<mi>x</mi><mo mathcolor=\"red\">)</mo>"
        let root = try node(tall + newline + decorated)
        let style = MathStyle(fontSize: 20, color: black)
        let original = try LayoutEngine(fontName: nil).layoutRoot(root, style: style)
        let broken = try LayoutEngine.lines(root, style: style, maximumWidth: .infinity, firstRowMaximumWidth: nil)
        let before = LineBreakingFuzzTests.marks([original], preservingFences: true)
        let after = LineBreakingFuzzTests.marks(broken.rows.map(\.box), preservingFences: true)
        XCTAssertEqual(before, after)
        XCTAssertGreaterThanOrEqual(after.filter { $0.kind == -1 }.count, 2, "background and fraction bar")
        let green = try XCTUnwrap(coloredInk(broken.rows[1].box, "green"))
        let plain = try lines("<mo form=\"infix\" lspace=\"0\">=</mo>" + decorated)
        assertInk(green, coloredInk(plain.rows[0].box, "green"))
    }

    func testShiftedContentKeepsNegativeRowExtents() throws {
        for shift in ["3em", "-3em"] {
            let height = shift.hasPrefix("-") ? shift : "+" + shift
            let depth = shift.hasPrefix("-") ? "+" + String(shift.dropFirst()) : "-" + shift
            let content = "<mpadded height=\"\(height)\" depth=\"\(depth)\" voffset=\"\(shift)\"><mi>x</mi></mpadded>"
            let local = "<mo mathcolor=\"red\">(</mo>\(content)<mo mathcolor=\"red\">)</mo>"
            let broken = try lines(tall + "<mspace linebreak=\"newline\"/>" + local)
            let plain = try lines(local)
            assertInk(coloredInk(broken.rows[1].box, "red"), coloredInk(plain.rows[0].box, "red"), shift)
        }
    }

    func testManyWholePairsRestretchWithBoundedWork() throws {
        func exercise(_ count: Int) throws {
            let body = tall + String(repeating: newline + pair, count: count)
            let broken = try lines(body)
            XCTAssertEqual(broken.rows.count, count + 1)
            let plain = try XCTUnwrap(coloredInk(try lines(pair).rows[0].box, "red"))
            for row in broken.rows.dropFirst() {
                XCTAssertEqual(try XCTUnwrap(coloredInk(row.box, "red")).height, plain.height, accuracy: 0.001)
            }
        }
        try assertCPUScaling(factor: 12, "whole fence pairs across forced rows",
                             baseline: { try exercise(64) }, larger: { try exercise(256) })
    }
}
