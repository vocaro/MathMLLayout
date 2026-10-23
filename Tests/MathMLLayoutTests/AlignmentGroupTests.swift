import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

/// MathML 3 3.5.5: exact space geometry plus the specification's seven-group equations.
final class AlignmentGroupTests: XCTestCase {
    private func space(_ width: Int, _ color: String) -> String {
        "<mspace width='\(width)em' height='1em' mathbackground='\(color)'/>"
    }
    private func row(_ body: String, attributes: String = "", cell: String = "") -> String {
        "<mtr \(attributes)><mtd \(cell)>\(body)</mtd></mtr>"
    }
    private func table(_ first: String, _ second: String, attributes: String = "") -> String {
        "<mtable \(attributes)>\(row(first))\(row(second))</mtable>"
    }
    private func rectangles(_ box: MathBox) -> [CGRect] {
        var found: [CGRect] = []
        func visit(_ box: MathBox, at origin: CGPoint) {
            for item in box.items {
                switch item {
                case .rect(let rect, _): found.append(rect.offsetBy(dx: origin.x, dy: origin.y))
                case .box(let box, let point): visit(box, at: CGPoint(x: origin.x + point.x, y: origin.y + point.y))
                default: break
                }
            }
        }
        visit(box, at: .zero)
        return found
    }
    private func runs(_ box: MathBox) -> [(run: GlyphRun, origin: CGPoint)] {
        var found: [(GlyphRun, CGPoint)] = []
        func visit(_ box: MathBox, at origin: CGPoint) {
            for item in box.items {
                switch item {
                case .glyphs(let run): found.append((run, origin))
                case .box(let box, let point): visit(box, at: CGPoint(x: origin.x + point.x, y: origin.y + point.y))
                default: break
                }
            }
        }
        visit(box, at: .zero)
        return found
    }
    private var first: String { "<maligngroup/>" + space(1, "red") + "<maligngroup/>" + space(2, "blue") }
    private var second: String { "<maligngroup/>" + space(3, "lime") + "<maligngroup/>" + space(1, "black") }

    func testLeftRightAndCenterSideWidths() throws {
        for (alignment, redX) in [("left", 0.0), ("right", 2.0), ("center", 1.0)] {
            let box = try innerBox(table(first, second, attributes: "groupalign='{\(alignment) left}'"))
            XCTAssertEqual(box.width, 5 * em, accuracy: 0.001)
            let rects = rectangles(box)
            XCTAssertEqual(rects.count, 4)
            XCTAssertEqual(rects[0].minX, redX * em, accuracy: 0.001)
            XCTAssertEqual(rects[1].minX, 3 * em, accuracy: 0.001)
            XCTAssertEqual(rects[2].minX, 0, accuracy: 0.001)
            XCTAssertEqual(rects[3].minX, 3 * em, accuracy: 0.001)
        }
    }

    func testExplicitMarksOverrideAutomaticPointsAndIgnoreExtraMarks() throws {
        let a = "<maligngroup/>" + space(1, "red") + "<malignmark edge='right'/>" + space(2, "blue") + "<malignmark/>"
        let b = "<maligngroup/>" + space(3, "lime") + "<malignmark/>" + space(1, "black")
        let box = try innerBox(table(a, b, attributes: "groupalign='{left}'"))
        let rects = rectangles(box)
        XCTAssertEqual(box.width, 5 * em, accuracy: 0.001)
        XCTAssertEqual(rects[0].minX, 2 * em, accuracy: 0.001)
        XCTAssertEqual(rects[1].minX, rects[3].minX, accuracy: 0.001)
    }

    func testGroupsCanCrossNestedRows() throws {
        let a = "<mrow><mrow><maligngroup/>" + space(1, "red") + "</mrow><maligngroup/><mrow>" + space(2, "blue") + "</mrow></mrow>"
        let b = "<mstyle><maligngroup/>" + space(3, "lime") + "<mrow><maligngroup/>" + space(1, "black") + "</mrow></mstyle>"
        let box = try innerBox(table(a, b, attributes: "groupalign='{right left}'"))
        let rects = rectangles(box)
        XCTAssertEqual(box.width, 5 * em, accuracy: 0.001)
        XCTAssertEqual(rects[0].minX, 2 * em, accuracy: 0.001)
        XCTAssertEqual(rects[1].minX, rects[3].minX, accuracy: 0.001)
    }

    func testCellRowAndGroupInheritanceAndRepeatedLists() throws {
        let body = "<mtable groupalign='{left}'>"
            + row(first, attributes: "groupalign='{right left}'")
            + row(second, cell: "groupalign='right left'") + "</mtable>"
        XCTAssertEqual(rectangles(try innerBox(body))[0].minX, 2 * em, accuracy: 0.001)
        let explicit = first.replacingOccurrences(of: "<maligngroup/>", with: "<maligngroup groupalign='right'/>")
        let rects = rectangles(try innerBox(table(explicit, second, attributes: "groupalign='{right}'")))
        XCTAssertEqual(rects[0].minX, 2 * em, accuracy: 0.001)
        XCTAssertEqual(rects[1].maxX, rects[3].maxX, accuracy: 0.001)
        XCTAssertEqual(AlignmentValues.column("{right left} {center}", index: 8), ["center"])
    }

    func testStyleGroupalignDefaultsApplyToTablesAndCanBeOverridden() throws {
        let styled = "<mstyle groupalign='{right left}'>" + table(first, second) + "</mstyle>"
        XCTAssertEqual(rectangles(try innerBox(styled))[0].minX, 2 * em, accuracy: 0.001)
        let overridden = "<mstyle groupalign='{right left}'>" + table(first, second, attributes: "groupalign='{left}'") + "</mstyle>"
        XCTAssertEqual(rectangles(try innerBox(overridden))[0].minX, 0, accuracy: 0.001)
    }

    func testDeferredStretchyChildrenKeepSourceFirstMarkPriority() throws {
        let engine = LayoutEngine(fontName: nil)
        var context = LayoutContext(fontSize: em, unclampedSize: em, minSize: 8, display: false, color: black)
        context.trackAlignment = true
        let element = try mathML("<mrow><mo>(<malignmark/></mo><mn>123<malignmark/></mn><mspace height='3em'/></mrow>").children[0]
        let box = try engine.layout(element, context, depth: 0)
        let marks = box.alignment.filter { if case .mark = $0.kind { return true }; return false }
        XCTAssertEqual(marks.count, 2)
        XCTAssertLessThan(marks[0].order, marks[1].order)
    }

    func testIndependentColumnsRepeatTheLastBracedList() throws {
        let body = "<mtable columnspacing='0' groupalign='{right} {left}'>"
            + "<mtr><mtd>\(first)</mtd><mtd>\(first)</mtd><mtd>\(first)</mtd></mtr>"
            + "<mtr><mtd>\(second)</mtd><mtd>\(second)</mtd><mtd>\(second)</mtd></mtr></mtable>"
        let rects = rectangles(try innerBox(body))
        XCTAssertEqual(rects[0].minX, 2 * em, accuracy: 0.001)
        XCTAssertEqual(rects[2].minX, 5 * em, accuracy: 0.001)
        XCTAssertEqual(rects[4].minX, 10 * em, accuracy: 0.001)
    }

    func testMissingAndEmptyGroupsAndUnalignedHeading() throws {
        let a = "<maligngroup/>" + space(1, "red")
        let box = try innerBox(table(a, second))
        XCTAssertEqual(box.width, 4 * em, accuracy: 0.001)
        let empty = "<maligngroup/><maligngroup/>" + space(1, "red")
        let rects = rectangles(try innerBox(table(empty, second)))
        XCTAssertEqual(rects[0].minX, 3 * em, accuracy: 0.001, "empty first group remains a distinct source group")
        let heading = "<mtable>" + row(space(10, "black")) + row(first) + row(second) + "</mtable>"
        let shifted = rectangles(try innerBox(heading))
        XCTAssertEqual(shifted[1].minX, 2.5 * em, accuracy: 0.001)
        XCTAssertEqual(shifted[2].minX, shifted[4].minX, accuracy: 0.001)
    }

    func testLabelsDoNotChangeGroupWidthsOrColumnIndices() throws {
        let body = "<mtable groupalign='{right left}'>"
            + "<mlabeledtr><mtd>" + space(10, "black") + "</mtd><mtd>\(first)</mtd></mlabeledtr>"
            + row(second) + "</mtable>"
        let rects = rectangles(try innerBox(body))
        XCTAssertEqual(rects[0].minX, 2 * em, accuracy: 0.001)
        XCTAssertEqual(rects[1].minX, rects[4].minX, accuracy: 0.001)
    }

    func testExplicitTokenMarkPositionsAreRetainedWithoutChangingText() throws {
        let parsed = try mathML("<mn>12<malignmark/>.3<malignmark edge='right'/></mn>").children[0]
        XCTAssertEqual(parsed.text, "12.3")
        XCTAssertEqual(parsed.children.map(\.tokenTextOffset), [2, 4])
        let body = table("<maligngroup/><mn>12<malignmark/>.3</mn>", "<maligngroup/><mn>4<malignmark/>.56</mn>")
        let drawn = runs(try innerBox(body))
        XCTAssertEqual(drawn[0].origin.x + drawn[0].run.positions[2].x,
                       drawn[1].origin.x + drawn[1].run.positions[1].x, accuracy: 0.001)
        XCTAssertEqual(try typeset("<mn>12<malignmark/>.3</mn>").width, try typeset("<mn>12.3</mn>").width, accuracy: 0.001)
    }

    func testDecimalPointAndInheritedCommaAlignAtTheFirstNumber() throws {
        for decimal in [".", ","] {
            let numbers = table("<maligngroup/><mn>12\(decimal)3</mn>", "<maligngroup/><mn>4\(decimal)56</mn>", attributes: "groupalign='{decimalpoint}'")
            let drawn = runs(try innerBox("<mstyle decimalpoint='\(decimal)'>\(numbers)</mstyle>"))
            XCTAssertEqual(drawn[0].origin.x + drawn[0].run.positions[2].x,
                           drawn[1].origin.x + drawn[1].run.positions[1].x, accuracy: 0.001)
        }
        let noDecimal = table("<maligngroup/><mn>12</mn>", "<maligngroup/><mn>4.56</mn>", attributes: "groupalign='{decimalpoint}'")
        let drawn = runs(try innerBox(noDecimal))
        XCTAssertEqual(drawn[0].origin.x + (try innerBox("<mn>12</mn>")).width,
                       drawn[1].origin.x + drawn[1].run.positions[1].x, accuracy: 0.001)
    }

    func testSpecificationSevenGroupSimultaneousEquations() throws {
        func equation(_ a: String, _ sign: String, _ b: String, _ rhs: String) -> String {
            "<mrow><mrow><mrow><maligngroup/><mn>\(a)</mn><mo>&#x2062;</mo><maligngroup/><mi>x</mi></mrow>"
                + "<maligngroup/><mo>\(sign)</mo><mrow><maligngroup/><mn>\(b)</mn><mo>&#x2062;</mo><maligngroup/><mi>y</mi></mrow></mrow>"
                + "<maligngroup/><mo>=</mo><maligngroup/>\(rhs)</mrow>"
        }
        for direction in ["ltr", "rtl"] {
            let body = table(equation("8.44", "+", "55", "<mn>0</mn>"), equation("3.1", "-", "0.7", "<mrow><mo>-</mo><mn>1.1</mn></mrow>"),
                             attributes: "dir='\(direction)' groupalign='{decimalpoint left left decimalpoint left left decimalpoint}'")
            let drawn = runs(try innerBox(body))
            // 7 runs in the first equation, 8 in the second (the negative constant adds a sign).
            XCTAssertEqual(drawn.count, 15)
            guard drawn.count == 15 else { return }
            XCTAssertEqual(drawn[0].origin.x + drawn[0].run.positions[1].x,
                           drawn[7].origin.x + drawn[7].run.positions[1].x, accuracy: 0.001)
            for (a, b) in [(1, 8), (2, 9), (4, 11), (5, 12)] {
                XCTAssertEqual(drawn[a].origin.x + drawn[a].run.positions[0].x,
                               drawn[b].origin.x + drawn[b].run.positions[0].x, accuracy: 0.001)
            }
            XCTAssertEqual(drawn[3].origin.x + (try innerBox("<mn>55</mn>")).width,
                           drawn[10].origin.x + drawn[10].run.positions[1].x, accuracy: 0.001)
        }
    }

    func testAlignmentScopesAndNestedMarks() throws {
        let inert = try innerBox(table(first, second, attributes: "alignmentscope='false'"))
        XCTAssertEqual(inert.width, 4 * em, accuracy: 0.001)
        let scoped = "<mtable alignmentscope='false true' columnspacing='0'><mtr><mtd>\(first)</mtd><mtd>\(first)</mtd></mtr>"
            + "<mtr><mtd>\(second)</mtd><mtd>\(second)</mtd></mtr></mtable>"
        XCTAssertEqual(try innerBox(scoped).width, 9 * em, accuracy: 0.001)
        func inner(_ width: Int, _ scope: String) -> String {
            "<mtable alignmentscope='\(scope)'>" + row(space(width, "red") + "<malignmark edge='right'/>" + space(1, "blue")) + "</mtable>"
        }
        let a = "<maligngroup/>" + inner(1, "false")
        let b = "<maligngroup/>" + space(3, "lime") + "<malignmark edge='right'/>" + space(1, "black")
        let rects = rectangles(try innerBox(table(a, b)))
        XCTAssertEqual(rects[1].minX, rects[3].minX, accuracy: 0.001)
        let opaque = rectangles(try innerBox(table("<maligngroup/>" + inner(1, "true"), b)))
        XCTAssertNotEqual(opaque[1].minX, opaque[3].minX)
    }

    func testDistinctSpanScopesAndUnbreakableGroupsKeepTheirNaturalWidths() throws {
        let span = "<mtable>" + row(first, cell: "columnspan='2'") + row(second, cell: "rowspan='2'") + "</mtable>"
        let spanningBox = try innerBox(span)
        XCTAssertEqual(spanningBox.width, 4.8 * em, accuracy: 0.001, "spanning tracks retain their internal gap")
        XCTAssertEqual(rectangles(spanningBox), rectangles(try innerBox(span.replacingOccurrences(of: "<maligngroup/>", with: ""))),
                       "groups in different column intervals remain independent")
        XCTAssertEqual(try innerBox("<mstyle dir='rtl'>\(table(first, second))</mstyle>").width, 5 * em, accuracy: 0.001)
        let formula = try mathML(table(first, second))
        let narrow = try MathLayout(formula, style: MathStyle(fontSize: em, color: black), maximumWidth: 2 * em)
        XCTAssertEqual(narrow.rows.count, 1)
        XCTAssertEqual(narrow.width, 5 * em, accuracy: 0.001, "these groups contain no legal automatic breaks")
        let forced = "<maligngroup/>" + space(1, "red") + "<mspace linebreak='newline'/>" + space(2, "blue")
        let broken = try typeset(table(forced, second))
        XCTAssertGreaterThan(broken.ascent + broken.descent, 3 * em)
    }


    func testDecimalLookupSkipsScriptAndFractionNumbers() throws {
        let a = "<maligngroup/><msup><mi>x</mi><mn>999.9</mn></msup><mfrac><mn>123.45</mn><mn>6.7</mn></mfrac><mn>12.3</mn>"
        let b = "<maligngroup/><mn>4.56</mn>"
        let drawn = runs(try innerBox(table(a, b, attributes: "groupalign='{decimalpoint}'")))
        XCTAssertEqual(drawn.count, 6)
        guard drawn.count == 6 else { return }
        XCTAssertEqual(drawn[4].origin.x + drawn[4].run.positions[2].x,
                       drawn[5].origin.x + drawn[5].run.positions[1].x, accuracy: 0.001)
    }

    func testExplicitMarksInsideFractionsReachTheOuterScope() throws {
        let a = "<maligngroup/><mfrac><mrow>" + space(1, "red") + "<malignmark edge='right'/>" + space(2, "blue") + "</mrow><mn>1</mn></mfrac>"
        let b = "<maligngroup/><mfrac><mrow>" + space(3, "lime") + "<malignmark/>" + space(1, "black") + "</mrow><mn>2</mn></mfrac>"
        let rects = rectangles(try innerBox(table(a, b)))
        XCTAssertEqual(rects.count, 6, "fraction rules are drawing rectangles too")
        // Each fraction draws its rule first, followed by the two numerator spaces.
        XCTAssertEqual(rects[2].minX, rects[5].minX, accuracy: 0.001)
    }

    func testPhantomGroupsKeepTheirSourceOrder() throws {
        let a = "<mphantom><maligngroup/>" + space(1, "red") + "<maligngroup/>" + space(2, "blue") + "</mphantom><maligngroup/>" + space(1, "black")
        let b = second + "<maligngroup/>" + space(2, "lime")
        let rects = rectangles(try innerBox(table(a, b)))
        XCTAssertEqual(rects[0].minX, rects[3].minX, accuracy: 0.001)
        XCTAssertEqual(try innerBox(table(a, b)).width, 7 * em, accuracy: 0.001)
    }

    func testInvalidLeadingContentAndAlignmentMarkerStylingAreInert() throws {
        let invalid = space(1, "red") + "<maligngroup/>" + space(2, "blue")
        XCTAssertEqual(try innerBox(table(invalid, invalid)).width, 3 * em, accuracy: 0.001)
        let marked = first.replacingOccurrences(of: "<maligngroup/>", with: "<maligngroup mathbackground='red' mathsize='50em'/>")
        XCTAssertEqual(rectangles(try innerBox(table(marked, second))).count, 4, "alignment elements have no background")
    }

    func testGroupSpanningCellBackgroundExpandsToTheAlignedWidth() throws {
        let body = "<mtable groupalign='{right left}'>" + row(first, cell: "mathbackground='black'") + row(second) + "</mtable>"
        let box = try innerBox(body)
        let rects = rectangles(box)
        XCTAssertEqual(rects[0].width, 5 * em, accuracy: 0.001)
        XCTAssertEqual(box.inkBounds?.width ?? 0, box.width, accuracy: 0.001)
    }

    func testGroupedRadicalsEnclosuresAndFractionsStayInsideTheirColumns() throws {
        for body in ["<msqrt><mn>2</mn></msqrt>", "<menclose notation='box'><mn>2</mn></menclose>", "<mfrac><mn>1</mn><mn>2</mn></mfrac>"] {
            let grouped = "<mtable frame='solid' columnspacing='0'><mtr><mtd><maligngroup/>\(body)</mtd><mtd>" + space(1, "red") + "</mtd></mtr></mtable>"
            let box = try innerBox(grouped)
            let ink = try XCTUnwrap(box.inkBounds)
            XCTAssertGreaterThanOrEqual(ink.minX, -0.001)
            XCTAssertLessThanOrEqual(ink.maxX, box.width + 0.001)
            let rect = try XCTUnwrap(rectangles(box).first(where: { $0.height == em }))
            XCTAssertGreaterThanOrEqual(rect.minX, (try innerBox(body)).inkBounds?.width ?? 0)
        }
    }

    func testStretchedOperatorTokenEndUsesItsRenderedWidth() throws {
        let engine = LayoutEngine(fontName: nil)
        var context = LayoutContext(fontSize: em, unclampedSize: em, minSize: 8, display: false, color: black)
        context.trackAlignment = true
        let element = try mathML("<mover><mo>→<malignmark edge='right'/></mo><mspace width='8em'/></mover>").children[0]
        let box = try engine.layout(element, context, depth: 0)
        let mark = try XCTUnwrap(box.alignment.first { if case .mark = $0.kind { return true }; return false })
        XCTAssertEqual(mark.x, box.width, accuracy: 0.001)
        XCTAssertGreaterThan(mark.x, (try innerBox("<mo>→</mo>")).width * 3)
    }

    func testNestedTableInScriptHasItsOwnDecimalBaseline() throws {
        let body = "<msup><mi>x</mi>" + table("<maligngroup/><mn>12.3</mn>", "<maligngroup/><mn>4.56</mn>", attributes: "groupalign='{decimalpoint}'") + "</msup>"
        let drawn = runs(try innerBox(body))
        XCTAssertEqual(drawn[1].origin.x + drawn[1].run.positions[2].x,
                       drawn[2].origin.x + drawn[2].run.positions[1].x, accuracy: 0.001)
    }

    func testInvisibleOperatorMarksOverrideAutomaticAlignmentAndAreCounted() throws {
        let a = "<maligngroup groupalign='right'/><mo>&#x2062;<malignmark/></mo>" + space(1, "red")
        let b = "<maligngroup/>" + space(3, "lime") + "<malignmark edge='right'/>" + space(1, "black")
        let rects = rectangles(try innerBox(table(a, b)))
        XCTAssertEqual(rects[0].minX, rects[2].minX, accuracy: 0.001)
        let marks = Array(repeating: MathMLNode(name: "malignmark"), count: MathLimits.nodes)
        let invisible = MathMLNode(name: "mo", children: marks, text: "\u{2062}")
        XCTAssertThrowsError(try innerBox(invisible)) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded) }
        let number = MathMLNode(name: "mn", children: marks, text: "1")
        XCTAssertThrowsError(try innerBox(number)) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded) }
    }

    func testSelectedActionMarksAddressTheirEnclosingRowNeighbors() throws {
        let a = "<maligngroup/>" + space(1, "red") + "<maction><malignmark/></maction><mo lspace='1em' rspace='0px'>x</mo>"
        let b = "<maligngroup/>" + space(3, "lime") + "<maction selection='2'><mi>unused</mi><malignmark/></maction><mo lspace='0px' rspace='0px'>x</mo>"
        let drawn = runs(try innerBox(table(a, b)))
        XCTAssertEqual(drawn.count, 2)
        XCTAssertEqual(drawn[0].origin.x + drawn[0].run.positions[0].x,
                       drawn[1].origin.x + drawn[1].run.positions[0].x, accuracy: 0.001)
    }

    func testOutsideScopeIsInertAndHostileGroupsStayBounded() throws {
        XCTAssertEqual(try innerBox(first).width, 3 * em, accuracy: 0.001)
        let groups = Array(repeating: MathMLNode(name: "maligngroup"), count: 10_000)
        let body = MathMLNode(name: "mtable", children: [MathMLNode(name: "mtr", children: [MathMLNode(name: "mtd", children: groups)])])
        XCTAssertEqual(try innerBox(body).width, 0)
        let huge = "<maligngroup/>" + String(repeating: "<mspace width='50000px'/>", count: 3) + "<malignmark/>"
        let other = "<maligngroup/><malignmark/>" + String(repeating: "<mspace width='50000px'/>", count: 3)
        XCTAssertThrowsError(try innerBox(table(huge, other))) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded) }
        let tooMany = MathMLNode(name: "mtable", children: [MathMLNode(name: "mtr", children: [MathMLNode(name: "mtd", children: Array(repeating: MathMLNode(name: "maligngroup"), count: MathLimits.nodes))])])
        XCTAssertThrowsError(try innerBox(tooMany)) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded) }
    }
}
