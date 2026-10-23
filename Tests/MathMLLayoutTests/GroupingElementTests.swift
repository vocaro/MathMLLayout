import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

/// The elements that group or adjust other content (MathML 3, 3.3 and 3.7): `math`, `mrow`,
/// `mstyle`, `mpadded`, `mphantom`, `mfenced`, `menclose`, `merror`, `maction`, `semantics`.
final class GroupingElementTests: XCTestCase {
    private let pixel: CGFloat = 0.6

    private func assertSameBox(_ a: String, _ b: String, display: Bool = false, _ message: String = "",
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let first = try innerBox(a, display: display), second = try innerBox(b, display: display)
        let label = message.isEmpty ? "\(a) vs \(b)" : message
        XCTAssertEqual(first.width, second.width, accuracy: 0.01, "width: \(label)", file: file, line: line)
        XCTAssertEqual(first.ascent, second.ascent, accuracy: 0.01, "ascent: \(label)", file: file, line: line)
        XCTAssertEqual(first.descent, second.descent, accuracy: 0.01, "descent: \(label)", file: file, line: line)
    }

    // MARK: Rows

    func testARowSetsItsChildrenOnOneBaseline() throws {
        let found = try inks("<mi mathcolor=\"red\">x</mi><mfrac><mn>1</mn><mn>2</mn></mfrac><msup><mi mathcolor=\"blue\">x</mi><mn>2</mn></msup><msqrt><mi mathcolor=\"lime\">x</mi></msqrt>",
                             display: true)
        let first = try XCTUnwrap(found[.red]), second = try XCTUnwrap(found[.blue]), third = try XCTUnwrap(found[.green])
        XCTAssertEqual(first.minY, second.minY, accuracy: 0.01); XCTAssertEqual(first.minY, third.minY, accuracy: 0.01)
        XCTAssertLessThan(first.maxX, second.minX); XCTAssertLessThan(second.maxX, third.minX)
        // A row's box is the sum of its children's advances and the union of their extents.
        let parts = try ["<mi>x</mi>", "<mfrac><mn>1</mn><mn>2</mn></mfrac>", "<msqrt><mi>y</mi></msqrt>", "<mspace width=\"1em\" height=\"3em\" depth=\"2em\"/>"].map { try innerBox($0) }
        let row = try innerBox("<mi>x</mi><mfrac><mn>1</mn><mn>2</mn></mfrac><msqrt><mi>y</mi></msqrt><mspace width=\"1em\" height=\"3em\" depth=\"2em\"/>")
        XCTAssertEqual(row.width, parts.reduce(0) { $0 + $1.width }, accuracy: 0.01)
        XCTAssertEqual(row.ascent, parts.map(\.ascent).max()!, accuracy: 0.01)
        XCTAssertEqual(row.descent, parts.map(\.descent).max()!, accuracy: 0.01)
    }

    func testGroupingIsTransparent() throws {
        let flat = "<mi>a</mi><mo>+</mo><mi>b</mi>"
        for wrapped in ["<mrow>\(flat)</mrow>", "<mrow><mrow>\(flat)</mrow></mrow>", "<mstyle>\(flat)</mstyle>", "<mrow><mrow><mi>a</mi></mrow><mo>+</mo><mrow><mi>b</mi></mrow></mrow>",
                        "<semantics><mrow>\(flat)</mrow></semantics>", "<maction>\(flat.isEmpty ? "" : "<mrow>\(flat)</mrow>")</maction>", "<mpadded>\(flat)</mpadded>"] {
            try assertSameBox(wrapped, flat)
        }
        let empty = try innerBox("")
        XCTAssertEqual([empty.width, empty.ascent, empty.descent], [0, 0, 0])
        for body in ["<mrow/>", "<mrow><mrow/><mrow/></mrow>", "<mstyle/>", "<mphantom/>", "<mpadded/>", "<semantics/>", "<maction/>", "<none/>", "<mprescripts/>",
                     "<malignmark/>", "<maligngroup/>", "<mi/>", "<mn/>", "<mo/>", "<mtext/>", "<mspace/>"] {
            let box = try innerBox(body)
            XCTAssertEqual([box.width, box.ascent, box.descent], [0, 0, 0], body)
            XCTAssertNil(box.inkBounds, body)
        }
    }

    func testElementsWithAnInferredRowMatchAnExplicitOne() throws {
        let children = "<mi>a</mi><mo>+</mo><mfrac><mn>1</mn><mn>2</mn></mfrac><mo>(</mo><mi>b</mi><mo>)</mo>"
        for element in ["msqrt", "mstyle", "merror", "mpadded", "mphantom", "menclose", "mtd", "mrow"] {
            for display in [false, true] {
                try assertSameBox("<\(element)>\(children)</\(element)>", "<\(element)><mrow>\(children)</mrow></\(element)>", display: display, element)
            }
        }
    }

    // MARK: The math element

    func testDisplayAttributeSelectsDisplayStyle() throws {
        let fraction = MathMLNode(name: "mfrac", children: [mi("a"), mi("b")])
        func height(_ attributes: [String: String], isDisplay: Bool = false) throws -> CGFloat {
            let layout = try MathLayout(MathMLNode(name: "math", attributes: attributes, children: [fraction]),
                                        style: MathStyle(fontSize: em, color: black, isDisplay: isDisplay))
            return layout.ascent + layout.descent
        }
        let text = try height([:]), display = try height(["display": "block"])
        XCTAssertGreaterThan(display, text + 2)
        XCTAssertEqual(try height(["display": "inline"]), text)
        XCTAssertEqual(try height([:], isDisplay: true), display, "the style asks for display")
        XCTAssertEqual(try height(["displaystyle": "true"]), display)
        XCTAssertEqual(try height(["display": "block", "displaystyle": "false"]), text, "displaystyle overrides display")
        XCTAssertEqual(try height(["display": "bogus"]), text)
        // Attributes that say nothing about layout are ignored.
        XCTAssertEqual(try height(["alttext": "a over b", "id": "eq1", "class": "c", "style": "color: red", "dir": "ltr", "href": "#", "xmlns": "x",
                                   "overflow": "scroll", "altimg": "a.png", "mode": "display"]), text)
    }

    /// MathML Core 2.1.2 and 3.1: `display` and the other enumerated attributes match ASCII
    /// case-insensitively, as the engine already does for `displaystyle`, `form` and `columnalign`.
    func testEnumeratedAttributesIgnoreCaseAndSurroundingSpace() throws {
        func height(_ display: String) throws -> CGFloat {
            let layout = try MathLayout(MathMLNode(name: "math", attributes: ["display": display], children: [MathMLNode(name: "mfrac", children: [mi("a"), mi("b")])]),
                                        style: MathStyle(fontSize: em, color: black))
            return layout.ascent + layout.descent
        }
        let block = try height("block")
        XCTAssertEqual(try height("BLOCK"), block, "display=\"BLOCK\"")
        XCTAssertEqual(try height("Block"), block, "display=\"Block\"")
        XCTAssertEqual(try height(" block "), block, "display=\" block \"")
        // mtable's side, likewise.
        let labeled = "<mlabeledtr><mtd><mtext mathcolor=\"red\">(1)</mtext></mtd><mtd><mspace width=\"3em\" height=\"1em\" mathbackground=\"blue\"/></mtd></mlabeledtr>"
        let left = try XCTUnwrap(try inks("<mtable side=\"left\">\(labeled)</mtable>")[.red])
        XCTAssertEqual(try XCTUnwrap(try inks("<mtable side=\" left \">\(labeled)</mtable>")[.red]).minX, left.minX, accuracy: pixel, "side=\" left \"")
    }

    // MARK: mpadded

    /// The box of a 10 × (6 + 4) px space padded with `attributes`.
    private func padded(_ attributes: String) throws -> MathBox {
        try innerBox("<mpadded \(attributes)><mspace width=\"10px\" height=\"6px\" depth=\"4px\"/></mpadded>")
    }

    func testPaddedDimensions() throws {
        let plain = try padded("")
        XCTAssertEqual([plain.width, plain.ascent, plain.descent], [10, 6, 4], "no attributes: the content's own box")
        let widths: [(String, CGFloat)] = [("20px", 20), ("1em", 20), ("+5px", 15), ("-4px", 6), ("200%", 20), ("+50%", 15), ("-50%", 5), ("2", 20), ("0", 0), ("0px", 0),
                                           ("2width", 20), ("1.5height", 9), ("50%depth", 2), ("+1width", 20), ("-0.5width", 5), ("+2height", 22),
                                           ("thickmathspace", 5 * em / 18), (" 20px ", 20), ("bogus", 10), ("", 10)]
        for (value, expected) in widths { XCTAssertEqual(try padded("width=\"\(value)\"").width, expected, accuracy: 0.01, "width=\(value)") }
        let heights: [(String, CGFloat)] = [("9px", 9), ("+2px", 8), ("-2px", 4), ("50%", 3), ("+100%", 12), ("2depth", 8), ("1width", 10), ("0", 0), ("bogus", 6)]
        for (value, expected) in heights { XCTAssertEqual(try padded("height=\"\(value)\"").ascent, expected, accuracy: 0.01, "height=\(value)") }
        let depths: [(String, CGFloat)] = [("1px", 1), ("+1px", 5), ("-1px", 3), ("150%", 6), ("1height", 6), ("0.5width", 5), ("0", 0)]
        for (value, expected) in depths { XCTAssertEqual(try padded("depth=\"\(value)\"").descent, expected, accuracy: 0.01, "depth=\(value)") }
        // Each attribute leaves the other dimensions alone, and they combine.
        let all = try padded("width=\"30px\" height=\"+4px\" depth=\"200%\"")
        XCTAssertEqual([all.width, all.ascent, all.descent], [30, 10, 8])
        XCTAssertEqual(try padded("width=\"30px\"").ascent, 6); XCTAssertEqual(try padded("height=\"30px\"").width, 10)
    }

    /// MathML 3, 3.3.6.2: "specifying a decrement that would produce a net negative value …
    /// has the same effect as setting the attribute to zero … the effective bounding box of an
    /// mpadded element always has non-negative dimensions."
    func testPaddedDimensionsNeverGoNegative() throws {
        XCTAssertEqual(try padded("width=\"-25px\"").width, 0, accuracy: 0.01, "width decremented past zero")
        XCTAssertEqual(try padded("height=\"-25px\"").ascent, 0, accuracy: 0.01, "height decremented past zero")
        XCTAssertEqual(try padded("depth=\"-25px\"").descent, 0, accuracy: 0.01, "depth decremented past zero")
        XCTAssertEqual(try padded("width=\"-300%\"").width, 0, accuracy: 0.01)
        // What follows a padded box is never placed before where it began.
        let found = try inks("<mspace width=\"2em\" height=\"1em\" mathbackground=\"red\"/><mpadded width=\"-5em\"><mspace width=\"1em\"/></mpadded><mspace width=\"1em\" height=\"1em\" mathbackground=\"blue\"/>")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(found[.blue]).minX, try XCTUnwrap(found[.red]).maxX - pixel)
    }

    func testPaddedOffsetsMoveTheContentWithoutResizingTheBox() throws {
        func content(_ attributes: String) throws -> (box: MathBox, ink: CGRect) {
            let box = try innerBox("<mpadded \(attributes)><mspace width=\"10px\" height=\"6px\" depth=\"4px\" mathbackground=\"red\"/></mpadded>")
            return (box, try XCTUnwrap(box.inkBounds))
        }
        let cases: [(String, CGFloat, CGFloat)] = [("", 0, -4), ("lspace=\"5px\"", 5, -4), ("lspace=\"-3px\"", -3, -4), ("lspace=\"0.5width\"", 5, -4),
                                                   ("lspace=\"50%\"", 5, -4), ("voffset=\"3px\"", 0, -1), ("voffset=\"-3px\"", 0, -7), ("voffset=\"1height\"", 0, 2),
                                                   ("lspace=\"2px\" voffset=\"2px\"", 2, -2), ("lspace=\"bogus\" voffset=\"bogus\"", 0, -4)]
        for (attributes, x, y) in cases {
            let found = try content(attributes)
            XCTAssertEqual(found.ink.minX, x, accuracy: 0.01, attributes); XCTAssertEqual(found.ink.minY, y, accuracy: 0.01, attributes)
            XCTAssertEqual([found.box.width, found.box.ascent, found.box.descent], [10, 6, 4], "\(attributes) does not resize the box")
        }
        // The usual idiom: room on both sides.
        let both = try content("width=\"+10px\" lspace=\"5px\"")
        XCTAssertEqual(both.box.width, 20); XCTAssertEqual(both.ink.minX, 5); XCTAssertEqual(both.ink.maxX, 15)
        // A smashed box: content drawn, nothing reserved.
        let smashed = try content("width=\"0\" height=\"0\" depth=\"0\"")
        XCTAssertEqual([smashed.box.width, smashed.box.ascent, smashed.box.descent], [0, 0, 0]); XCTAssertEqual(smashed.ink.width, 10)
    }

    // MARK: mphantom

    func testPhantomsReserveRoomAndDrawNothing() throws {
        for content in ["<mi>x</mi>", "<mfrac><mi>a</mi><mi>b</mi></mfrac>", "<msqrt><mi>x</mi></msqrt>", "<mo>(</mo><mi>x</mi><mo>)</mo>",
                        "<mtable frame=\"solid\"><mtr><mtd><mi>a</mi></mtd></mtr></mtable>", "<menclose notation=\"box\"><mi>x</mi></menclose>",
                        "<mi mathbackground=\"red\">x</mi>", "<merror><mi>x</mi></merror>"] {
            for display in [false, true] {
                try assertSameBox("<mphantom>\(content)</mphantom>", content, display: display)
                XCTAssertNil(try innerBox("<mphantom>\(content)</mphantom>", display: display).inkBounds, content)
            }
        }
        // A phantom fence still stretches, and a phantom strut still stretches real fences.
        let tall = "<mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mi>c</mi></mfrac>"
        try assertSameBox("<mphantom><mo>(</mo></mphantom>\(tall)<mo>)</mo>", "<mo>(</mo>\(tall)<mo>)</mo>", display: true)
        try assertSameBox("<mo>(</mo><mi>x</mi><mphantom>\(tall)</mphantom><mo>)</mo>", "<mo>(</mo><mi>x</mi>\(tall)<mo>)</mo>", display: true)
    }

    // MARK: mfenced

    func testFencedIsTheRowItAbbreviates() throws {
        // MathML 3, 3.3.8.2.
        let a = "<mi>a</mi>", b = "<mi>b</mi>", c = "<mi>c</mi>"
        func comma(_ text: String = ",") -> String { "<mo separator=\"true\">\(text)</mo>" }
        func row(_ open: String, _ inner: String, _ close: String) -> String {
            "<mrow><mo fence=\"true\" form=\"prefix\">\(open)</mo>\(inner)<mo fence=\"true\" form=\"postfix\">\(close)</mo></mrow>"
        }
        for display in [false, true] {
            try assertSameBox("<mfenced>\(a)\(b)</mfenced>", row("(", "<mrow>\(a)\(comma())\(b)</mrow>", ")"), display: display)
            try assertSameBox("<mfenced>\(a)</mfenced>", row("(", a, ")"), display: display, "one child needs no inner row")
            try assertSameBox("<mfenced>\(a)\(b)\(c)</mfenced>", row("(", "<mrow>\(a)\(comma())\(b)\(comma())\(c)</mrow>", ")"), display: display)
            try assertSameBox("<mfenced open=\"[\" close=\"]\">\(a)\(b)</mfenced>", row("[", "<mrow>\(a)\(comma())\(b)</mrow>", "]"), display: display)
            try assertSameBox("<mfenced open=\"{\" close=\"\">\(a)</mfenced>", "<mrow><mo fence=\"true\" form=\"prefix\">{</mo>\(a)</mrow>", display: display,
                              "an empty close draws no fence")
            try assertSameBox("<mfenced open=\"\" close=\"\">\(a)\(b)</mfenced>", "<mrow><mrow>\(a)\(comma())\(b)</mrow></mrow>", display: display)
            try assertSameBox("<mfenced separators=\";\">\(a)\(b)\(c)</mfenced>", row("(", "<mrow>\(a)\(comma(";"))\(b)\(comma(";"))\(c)</mrow>", ")"), display: display,
                              "the last separator repeats")
            try assertSameBox("<mfenced separators=\" ; , \">\(a)\(b)\(c)</mfenced>", row("(", "<mrow>\(a)\(comma(";"))\(b)\(comma())\(c)</mrow>", ")"), display: display,
                              "space in separators is ignored")
            try assertSameBox("<mfenced separators=\";,|\">\(a)\(b)</mfenced>", row("(", "<mrow>\(a)\(comma(";"))\(b)</mrow>", ")"), display: display,
                              "extra separators are unused")
            try assertSameBox("<mfenced separators=\"\">\(a)\(b)\(c)</mfenced>", row("(", "<mrow>\(a)\(b)\(c)</mrow>", ")"), display: display, "no separators")
            try assertSameBox("<mfenced open=\"|\" close=\"|\">\(a)</mfenced>", row("|", a, "|"), display: display)
            try assertSameBox("<mfenced open=\"⟨\" close=\"⟩\" separators=\"|\">\(a)\(b)</mfenced>", row("⟨", "<mrow>\(a)\(comma("|"))\(b)</mrow>", "⟩"), display: display)
        }
        // Its fences stretch like any others.
        let tall = "<mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mi>c</mi></mfrac>"
        try assertSameBox("<mfenced>\(tall)</mfenced>", "<mrow><mo>(</mo>\(tall)<mo>)</mo></mrow>", display: true)
        try assertSameBox("<mfenced open=\"[\" close=\"]\"><mtable><mtr><mtd><mn>1</mn></mtd></mtr><mtr><mtd><mn>2</mn></mtd></mtr></mtable></mfenced>",
                          "<mrow><mo>[</mo><mtable><mtr><mtd><mn>1</mn></mtd></mtr><mtr><mtd><mn>2</mn></mtd></mtr></mtable><mo>]</mo></mrow>")
        XCTAssertGreaterThan(try innerBox("<mfenced/>").width, 0.4 * em, "an empty mfenced is a pair of parentheses")
    }

    // MARK: menclose

    /// An enclosure around a red 2em × (1em + 0.5em) block: the box, the notation's own ink, and
    /// where the content went.
    private func enclosed(_ notation: String?) throws -> (box: MathBox, lines: CGRect?, content: CGRect) {
        let attribute = notation.map { "notation=\"\($0)\"" } ?? ""
        let body = "<menclose \(attribute)><mspace width=\"2em\" height=\"1em\" depth=\"0.5em\" mathbackground=\"red\"/></menclose>"
        let found = try inks(body)
        return (try innerBox(body), found[.black], try XCTUnwrap(found[.red]))
    }

    func testStrikesAndUnknownNotationsDoNotResizeTheContent() throws {
        for notation in ["updiagonalstrike", "downdiagonalstrike", "horizontalstrike", "verticalstrike", "updiagonalstrike downdiagonalstrike",
                         "updiagonalarrow", "no-such-notation", "", "phasorangle"] {
            let found = try enclosed(notation)
            XCTAssertEqual([found.box.width, found.box.ascent, found.box.descent], [2 * em, em, 0.5 * em], notation)
            XCTAssertEqual(found.content.minX, 0, accuracy: pixel, notation)
        }
        for notation in ["no-such-notation", "", "phasorangle", "Box"] { XCTAssertNil(try enclosed(notation).lines, "\(notation) draws nothing") }
        // Each strike crosses the content the way its name says.
        let up = try XCTUnwrap(try inks("<menclose notation=\"updiagonalstrike\"><mspace width=\"2em\" height=\"1em\" depth=\"0.5em\"/></menclose>")[.black])
        XCTAssertEqual(up.width, 2 * em, accuracy: 1.5); XCTAssertEqual(up.height, 1.5 * em, accuracy: 1.5)
        let horizontal = try XCTUnwrap(try inks("<menclose notation=\"horizontalstrike\"><mspace width=\"2em\" height=\"1em\" depth=\"0.5em\"/></menclose>")[.black])
        XCTAssertEqual(horizontal.midY, 0.25 * em, accuracy: pixel, "through the middle of the content")
        XCTAssertEqual(horizontal.width, 2 * em, accuracy: 1.5); XCTAssertLessThan(horizontal.height, 3)
        let vertical = try XCTUnwrap(try inks("<menclose notation=\"verticalstrike\"><mspace width=\"2em\" height=\"1em\" depth=\"0.5em\"/></menclose>")[.black])
        XCTAssertEqual(vertical.midX, em, accuracy: pixel); XCTAssertEqual(vertical.height, 1.5 * em, accuracy: 1.5); XCTAssertLessThan(vertical.width, 3)
    }

    func testFramesPadTheContentAndDrawAtTheBoxEdge() throws {
        for notation in ["box", "roundedbox", "circle"] {
            let found = try enclosed(notation), lines = try XCTUnwrap(found.lines, notation)
            XCTAssertGreaterThan(found.box.width, 2 * em + 4, notation)
            XCTAssertGreaterThan(found.box.ascent, em + 2, notation); XCTAssertGreaterThan(found.box.descent, 0.5 * em + 2, notation)
            // The frame is the box's outline, and the content is centered inside it with clearance.
            XCTAssertEqual(lines.minX, 0, accuracy: pixel, notation); XCTAssertEqual(lines.maxX, found.box.width, accuracy: pixel, notation)
            XCTAssertEqual(lines.maxY, found.box.ascent, accuracy: pixel, notation); XCTAssertEqual(lines.minY, -found.box.descent, accuracy: pixel, notation)
            XCTAssertEqual(found.content.midX, found.box.width / 2, accuracy: pixel, notation)
            XCTAssertGreaterThan(found.content.minX, 2, notation); XCTAssertLessThan(found.content.maxY, found.box.ascent - 2, notation)
            XCTAssertEqual(found.content.minY, -0.5 * em, accuracy: pixel, "the content stays on its baseline: \(notation)")
        }
        let box = try enclosed("box").box, circle = try enclosed("circle").box
        XCTAssertGreaterThan(circle.width, box.width + 4, "an ellipse around the padded box is larger than it")
        XCTAssertGreaterThan(circle.height, box.height + 4)
    }

    func testSideNotationsDrawOnTheirSides() throws {
        let frame = try enclosed("box")
        func lines(_ notation: String) throws -> CGRect {
            let found = try enclosed(notation)
            XCTAssertEqual(found.box.width, frame.box.width, accuracy: 0.01, "\(notation) pads like a box")
            return try XCTUnwrap(found.lines, notation)
        }
        let width = frame.box.width, top = frame.box.ascent, bottom = -frame.box.descent
        let left = try lines("left"), right = try lines("right"), over = try lines("top"), under = try lines("bottom")
        XCTAssertEqual(left.midX, 0, accuracy: 1.5); XCTAssertLessThan(left.width, 3); XCTAssertEqual(left.height, top - bottom, accuracy: 1.5)
        XCTAssertEqual(right.midX, width, accuracy: 1.5); XCTAssertLessThan(right.width, 3)
        XCTAssertEqual(over.midY, top, accuracy: 1.5); XCTAssertLessThan(over.height, 3); XCTAssertEqual(over.width, width, accuracy: 1.5)
        XCTAssertEqual(under.midY, bottom, accuracy: 1.5); XCTAssertLessThan(under.height, 3)
        // Combinations: all four sides are the box; actuarial is top and right; madruwb is bottom and right.
        XCTAssertEqual(try lines("left right top bottom"), try XCTUnwrap(frame.lines))
        XCTAssertEqual(try lines("actuarial"), try lines("top right")); XCTAssertEqual(try lines("madruwb"), try lines("bottom right"))
        XCTAssertEqual(try lines("  top \n left  "), try lines("left top"), "notations are separated by any white space")
        // Long division: a bar over and a curve at the left. It is also the default notation.
        let division = try enclosed("longdiv"), fallback = try enclosed(nil)
        XCTAssertEqual(fallback.box.width, division.box.width); XCTAssertEqual(fallback.lines, division.lines)
        XCTAssertGreaterThan(division.box.width, frame.box.width, "room for the curve")
        XCTAssertEqual(try XCTUnwrap(division.lines).maxY, top, accuracy: pixel)
        XCTAssertLessThan(division.content.maxX, try XCTUnwrap(division.lines).maxX)
    }

    func testEveryNotationKeepsItsInkInsideItsBox() throws {
        let notations = ["box", "roundedbox", "circle", "left", "right", "top", "bottom", "longdiv", "actuarial", "madruwb", "radical",
                         "updiagonalstrike", "downdiagonalstrike", "horizontalstrike", "verticalstrike", "box updiagonalstrike", "circle horizontalstrike",
                         "radical box", "longdiv circle"]
        for notation in notations {
            for content in ["<mi>x</mi>", "<mfrac><mi>a</mi><mi>b</mi></mfrac>", "<mn>1234567</mn>"] {
                let box = try innerBox("<menclose notation=\"\(notation)\">\(content)</menclose>")
                let ink = try XCTUnwrap(box.inkBounds), label = "\(notation) around \(content)"
                XCTAssertGreaterThanOrEqual(ink.minX, -0.15 * em, "left: \(label)"); XCTAssertLessThanOrEqual(ink.maxX, box.width + 0.15 * em, "right: \(label)")
                XCTAssertLessThanOrEqual(ink.maxY, box.ascent + 0.01, "top: \(label)"); XCTAssertGreaterThanOrEqual(ink.minY, -box.descent - 0.01, "bottom: \(label)")
            }
        }
    }

    /// The arrowhead of `updiagonalarrow` is part of the enclosure: it must not be drawn outside
    /// the box, over whatever is next to it.
    func testTheDiagonalArrowStaysInsideItsBox() throws {
        // Content wide, tall and ordinary, and content smaller than the head: a period, a minus sign, a bar.
        let contents = ["<mspace width=\"3em\" height=\"0.5em\"/>", "<mspace width=\"0.5em\" height=\"3em\"/>", "<mi>x</mi>", "<mn>1234567</mn>",
                        "<mo>.</mo>", "<mo>−</mo>", "<mo>|</mo>"]
        for notation in ["updiagonalarrow", "updiagonalstrike updiagonalarrow", "box updiagonalarrow", "circle updiagonalarrow"] {
            for content in contents {
                let box = try innerBox("<menclose notation=\"\(notation)\">\(content)</menclose>"), label = "\(notation) around \(content)"
                let ink = try XCTUnwrap(box.inkBounds)
                XCTAssertLessThanOrEqual(ink.maxX, box.width + 0.01, "right: \(label)"); XCTAssertLessThanOrEqual(ink.maxY, box.ascent + 0.01, "top: \(label)")
                XCTAssertGreaterThanOrEqual(ink.minX, -0.01, "left: \(label)"); XCTAssertGreaterThanOrEqual(ink.minY, -box.descent - 0.01, "bottom: \(label)")
            }
        }
    }

    /// The box makes room for the head where the head needs it, and the arrow is drawn as it was:
    /// from corner to corner of the content, along the strike that converters write with it.
    func testTheDiagonalArrowGrowsItsBoxByItsHead() throws {
        let barb = 0.25 * em
        func enclosure(_ notation: String, _ content: String) throws -> (box: MathBox, lines: CGRect) {
            let body = "<menclose notation=\"\(notation)\">\(content)</menclose>"
            return (try innerBox(body), try XCTUnwrap(try inks(body)[.black], body))
        }
        // Wide content: the upper barb passes the top, and nothing else moves.
        let wide = "<mspace width=\"3em\" height=\"0.5em\"/>"
        let over = try enclosure("updiagonalarrow", wide), strike = try enclosure("updiagonalstrike", wide)
        XCTAssertEqual([over.box.width, over.box.descent], [3 * em, 0], "room above only")
        XCTAssertGreaterThan(over.box.ascent, 0.5 * em + 1); XCTAssertLessThan(over.box.ascent, 0.5 * em + barb / 2, "less than half a barb")
        XCTAssertEqual(over.box.ascent, try XCTUnwrap(over.box.inkBounds).maxY, accuracy: 0.01, "what the head needs and no more")
        XCTAssertEqual(over.lines.minX, strike.lines.minX, accuracy: pixel); XCTAssertEqual(over.lines.minY, strike.lines.minY, accuracy: pixel)
        XCTAssertEqual(over.lines.maxX, strike.lines.maxX, accuracy: pixel, "the tip is the strike's end")
        // Tall content: the lower barb passes the right side.
        let tall = "<mspace width=\"0.5em\" height=\"3em\"/>"
        let beside = try enclosure("updiagonalarrow", tall), upright = try enclosure("updiagonalstrike", tall)
        XCTAssertEqual([beside.box.ascent, beside.box.descent], [3 * em, 0], "room at the right only")
        XCTAssertGreaterThan(beside.box.width, 0.5 * em + 1); XCTAssertLessThan(beside.box.width, 0.5 * em + barb / 2)
        XCTAssertEqual(beside.box.width, try XCTUnwrap(beside.box.inkBounds).maxX, accuracy: 0.01)
        XCTAssertEqual(beside.lines.minX, upright.lines.minX, accuracy: pixel); XCTAssertEqual(beside.lines.maxY, upright.lines.maxY, accuracy: pixel)
        // With the strike the box is the arrow's, and with a frame the room is outside the frame.
        try assertSameBox("<menclose notation=\"updiagonalstrike updiagonalarrow\">\(wide)</menclose>", "<menclose notation=\"updiagonalarrow\">\(wide)</menclose>")
        let framed = try innerBox("<menclose notation=\"box\">\(wide)</menclose>"), both = try innerBox("<menclose notation=\"box updiagonalarrow\">\(wide)</menclose>")
        XCTAssertEqual([both.width, both.descent], [framed.width, framed.descent]); XCTAssertGreaterThan(both.ascent, framed.ascent + 0.5)
        // Content narrower than the head is long has a barb past its left side too, and moves along to make room.
        let narrow = "<menclose notation=\"updiagonalarrow\"><mspace width=\"0.1em\" height=\"1em\" mathbackground=\"red\"/></menclose>"
        let thin = try innerBox(narrow), content = try XCTUnwrap(try inks(narrow)[.red])
        XCTAssertGreaterThan(content.minX, 1, "room at the left"); XCTAssertGreaterThan(thin.width, content.maxX + 1, "and at the right")
        XCTAssertEqual([thin.ascent, thin.descent], [em, 0])
    }

    // MARK: merror, maction, semantics

    func testErrorsAreFramedInRed() throws {
        let found = try inks("<merror><mtext>bad input</mtext></merror>")
        let frame = try XCTUnwrap(found[.red]), text = try XCTUnwrap(found[.black])
        XCTAssertTrue(frame.insetBy(dx: 1, dy: 1).contains(text), "\(frame) should frame \(text)")
        let box = try innerBox("<merror><mtext>bad input</mtext></merror>"), plain = try innerBox("<mtext>bad input</mtext>")
        XCTAssertGreaterThan(box.width, plain.width + 2); XCTAssertGreaterThan(box.ascent, plain.ascent + 1); XCTAssertGreaterThan(box.descent, plain.descent + 1)
        XCTAssertEqual(frame.maxX, box.width, accuracy: pixel)
    }

    func testActionShowsItsSelectedChild() throws {
        let children = "<mi>a</mi><mfrac><mn>1</mn><mn>2</mn></mfrac><msqrt><mi>c</mi></msqrt>"
        let shown = ["<mi>a</mi>", "<mfrac><mn>1</mn><mn>2</mn></mfrac>", "<msqrt><mi>c</mi></msqrt>"]
        try assertSameBox("<maction>\(children)</maction>", shown[0], "the first child by default")
        for (selection, expected) in [("1", 0), ("2", 1), ("3", 2), (" 2 ", 1), ("0", 0), ("4", 0), ("-1", 0), ("bogus", 0), ("", 0), ("99999999999999999999", 0)] {
            try assertSameBox("<maction actiontype=\"toggle\" selection=\"\(selection)\">\(children)</maction>", shown[expected], "selection=\(selection)")
        }
        for actiontype in ["tooltip", "statusline", "input", "no-such-type"] {
            try assertSameBox("<maction actiontype=\"\(actiontype)\">\(children)</maction>", shown[0], actiontype)
        }
    }

    func testSemanticsShowsItsPresentationChild() throws {
        let annotations = "<annotation encoding=\"application/x-tex\">\\frac{1}{2}</annotation>"
            + "<annotation-xml encoding=\"MathML-Content\"><apply><divide/><cn>1</cn><cn>2</cn></apply></annotation-xml>"
            + "<annotation-xml encoding=\"application/xhtml+xml\"><span xmlns=\"http://www.w3.org/1999/xhtml\">½</span></annotation-xml>"
        let fraction = "<mfrac><mn>1</mn><mn>2</mn></mfrac>"
        for display in [false, true] {
            try assertSameBox("<semantics>\(fraction)\(annotations)</semantics>", fraction, display: display)
            try assertSameBox("<semantics>\(annotations)\(fraction)</semantics>", fraction, display: display, "annotations first")
        }
        let none = try innerBox("<semantics>\(annotations)</semantics>")
        XCTAssertEqual([none.width, none.ascent, none.descent], [0, 0, 0], "only annotations: nothing to show")
        // An annotation's content is never laid out, whatever it holds.
        XCTAssertNoThrow(try typeset("<semantics><mi>x</mi><annotation-xml><no-such-element><mfrac/></no-such-element></annotation-xml></semantics>"))
    }

    /// What is read aloud is what is drawn: the selected child of an action, and the
    /// presentation child of `semantics`, whichever position it is in.
    func testTheSpokenReadingFollowsTheChildThatIsDrawn() throws {
        XCTAssertEqual(try mathML("<maction selection=\"1\"><mi>a</mi><mi>b</mi></maction>").accessibilityDescription, "a")
        XCTAssertEqual(try mathML("<maction actiontype=\"toggle\" selection=\"2\"><mi>a</mi><mi>b</mi></maction>").accessibilityDescription, "b",
                       "selection=2 draws b")
        XCTAssertEqual(try mathML("<semantics><mi>x</mi><annotation encoding=\"TeX\">x</annotation></semantics>").accessibilityDescription, "x")
        XCTAssertEqual(try mathML("<semantics><annotation encoding=\"TeX\">x</annotation><mi>x</mi></semantics>").accessibilityDescription, "x",
                       "the annotation comes first, and x is drawn")
    }

    // MARK: What is not presentation MathML

    func testUnknownElementsThrowUnsupportedWithTheirName() {
        for name in ["apply", "ci", "cn", "csymbol", "foo", "div", "span", "svg", "mspan", "mmath", "MI", "Mrow"] {
            XCTAssertThrowsError(try typeset("<\(name)/>"), name) { XCTAssertEqual($0 as? MathLayoutError, .unsupported(name), name) }
            XCTAssertThrowsError(try typeset("<mrow><mi>x</mi><mfrac><mi>a</mi><\(name)><mi>b</mi></\(name)></mfrac></mrow>"), name) {
                XCTAssertEqual($0 as? MathLayoutError, .unsupported(name), "\(name), nested")
            }
        }
        // The first unsupported element in document order is the one reported.
        XCTAssertThrowsError(try typeset("<foo/><bar/>")) { XCTAssertEqual($0 as? MathLayoutError, .unsupported("foo")) }
        // Hidden content is still checked: a phantom or an unselected action child is not laid out twice.
        XCTAssertThrowsError(try typeset("<mphantom><foo/></mphantom>")) { XCTAssertEqual($0 as? MathLayoutError, .unsupported("foo")) }
        XCTAssertNoThrow(try typeset("<maction selection=\"1\"><mi>x</mi><foo/></maction>"), "only the selected child is laid out")
    }
}
