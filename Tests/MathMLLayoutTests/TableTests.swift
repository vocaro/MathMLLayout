import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

/// `mtable`, `mtr`, `mtd` and `mlabeledtr` (MathML 3, 3.5), measured with cells of known sizes.
final class TableTests: XCTestCase {
    private let pixel: CGFloat = 0.6
    private let axis = constant(\.axisHeight)
    private var ex: CGFloat { (try? innerBox("<mspace width=\"1ex\"/>").width) ?? 0 }

    /// A coloured cell of exact size, in ems.
    private func cell(_ width: CGFloat, _ height: CGFloat, _ depth: CGFloat, _ color: String, attributes: String = "") -> String {
        "<mtd \(attributes)><mspace width=\"\(width)em\" height=\"\(height)em\" depth=\"\(depth)em\" mathbackground=\"\(color)\"/></mtd>"
    }

    /// Two rows of two cells. Columns are 3em and 2em wide; both rows are 1.5em tall, the first
    /// with a 1em ascent and the second with a 0.5em ascent.
    ///
    ///     red   1 × (1 + 0.5)        blue  2 × (0.5 + 0.25)
    ///     lime  3 × (0.5 + 1)        black 1 × (0.25 + 0.25)
    private func grid(_ attributes: String = "", firstRow: String = "", lastCell: String = "") -> String {
        "<mtable \(attributes)><mtr \(firstRow)>\(cell(1, 1, 0.5, "red"))\(cell(2, 0.5, 0.25, "blue"))</mtr>"
            + "<mtr>\(cell(3, 0.5, 1, "lime"))\(cell(1, 0.25, 0.25, "black", attributes: lastCell))</mtr></mtable>"
    }

    private func cells(_ body: String, display: Bool = false) throws -> (red: CGRect, blue: CGRect, green: CGRect, black: CGRect) {
        let found = try inks(body, display: display)
        return (try XCTUnwrap(found[.red]), try XCTUnwrap(found[.blue]), try XCTUnwrap(found[.green]), try XCTUnwrap(found[.black]))
    }

    // MARK: The grid

    func testDefaultGridGeometry() throws {
        let box = try innerBox(grid()), height = 3 * em + ex
        XCTAssertEqual(box.width, 3 * em + 0.8 * em + 2 * em, accuracy: 0.01, "columns as wide as their widest cells, 0.8em apart")
        XCTAssertEqual(box.height, height, accuracy: 0.01, "rows as tall as their tallest cells, 1ex apart")
        XCTAssertEqual((box.ascent - box.descent) / 2, axis, accuracy: 0.01, "centred on the math axis")
        let found = try cells(grid()), top = box.ascent
        // Cells are centred in their columns.
        XCTAssertEqual(found.red.midX, 1.5 * em, accuracy: pixel)
        XCTAssertEqual(found.green.minX, 0, accuracy: pixel)
        XCTAssertEqual(found.blue.minX, 3.8 * em, accuracy: pixel)
        XCTAssertEqual(found.black.midX, 4.8 * em, accuracy: pixel)
        // Rows align on their baselines: the first is 1em below the top.
        XCTAssertEqual(found.red.maxY, top, accuracy: pixel)
        XCTAssertEqual(found.blue.maxY, top - 0.5 * em, accuracy: pixel)
        XCTAssertEqual(found.red.minY, top - 1.5 * em, accuracy: pixel)
        XCTAssertEqual(found.green.maxY, top - 1.5 * em - ex, accuracy: pixel)
        XCTAssertEqual(found.black.maxY, top - 1.5 * em - ex - 0.25 * em, accuracy: pixel)
        XCTAssertEqual(found.green.minY, -box.descent, accuracy: pixel)
    }

    func testCellsOfRealContentShareBaselinesAndColumns() throws {
        let body = "<mtable><mtr><mtd><mi mathcolor=\"red\">a</mi></mtd><mtd><mfrac mathcolor=\"blue\"><mn>1</mn><mn>2</mn></mfrac></mtd></mtr>"
            + "<mtr><mtd><mi mathcolor=\"lime\">a</mi><mi mathcolor=\"lime\">a</mi><mi mathcolor=\"lime\">a</mi></mtd><mtd><mi>a</mi></mtd></mtr></mtable>"
        let found = try cells(body)
        XCTAssertEqual(found.red.midX, found.green.midX, accuracy: 1, "one column")
        XCTAssertEqual(found.blue.midX, found.black.midX, accuracy: 1)
        XCTAssertEqual(found.green.minY, found.black.minY, accuracy: 0.3, "one baseline")
        XCTAssertGreaterThan(found.red.minY, found.green.maxY, "rows do not overlap")
        XCTAssertGreaterThan(found.blue.minY, found.black.maxY)
        XCTAssertGreaterThan(found.blue.minX, found.green.maxX + 0.7 * em)
        // The letter beside a fraction sits on the fraction's baseline, not its middle.
        let letter = try XCTUnwrap(try inks("<mi mathcolor=\"red\">a</mi><mfrac mathcolor=\"blue\"><mn>1</mn><mn>2</mn></mfrac>")[.red])
        let fraction = try XCTUnwrap(try inks("<mi mathcolor=\"red\">a</mi><mfrac mathcolor=\"blue\"><mn>1</mn><mn>2</mn></mfrac>")[.blue])
        XCTAssertEqual(found.red.minY - found.blue.minY, letter.minY - fraction.minY, accuracy: 0.5)
    }

    func testColumnAlign() throws {
        XCTAssertEqual(try cells(grid("columnalign=\"left\"")).red.minX, 0, accuracy: pixel)
        XCTAssertEqual(try cells(grid("columnalign=\"left\"")).black.minX, 3.8 * em, accuracy: pixel, "one value applies to every column")
        XCTAssertEqual(try cells(grid("columnalign=\"right\"")).red.maxX, 3 * em, accuracy: pixel)
        XCTAssertEqual(try cells(grid("columnalign=\"right\"")).black.maxX, 5.8 * em, accuracy: pixel)
        let mixed = try cells(grid("columnalign=\" Right  left \""))
        XCTAssertEqual(mixed.red.maxX, 3 * em, accuracy: pixel); XCTAssertEqual(mixed.black.minX, 3.8 * em, accuracy: pixel)
        XCTAssertEqual(try cells(grid("columnalign=\"center\"")).red.midX, 1.5 * em, accuracy: pixel)
        // A row's value beats the table's, and a cell's beats the row's.
        let byRow = try cells(grid("columnalign=\"right\"", firstRow: "columnalign=\"left\""))
        XCTAssertEqual(byRow.red.minX, 0, accuracy: pixel); XCTAssertEqual(byRow.black.maxX, 5.8 * em, accuracy: pixel)
        let byCell = try cells(grid("columnalign=\"right\"", lastCell: "columnalign=\"left\""))
        XCTAssertEqual(byCell.black.minX, 3.8 * em, accuracy: pixel); XCTAssertEqual(byCell.red.maxX, 3 * em, accuracy: pixel)
        XCTAssertEqual(try cells(grid("columnalign=\"bogus\"")).red.midX, 1.5 * em, accuracy: pixel, "an unknown value centres")
    }

    func testRowAndColumnSpacing() throws {
        let tight = try innerBox(grid("rowspacing=\"0\" columnspacing=\"0\""))
        XCTAssertEqual(tight.width, 5 * em, accuracy: 0.01); XCTAssertEqual(tight.height, 3 * em, accuracy: 0.01)
        let loose = try innerBox(grid("rowspacing=\"1em\" columnspacing=\"2em\""))
        XCTAssertEqual(loose.width, 7 * em, accuracy: 0.01); XCTAssertEqual(loose.height, 4 * em, accuracy: 0.01)
        XCTAssertEqual(try innerBox(grid("rowspacing=\"2ex\" columnspacing=\"10px\"")).height, 3 * em + 2 * ex, accuracy: 0.01)
        XCTAssertEqual(try innerBox(grid("rowspacing=\"2ex\" columnspacing=\"10px\"")).width, 5 * em + 10, accuracy: 0.01)
        XCTAssertEqual(try innerBox(grid("rowspacing=\"-1em\" columnspacing=\"-1em\"")).width, 5 * em, accuracy: 0.01, "negative spacing is none")
        XCTAssertEqual(try innerBox(grid("rowspacing=\"bogus\" columnspacing=\"bogus\"")).width, 5.8 * em, accuracy: 0.01, "invalid spacing is the default")
        XCTAssertEqual(try innerBox(grid("columnspacing=\"thickmathspace\"")).width, 5 * em + 5 * em / 18, accuracy: 0.01)
        // One value per gap; the last repeats.
        let three = "<mtable columnspacing=\"1em 2em\" rowspacing=\"0\"><mtr>\(cell(1, 1, 0, "red"))\(cell(1, 1, 0, "blue"))\(cell(1, 1, 0, "lime"))\(cell(1, 1, 0, "black"))</mtr></mtable>"
        let found = try cells(three)
        XCTAssertEqual(found.blue.minX - found.red.maxX, em, accuracy: pixel)
        XCTAssertEqual(found.green.minX - found.blue.maxX, 2 * em, accuracy: pixel)
        XCTAssertEqual(found.black.minX - found.green.maxX, 2 * em, accuracy: pixel)
    }

    // MARK: Frame and lines

    /// The grid with cells that draw nothing, so the only ink is the table's own lines.
    private func lines(_ attributes: String) throws -> (ink: CGRect?, box: MathBox) {
        let body = grid(attributes).replacingOccurrences(of: " mathbackground=\"red\"", with: "").replacingOccurrences(of: " mathbackground=\"blue\"", with: "")
            .replacingOccurrences(of: " mathbackground=\"lime\"", with: "").replacingOccurrences(of: " mathbackground=\"black\"", with: "")
        return (Rendering(try typeset(body)).bounds(), try innerBox(body))
    }

    func testFrame() throws {
        XCTAssertNil(try lines("").ink)
        XCTAssertNil(try lines("frame=\"none\"").ink)
        for style in ["solid", "dashed"] {
            let (ink, box) = try lines("frame=\"\(style)\"")
            let frame = try XCTUnwrap(ink, style)
            XCTAssertEqual(box.width, 5.8 * em + 2 * 0.4 * em, accuracy: 0.01, "default framespacing is 0.4em each side")
            XCTAssertEqual(box.height, 3 * em + ex + 2 * 0.5 * ex, accuracy: 0.01, "and 0.5ex above and below")
            XCTAssertEqual(frame.minX, 0, accuracy: pixel, style); XCTAssertEqual(frame.maxX, box.width, accuracy: pixel, style)
            XCTAssertEqual(frame.maxY, box.ascent, accuracy: pixel, style); XCTAssertEqual(frame.minY, -box.descent, accuracy: pixel, style)
        }
        let spaced = try lines("frame=\"solid\" framespacing=\"1em 2ex\"").box
        XCTAssertEqual(spaced.width, 5.8 * em + 2 * em, accuracy: 0.01); XCTAssertEqual(spaced.height, 3 * em + ex + 4 * ex, accuracy: 0.01)
        XCTAssertEqual(try lines("framespacing=\"1em 2ex\"").box.width, 5.8 * em, accuracy: 0.01, "framespacing needs a frame")
        // The framed cells are inset by the frame spacing.
        XCTAssertEqual(try cells(grid("frame=\"solid\" columnalign=\"left\"")).green.minX, 0.4 * em, accuracy: pixel)
    }

    func testFrameSpacingOfZero() throws {
        // Fails until https://github.com/vocaro/MathMLLayout/issues/17 is fixed.
        let tight = try lines("frame=\"solid\" framespacing=\"0 0\"").box
        XCTAssertEqual(tight.width, 5.8 * em, accuracy: 0.01, "framespacing=\"0 0\" puts the frame against the cells")
        XCTAssertEqual(tight.height, 3 * em + ex, accuracy: 0.01)
        XCTAssertEqual(try lines("frame=\"solid\" framespacing=\"0em 0ex\"").box.width, 5.8 * em, accuracy: 0.01)
    }

    func testRowAndColumnLines() throws {
        let box = try innerBox(grid()), top = box.ascent
        for style in ["solid", "dashed"] {
            let row = try XCTUnwrap(try lines("rowlines=\"\(style)\"").ink, style)
            XCTAssertEqual(row.midY, top - 1.5 * em - ex / 2, accuracy: pixel, "a row line is half-way through the gap")
            XCTAssertEqual(row.minX, 0, accuracy: 1.5, style); XCTAssertEqual(row.maxX, box.width, accuracy: 1.5, style)
            XCTAssertLessThan(row.height, 3)
            let column = try XCTUnwrap(try lines("columnlines=\"\(style)\"").ink, style)
            XCTAssertEqual(column.midX, 3.4 * em, accuracy: pixel, "a column line is half-way through the gap")
            XCTAssertEqual(column.maxY, top, accuracy: 1.5, style); XCTAssertEqual(column.minY, -box.descent, accuracy: 1.5, style)
            XCTAssertLessThan(column.width, 3)
        }
        XCTAssertNil(try lines("rowlines=\"none\" columnlines=\"none\"").ink)
        // One value per gap; the last repeats. Three rows: no line, then a line.
        let rows = (0..<4).map { _ in "<mtr><mtd><mspace width=\"2em\" height=\"1em\"/></mtd></mtr>" }.joined()
        let partial = try XCTUnwrap(Rendering(try typeset("<mtable rowlines=\"none solid\" rowspacing=\"1em\">\(rows)</mtable>")).bounds())
        let table = try innerBox("<mtable rowlines=\"none solid\" rowspacing=\"1em\">\(rows)</mtable>")
        XCTAssertEqual(partial.maxY, table.ascent - 3.5 * em, accuracy: 1, "the first gap has no line")
        XCTAssertEqual(partial.minY, table.ascent - 5.5 * em, accuracy: 1, "the second and third do")
    }

    // MARK: align

    func testAlign() throws {
        let height = 3 * em + ex
        func extents(_ align: String) throws -> (ascent: CGFloat, descent: CGFloat) {
            let box = try innerBox(grid("align=\"\(align)\""))
            XCTAssertEqual(box.height, height, accuracy: 0.01, align)
            return (box.ascent, box.descent)
        }
        XCTAssertEqual(try extents("axis").ascent, height / 2 + axis, accuracy: 0.01)
        XCTAssertEqual(try extents("center").ascent, height / 2, accuracy: 0.01)
        XCTAssertEqual(try extents("baseline").ascent, height / 2, accuracy: 0.01, "baseline, without a row, is the centre (MathML 3)")
        XCTAssertEqual(try extents("top").ascent, 0, accuracy: 0.01, "the table hangs from the baseline")
        XCTAssertEqual(try extents("bottom").descent, 0, accuracy: 0.01, "the table stands on the baseline")
        XCTAssertEqual(try extents(" TOP ").ascent, 0, accuracy: 0.01)
        XCTAssertEqual(try extents("bogus").ascent, height / 2 + axis, accuracy: 0.01, "an unknown value is the default")
        // With a row number, that row takes the place: row 1 is 1em + 0.5em, row 2 is 0.5em + 1em.
        XCTAssertEqual(try extents("baseline 1").ascent, em, accuracy: 0.01)
        XCTAssertEqual(try extents("baseline 2").ascent, 1.5 * em + ex + 0.5 * em, accuracy: 0.01)
        XCTAssertEqual(try extents("baseline -1").ascent, 1.5 * em + ex + 0.5 * em, accuracy: 0.01, "negative numbers count from the bottom")
        XCTAssertEqual(try extents("baseline -2").ascent, em, accuracy: 0.01)
        XCTAssertEqual(try extents("top 2").ascent, 1.5 * em + ex, accuracy: 0.01)
        XCTAssertEqual(try extents("bottom 1").ascent, 1.5 * em, accuracy: 0.01)
        XCTAssertEqual(try extents("center 1").ascent, 0.75 * em, accuracy: 0.01)
        XCTAssertEqual(try extents("center 2").ascent, 1.5 * em + ex + 0.75 * em, accuracy: 0.01)
        XCTAssertEqual(try extents("baseline 0").ascent, height / 2, accuracy: 0.01, "row 0 does not exist: ignored")
        XCTAssertEqual(try extents("baseline x").ascent, height / 2, accuracy: 0.01)
        // A row-aligned table of text reads along the line: x = [a; b] with the first row on the baseline.
        let found = try inks("<mi mathcolor=\"red\">x</mi><mtable align=\"baseline 1\"><mtr><mtd><mi mathcolor=\"blue\">x</mi></mtd></mtr><mtr><mtd><mi>x</mi></mtd></mtr></mtable>")
        XCTAssertEqual(try XCTUnwrap(found[.red]).minY, try XCTUnwrap(found[.blue]).minY, accuracy: 0.01)
    }

    /// MathML 3, 3.5.1.2: with a row number, "axis" aligns that row's axis with the
    /// environment's, which puts the row's baseline on the baseline; and a row number that is
    /// out of range is ignored.
    func testAlignWithARowNumberFollowsMathML3() throws {
        // Fails until https://github.com/vocaro/MathMLLayout/issues/11 is fixed.
        func ascent(_ align: String) throws -> CGFloat { try innerBox(grid("align=\"\(align)\"")).ascent }
        XCTAssertEqual(try ascent("axis 1"), try ascent("baseline 1"), accuracy: 0.01, "axis 1: row 1's axis on the axis")
        XCTAssertEqual(try ascent("axis 2"), try ascent("baseline 2"), accuracy: 0.01, "axis 2")
        XCTAssertEqual(try ascent("top 9"), try ascent("top"), accuracy: 0.01, "an out-of-range row number is ignored")
        XCTAssertEqual(try ascent("bottom -9"), try ascent("bottom"), accuracy: 0.01)
    }

    // MARK: Style in cells

    private let fractionCell = "<mfrac><mi>a</mi><mi>b</mi></mfrac>"

    func testCellsAreInTextStyleByDefault() throws {
        // MathML Core 3.5.1: displaystyle is false in a table whatever surrounds it.
        let text = try innerBox(fractionCell), display = try innerBox(fractionCell, display: true)
        XCTAssertGreaterThan(display.height, text.height + 2)
        for outer in [false, true] {
            XCTAssertEqual(try innerBox("<mtable><mtr><mtd>\(fractionCell)</mtd></mtr></mtable>", display: outer).height, text.height, accuracy: 0.01)
        }
        // displaystyle on a row or a cell, or an mstyle in the cell, turns it on.
        for body in ["<mtable><mtr displaystyle=\"true\"><mtd>\(fractionCell)</mtd></mtr></mtable>",
                     "<mtable><mtr><mtd displaystyle=\"true\">\(fractionCell)</mtd></mtr></mtable>",
                     "<mtable><mtr><mtd><mstyle displaystyle=\"true\">\(fractionCell)</mstyle></mtd></mtr></mtable>"] {
            XCTAssertEqual(try innerBox(body).height, display.height, accuracy: 0.01, body)
        }
        // The script level is the surroundings': a cell's em is the table's.
        XCTAssertEqual(try innerBox("<mtable><mtr><mtd><mspace width=\"1em\"/></mtd></mtr></mtable>").width, em, accuracy: 0.01)
        XCTAssertEqual(try innerBox("<mstyle scriptlevel=\"1\"><mtable><mtr><mtd><mspace width=\"1em\"/></mtd></mtr></mtable></mstyle>").width, 0.7 * em, accuracy: 0.01)
    }

    /// MathML 3, 3.5.1.2 and MathML Core 3.5.1: `<mtable displaystyle="true">` sets its cells in
    /// display style. LaTeX converters write aligned equations and `cases` this way.
    func testDisplayStyleOnTheTableReachesItsCells() throws {
        // Fails until https://github.com/vocaro/MathMLLayout/issues/6 is fixed.
        let display = try innerBox(fractionCell, display: true), text = try innerBox(fractionCell)
        for outer in [false, true] {
            let table = try innerBox("<mtable displaystyle=\"true\"><mtr><mtd>\(fractionCell)</mtd></mtr></mtable>", display: outer)
            XCTAssertEqual(table.height, display.height, accuracy: 0.01, "mtable displaystyle=true, outer display \(outer)")
            XCTAssertEqual(table.width, display.width, accuracy: 0.01)
        }
        XCTAssertEqual(try innerBox("<mtable displaystyle=\"false\"><mtr><mtd>\(fractionCell)</mtd></mtr></mtable>", display: true).height, text.height, accuracy: 0.01)
        // A sum in an aligned display keeps its limits above and below.
        let stacked = try innerBox("<munderover><mo>∑</mo><mi>i</mi><mi>n</mi></munderover>", display: true)
        XCTAssertEqual(try innerBox("<mtable displaystyle=\"true\"><mtr><mtd><munderover><mo>∑</mo><mi>i</mi><mi>n</mi></munderover></mtd></mtr></mtable>").height,
                       stacked.height, accuracy: 0.01)
    }

    func testStyleAttributesOnRowsAndCellsAreInherited() throws {
        let body = "<mtable><mtr mathcolor=\"red\"><mtd><mi>a</mi></mtd><mtd mathcolor=\"blue\"><mi>b</mi></mtd></mtr>"
            + "<mtr><mtd mathvariant=\"bold\" mathcolor=\"lime\"><mi>c</mi></mtd><mtd><mi>d</mi></mtd></mtr></mtable>"
        let found = try cells(body)
        XCTAssertLessThan(found.red.maxX, found.blue.minX)
        XCTAssertLessThan(found.green.maxY, found.red.minY)
        let bold = try innerBox("<mtable><mtr><mtd mathvariant=\"bold\"><mi>c</mi></mtd></mtr></mtable>").width
        XCTAssertEqual(bold, try innerBox("<mi mathvariant=\"bold\">c</mi>").width, accuracy: 0.01)
        XCTAssertEqual(try innerBox("<mtable mathsize=\"40px\"><mtr><mtd><mspace width=\"1em\"/></mtd></mtr></mtable>").width, 40, accuracy: 0.01)
    }

    // MARK: Labels

    func testLabeledRows() throws {
        func labeled(_ attributes: String = "") -> String {
            "<mtable \(attributes)><mlabeledtr><mtd><mtext mathcolor=\"red\">(1)</mtext></mtd>\(cell(3, 1, 0.5, "blue"))</mlabeledtr><mtr>\(cell(2, 1, 0.5, "lime"))</mtr></mtable>"
        }
        let label = try innerBox("<mtext>(1)</mtext>").width
        let right = try inks(labeled()), box = try innerBox(labeled())
        XCTAssertEqual(box.width, 3 * em + 0.8 * em + label, accuracy: 0.01, "grid, minlabelspacing of 0.8em, label")
        XCTAssertEqual(try XCTUnwrap(right[.red]).minX, 3.8 * em, accuracy: 1.5, "the label is at the right by default")
        XCTAssertEqual(try XCTUnwrap(right[.blue]).minX, 0, accuracy: pixel)
        XCTAssertEqual(try XCTUnwrap(right[.green]).midX, 1.5 * em, accuracy: pixel, "the label is not a column: unlabeled rows keep the grid")
        // The label is on its row's baseline: a parenthesis descends below it.
        XCTAssertLessThan(try XCTUnwrap(right[.red]).minY, try XCTUnwrap(right[.blue]).minY + 0.5 * em)
        XCTAssertGreaterThan(try XCTUnwrap(right[.red]).minY, try XCTUnwrap(right[.blue]).minY - 0.2 * em)
        for side in ["left", "leftoverlap", "LEFT"] {
            let left = try inks(labeled("side=\"\(side)\""))
            XCTAssertEqual(try XCTUnwrap(left[.blue]).minX, label + 0.8 * em, accuracy: pixel, side)
            XCTAssertLessThan(try XCTUnwrap(left[.red]).maxX, label + 1, side)
        }
        XCTAssertEqual(try innerBox(labeled("minlabelspacing=\"2em\"")).width, 5 * em + label, accuracy: 0.01)
        XCTAssertEqual(try innerBox(labeled("side=\"right\" minlabelspacing=\"0\"")).width, 3 * em + label, accuracy: 0.01)
        // A labeled row with only its label, and one with no children at all.
        XCTAssertNoThrow(try typeset("<mtable><mlabeledtr><mtd><mtext>(1)</mtext></mtd></mlabeledtr><mlabeledtr/></mtable>"))
    }

    // MARK: Irregular tables

    private func assertSameBox(_ a: String, _ b: String, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
        let first = try innerBox(a), second = try innerBox(b), label = message.isEmpty ? "\(a) vs \(b)" : message
        XCTAssertEqual(first.width, second.width, accuracy: 0.01, "width: \(label)", file: file, line: line)
        XCTAssertEqual(first.ascent, second.ascent, accuracy: 0.01, "ascent: \(label)", file: file, line: line)
        XCTAssertEqual(first.descent, second.descent, accuracy: 0.01, "descent: \(label)", file: file, line: line)
    }

    func testRowsAndCellsAreInferred() throws {
        let table = "<mtable><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr><mtr><mtd><mi>c</mi></mtd><mtd><mi>d</mi></mtd></mtr></mtable>"
        try assertSameBox("<mtable><mtr><mi>a</mi><mi>b</mi></mtr><mtr><mi>c</mi><mi>d</mi></mtr></mtable>", table, "cells without mtd")
        let column = "<mtable><mtr><mtd><mi>a</mi></mtd></mtr><mtr><mtd><mi>b</mi></mtd></mtr></mtable>"
        try assertSameBox("<mtable><mi>a</mi><mi>b</mi></mtable>", column, "rows without mtr")
        try assertSameBox("<mtable><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtable>", column, "an mtd directly in a table is a row")
        try assertSameBox("<mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr>", "<mtable><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr></mtable>",
                          "a row outside a table")
        try assertSameBox("<mtd><mi>a</mi><mo>+</mo><mi>b</mi></mtd>", "<mrow><mi>a</mi><mo>+</mo><mi>b</mi></mrow>", "a cell outside a table is a row")
        try assertSameBox("<mtable><mtr><mtd><mi>a</mi><mo>+</mo><mi>b</mi></mtd></mtr></mtable>",
                          "<mtable><mtr><mtd><mrow><mi>a</mi><mo>+</mo><mi>b</mi></mrow></mtd></mtr></mtable>", "a cell infers a row")
    }

    func testRaggedAndEmptyTables() throws {
        // A short row leaves its missing cells empty; the grid is as wide as the longest row.
        let ragged = "<mtable columnspacing=\"1em\"><mtr>\(cell(1, 1, 0, "red"))</mtr><mtr>\(cell(1, 1, 0, "blue"))\(cell(1, 1, 0, "lime"))\(cell(1, 1, 0, "black"))</mtr><mtr/></mtable>"
        XCTAssertEqual(try innerBox(ragged).width, 5 * em, accuracy: 0.01)
        let found = try cells(ragged)
        XCTAssertEqual(found.red.minX, found.blue.minX, accuracy: pixel)
        for body in ["<mtable/>", "<mtable></mtable>", "<mtable><mtr/></mtable>", "<mtable><mtr><mtd/></mtr></mtable>", "<mtable><mtr/><mtr/><mtr/></mtable>",
                     "<mtable frame=\"solid\" rowlines=\"solid\" columnlines=\"solid\"/>", "<mtable align=\"baseline 1\"/>", "<mtr/>", "<mtd/>", "<mlabeledtr/>",
                     "<mtable><mtr><mtd><mtable><mtr/></mtable></mtd></mtr></mtable>"] {
            let layout = try typeset(body)
            XCTAssertTrue(layout.width.isFinite && layout.ascent.isFinite && layout.descent.isFinite, body)
            XCTAssertGreaterThanOrEqual(layout.width, 0, body)
        }
        // Spans are documented as ignored: the cell takes one place and nothing throws.
        try assertSameBox("<mtable><mtr><mtd columnspan=\"2\" rowspan=\"3\"><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr></mtable>",
                          "<mtable><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr></mtable>")
    }

    private func assertInkInsideBox(_ attributes: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let box = try innerBox(grid(attributes))
        let ink = try XCTUnwrap(box.inkBounds, attributes, file: file, line: line)
        XCTAssertGreaterThanOrEqual(ink.minX, -0.01, "left: \(attributes)", file: file, line: line)
        XCTAssertLessThanOrEqual(ink.maxX, box.width + 0.01, "right: \(attributes)", file: file, line: line)
        XCTAssertLessThanOrEqual(ink.maxY, box.ascent + 0.01, "top: \(attributes)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(ink.minY, -box.descent - 0.01, "bottom: \(attributes)", file: file, line: line)
    }

    func testFramesStayInsideTheBox() throws {
        for attributes in ["frame=\"solid\"", "frame=\"dashed\"", "frame=\"solid\" framespacing=\"0.1em 0.1ex\"", "side=\"left\" frame=\"solid\"",
                           "frame=\"solid\" align=\"baseline 2\""] {
            try assertInkInsideBox(attributes)
        }
    }

    /// A table's rules end at its edges: they must not stick out of the box, or through a frame.
    func testRowAndColumnLinesStayInsideTheBox() throws {
        // Fails until https://github.com/vocaro/MathMLLayout/issues/12 is fixed.
        for attributes in ["rowlines=\"solid\"", "columnlines=\"solid\"", "rowlines=\"dashed\" columnlines=\"dashed\"",
                           "frame=\"solid\" rowlines=\"solid\" columnlines=\"solid\""] {
            try assertInkInsideBox(attributes)
        }
    }
}
