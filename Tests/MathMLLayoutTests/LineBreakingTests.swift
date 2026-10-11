import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

/// Line breaking (MathML 3, 3.1.7): rows, where they break, how they are indented and stacked.
final class LineBreakingTests: MathTestCase {
    let em: CGFloat = 20
    /// The space each side of a binary operator and of a relation.
    var medium: CGFloat { em * 4 / 18 }
    var thick: CGFloat { em * 5 / 18 }

    func broken(_ body: String, width: CGFloat = .infinity, first: CGFloat? = nil, display: Bool = false) throws -> MathLayout {
        try MathLayout(node(body, display: display), style: MathStyle(fontSize: em, color: black), maximumWidth: width,
                       firstRowMaximumWidth: first)
    }

    func width(_ body: String) throws -> CGFloat { try layout(body, size: em).width }

    func mi(_ name: String) -> String { "<mi>\(name)</mi>" }
    func mo(_ text: String, _ attributes: String = "") -> String { "<mo \(attributes)>\(text)</mo>" }
    func red(_ text: String, _ attributes: String = "") -> String { mo(text, "mathcolor=\"red\" \(attributes)") }
    func blue(_ text: String, _ attributes: String = "") -> String { mo(text, "mathcolor=\"blue\" \(attributes)") }

    enum Tint { case any, red, blue }

    /// Draws one row alone, as a host placing rows on text lines does, and returns the bounds of
    /// its ink (or of its ink of one colour), in points relative to the row's baseline origin, y up.
    func ink(_ row: MathLayout.Row, _ tint: Tint = .any, margin: CGFloat = 20) -> CGRect? {
        let scale: CGFloat = 2
        let width = Int((row.width + 2 * margin) * scale), height = Int((row.ascent + row.descent + 2 * margin) * scale)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        row.draw(in: context, baselineOrigin: CGPoint(x: margin, y: margin + row.descent))
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let pixel = (y * width + x) * 4
                let r = Int(pixels[pixel]), g = Int(pixels[pixel + 1]), b = Int(pixels[pixel + 2]), a = Int(pixels[pixel + 3])
                let matches = switch tint {
                case .any: a > 24
                case .red: r > 96 && g * 3 < r && b * 3 < r
                case .blue: b > 96 && r * 3 < b && g * 3 < b
                }
                if matches { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
            }
        }
        guard maxX >= 0 else { return nil }
        let top = CGFloat(height - minY) / scale, bottom = CGFloat(height - maxY - 1) / scale
        return CGRect(x: CGFloat(minX) / scale - margin, y: bottom - margin - row.descent,
                      width: CGFloat(maxX - minX + 1) / scale, height: top - bottom)
    }

    /// The index of each row that draws something in `tint`.
    func rows(_ layout: MathLayout, drawing tint: Tint) -> [Int] {
        layout.rows.indices.filter { ink(layout.rows[$0], tint) != nil }
    }

    /// Whether the row's first ink, at its left edge, is of `tint`: the operator a line broke before.
    func starts(_ row: MathLayout.Row, with tint: Tint) -> Bool {
        guard let colored = ink(row, tint), let all = ink(row) else { return false }
        return colored.minX <= all.minX + 0.5
    }

    func ends(_ row: MathLayout.Row, with tint: Tint) -> Bool {
        guard let colored = ink(row, tint), let all = ink(row) else { return false }
        return colored.maxX >= all.maxX - 0.5
    }

    /// Asserts the widths of a layout's rows, top to bottom.
    func assertWidths(_ layout: MathLayout, _ expected: [CGFloat], _ message: String = "", file: StaticString = #filePath,
                      line: UInt = #line) {
        XCTAssertEqual(layout.rows.count, expected.count, message, file: file, line: line)
        for (row, width) in zip(layout.rows, expected) {
            XCTAssertEqual(row.width, width, accuracy: 0.01, message, file: file, line: line)
        }
    }

    /// "alpha + beta + …" from names, with `plus` between them.
    func sum(_ names: [String], _ plus: String = "<mo>+</mo>") -> String { names.map(mi).joined(separator: plus) }

    let names = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta"]

    // MARK: Rows

    func testOneRowWithoutAWidthIsTheLayoutItWas() throws {
        let body = "<mi>x</mi><mo>=</mo><mfrac><mrow><mo>−</mo><mi>b</mi><mo>±</mo><msqrt><msup><mi>b</mi><mn>2</mn></msup><mo>−</mo><mn>4</mn><mi>a</mi><mi>c</mi></msqrt></mrow><mrow><mn>2</mn><mi>a</mi></mrow></mfrac>"
        let plain = try MathLayout(node(body, display: true), style: MathStyle(fontSize: em, color: black))
        XCTAssertEqual(plain.rows.count, 1)
        let row = try XCTUnwrap(plain.rows.first)
        XCTAssertEqual(row.origin, .zero)
        XCTAssertEqual(row.origin.y.sign, .plus, "zero, not minus zero")
        XCTAssertEqual([row.width, row.ascent, row.descent], [plain.width, plain.ascent, plain.descent])
        // A width it fits changes nothing, to the last bit: exactly its own width is enough.
        for width in [plain.width, plain.width + 100, 1e9] {
            let fitted = try broken(body, width: width, display: true)
            XCTAssertEqual(fitted.rows.count, 1)
            XCTAssertEqual([fitted.width, fitted.ascent, fitted.descent], [plain.width, plain.ascent, plain.descent])
            XCTAssertEqual(ink(fitted), ink(plain))
        }
        XCTAssertEqual(ink(row), ink(plain), "the one row draws what the layout draws")
    }

    func testRowsFitTheLineAndTogetherHoldTheFormula() throws {
        let body = "<mi>y</mi><mo>=</mo>" + sum(names)
        let whole = try width(body)
        for limit in [whole - 1, whole * 0.7, whole * 0.5, whole * 0.3, 120, 90] {
            let layout = try broken(body, width: limit)
            XCTAssertGreaterThan(layout.rows.count, 1, "\(limit)")
            for row in layout.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, limit + 0.001, "\(limit)") }
            XCTAssertLessThanOrEqual(layout.widestUnbreakableWidth, limit)
            // Every break here is before a "+", whose space before it is trimmed and nothing else.
            let content = layout.rows.reduce(0) { $0 + $1.width }
            XCTAssertEqual(content + CGFloat(layout.rows.count - 1) * medium, whole, accuracy: 0.01, "\(limit)")
            // The layout's box: the first row's baseline, down through the last row.
            XCTAssertEqual(layout.width, layout.rows.map { $0.origin.x + $0.width }.max()!, accuracy: 0.001)
            XCTAssertEqual(layout.ascent, layout.rows[0].ascent, accuracy: 0.001)
            XCTAssertEqual(layout.descent, layout.rows.last!.descent - layout.rows.last!.origin.y, accuracy: 0.001)
            XCTAssertEqual(layout.rows[0].origin, .zero)
            for (above, below) in zip(layout.rows, layout.rows.dropFirst()) {
                XCTAssertLessThan(below.origin.y + below.ascent, above.origin.y - above.descent + 0.001, "rows do not overlap")
            }
        }
        // Fuller rows are preferred: as few rows as the width allows.
        let half = try broken(body, width: whole * 0.55)
        XCTAssertEqual(half.rows.count, 2)
    }

    func testRowsAreDrawnAloneInsideTheirOwnBoxes() throws {
        // Italic letters lean past their advances, more so where an invisible times starts the row.
        let bodies: [(String, CGFloat)] = [
            ("<mi>f</mi><mo>=</mo>" + sum(names), 100),
            (["j", "f", "j", "f", "j", "f", "j", "f"].map(mi).joined(separator: "<mo>\u{2062}</mo>"), 22),
            ("<mi>y</mi><mo>=</mo><msubsup><mo>∫</mo><mn>0</mn><mn>1</mn></msubsup><mi>f</mi><mo>+</mo><mfrac><mi>a</mi><mi>b</mi></mfrac><mo>+</mo><msqrt><mi>x</mi></msqrt><mo>+</mo><mover><mi>A</mi><mo>~</mo></mover>", 60),
        ]
        for (body, limit) in bodies {
            for display in [false, true] {
                let layout = try broken(body, width: limit, display: display)
                XCTAssertGreaterThan(layout.rows.count, 2, body)
                var union: CGRect?
                for row in layout.rows {
                    guard let ink = ink(row) else { XCTFail(body); continue }
                    XCTAssertGreaterThanOrEqual(ink.minX, -0.5, body)
                    XCTAssertLessThanOrEqual(ink.maxX, row.width + 0.5, body)
                    XCTAssertLessThanOrEqual(row.origin.x + row.width, max(limit, layout.widestUnbreakableWidth) + 0.001, body)
                    XCTAssertLessThanOrEqual(ink.maxY, row.ascent + 0.5, body)
                    XCTAssertGreaterThanOrEqual(ink.minY, -row.descent - 0.5, body)
                    let placed = ink.offsetBy(dx: row.origin.x, dy: row.origin.y)
                    union = union.map { $0.union(placed) } ?? placed
                }
                // Drawing the layout draws every row at its origin.
                let all = try XCTUnwrap(ink(layout))
                let rows = try XCTUnwrap(union)
                for (whole, part) in [(all.minX, rows.minX), (all.maxX, rows.maxX), (all.minY, rows.minY), (all.maxY, rows.maxY)] {
                    XCTAssertEqual(whole, part, accuracy: 1, body)
                }
            }
        }
    }

    func testRowsAreStackedLikeLinesOfText() throws {
        let body = "<mi>y</mi><mo>=</mo>" + sum(names)
        let layout = try broken(body, width: 100)
        XCTAssertGreaterThan(layout.rows.count, 3)
        let font = MathFont.named(nil)
        let distance = (CTFontGetAscent(font.base) + CTFontGetDescent(font.base) + font.constants.mathLeading) * em
        for (above, below) in zip(layout.rows, layout.rows.dropFirst()) {
            XCTAssertEqual(above.origin.y - below.origin.y, distance, accuracy: 0.001,
                           "rows of plain symbols keep one baseline distance, whatever their ink")
        }
        // A tall row pushes its neighbours away by its own extent and the leading.
        let tall = try broken("<mi>y</mi><mo>=</mo><mi>alpha</mi><mo>+</mo><mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mfrac><mi>c</mi><mi>d</mi></mfrac></mfrac><mo>+</mo><mi>gamma</mi>",
                              width: 100, display: true)
        XCTAssertEqual(tall.rows.count, 3)
        XCTAssertGreaterThan(tall.rows[1].ascent + tall.rows[1].descent, 2 * em)
        let leading = font.constants.mathLeading * em
        XCTAssertEqual(tall.rows[0].origin.y - tall.rows[1].origin.y,
                       CTFontGetDescent(font.base) * em + leading + tall.rows[1].ascent, accuracy: 0.001)
        XCTAssertEqual(tall.rows[1].origin.y - tall.rows[2].origin.y,
                       tall.rows[1].descent + leading + CTFontGetAscent(font.base) * em, accuracy: 0.001)
        // `lineleading` scales the leading, or replaces it.
        func gap(_ leading: String) throws -> CGFloat {
            let layout = try broken("<mstyle lineleading=\"\(leading)\">\(body)</mstyle>", width: 100)
            return layout.rows[0].origin.y - layout.rows[1].origin.y
        }
        XCTAssertEqual(try gap("100%"), distance, accuracy: 0.001)
        XCTAssertEqual(try gap("300%"), distance + 2 * leading, accuracy: 0.001)
        XCTAssertEqual(try gap("0"), distance - leading, accuracy: 0.001)
        XCTAssertEqual(try gap("1em"), distance - leading + em, accuracy: 0.001)
        // It is read from the operator the line breaks at.
        let own = try broken("<mi>alpha</mi><mo linebreak=\"newline\" lineleading=\"2em\">=</mo><mi>beta</mi><mo linebreak=\"newline\">+</mo><mi>gamma</mi>")
        XCTAssertEqual(own.rows[0].origin.y - own.rows[1].origin.y, distance - leading + 2 * em, accuracy: 0.001)
        XCTAssertEqual(own.rows[1].origin.y - own.rows[2].origin.y, distance, accuracy: 0.001)
    }

    // MARK: Where lines break

    func testBreaksAtRelationsBeforeSumsBeforeProducts() throws {
        // One break to make: at the relation, not at the "+" that would fill the row more.
        let equation = mi("alpha") + blue("+") + mi("beta") + red("=") + mi("gamma") + blue("+") + mi("delta")
        var layout = try broken(equation, width: try width(equation) - 1)
        XCTAssertEqual(layout.rows.count, 2)
        XCTAssertTrue(starts(layout.rows[1], with: .red), "the line breaks before the relation")
        XCTAssertEqual(rows(layout, drawing: .blue), [0, 1])
        // A sum breaks at its "+", not inside a product.
        let terms = mi("alpha") + red("×") + mi("beta") + blue("+") + mi("gamma") + red("×") + mi("delta")
        layout = try broken(terms, width: try width(terms) - 1)
        XCTAssertEqual(layout.rows.count, 2)
        XCTAssertTrue(starts(layout.rows[1], with: .blue))
        // So does one whose products are written with invisible times.
        let invisible = mi("alpha") + mo("\u{2062}") + mi("beta") + blue("+") + mi("gamma") + mo("\u{2062}") + mi("delta")
        layout = try broken(invisible, width: try width(invisible) - 1)
        XCTAssertEqual(layout.rows.count, 2)
        XCTAssertTrue(starts(layout.rows[1], with: .blue))
        // A product breaks at its operators when it must: visible ones, and invisible times.
        layout = try broken(terms, width: try width(mi("alpha") + mo("×") + mi("beta")) - 1)
        XCTAssertEqual(layout.rows.count, 4)
        XCTAssertTrue(starts(layout.rows[1], with: .red))
        XCTAssertTrue(starts(layout.rows[2], with: .blue))
        XCTAssertTrue(starts(layout.rows[3], with: .red))
        layout = try broken(invisible, width: try width(mi("alpha") + mo("\u{2062}") + mi("beta")) - 1)
        XCTAssertEqual(layout.rows.count, 4)
        XCTAssertEqual(layout.rows[1].width, try width(mi("beta")), accuracy: 0.01, "an invisible times shows nothing where a line breaks")
        // The classes are the operator dictionary's own.
        XCTAssertEqual(OperatorDictionary.entry("=", form: .infix).breakClass, .relation)
        XCTAssertEqual(OperatorDictionary.entry("≤", form: .infix).breakClass, .relation)
        XCTAssertEqual(OperatorDictionary.entry("→", form: .infix).breakClass, .relation)
        XCTAssertEqual(OperatorDictionary.entry("+", form: .infix).breakClass, .additive)
        XCTAssertEqual(OperatorDictionary.entry("−", form: .infix).breakClass, .additive)
        XCTAssertEqual(OperatorDictionary.entry("×", form: .infix).breakClass, .multiplicative)
        XCTAssertEqual(OperatorDictionary.entry("\u{2062}", form: .infix).breakClass, .multiplicative)
        XCTAssertEqual(OperatorDictionary.entry(",", form: .infix).breakClass, .separator)
        XCTAssertEqual(OperatorDictionary.entry("+", form: .prefix).breakClass, .none)
        XCTAssertEqual(OperatorDictionary.entry("(", form: .prefix).breakClass, .none)
        XCTAssertEqual(OperatorDictionary.entry("!", form: .postfix).breakClass, .none)
        XCTAssertEqual(OperatorDictionary.entry("\u{2061}", form: .infix).breakClass, .glue)
        XCTAssertEqual(OperatorDictionary.entry("mod", form: .infix).breakClass, .relation, "unknown, between operands")
        XCTAssertEqual(OperatorDictionary.entry("mod", form: .prefix).breakClass, .none)
        // The spacing the dictionary gives is what it was.
        XCTAssertEqual(OperatorDictionary.entry("+", form: .infix).lspace, 4)
        XCTAssertEqual(OperatorDictionary.entry("∧", form: .infix).rspace, 4)
        XCTAssertEqual(OperatorDictionary.entry("mod", form: .prefix).lspace, 5)
    }

    func testNestingCostsABreak() throws {
        // Flat, the row fills as far as it can: the break is before the last "+" that fits.
        let flat = mi("alpha") + mo("+") + mi("beta") + blue("+") + mi("gamma") + red("+") + mi("delta")
        let limit = try width(flat) - 1
        var layout = try broken(flat, width: limit)
        XCTAssertEqual(layout.rows.count, 2)
        XCTAssertTrue(starts(layout.rows[1], with: .red))
        // With the last two terms in brackets, that "+" is nested and the outer one is chosen.
        for nested in [
            mi("alpha") + mo("+") + mi("beta") + blue("+") + "<mfenced><mrow>" + mi("gamma") + red("+") + mi("delta") + "</mrow></mfenced>",
            mi("alpha") + mo("+") + mi("beta") + blue("+") + "<mrow><mo>(</mo><mrow>" + mi("gamma") + red("+") + mi("delta") + "</mrow><mo>)</mo></mrow>",
            // Brackets written flat in the one row nest what is between them just the same.
            mi("alpha") + mo("+") + mi("beta") + blue("+") + mo("(") + mi("gamma") + red("+") + mi("delta") + mo(")"),
        ] {
            layout = try broken(nested, width: limit)
            XCTAssertEqual(layout.rows.count, 2, nested)
            XCTAssertTrue(starts(layout.rows[1], with: .blue), nested)
            // It still breaks inside the brackets when nothing else will do.
            layout = try broken(nested, width: try width(mo("(") + mi("gamma") + mo("+") + mi("delta") + mo(")")) - 1)
            XCTAssertEqual(rows(layout, drawing: .red).count, 1, nested)
            XCTAssertTrue(starts(layout.rows[rows(layout, drawing: .red)[0]], with: .red), nested)
        }
        // A row that only wraps another, or wraps one operator, is no deeper than what it holds.
        let wrapped = "<mrow><mstyle>" + mi("alpha") + mo("+") + mi("beta") + blue("+") + mi("gamma") + "<mstyle mathcolor=\"red\"><mo>+</mo></mstyle>"
            + mi("delta") + "</mstyle></mrow>"
        layout = try broken(wrapped, width: limit)
        XCTAssertEqual(layout.rows.count, 2)
        XCTAssertTrue(starts(layout.rows[1], with: .red))
    }

    func testNeverBreaksWhereAnOperatorHoldsItsOperand() throws {
        // On a line of no width every break that is allowed is made, and these are not:
        // before a sign, between a function and its argument, after an opening fence, before a
        // closing fence or a postfix operator.
        let parts = [
            "<mo>−</mo><mi>a</mi>",
            "<mo>+</mo><mi>sin</mi><mo>\u{2061}</mo><mi>x</mi>",
            "<mo>+</mo><mo>(</mo><mi>b</mi>",
            "<mo>−</mo><mi>c</mi><mo>)</mo>",
            "<mo>+</mo><mi>n</mi><mo>!</mo>",
            "<mo>=</mo><mo>−</mo><mn>3</mn>",
            "<mo>×</mo><mo>(</mo><mo>−</mo><mi>d</mi><mo>)</mo>",
        ]
        let layout = try broken(parts.joined(), width: 0)
        XCTAssertEqual(layout.rows.count, parts.count, "one row for each part, and no more")
        // Together the rows hold everything but the space before each operator a line broke at.
        XCTAssertEqual(layout.rows.reduce(0) { $0 + $1.width } + 5 * medium + thick, try width(parts.joined()), accuracy: 0.01)
        XCTAssertEqual(layout.rows[0].width, try width(parts[0]), accuracy: 0.01)
        XCTAssertEqual(layout.widestUnbreakableWidth, layout.rows.map(\.width).max()!, accuracy: 0.001)
        // Separators break after, not before: the comma ends its row.
        let list = mi("f") + mo("\u{2061}") + mo("(") + mi("alpha") + red(",") + mi("beta") + red(",") + mi("gamma") + mo(")")
        let separated = try broken(list, width: 0)
        XCTAssertEqual(separated.rows.count, 3)
        XCTAssertTrue(ends(separated.rows[0], with: .red))
        XCTAssertTrue(ends(separated.rows[1], with: .red))
        XCTAssertNil(ink(separated.rows[2], .red))
        // The same from `mfenced`, whose separators are its own.
        let fenced = try broken("<mi>f</mi><mo>\u{2061}</mo><mfenced><mi>alpha</mi><mi>beta</mi><mi>gamma</mi></mfenced>", width: 0)
        assertWidths(fenced, separated.rows.map(\.width))
    }

    func testForcedBreaksApplyAtAnyWidth() throws {
        let alpha = try width(mi("alpha")), beta = try width(mi("beta")), gamma = try width(mi("gamma"))
        let equals = try width(mo("=")), plus = try width(mo("+"))
        // Before the operator by default, with no width given at all.
        var layout = try broken(mi("alpha") + mo("=", "linebreak=\"newline\"") + mi("beta") + mo("+") + mi("gamma"))
        XCTAssertEqual(layout.rows.count, 2)
        XCTAssertEqual(layout.rows[0].width, alpha, accuracy: 0.01)
        XCTAssertEqual(layout.rows[1].width, equals + thick + beta + medium + plus + medium + gamma, accuracy: 0.01)
        XCTAssertGreaterThan(layout.descent, layout.rows[0].descent + em, "the layout reaches down through its last row")
        // After it with `linebreakstyle="after"`.
        layout = try broken(mi("alpha") + mo("=", "linebreak=\"newline\" linebreakstyle=\"after\"") + mi("beta"))
        assertWidths(layout, [alpha + thick + equals, beta])
        // At an `mspace`, and MathML 2's `indentingnewline` means the same.
        for value in ["newline", "indentingnewline"] {
            layout = try broken(mi("alpha") + "<mspace linebreak=\"\(value)\"/>" + mi("beta") + mo("+") + mi("gamma"))
            XCTAssertEqual(layout.rows.count, 2, value)
            XCTAssertEqual(layout.rows[0].width, alpha, accuracy: 0.01)
            XCTAssertEqual(layout.rows[1].width, beta + medium + plus + medium + gamma, accuracy: 0.01)
        }
        // An `mspace` with a size is a space, whatever its `linebreak` (MathML 3, 3.2.7.2).
        layout = try broken(mi("alpha") + "<mspace width=\"1em\" linebreak=\"newline\"/>" + mi("beta"))
        XCTAssertEqual(layout.rows.count, 1)
        XCTAssertEqual(layout.width, alpha + em + beta, accuracy: 0.01)
        // Even where no automatic break would go: before a sign, inside a nested row.
        layout = try broken("<mrow><mo>(</mo><mrow>" + mo("−", "linebreak=\"newline\"") + mi("alpha") + mo("+") + mi("beta")
            + "</mrow><mo>)</mo></mrow>")
        XCTAssertEqual(layout.rows.count, 2)
        // A break that would leave an empty row is none: before the first unit, after the last.
        layout = try broken("<mspace linebreak=\"newline\"/>" + mi("alpha") + mo("=") + mi("beta")
            + mo("!", "linebreak=\"newline\" linebreakstyle=\"after\""))
        XCTAssertEqual(layout.rows.count, 1)
        // Forced and automatic breaks together: every forced one, and what the width asks between them.
        let long = mi("y") + mo("=") + sum(Array(names.prefix(4))) + red("=", "linebreak=\"newline\"") + sum(Array(names.suffix(4)))
        layout = try broken(long, width: try width(sum(Array(names.prefix(3)))))
        XCTAssertGreaterThan(layout.rows.count, 3)
        let forced = rows(layout, drawing: .red)
        XCTAssertEqual(forced.count, 1)
        XCTAssertTrue(starts(layout.rows[forced[0]], with: .red))
        for row in layout.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, try width(sum(Array(names.prefix(3)))) + 0.001) }
        // `mstyle` sets the default its operators inherit.
        layout = try broken("<mstyle linebreak=\"newline\">" + mi("alpha") + mo("=") + mi("beta") + mo("+") + mi("gamma") + "</mstyle>")
        XCTAssertEqual(layout.rows.count, 3)
    }

    func testNoBreakAndBreakHints() throws {
        let terms = Array(names.prefix(4))
        let limit = try width(sum(terms)) - 1
        // Without a hint: before the last "+".
        var layout = try broken(sum(Array(terms.prefix(3))) + red("+") + mi(terms[3]), width: limit)
        XCTAssertEqual(layout.rows.count, 2)
        XCTAssertTrue(starts(layout.rows[1], with: .red))
        // `nobreak` there moves the break to the "+" before.
        layout = try broken(sum(Array(terms.prefix(2))) + blue("+") + mi(terms[2]) + red("+", "linebreak=\"nobreak\"") + mi(terms[3]),
                            width: limit)
        XCTAssertEqual(layout.rows.count, 2)
        XCTAssertTrue(starts(layout.rows[1], with: .blue))
        XCTAssertEqual(rows(layout, drawing: .red), [1])
        // So does `badbreak`, while a better place fits.
        layout = try broken(sum(Array(terms.prefix(2))) + blue("+") + mi(terms[2]) + red("+", "linebreak=\"badbreak\"") + mi(terms[3]),
                            width: limit)
        XCTAssertTrue(starts(layout.rows[1], with: .blue))
        // `goodbreak` draws the break to an operator it would otherwise pass.
        layout = try broken(sum(Array(terms.prefix(2))) + blue("+", "linebreak=\"goodbreak\"") + mi(terms[2]) + red("+") + mi(terms[3]),
                            width: limit)
        XCTAssertEqual(layout.rows.count, 2)
        XCTAssertTrue(starts(layout.rows[1], with: .blue))
        // It makes a break possible where there is none by default, here at a division slash.
        let slash = mi("alpha") + mo("/") + mi("beta")
        XCTAssertEqual(try broken(slash, width: 0).rows.count, 1)
        XCTAssertEqual(try broken(mi("alpha") + mo("/", "linebreak=\"goodbreak\"") + mi("beta"), width: 0).rows.count, 2)
        // With every break forbidden the row cannot break: it overflows, and says by how much.
        let rigid = "<mstyle linebreak=\"nobreak\">" + sum(terms) + "</mstyle>"
        layout = try broken(rigid, width: 50)
        XCTAssertEqual(layout.rows.count, 1)
        XCTAssertEqual(layout.widestUnbreakableWidth, try width(sum(terms)), accuracy: 0.01)
        XCTAssertGreaterThan(layout.widestUnbreakableWidth, 50)
        // `nobreak` on one operator does not hold back the break of the next (MathML 3, 3.2.5.2.2).
        layout = try broken(mi("alpha") + mo("+", "linebreak=\"nobreak\"") + mi("beta") + red("+") + mi("gamma"), width: 0)
        XCTAssertEqual(layout.rows.count, 2)
        XCTAssertTrue(starts(layout.rows[1], with: .red))
    }

    func testLinebreakStyles() throws {
        let alpha = try width(mi("alpha")), beta = try width(mi("beta")), plus = try width(mo("+"))
        let body = { (attributes: String) in self.mi("alpha") + self.red("+", "linebreak=\"newline\" " + attributes) + self.mi("beta") }
        // Before: the operator starts the new row, with its space after it and none before.
        var layout = try broken(body(""))
        assertWidths(layout, [alpha, plus + medium + beta])
        XCTAssertTrue(starts(layout.rows[1], with: .red))
        // After: it ends the row it was on.
        layout = try broken(body("linebreakstyle=\"after\""))
        assertWidths(layout, [alpha + medium + plus, beta])
        XCTAssertTrue(ends(layout.rows[0], with: .red))
        // Duplicate: both.
        layout = try broken(body("linebreakstyle=\"duplicate\""))
        assertWidths(layout, [alpha + medium + plus, plus + medium + beta])
        XCTAssertTrue(ends(layout.rows[0], with: .red))
        XCTAssertTrue(starts(layout.rows[1], with: .red))
        // `infixlinebreakstyle` on an `mstyle` is the default of the operators in it, which may still choose.
        layout = try broken("<mstyle infixlinebreakstyle=\"after\">" + body("") + "</mstyle>")
        XCTAssertTrue(ends(layout.rows[0], with: .red))
        layout = try broken("<mstyle infixlinebreakstyle=\"after\">" + body("linebreakstyle=\"before\"") + "</mstyle>")
        XCTAssertTrue(starts(layout.rows[1], with: .red))
        layout = try broken("<mstyle linebreakstyle=\"before\" infixlinebreakstyle=\"duplicate\">" + body("linebreakstyle=\"infixlinebreakstyle\"")
            + "</mstyle>")
        XCTAssertEqual(rows(layout, drawing: .red), [0, 1])
        // Automatic breaks follow the style too, and every row still fits.
        let long = "<mstyle infixlinebreakstyle=\"duplicate\">" + sum(names, red("+")) + "</mstyle>"
        layout = try broken(long, width: 150)
        XCTAssertGreaterThan(layout.rows.count, 2)
        for (index, row) in layout.rows.enumerated() {
            XCTAssertLessThanOrEqual(row.origin.x + row.width, 150.001)
            if index > 0 { XCTAssertTrue(starts(row, with: .red)) }
            if index < layout.rows.count - 1 { XCTAssertTrue(ends(row, with: .red)) }
        }
    }

    func testInvisibleTimesShowsItsCharacterWhereALineBreaks() throws {
        let alpha = try width(mi("alpha")), beta = try width(mi("beta")), times = try width(mo("×"))
        let product = { (attributes: String) in self.mi("alpha") + self.mo("\u{2062}", attributes) + self.mi("beta") }
        // Unbroken, the character is not shown.
        XCTAssertEqual(try broken("<mstyle linebreakmultchar=\"×\">" + product("") + "</mstyle>").width, alpha + beta, accuracy: 0.01)
        // Broken without one, nothing is.
        var layout = try broken(product("linebreak=\"newline\""))
        assertWidths(layout, [alpha, beta])
        // With one, it starts the new row, spaced as the operator it is.
        layout = try broken("<mstyle linebreakmultchar=\"×\" mathcolor=\"red\">" + product("linebreak=\"newline\"") + "</mstyle>")
        XCTAssertEqual(layout.rows.count, 2)
        XCTAssertEqual(layout.rows[0].width, alpha, accuracy: 0.01)
        XCTAssertEqual(layout.rows[1].width, times + medium + beta, accuracy: 0.01)
        XCTAssertNotNil(ink(layout.rows[1], .red))
        // On the operator itself, and after or on both sides by `linebreakstyle`.
        layout = try broken(product("linebreak=\"newline\" linebreakmultchar=\"×\" linebreakstyle=\"after\""))
        XCTAssertEqual(layout.rows[0].width, alpha + medium + times, accuracy: 0.01)
        XCTAssertEqual(layout.rows[1].width, beta, accuracy: 0.01)
        layout = try broken(product("linebreak=\"newline\" linebreakmultchar=\"×\" linebreakstyle=\"duplicate\""))
        XCTAssertEqual(layout.rows[0].width, alpha + medium + times, accuracy: 0.01)
        XCTAssertEqual(layout.rows[1].width, times + medium + beta, accuracy: 0.01)
        // Automatic breaks count what they add: rows with the character still fit.
        let long = "<mstyle linebreakmultchar=\"·\">" + names.map(mi).joined(separator: mo("\u{2062}")) + "</mstyle>"
        layout = try broken(long, width: 100)
        XCTAssertGreaterThan(layout.rows.count, 2)
        for row in layout.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, 100.001) }
        let plain = try broken(names.map(mi).joined(separator: mo("\u{2062}")), width: 100)
        XCTAssertGreaterThan(layout.rows.reduce(0) { $0 + $1.width }, plain.rows.reduce(0) { $0 + $1.width } + 10)
        // Other operators are untouched by it.
        layout = try broken("<mstyle linebreakmultchar=\"×\">" + mi("alpha") + mo("+", "linebreak=\"newline\"") + mi("beta") + "</mstyle>")
        XCTAssertEqual(layout.rows[1].width, try width(mo("+")) + medium + beta, accuracy: 0.01)
    }

    func testOperatorsThatShareABreakEachShowWhatTheyShowThere() throws {
        let alpha = try width(mi("alpha")), beta = try width(mi("beta")), times = try width(mo("×")), dot = try width(mo("⋅"))
        XCTAssertNotEqual(times, dot, accuracy: 1)
        // An operator that breaks after it and the next that breaks before it are one place to break.
        // Here each is an invisible times with a character of its own: one ends the row, the other
        // starts the next, whichever of the two the break is counted as.
        for (first, second) in [("", ""), ("linebreak=\"newline\"", ""), ("", "linebreak=\"newline\""), ("linebreak=\"badbreak\"", "")] {
            let layout = try broken(mi("alpha") + mo("\u{2062}", "linebreakstyle=\"after\" linebreakmultchar=\"×\" \(first)")
                + mo("\u{2062}", "linebreakmultchar=\"⋅\" \(second)") + mi("beta"), width: 0)
            assertWidths(layout, [alpha + medium + times, dot + medium + beta], "\(first) \(second)")
        }
        // A comma breaks after it and is the better place than the times that follows, which shows its
        // character all the same.
        var layout = try broken(mi("alpha") + mo(",") + mo("\u{2062}", "linebreakmultchar=\"×\"") + mi("beta"), width: 0)
        assertWidths(layout, [alpha + (try width(mo(","))), times + medium + beta])
        // So does a times that breaks after it before a relation, the better place again.
        layout = try broken(mi("alpha") + mo("\u{2062}", "linebreakstyle=\"after\" linebreakmultchar=\"×\"") + red("=", "form=\"infix\"")
            + mi("beta"), width: 0)
        assertWidths(layout, [alpha + medium + times, (try width(mo("="))) + thick + beta])
        XCTAssertTrue(starts(layout.rows[1], with: .red))
        // A repeated operator starts the new row, and the character of the times it shares the break
        // with comes after it, next to the operand it multiplies.
        let repeated = "linebreak=\"newline\" linebreakstyle=\"duplicate\""
        let plain = try broken(mi("alpha") + mo("=", repeated) + mo("\u{2062}") + mi("beta"))
        layout = try broken(mi("alpha") + red("=", repeated) + mo("\u{2062}", "linebreakmultchar=\"×\"") + mi("beta"))
        assertWidths(layout, [plain.rows[0].width, plain.rows[1].width + times + medium])
        XCTAssertTrue(ends(layout.rows[0], with: .red))
        XCTAssertTrue(starts(layout.rows[1], with: .red))
        let black = try XCTUnwrap(ink(layout.rows[1])), equals = try XCTUnwrap(ink(layout.rows[1], .red))
        XCTAssertGreaterThan(black.width, equals.width + times + beta, "the repeated sign, the character and the operand")
        // Automatic breaks count what both add: every row still fits, and holds both characters.
        let pair = mo("\u{2062}", "linebreakstyle=\"after\" linebreakmultchar=\"×\"") + mo("\u{2062}", "linebreakmultchar=\"⋅\"")
        let long = names.map(mi).joined(separator: pair)
        layout = try broken(long, width: 100)
        XCTAssertGreaterThan(layout.rows.count, 2)
        for row in layout.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, 100.001) }
        XCTAssertEqual(layout.rows.reduce(0) { $0 + $1.width },
                       try width(long) + CGFloat(layout.rows.count - 1) * (times + dot + 2 * medium), accuracy: 0.01)
    }

    func testBreaksInsideFencesKeepOneBracketSize() throws {
        let tall = "<mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mfrac><mi>c</mi><mi>d</mi></mfrac></mfrac>"
        let inner = "<mstyle mathcolor=\"black\">" + tall + mo("+") + mi("beta") + mo("+") + mi("gamma") + mo("+") + mi("delta") + "</mstyle>"
        // The brackets are red, however they are written.
        let bodies = [
            "<mi>f</mi><mo>\u{2061}</mo><mstyle mathcolor=\"red\"><mfenced>\(inner)</mfenced></mstyle>",
            "<mi>f</mi><mo>\u{2061}</mo><mrow>\(red("("))<mrow>\(inner)</mrow>\(red(")"))</mrow>",
            "<mi>f</mi><mo>\u{2061}</mo>\(red("("))\(inner)\(red(")"))",
            "<mstyle displaystyle=\"true\"><semantics><mrow><mi>f</mi><mo>\u{2061}</mo><maction><mstyle mathcolor=\"red\"><mfenced>\(inner)</mfenced></mstyle></maction></mrow></semantics></mstyle>",
        ]
        let plain = try XCTUnwrap(ink(try broken(mo("(") + mi("x") + mo(")"), display: true)))
        for body in bodies {
            let whole = try broken(body, display: true)
            XCTAssertEqual(whole.rows.count, 1, body)
            let unbroken = try XCTUnwrap(ink(whole.rows[0], .red))
            XCTAssertGreaterThan(unbroken.height, plain.height * 2, "stretched to the fraction")
            for share in [0.8, 0.6, 0.4] {
                let layout = try broken(body, width: whole.width * share, display: true)
                XCTAssertGreaterThan(layout.rows.count, 1, body)
                for row in layout.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, whole.width * share + 0.001, body) }
                // The opening bracket is on the first row with the tall fraction, the closing one on
                // the last with plain letters, where a bracket laid out afresh would be small.
                XCTAssertEqual(rows(layout, drawing: .red), [0, layout.rows.count - 1], body)
                let opening = try XCTUnwrap(ink(layout.rows[0], .red)), closing = try XCTUnwrap(ink(layout.rows.last!, .red))
                XCTAssertEqual(opening.height, unbroken.height, accuracy: 0.5, body)
                XCTAssertEqual(closing.height, opening.height, accuracy: 0.5, body)
                XCTAssertEqual(closing.midY, opening.midY, accuracy: 0.5, "both centred on the one axis")
                XCTAssertTrue(ends(layout.rows.last!, with: .red), body)
            }
        }
    }

    func testBreaksInsideTheBaseOfScripts() throws {
        let inner = mi("alpha") + mo("+") + mi("beta") + blue("+") + mi("gamma") + mo("+") + mi("delta")
        let base = "<mrow>" + mo("(") + "<mrow>" + inner + "</mrow>" + mo(")") + "</mrow>"
        let scripted = [
            "<msup>\(base)<mn mathcolor=\"red\">2</mn></msup>",
            "<msub>\(base)<mn mathcolor=\"red\">2</mn></msub>",
            "<msubsup>\(base)<mn mathcolor=\"red\">0</mn><mn mathcolor=\"red\">1</mn></msubsup>",
            "<mmultiscripts>\(base)<mn mathcolor=\"red\">0</mn><none/><mprescripts/><none/><mn mathcolor=\"red\">1</mn></mmultiscripts>",
        ]
        for (index, body) in scripted.enumerated() {
            let formula = mi("y") + mo("=") + body + mo("+") + mi("z")
            let whole = try broken(formula)
            XCTAssertEqual(whole.rows.count, 1)
            let unbroken = try XCTUnwrap(ink(whole.rows[0], .red))
            // The base breaks at its operators like any bracketed row, and its scripts stay with it.
            let layout = try broken(formula, width: whole.width * 0.6)
            XCTAssertGreaterThan(layout.rows.count, 1, body)
            for row in layout.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, whole.width * 0.6 + 0.001, body) }
            XCTAssertEqual(rows(layout, drawing: .blue).count, 1, body)
            XCTAssertTrue(starts(layout.rows[rows(layout, drawing: .blue)[0]], with: .blue), "the line broke inside the base")
            // Each script is as high as it was, on the row of the bracket it belongs to.
            let scripts = rows(layout, drawing: .red)
            XCTAssertEqual(scripts.count, index == 3 ? 2 : 1, body)
            let last = try XCTUnwrap(ink(layout.rows[scripts.last!], .red))
            if index < 3 {
                XCTAssertEqual(last.minY, unbroken.minY, accuracy: 0.5, body)
                XCTAssertEqual(last.maxY, unbroken.maxY, accuracy: 0.5, body)
            }
            // On a line of no width nothing parts a script from its base: one row for each term, no more.
            let narrow = try broken(formula, width: 0)
            XCTAssertEqual(narrow.rows.count, 6, body)
            XCTAssertEqual(rows(narrow, drawing: .red), index == 3 ? [1, 4] : [4], body)
        }
        // A base that is no row, or is an operator, is the unit it was.
        XCTAssertEqual(try broken("<msup><mi>x</mi><mn>2</mn></msup>", width: 0).rows.count, 1)
        XCTAssertEqual(try broken(mi("a") + "<msub><mrow><mo>+</mo></mrow><mn>2</mn></msub>" + mi("b"), width: 0).rows.count, 2)
        // The unbroken layout is what it was.
        XCTAssertEqual(try broken(scripted[0]).width, try layout(scripted[0], size: em).width)
    }

    func testAnOperatorThatStartsARowKeepsItsBinarySpacing() throws {
        let alpha = try width(mi("alpha")), beta = try width(mi("beta")), plus = try width(mo("+")), equals = try width(mo("="))
        let layout = try broken(mi("alpha") + mo("+") + mi("beta") + mo("=") + mi("alpha"), width: 0)
        XCTAssertEqual(layout.rows.count, 3)
        // "+ beta" laid out on its own is a sign and its operand, with no space between them.
        XCTAssertEqual(try width(mo("+") + mi("beta")), plus + beta, accuracy: 0.01)
        // On the row a line break made, the "+" is still the binary operator it was: its space
        // after it, and none before it at the row's edge.
        XCTAssertEqual(layout.rows[1].width, plus + medium + beta, accuracy: 0.01)
        XCTAssertEqual(layout.rows[2].width, equals + thick + alpha, accuracy: 0.01)
        // The row before ends with its last operand: no space after it.
        XCTAssertEqual(layout.rows[0].width, alpha, accuracy: 0.01)
        let first = try XCTUnwrap(ink(layout.rows[1]))
        XCTAssertLessThan(first.minX, 2, "the operator is at the row's left edge")
        // The formula's own edges are where the unbroken row has them.
        let edged = try broken(mo("=") + mi("alpha") + mo("+", "linebreak=\"newline\"") + mi("beta") + mo(","))
        let unbroken = try width(mo("=") + mi("alpha") + mo("+") + mi("beta") + mo(","))
        XCTAssertEqual(edged.rows[0].width + edged.rows[1].width + medium, unbroken, accuracy: 0.01)
    }

    // MARK: Indentation

    func testDefaultIndentation() throws {
        let body = mi("y") + mo("=") + sum(names)
        // Display style: rows are flush left and the rows after the first are indented by an em.
        let display = try broken(body, width: 150, display: true)
        XCTAssertGreaterThan(display.rows.count, 2)
        XCTAssertEqual(display.rows.map(\.origin.x), [0] + [CGFloat](repeating: em, count: display.rows.count - 1))
        for row in display.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, 150.001) }
        // An inline formula does not indent: its rows continue the text's lines.
        let inline = try broken(body, width: 150)
        XCTAssertGreaterThan(inline.rows.count, 2)
        XCTAssertEqual(inline.rows.map(\.origin.x), [CGFloat](repeating: 0, count: inline.rows.count))
        // Forced breaks indent the same way.
        let forced = try broken(mi("alpha") + mo("=", "linebreak=\"newline\"") + mi("beta"), display: true)
        XCTAssertEqual(forced.rows.map(\.origin.x), [0, em])
        XCTAssertEqual(forced.width, max(forced.rows[0].width, em + forced.rows[1].width), accuracy: 0.001)
        // The em is the formula's.
        let large = try MathLayout(node(body, display: true), style: MathStyle(fontSize: 30, color: black), maximumWidth: 150)
        XCTAssertEqual(large.rows[1].origin.x, 30)
        // An unbreakable unit too wide for what the indentation leaves gives the indentation up.
        let wide = try width(mo("=") + mi("abcdefghijklmnop"))
        let tight = try broken(mi("y") + mo("=") + mi("abcdefghijklmnop") + mo("+") + mi("z"), width: wide - thick + 5, display: true)
        XCTAssertEqual(tight.rows.count, 3)
        XCTAssertEqual(tight.rows[1].origin.x, 5, accuracy: 0.01)
        XCTAssertEqual(tight.rows[2].origin.x, em)
        XCTAssertLessThanOrEqual(tight.widestUnbreakableWidth, wide - thick + 5)
    }

    func testIndentAlignAndShift() throws {
        let body = mi("y") + mo("=") + sum(names)
        func styled(_ attributes: String, width: CGFloat = 150, display: Bool = true) throws -> MathLayout {
            try broken("<mstyle \(attributes)>\(body)</mstyle>", width: width, display: display)
        }
        // Explicit alignment always applies, in either style, within the line's width.
        for display in [false, true] {
            var layout = try styled("indentalign=\"left\"", display: display)
            XCTAssertGreaterThan(layout.rows.count, 2)
            for row in layout.rows { XCTAssertEqual(row.origin.x, 0) }
            layout = try styled("indentalign=\"center\"", display: display)
            for row in layout.rows { XCTAssertEqual(row.origin.x + row.width / 2, 75, accuracy: 0.001) }
            layout = try styled("indentalign=\"right\"", display: display)
            for row in layout.rows { XCTAssertEqual(row.origin.x + row.width, 150, accuracy: 0.001) }
            XCTAssertEqual(layout.width, 150, accuracy: 0.001)
        }
        // `indentshift` moves every row from where its alignment puts it; a share is of the line's width.
        var layout = try styled("indentalign=\"left\" indentshift=\"1.5em\"")
        for row in layout.rows { XCTAssertEqual(row.origin.x, 1.5 * em, accuracy: 0.001) }
        layout = try styled("indentshift=\"10%\"")
        for row in layout.rows { XCTAssertEqual(row.origin.x, 15, accuracy: 0.001) }
        layout = try styled("indentalign=\"right\" indentshift=\"-12px\"")
        for row in layout.rows { XCTAssertEqual(row.origin.x + row.width, 138, accuracy: 0.001) }
        layout = try styled("indentalign=\"center\" indentshift=\"10px\"")
        for row in layout.rows { XCTAssertEqual(row.origin.x + row.width / 2, 85, accuracy: 0.001) }
        for row in layout.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, 150.001) }
        // The first and last rows have their own.
        layout = try styled("indentalign=\"left\" indentshift=\"2em\" indentshiftfirst=\"0\" indentalignlast=\"right\" indentshiftlast=\"0\"")
        XCTAssertGreaterThan(layout.rows.count, 3)
        XCTAssertEqual(layout.rows[0].origin.x, 0)
        for row in layout.rows.dropFirst().dropLast() { XCTAssertEqual(row.origin.x, 2 * em, accuracy: 0.001) }
        XCTAssertEqual(layout.rows.last!.origin.x + layout.rows.last!.width, 150, accuracy: 0.001)
        layout = try styled("indentalignfirst=\"center\" indentshiftlast=\"3em\"")
        XCTAssertEqual(layout.rows[0].origin.x + layout.rows[0].width / 2, 75, accuracy: 0.001)
        XCTAssertEqual(layout.rows[1].origin.x, em, "the rest are `auto`: the default indentation")
        XCTAssertEqual(layout.rows.last!.origin.x, 3 * em, accuracy: 0.001)
        // With exactly two rows the second is the last (MathML 3, 3.2.5.2.3).
        layout = try broken(mi("alpha") + mo("=", "linebreak=\"newline\" indentshift=\"1em\" indentshiftlast=\"4em\"") + mi("beta"))
        XCTAssertEqual(layout.rows.map(\.origin.x), [0, 4 * em])
        // The first row's apply to a formula of one row, with or without a width.
        layout = try broken("<mstyle indentshiftfirst=\"2em\">" + mi("alpha") + "</mstyle>")
        XCTAssertEqual(layout.rows[0].origin.x, 2 * em)
        XCTAssertEqual(layout.width, 2 * em + layout.rows[0].width, accuracy: 0.001)
        layout = try broken("<mstyle indentalignfirst=\"right\">" + mi("alpha") + "</mstyle>", width: 200)
        XCTAssertEqual(layout.rows[0].origin.x + layout.rows[0].width, 200, accuracy: 0.001)
        // The attributes are read at the operator the line breaks at, which may set its own.
        layout = try broken(mi("alpha") + mo("=", "linebreak=\"newline\" indentshift=\"3em\"") + mi("beta")
            + mo("+", "linebreak=\"newline\" indentalign=\"left\"") + mi("gamma"), display: true)
        XCTAssertEqual(layout.rows.map(\.origin.x), [0, 3 * em, 0])
        // And on `math` itself.
        var root = try node(mi("alpha") + mo("=", "linebreak=\"newline\"") + mi("beta"))
        root.attributes["indentshift"] = "25px"
        root.attributes["indentshiftfirst"] = "5px"
        let rooted = try MathLayout(root, style: MathStyle(fontSize: em, color: black))
        XCTAssertEqual(rooted.rows.map(\.origin.x), [5, 25])
        // With no line to align within, centred and right-aligned rows align within the widest row.
        let free = "<mstyle indentalign=\"ALIGN\">" + sum(Array(names.prefix(3))) + mo("=", "linebreak=\"newline\"") + mi("x")
            + mo("+", "linebreak=\"newline\"") + mi("yy") + "</mstyle>"
        layout = try broken(free.replacingOccurrences(of: "ALIGN", with: "center"))
        XCTAssertEqual(layout.rows.count, 3)
        XCTAssertEqual(layout.rows[0].origin.x, 0)
        XCTAssertEqual(layout.width, layout.rows[0].width, accuracy: 0.001)
        for row in layout.rows { XCTAssertEqual(row.origin.x + row.width / 2, layout.width / 2, accuracy: 0.001) }
        layout = try broken(free.replacingOccurrences(of: "ALIGN", with: "right"))
        for row in layout.rows { XCTAssertEqual(row.origin.x + row.width, layout.width, accuracy: 0.001) }
        // Values that do not parse change nothing.
        layout = try styled("indentalign=\"middle\" indentshift=\"wide\" lineleading=\"tall\" linebreak=\"maybe\"")
        let plain = try broken(body, width: 150, display: true)
        XCTAssertEqual(layout.rows.map(\.origin), plain.rows.map(\.origin))
    }

    func testIndentationIsReadAtTheOperatorALineBreaksAt() throws {
        // On an operator the attributes "control linebreaking and indentation of the following line"
        // (MathML 3, 3.1.7.1): the row after the break there, and no row after that.
        var layout = try broken(mi("alpha") + mo("=", "linebreak=\"newline\" indentshift=\"3em\"") + mi("beta")
            + mo("+", "linebreak=\"newline\"") + mi("gamma"))
        XCTAssertEqual(layout.rows.map(\.origin.x), [0, 3 * em, 0])
        // They "apply if a linebreak occurs at that element" (3.2.5.2.3): where none does, they do nothing.
        layout = try broken(mi("alpha") + mo("=", "indentshift=\"3em\" indentshiftfirst=\"2em\"") + mi("beta")
            + mo("+", "linebreak=\"newline\"") + mi("gamma"))
        XCTAssertEqual(layout.rows.map(\.origin.x), [0, 0])
        // Whose `indentshiftfirst` places the first row the specification leaves open. Here it is the
        // operator the first row ends at,
        layout = try broken(mi("alpha") + mo("=", "linebreak=\"newline\" indentshiftfirst=\"2em\"") + mi("beta"))
        XCTAssertEqual(layout.rows.map(\.origin.x), [2 * em, 0])
        // not one that a later row ends at,
        layout = try broken(mi("alpha") + mo("=", "linebreak=\"newline\"") + mi("beta")
            + mo("+", "linebreak=\"newline\" indentshiftfirst=\"2em\"") + mi("gamma"))
        XCTAssertEqual(layout.rows.map(\.origin.x), [0, 0, 0])
        // and failing that the row the formula starts in, which is all a formula of one row has.
        layout = try broken("<mstyle indentshiftfirst=\"2em\">" + mi("alpha") + "</mstyle>" + mo("=") + mi("beta"))
        XCTAssertEqual(layout.rows.map(\.origin.x), [2 * em])
        layout = try broken("<mstyle indentshiftfirst=\"2em\">" + mi("alpha") + "</mstyle>" + mo("=", "linebreak=\"newline\"") + mi("beta"))
        XCTAssertEqual(layout.rows.map(\.origin.x), [2 * em, 0])
    }

    func testIndentTargetAlignsWithAnElementAbove() throws {
        // MathML 3's own example (3.2.5.9): the second "=" under the first, the last "+" under the first.
        let lhs = "<mrow><mi>f</mi><mo>\u{2061}</mo><mo>(</mo><mi>x</mi><mo>)</mo></mrow>"
        let power = "<msup><mrow><mo>(</mo><mrow><mi>x</mi><mo>+</mo><mn>1</mn></mrow><mo>)</mo></mrow><mn>4</mn></msup>"
        let first = "<msup><mi>x</mi><mn>4</mn></msup>"
        let body = "<mrow>\(lhs)<mo id='eq1-equals'>=</mo><mrow>\(power)"
            + "<mo linebreak='newline' linebreakstyle='before' indentalign='id' indenttarget='eq1-equals'>=</mo>"
            + "<mrow>\(first)<mo id='eq1-plus'>+</mo><mrow><mn>4</mn><mo>\u{2062}</mo><msup><mi>x</mi><mn>3</mn></msup></mrow>"
            + "<mo>+</mo><mrow><mn>6</mn><mo>\u{2062}</mo><msup><mi>x</mi><mn>2</mn></msup></mrow>"
            + "<mo linebreak='newline' linebreakstyle='before' indentalignlast='id' indenttarget='eq1-plus'>+</mo>"
            + "<mrow><mn>4</mn><mo>\u{2062}</mo><mi>x</mi></mrow><mo>+</mo><mn>1</mn></mrow></mrow></mrow>"
        let equals = try width(lhs) + thick
        for display in [false, true] {
            let layout = try broken(body, display: display)
            XCTAssertEqual(layout.rows.count, 3)
            XCTAssertEqual(layout.rows[0].origin.x, 0)
            XCTAssertEqual(layout.rows[1].origin.x, equals, accuracy: 0.01, "the row starts where the first \"=\" does")
            let plus = equals + (try width(mo("="))) + thick + (try width(first)) + medium
            XCTAssertEqual(layout.rows[2].origin.x, plus, accuracy: 0.01, "on the second row, the first \"+\" is that far in")
            XCTAssertEqual(layout.width, max(layout.rows[1].origin.x + layout.rows[1].width, layout.rows[0].width), accuracy: 0.001)
        }
        // The target may be any element of the row above: an operand, a nested row.
        var layout = try broken(mi("alpha") + mo("=") + "<mrow id=\"rhs\">" + mi("beta") + mo("+") + mi("gamma") + "</mrow>"
            + mo("+", "linebreak=\"newline\" indentalign=\"id\" indenttarget=\"rhs\"") + mi("delta"), display: true)
        XCTAssertEqual(layout.rows[1].origin.x, try width(mi("alpha")) + 2 * thick + (try width(mo("="))), accuracy: 0.01)
        // `indentshift` is from there.
        layout = try broken(mi("alpha") + mo("=", "id=\"eq\"") + mi("beta")
            + mo("+", "linebreak=\"newline\" indentalign=\"id\" indenttarget=\"eq\" indentshift=\"1em\"") + mi("delta"))
        XCTAssertEqual(layout.rows[1].origin.x, try width(mi("alpha")) + thick + em, accuracy: 0.01)
        // It follows automatic breaks too, row after row, and the rows still fit.
        let long = "<mstyle indentalign=\"id\" indenttarget=\"rhs\">" + mi("y") + mo("=") + "<mrow id=\"rhs\">" + sum(names) + "</mrow></mstyle>"
        layout = try broken(long, width: 160, display: true)
        XCTAssertGreaterThan(layout.rows.count, 3)
        let rhs = try width(mi("y")) + 2 * thick + (try width(mo("=")))
        for row in layout.rows.dropFirst() { XCTAssertEqual(row.origin.x, rhs, accuracy: 0.01) }
        for row in layout.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, 160.001) }
        // An element that is not on a row above (unknown, on the same row, or later) makes it `auto`.
        for target in ["nowhere", "same", "later"] {
            layout = try broken(mi("alpha") + mo("=", "linebreak=\"newline\" indentalign=\"id\" indenttarget=\"\(target)\"")
                + "<mi id=\"same\">beta</mi>" + mo("+", "linebreak=\"newline\"") + "<mi id=\"later\">gamma</mi>", display: true)
            XCTAssertEqual(layout.rows[1].origin.x, em, target)
        }
    }

    // MARK: Text and tables

    func testLongTextWrapsAtItsSpaces() throws {
        let sentence = "the future value of the account after ten years of compound interest"
        let body = "<mtext>\(sentence)</mtext>"
        let whole = try width(body)
        let space = try width("<mtext>a b</mtext>") - (try width("<mtext>a</mtext>")) - (try width("<mtext>b</mtext>"))
        XCTAssertGreaterThan(space, 2)
        for limit in [whole * 0.7, 200, 120] {
            let layout = try broken(body, width: limit)
            XCTAssertGreaterThan(layout.rows.count, 1)
            for row in layout.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, limit + 0.001) }
            // The rows hold all of the text but the space each break replaced.
            // (and a hair where a row's last letter leans past its advance).
            XCTAssertEqual(layout.rows.reduce(0) { $0 + $1.width } + CGFloat(layout.rows.count - 1) * space, whole, accuracy: 1.5)
        }
        // Each row is the words it holds, measured as text.
        let two = try broken("<mtext>alpha beta gamma delta</mtext>", width: try width("<mtext>alpha beta gamma</mtext>") + 1)
        assertWidths(two, [try width("<mtext>alpha beta gamma</mtext>"), try width("<mtext>delta</mtext>")])
        // A word wider than the line overflows alone, and is what cannot break.
        let narrow = try broken(body, width: 30)
        XCTAssertEqual(narrow.rows.count, sentence.split(separator: " ").count)
        XCTAssertEqual(narrow.widestUnbreakableWidth, try width("<mtext>compound</mtext>"), accuracy: 0.6)
        XCTAssertEqual(try broken(body).widestUnbreakableWidth, narrow.widestUnbreakableWidth, accuracy: 0.001, "whatever the width")
        // Text among operators: the relation is the better place, the text's spaces the next.
        let mixed = "<mtext>the future value</mtext>" + red("=") + "<mtext>the principal and its growth</mtext>"
        var layout = try broken(mixed, width: try width(mixed) - 1)
        XCTAssertEqual(layout.rows.count, 2)
        XCTAssertTrue(starts(layout.rows[1], with: .red), "an operator that is first after an mtext is still the relation it is")
        layout = try broken(mixed, width: try width("<mtext>the future</mtext>") + 1)
        XCTAssertGreaterThan(layout.rows.count, 4)
        for row in layout.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, try width("<mtext>the future</mtext>") + 1.001) }
        // A no-break space keeps its words together, and so does `linebreak="nobreak"` above the text.
        XCTAssertEqual(try broken("<mtext>alpha\u{A0}beta gamma</mtext>", width: 0).rows.count, 2)
        XCTAssertEqual(try broken("<mstyle linebreak=\"nobreak\"><mtext>alpha beta gamma</mtext></mstyle>", width: 0).rows.count, 1)
        // Right-to-left text stays whole: its words are drawn last first.
        XCTAssertEqual(try broken("<mtext>שלום עולם טוב</mtext>", width: 0).rows.count, 1)
        // Other tokens do not break at spaces.
        XCTAssertEqual(try broken("<mi>alpha beta</mi><mn>1 000 000</mn><ms>a b</ms>", width: 0).rows.count, 1)
    }

    func testTableCellsWrap() throws {
        let cases = "<mtable columnalign=\"left left\"><mtr><mtd><msup><mi>x</mi><mn>2</mn></msup></mtd>"
            + "<mtd><mtext>if x is greater than or equal to zero</mtext></mtd></mtr>"
            + "<mtr><mtd><mrow><mo>−</mo><mi>x</mi></mrow></mtd><mtd><mtext>otherwise, when it is negative</mtext></mtd></mtr></mtable>"
        let natural = try broken(cases, display: true)
        XCTAssertEqual(natural.rows.count, 1)
        for limit in [natural.width - 1, natural.width * 0.75, natural.width * 0.5] {
            let layout = try broken(cases, width: limit, display: true)
            XCTAssertEqual(layout.rows.count, 1, "a table is one unit: it narrows, its cells wrap")
            XCTAssertLessThanOrEqual(layout.width, limit + 0.001)
            XCTAssertLessThanOrEqual(layout.widestUnbreakableWidth, limit + 0.001)
            XCTAssertGreaterThan(height(layout), height(natural) + em * 0.8, "wrapped cells are taller")
            let ink = try XCTUnwrap(ink(layout))
            XCTAssertLessThanOrEqual(ink.maxX, limit + 0.5)
            XCTAssertGreaterThan(ink.maxX, limit * 0.6, "the columns take the room there is")
        }
        // Narrower than its words allow, it is as narrow as they do, and says so.
        let least = try broken(cases, width: 20, display: true)
        XCTAssertEqual(least.rows.count, 1)
        XCTAssertGreaterThan(least.width, 20)
        XCTAssertEqual(least.widestUnbreakableWidth, least.width, accuracy: 0.001)
        XCTAssertLessThan(least.width, natural.width / 2)
        XCTAssertEqual(try broken(cases, width: least.width, display: true).width, least.width, accuracy: 0.01)
        // Beside its brace, the table narrows to leave room for it rather than move to a row of its own.
        let function = "<mi>f</mi><mo>\u{2061}</mo><mrow><mo>(</mo><mi>x</mi><mo>)</mo></mrow><mo>=</mo><mrow><mo>{</mo>\(cases)</mrow>"
        let unbroken = try broken(function, display: true)
        for limit in [unbroken.width - 1, unbroken.width * 0.8] {
            let layout = try broken(function, width: limit, display: true)
            XCTAssertEqual(layout.rows.count, 1, "\(limit)")
            XCTAssertLessThanOrEqual(layout.width, limit + 0.001)
        }
        // When even that is too little, the row breaks before the relation and the table fills the line.
        let narrow = try broken(function, width: least.width + 45, display: true)
        XCTAssertEqual(narrow.rows.count, 2)
        for row in narrow.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, least.width + 45.001) }
        // Cells of operators wrap at their operators, each column to its own width.
        let aligned = "<mtable columnalign=\"right left\"><mtr><mtd><mi>y</mi></mtd><mtd>" + mo("=") + sum(names) + "</mtd></mtr>"
            + "<mtr><mtd><mi>z</mi></mtd><mtd><mo>=</mo><mn>1</mn></mtd></mtr></mtable>"
        let wide = try broken(aligned, display: true)
        let wrapped = try broken(aligned, width: wide.width / 2, display: true)
        XCTAssertEqual(wrapped.rows.count, 1)
        XCTAssertLessThanOrEqual(wrapped.width, wide.width / 2 + 0.001)
        XCTAssertGreaterThan(height(wrapped), height(wide) + em)
        // A table that fits is untouched, and so is one laid out with no width.
        XCTAssertEqual(try broken(cases, width: natural.width, display: true).width, natural.width)
        XCTAssertEqual(try broken(cases, width: natural.width + 50, display: true).descent, natural.descent)
        // A forced break in a cell stacks it, whatever the width.
        let stacked = try broken("<mtable><mtr><mtd><mi>alpha</mi><mspace linebreak=\"newline\"/><mi>beta</mi></mtd><mtd><mi>x</mi></mtd></mtr></mtable>")
        let flat = try broken("<mtable><mtr><mtd><mi>alpha</mi><mi>beta</mi></mtd><mtd><mi>x</mi></mtd></mtr></mtable>")
        XCTAssertGreaterThan(height(stacked), height(flat) + em * 0.8)
        XCTAssertLessThan(stacked.width, flat.width - 10)
    }

    func testFractionsRadicalsAndEnclosuresWrapTheirContent() throws {
        let long = sum(names)
        for (body, name) in [
            ("<mfrac><mrow>\(long)</mrow><mn>2</mn></mfrac>", "numerator"),
            ("<mfrac><mn>1</mn><mrow>\(long)</mrow></mfrac>", "denominator"),
            ("<msqrt>\(long)</msqrt>", "radicand"),
            ("<mroot><mrow>\(long)</mrow><mn>3</mn></mroot>", "root"),
            ("<menclose notation=\"box\">\(long)</menclose>", "enclosure"),
        ] {
            let natural = try broken(body, display: true)
            for limit in [natural.width - 1, natural.width / 2] {
                let layout = try broken(body, width: limit, display: true)
                XCTAssertEqual(layout.rows.count, 1, name)
                XCTAssertLessThanOrEqual(layout.width, limit + 0.001, name)
                XCTAssertGreaterThan(height(layout), height(natural) + em * 0.8, name)
                let ink = try XCTUnwrap(ink(layout))
                XCTAssertLessThanOrEqual(ink.maxX, layout.width + 0.5, name)
                XCTAssertLessThanOrEqual(ink.maxY, layout.ascent + 0.5, name)
                XCTAssertGreaterThanOrEqual(ink.minY, -layout.descent - 0.5, name)
            }
            XCTAssertEqual(try broken(body, width: natural.width, display: true).descent, natural.descent, name)
        }
        // Beside other terms the fraction narrows as far as its row needs.
        let body = "<mi>y</mi><mo>=</mo><mfrac><mrow>\(long)</mrow><mn>2</mn></mfrac><mo>+</mo><mn>1</mn>"
        let layout = try broken(body, width: 200, display: true)
        for row in layout.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, 200.001) }
        XCTAssertLessThanOrEqual(layout.widestUnbreakableWidth, 200.001)
        // Where the row can break instead, it does: the fraction is whole on the row after the relation.
        let fraction = "<mfrac><mrow>\(sum(Array(names.prefix(4))))</mrow><mn>2</mn></mfrac>"
        let unbroken = try broken(mi("y") + mo("=") + fraction, display: true)
        let equation = try broken(mi("y") + mo("=") + fraction, width: unbroken.width - 5, display: true)
        XCTAssertEqual(equation.rows.count, 2)
        XCTAssertEqual(equation.rows[1].ascent, try broken(fraction, display: true).ascent, accuracy: 0.01)
        // A forced break inside one stacks its lines whatever the width.
        let forced = try broken("<mfrac><mrow><mi>alpha</mi><mo linebreak=\"newline\">+</mo><mi>beta</mi></mrow><mn>2</mn></mfrac>", display: true)
        let whole = try broken("<mfrac><mrow><mi>alpha</mi><mo>+</mo><mi>beta</mi></mrow><mn>2</mn></mfrac>", display: true)
        XCTAssertEqual(forced.rows.count, 1)
        XCTAssertGreaterThan(forced.ascent, whole.ascent + em * 0.8)
        XCTAssertLessThan(forced.width, whole.width - 20)
    }

    func testWhatIsNotARowIsOneUnit() throws {
        let inner = sum(Array(names.prefix(4)))
        let natural = try width(inner)
        // A phantom, a row with a background, padding, a limit: a line breaks around them, not inside.
        for body in [
            "<mphantom>\(inner)</mphantom>", "<mrow mathbackground=\"yellow\">\(inner)</mrow>", "<mpadded>\(inner)</mpadded>",
            "<munder><mrow>\(inner)</mrow><mo>⏟</mo></munder>", "<mover><mrow>\(inner)</mrow><mo>¯</mo></mover>",
        ] {
            let layout = try broken(mi("x") + mo("=") + body + mo("+") + mi("y"), width: 0)
            XCTAssertEqual(layout.rows.count, 3, body)
            XCTAssertGreaterThanOrEqual(layout.rows[1].width, natural, body)
            XCTAssertGreaterThanOrEqual(layout.widestUnbreakableWidth, natural, body)
        }
        let phantom = try broken("<mphantom>\(inner)</mphantom>", width: 0)
        XCTAssertEqual(phantom.rows.count, 1)
        XCTAssertEqual(phantom.width, natural, accuracy: 0.01)
        XCTAssertNil(ink(phantom), "and a phantom still draws nothing")
        // The same row bare breaks at every operator.
        XCTAssertEqual(try broken(mi("x") + mo("=") + "<mrow>\(inner)</mrow>" + mo("+") + mi("y"), width: 0).rows.count, 6)
    }

    // MARK: Inline formulas and hosts

    func testFirstRowMaximumWidth() throws {
        let body = mi("y") + mo("=") + sum(names)
        let whole = try width(body)
        // The first row fits what is left of the text line, the rest fit the full width.
        let layout = try broken(body, width: 200, first: 80)
        XCTAssertGreaterThan(layout.rows.count, 2)
        XCTAssertLessThanOrEqual(layout.rows[0].width, 80.001)
        for row in layout.rows.dropFirst() { XCTAssertLessThanOrEqual(row.width, 200.001) }
        XCTAssertGreaterThan(layout.rows.dropFirst().map(\.width).max()!, 100, "later rows use the full line")
        XCTAssertEqual(layout.rows.map(\.origin.x), [CGFloat](repeating: 0, count: layout.rows.count), "inline rows do not indent")
        let even = try broken(body, width: 200)
        XCTAssertGreaterThan(even.rows[0].width, 100)
        // It bounds only the first row, even when the formula would fit one full line.
        let short = try broken(body, width: whole + 10, first: 60)
        XCTAssertEqual(short.rows.count, 2)
        XCTAssertLessThanOrEqual(short.rows[0].width, 60.001)
        // With room for everything it changes nothing.
        XCTAssertEqual(try broken(body, width: whole + 10, first: whole + 5).rows.count, 1)
        // Too little for even the first unit: that unit overflows the first row, for the host to see.
        let none = try broken(mi("alpha") + mo("+") + mi("beta"), width: 200, first: 5)
        XCTAssertEqual(none.rows.count, 2)
        assertWidths(none, [try width(mi("alpha")), try width(mo("+")) + medium + (try width(mi("beta")))])
        XCTAssertGreaterThan(none.rows[0].width, 5)
        // The rows are fragments a host draws where it likes: each alone draws what the layout draws there.
        for row in layout.rows {
            let alone = try XCTUnwrap(ink(row))
            XCTAssertGreaterThan(alone.width, row.width * 0.8)
        }
    }

    func testAxisHeightAndWidestUnbreakableWidth() throws {
        let constants = MathFont.named(nil).constants
        for size in [10, 17, 24] as [CGFloat] {
            let layout = try MathLayout(node(mi("x")), style: MathStyle(fontSize: size, color: black))
            XCTAssertEqual(layout.axisHeight, constants.axisHeight * size)
        }
        // A fraction's rule is on the axis the layout reports.
        let fraction = try broken("<mfrac><mi>a</mi><mi>b</mi></mfrac>", display: true)
        XCTAssertEqual((fraction.ascent - fraction.descent) / 2, fraction.axisHeight, accuracy: 3)
        // The widest unit that cannot break: here the fraction, with the operator it starts a row with.
        let body = mi("y") + mo("=") + mi("alpha") + mo("+") + "<mfrac><mrow>" + sum(Array(names.prefix(3))) + "</mrow><mn>2</mn></mfrac>"
            + mo("+") + mi("beta")
        let unit = try width(mo("+")) + medium + (try width("<mfrac><mrow>" + sum(Array(names.prefix(3))) + "</mrow><mn>2</mn></mfrac>"))
        let free = try broken(body)
        XCTAssertEqual(free.rows.count, 1)
        XCTAssertEqual(free.widestUnbreakableWidth, unit, accuracy: 0.01)
        XCTAssertLessThan(free.widestUnbreakableWidth, free.width)
        // At exactly that width no row overflows; any narrower, one does, and the layout says so without throwing.
        let exact = try broken(body, width: unit)
        for row in exact.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, unit + 0.001) }
        XCTAssertEqual(exact.widestUnbreakableWidth, unit, accuracy: 0.01)
        let over = try broken(body, width: 30)
        XCTAssertGreaterThan(over.widestUnbreakableWidth, 30)
        XCTAssertEqual(over.rows.count, 4)
        XCTAssertEqual(over.rows.filter { $0.origin.x + $0.width > 30.001 }.count, 3, "every unit wider than the line overflows alone")
        XCTAssertEqual(over.width, over.rows.map(\.width).max()!, accuracy: 0.001)
        for row in over.rows { XCTAssertEqual(row.origin.x, 0, "a row that overflows starts at the edge") }
        // A formula that is one unit is as wide as itself.
        let single = try broken("<mfrac><mi>a</mi><mi>b</mi></mfrac>", width: 1)
        XCTAssertEqual(single.rows.count, 1)
        XCTAssertEqual(single.widestUnbreakableWidth, single.width)
        // Odd widths are widths: nothing, less than nothing, not a number.
        for odd in [0, -50, CGFloat.nan, -CGFloat.infinity] {
            let layout = try broken(body, width: odd, first: odd)
            XCTAssertEqual(layout.rows.count, odd.isNaN ? 1 : 4, "\(odd)")
        }
    }

    func testBreakingIsDeterministicAndThreadSafe() throws {
        let body = mi("y") + mo("=") + sum(names) + mo("=") + "<mfenced><mrow>" + sum(names) + "</mrow></mfenced>" + mo("×") + "<mtext>some words of text</mtext>"
        let parsed = try node(body, display: true)
        let style = MathStyle(fontSize: 17, color: black)
        let reference = try MathLayout(parsed, style: style, maximumWidth: 180, firstRowMaximumWidth: 90)
        XCTAssertGreaterThan(reference.rows.count, 4)
        func geometry(_ layout: MathLayout) -> [CGFloat] {
            [layout.width, layout.ascent, layout.descent, layout.widestUnbreakableWidth]
                + layout.rows.flatMap { [$0.origin.x, $0.origin.y, $0.width, $0.ascent, $0.descent] }
        }
        let expected = geometry(reference)
        let results = UnsafeMutableBufferPointer<Bool>.allocate(capacity: 64)
        defer { results.deallocate() }
        results.initialize(repeating: false)
        let sendable = SendableResults(buffer: results)
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            let style = MathStyle(fontSize: 17, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            guard let layout = try? MathLayout(parsed, style: style, maximumWidth: 180, firstRowMaximumWidth: 90) else { return }
            let geometry = [layout.width, layout.ascent, layout.descent, layout.widestUnbreakableWidth]
                + layout.rows.flatMap { [$0.origin.x, $0.origin.y, $0.width, $0.ascent, $0.descent] }
            sendable.buffer[index] = geometry == expected
        }
        XCTAssertTrue(results.allSatisfy { $0 })
        XCTAssertEqual(ink(try MathLayout(parsed, style: style, maximumWidth: 180, firstRowMaximumWidth: 90)), ink(reference))
    }

    func testUntrustedInputStaysBounded() throws {
        let style = MathStyle(fontSize: 17, color: black)
        // The limits on depth, nodes and text hold with a width as without.
        let deep = String(repeating: "<mrow>", count: 100) + "<mi>x</mi>" + String(repeating: "</mrow>", count: 100)
        XCTAssertThrowsError(try broken(deep, width: 100)) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded) }
        let many = MathMLNode(name: "math", children: Array(repeating: MathMLNode(name: "mi", text: "x"), count: 30_000))
        XCTAssertThrowsError(try MathLayout(many, style: style, maximumWidth: 100)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
        XCTAssertThrowsError(try broken("<mtext>\(String(repeating: "a ", count: 30_000))</mtext>", width: 100)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
        // A formula whose rows stack past the size limit is refused; unbroken it is too wide, and refused too.
        let tall = MathMLNode(name: "math", children: (0..<6_000).flatMap { _ in
            [MathMLNode(name: "mi", text: "x"), MathMLNode(name: "mo", attributes: ["linebreak": "newline"], text: "+")]
        } + [MathMLNode(name: "mi", text: "x")])
        XCTAssertThrowsError(try MathLayout(tall, style: style)) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded) }
        XCTAssertThrowsError(try broken("<mspace width=\"999em\"/><mspace width=\"999em\"/><mspace width=\"999em\"/>", width: 100)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
        // The largest formula allowed breaks in time near linear in its size, however wide the line:
        // the search looks a bounded way back from each row's end.
        let terms = (0..<9_900).flatMap { _ in [MathMLNode(name: "mi", text: "x"), MathMLNode(name: "mo", text: "+")] }
        let large = MathMLNode(name: "math", children: terms + [MathMLNode(name: "mi", text: "x")])
        let small = MathStyle(fontSize: 2, color: black)
        let whole = try MathLayout(large, style: small)
        XCTAssertEqual(whole.rows.count, 1)
        let start = Date()
        for limit in [whole.width - 1, whole.width / 2, whole.width / 40, 50, 0] {
            let layout = try MathLayout(large, style: small, maximumWidth: limit)
            XCTAssertGreaterThan(layout.rows.count, 1)
            XCTAssertLessThanOrEqual(layout.width, max(limit, layout.widestUnbreakableWidth) + 0.001)
            if limit == whole.width / 2 { XCTAssertEqual(layout.rows.count, 3) }
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 60, "five layouts of 19,801 nodes: seconds, where a quadratic search takes minutes")
        // Ids and targets everywhere, and a forced break at every operator: still bounded.
        let targeted = MathMLNode(name: "math", attributes: ["indentalign": "id", "indenttarget": "t0"], children: (0..<3_000).flatMap {
            [MathMLNode(name: "mi", attributes: ["id": "t\($0)"], text: "x"),
             MathMLNode(name: "mo", attributes: ["linebreak": "newline", "indenttarget": "t\($0)"], text: "+")]
        } + [MathMLNode(name: "mi", text: "x")])
        let rows = try MathLayout(targeted, style: MathStyle(fontSize: 1, color: black), maximumWidth: 40)
        XCTAssertEqual(rows.rows.count, 3_001)
    }
}

private struct SendableResults: @unchecked Sendable {
    let buffer: UnsafeMutableBufferPointer<Bool>
}
