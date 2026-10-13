import CoreGraphics
import Foundation
import MathMLLayout
import XCTest

/// End-to-end checks of what a host relies on, through the public API only (no `@testable`):
/// line breaking, inline fragments, `mglyph`, elementary math and localized readings.
final class AcceptanceTests: MathTestCase {
    private func style(display: Bool = false, images: MathImageProvider? = nil) -> MathStyle {
        MathStyle(fontSize: 20, color: black, isDisplay: display, imageProvider: images)
    }

    private func broken(_ body: String, width: CGFloat, first: CGFloat? = nil, display: Bool = true) throws -> MathLayout {
        try MathLayout(node(body, display: display), style: style(display: display), maximumWidth: width,
                       firstRowMaximumWidth: first)
    }

    /// The width of `body` on one line, as a row holding only it would measure.
    private func natural(_ body: String) throws -> CGFloat { try layout(body, display: true).width }

    // MARK: Bitmaps

    private struct Bitmap: Equatable {
        var width: Int, height: Int
        var pixels: [UInt8]
        /// Premultiplied RGBA at a point, y up from the bottom-left.
        func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let offset = ((height - 1 - y) * width + x) * 4
            return (pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
        }
        /// Bounds of everything drawn, in pixels, y up.
        var ink: CGRect? {
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
            for y in 0..<height {
                for x in 0..<width where pixel(x: x, y: y).a > 24 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
    }

    /// A `width` × `height` point canvas at 2x, y up, drawn by `draw`.
    private func bitmap(width: CGFloat, height: CGFloat, draw: (CGContext) -> Void) -> Bitmap {
        let scale: CGFloat = 2
        let columns = max(Int((width * scale).rounded(.up)), 1), rows = max(Int((height * scale).rounded(.up)), 1)
        let context = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        draw(context)
        let data = context.data!.bindMemory(to: UInt8.self, capacity: columns * rows * 4)
        return Bitmap(width: columns, height: rows, pixels: Array(UnsafeBufferPointer(start: data, count: columns * rows * 4)))
    }

    /// The ink of one row drawn alone, in points relative to its baseline origin.
    private func ink(of row: MathLayout.Row, margin: CGFloat = 20) -> CGRect? {
        let drawn = bitmap(width: row.width + 2 * margin, height: row.ascent + row.descent + 2 * margin) {
            row.draw(in: $0, baselineOrigin: CGPoint(x: margin, y: margin + row.descent))
        }
        return drawn.ink.map {
            CGRect(x: $0.minX / 2 - margin, y: $0.minY / 2 - margin - row.descent, width: $0.width / 2, height: $0.height / 2)
        }
    }

    /// A 20 × 10 pixel image, red above and blue below.
    private func flag() -> CGImage {
        let context = CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 80,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 5))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 5, width: 20, height: 5))
        return context.makeImage()!
    }

    // MARK: Line breaking

    private func terms(_ names: [String], _ operators: [String]) -> String {
        var body = ""
        for (index, name) in names.enumerated() {
            if index > 0 { body += "<mo>\(operators[(index - 1) % operators.count])</mo>" }
            body += "<mi>\(name)</mi>"
        }
        return body
    }

    func testAFormulaWiderThanItsLineBreaksIntoRowsThatFit() throws {
        let body = "<mi>yyyy</mi><mo>=</mo>" + terms((1...12).map { "term\($0)" }, ["+", "−"])
        let unbroken = try layout(body, display: true)
        XCTAssertEqual(unbroken.rows.count, 1)
        XCTAssertEqual(unbroken.rows[0].width, unbroken.width, accuracy: 0.01)
        for divisor in [2.0, 3.0, 5.0] as [CGFloat] {
            let limit = unbroken.width / divisor
            let result = try broken(body, width: limit)
            XCTAssertGreaterThanOrEqual(result.rows.count, Int(divisor), "\(divisor)")
            for row in result.rows {
                XCTAssertLessThanOrEqual(row.origin.x + row.width, limit + 0.01, "\(divisor)")
                XCTAssertGreaterThan(row.width, 0)
            }
            XCTAssertLessThanOrEqual(result.width, limit + 0.01)
            // Rows run down the page from the first row's baseline, without overlapping.
            XCTAssertEqual(result.rows[0].origin.y, 0, accuracy: 0.01)
            XCTAssertEqual(result.ascent, result.rows[0].ascent, accuracy: 0.01)
            for (upper, lower) in zip(result.rows, result.rows.dropFirst()) {
                XCTAssertLessThanOrEqual(lower.origin.y + lower.ascent, upper.origin.y - upper.descent + 0.01)
            }
            let last = result.rows[result.rows.count - 1]
            XCTAssertEqual(result.descent, last.descent - last.origin.y, accuracy: 0.01)
        }
    }

    func testBreaksPreferRelationsThenAdditiveThenMultiplicativeOperators() throws {
        // One break is needed, and every operator is a place it could go.
        let relation = "<mi>aaaa</mi><mo>+</mo><mi>bbbb</mi><mo>=</mo><mi>cccc</mi><mo>+</mo><mi>dddd</mi>"
        var result = try broken(relation, width: try natural(relation) * 0.8)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows[0].width, try natural("<mi>aaaa</mi><mo>+</mo><mi>bbbb</mi>"), accuracy: 1.5)

        let additive = "<mi>aaaa</mi><mo>×</mo><mi>bbbb</mi><mo>+</mo><mi>cccc</mi><mo>×</mo><mi>dddd</mi>"
        result = try broken(additive, width: try natural(additive) * 0.8)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows[0].width, try natural("<mi>aaaa</mi><mo>×</mo><mi>bbbb</mi>"), accuracy: 1.5)

        // Nesting costs: an outer plus wins over the one inside the parentheses.
        let nested = "<mi>aaaa</mi><mo>+</mo><mrow><mo>(</mo><mi>bbbb</mi><mo>+</mo><mi>cccc</mi><mo>)</mo></mrow><mo>+</mo><mi>dddd</mi>"
        result = try broken(nested, width: try natural(nested) * 0.85)
        XCTAssertEqual(result.rows.count, 2)
        let inside = try natural("<mi>aaaa</mi><mo>+</mo><mrow><mo>(</mo><mi>bbbb</mi></mrow>")
        XCTAssertGreaterThan(abs(result.rows[0].width - inside), 3, "broke inside the parentheses")
    }

    func testBreaksInsideNestedRowsAndFences() throws {
        let sum = terms((1...8).map { "term\($0)" }, ["+"])
        for group in ["<mrow><mo>(</mo>\(sum)<mo>)</mo></mrow>", "<mfenced><mrow>\(sum)</mrow></mfenced>",
                      "<mfenced open=\"[\" close=\"]\"><mi>first</mi><mrow>\(sum)</mrow></mfenced>",
                      "<mstyle mathcolor=\"red\"><mrow><mrow>\(sum)</mrow></mrow></mstyle>"] {
            let body = "<mi>y</mi><mo>=</mo>" + group
            let limit = try natural(group) / 3
            let result = try broken(body, width: limit)
            XCTAssertGreaterThanOrEqual(result.rows.count, 3, group)
            for row in result.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, limit + 0.01, group) }
        }
        // A bracket pair split across rows keeps one size: the closing one is as tall as the
        // opening one, which the fraction on the first row stretched.
        let tall = "<mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mfrac><mi>c</mi><mi>d</mi></mfrac></mfrac>"
        let split = try broken("<mfenced><mrow>\(tall)<mo>+</mo><mi>bbbb</mi><mo linebreak=\"newline\">+</mo><mi>cccc</mi></mrow></mfenced>",
                               width: .infinity)
        XCTAssertEqual(split.rows.count, 2)
        let heights = split.rows.map { $0.ascent + $0.descent }
        XCTAssertGreaterThan(heights[1], heights[0] * 0.85)
        XCTAssertGreaterThan(heights[1], try height(layout("<mo>+</mo><mi>cccc</mi><mo>)</mo>", display: true)) * 1.5)
    }

    func testAuthoredLineBreaksApply() throws {
        let forced = try broken("<mi>aaaa</mi><mo linebreak=\"newline\">=</mo><mi>bbbb</mi>", width: .infinity)
        XCTAssertEqual(forced.rows.count, 2)
        XCTAssertEqual(forced.rows[0].width, try natural("<mi>aaaa</mi>"), accuracy: 1.5, "the operator starts the next row")
        XCTAssertEqual(try layout("<mi>aaaa</mi><mo linebreak=\"newline\">=</mo><mi>bbbb</mi>").rows.count, 2,
                       "forced breaks need no width")
        let after = try broken("<mi>aaaa</mi><mo linebreak=\"newline\" linebreakstyle=\"after\">=</mo><mi>bbbb</mi>", width: .infinity)
        XCTAssertEqual(after.rows.count, 2)
        XCTAssertEqual(after.rows[1].width, try natural("<mi>bbbb</mi>"), accuracy: 1.5, "the operator ends its row")
        let space = try broken("<mi>aaaa</mi><mspace linebreak=\"newline\"/><mi>bbbb</mi>", width: .infinity)
        XCTAssertEqual(space.rows.count, 2)
        // nobreak: the only place left to break is the plus.
        let kept = "<mi>aaaa</mi><mo linebreak=\"nobreak\">=</mo><mi>bbbb</mi><mo>+</mo><mi>cccc</mi>"
        let result = try broken(kept, width: try natural(kept) * 0.8)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows[0].width, try natural("<mi>aaaa</mi><mo>=</mo><mi>bbbb</mi>"), accuracy: 1.5)
    }

    func testAnOperatorThatStartsARowKeepsItsBinarySpacing() throws {
        let result = try broken("<mi>aaaa</mi><mo linebreak=\"newline\">+</mo><mi>bbbb</mi>", width: .infinity)
        XCTAssertEqual(result.rows.count, 2)
        // Laid out on its own, a leading plus is a sign and sits tight against its operand.
        let sign = try natural("<mo>+</mo><mi>bbbb</mi>")
        XCTAssertEqual(result.rows[1].width - sign, 20 * 4 / 18, accuracy: 1)
    }

    func testIndentationAttributes() throws {
        let body = { (attributes: String) in
            "<mi>aaaa</mi><mo>=</mo><mi>bbbb</mi><mo linebreak=\"newline\" \(attributes)>+</mo><mi>cccc</mi>"
        }
        let shifted = try broken(body("indentalign=\"left\" indentshift=\"3em\""), width: 400)
        XCTAssertEqual(shifted.rows[1].origin.x - shifted.rows[0].origin.x, 60, accuracy: 0.5)
        let right = try broken(body("indentalign=\"right\""), width: 400)
        XCTAssertEqual(right.rows[1].origin.x + right.rows[1].width, 400, accuracy: 0.5)
        let centre = try broken(body("indentalign=\"center\""), width: 400)
        XCTAssertEqual(centre.rows[1].origin.x + centre.rows[1].width / 2, 200, accuracy: 0.5)
        // Display rows indent their continuations by default; inline fragments do not.
        let display = try broken(body(""), width: 400)
        XCTAssertGreaterThan(display.rows[1].origin.x, display.rows[0].origin.x + 1)
        let inline = try broken(body(""), width: 400, display: false)
        XCTAssertEqual(inline.rows[1].origin.x, inline.rows[0].origin.x, accuracy: 0.01)
    }

    func testLongTextAndTableCellsWrap() throws {
        let words = (1...24).map { "word\($0)" }.joined(separator: " ")
        let text = "<mtext>\(words)</mtext>"
        let limit = try natural(text) / 4
        let wrapped = try broken(text, width: limit)
        XCTAssertGreaterThanOrEqual(wrapped.rows.count, 4)
        for row in wrapped.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, limit + 0.01) }

        let table = "<mtable><mtr><mtd><mtext>\(words)</mtext></mtd><mtd>\(terms((1...10).map { "term\($0)" }, ["+"]))</mtd></mtr>"
            + "<mtr><mtd><mi>x</mi></mtd><mtd><mi>y</mi></mtd></mtr></mtable>"
        let wide = try layout(table, display: true)
        let narrow = try broken(table, width: wide.width / 3)
        XCTAssertLessThanOrEqual(narrow.width, wide.width / 3 + 0.01)
        XCTAssertGreaterThan(narrow.ascent + narrow.descent, (wide.ascent + wide.descent) * 1.5, "cells grew taller as they wrapped")
    }

    func testAxisHeightAndWidestUnbreakableUnitArePublic() throws {
        let body = "<mi>y</mi><mo>=</mo>" + terms(["short", "muchlongeridentifier", "mid"], ["+"])
        let small = try layout(body, display: true)
        XCTAssertGreaterThan(small.axisHeight, 0.2 * 20)
        XCTAssertLessThan(small.axisHeight, 0.3 * 20)
        let large = try MathLayout(node(body, display: true), style: MathStyle(fontSize: 40, color: black, isDisplay: true))
        XCTAssertEqual(large.axisHeight, small.axisHeight * 2, accuracy: 0.01)
        // A fraction's bar lies on the axis.
        let bar = try XCTUnwrap(ink(try layout("<mfrac><mphantom><mi>a</mi></mphantom><mphantom><mi>b</mi></mphantom></mfrac>", display: true)))
        XCTAssertEqual(bar.midY, small.axisHeight, accuracy: 0.5)

        let unit = small.widestUnbreakableWidth
        XCTAssertGreaterThanOrEqual(unit, try natural("<mi>muchlongeridentifier</mi>") - 1)
        XCTAssertLessThan(unit, small.width)
        // It is the narrowest width that still holds every row.
        let tight = try broken(body, width: unit)
        for row in tight.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, unit + 0.01) }
        XCTAssertEqual(tight.widestUnbreakableWidth, unit, accuracy: 0.01)
        // Narrower than that, the unit overflows instead of throwing, and the host can tell.
        let overflowing = try broken(body, width: unit / 2)
        XCTAssertGreaterThan(overflowing.width, unit / 2)
        XCTAssertGreaterThan(overflowing.widestUnbreakableWidth, unit / 2)
    }

    // MARK: Inline fragments

    func testInlineRowsAreSeparatelyDrawableFragments() throws {
        let body = "<mi>yyyy</mi><mo>=</mo>" + terms((1...9).map { "term\($0)" }, ["+", "−"])
            + "<mo>+</mo><mfrac><mi>a</mi><mi>b</mi></mfrac><mo>+</mo><msup><mi>f</mi><mn>2</mn></msup>"
        let result = try broken(body, width: 240, first: 90, display: false)
        XCTAssertGreaterThanOrEqual(result.rows.count, 3)
        XCTAssertLessThanOrEqual(result.rows[0].width, 90.01, "the first fragment fits what is left of its text line")
        XCTAssertGreaterThan(result.rows[1].width, 90, "later fragments get the whole line")
        for row in result.rows {
            XCTAssertLessThanOrEqual(row.width, 240.01)
            // Each fragment's box covers its own ink, so a host can place and clip it alone.
            let drawn = try XCTUnwrap(ink(of: row))
            XCTAssertGreaterThanOrEqual(drawn.minX, -0.5)
            XCTAssertLessThanOrEqual(drawn.maxX, row.width + 0.5)
            XCTAssertLessThanOrEqual(drawn.maxY, row.ascent + 0.5)
            XCTAssertGreaterThanOrEqual(drawn.minY, -row.descent - 0.5)
        }
        // Drawing every fragment at its origin is drawing the layout.
        let size = CGSize(width: result.width + 20, height: result.ascent + result.descent + 20)
        let origin = CGPoint(x: 10, y: 10 + result.descent)
        let whole = bitmap(width: size.width, height: size.height) { result.draw(in: $0, baselineOrigin: origin) }
        let pieces = bitmap(width: size.width, height: size.height) { context in
            for row in result.rows {
                row.draw(in: context, baselineOrigin: CGPoint(x: origin.x + row.origin.x, y: origin.y + row.origin.y))
            }
        }
        XCTAssertNotNil(whole.ink)
        XCTAssertEqual(whole, pieces)
    }

    // MARK: mglyph

    func testGlyphImagesLayOutAndDraw() throws {
        let image = flag()
        let requests = Requests()
        let images = MathImageProvider { source in
            requests.add(source)
            return source == "flag.png" ? image : nil
        }
        func glyphs(_ body: String) throws -> MathLayout { try MathLayout(node(body), style: style(images: images)) }

        // In a token, sized by its attributes: 30 wide, its bottom 5 below the baseline.
        let sized = try glyphs("<mi><mglyph src=\"flag.png\" width=\"30px\" height=\"20px\" valign=\"-5px\" alt=\"flag\"/></mi>")
        XCTAssertEqual(sized.width, 30, accuracy: 0.01)
        XCTAssertEqual(sized.ascent, 15, accuracy: 0.01)
        XCTAssertEqual(sized.descent, 5, accuracy: 0.01)
        XCTAssertEqual(requests.sources, ["flag.png"])
        let drawn = bitmap(width: 30, height: 20) { sized.draw(in: $0, baselineOrigin: CGPoint(x: 0, y: 5)) }
        let top = drawn.pixel(x: 30, y: 34), bottom = drawn.pixel(x: 30, y: 6)
        XCTAssertTrue(top.r > 200 && top.b < 60, "the image is upright: red above")
        XCTAssertTrue(bottom.b > 200 && bottom.r < 60, "and blue below")

        // Without sizes, the image's own; with one, its proportions.
        let intrinsic = try glyphs("<mtext><mglyph src=\"flag.png\" alt=\"flag\"/></mtext>")
        XCTAssertEqual(intrinsic.width, 20, accuracy: 0.01)
        XCTAssertEqual(intrinsic.ascent + intrinsic.descent, 10, accuracy: 0.01)
        let proportional = try glyphs("<mn><mglyph src=\"flag.png\" width=\"60px\" alt=\"flag\"/></mn>")
        XCTAssertEqual(proportional.ascent + proportional.descent, 30, accuracy: 0.01)

        // At row level (MathML 2), and mixed with a token's text.
        let x = try glyphs("<mi>x</mi>").width
        let rowLevel = try glyphs("<mrow><mi>x</mi><mglyph src=\"flag.png\" alt=\"flag\"/></mrow>")
        XCTAssertEqual(rowLevel.width, x + 20, accuracy: 1)
        let mixed = try glyphs("<mtext>ab<mglyph src=\"flag.png\" alt=\"flag\"/>cd</mtext>")
        XCTAssertEqual(mixed.width, try glyphs("<mtext>ab</mtext>").width + 20 + (try glyphs("<mtext>cd</mtext>").width), accuracy: 1)
    }

    func testGlyphsWithoutAnImageFallBackToTheirAltText() throws {
        let alt = try layout("<mtext>flag</mtext>")
        let none = MathImageProvider { _ in nil }
        let token = "<mtext><mglyph src=\"missing.png\" width=\"30px\" height=\"20px\" alt=\"flag\"/></mtext>"
        for images in [nil, none] {
            for body in [token, "<mrow><mglyph src=\"missing.png\" alt=\"flag\"/></mrow>",
                         "<mo><mglyph src=\"missing.png\" alt=\"flag\"/></mo>"] {
                let result = try MathLayout(node(body), style: style(images: images))
                XCTAssertEqual(result.width, alt.width, accuracy: 0.5, body)
                XCTAssertNotNil(ink(result), body)
            }
        }
        // No alt either: a visible stand-in, never an error.
        XCTAssertNotNil(ink(try layout("<mi><mglyph src=\"missing.png\"/></mi>")))
        // The reading is the alt text, with or without an image.
        XCTAssertEqual(try node(token).accessibilityDescription, "flag")
        XCTAssertEqual(try node("<mi>x</mi><mo>+</mo><mglyph src=\"missing.png\" alt=\"flag\"/>").accessibilityDescription, "x plus flag")
        XCTAssertEqual(try node("<mtext>a <mglyph src=\"f.png\" alt=\"flag\"/> b</mtext>").accessibilityDescription, "a flag b")
    }

    // MARK: Elementary math

    private let addition = """
        <mstack><mscarries><mscarry><none/></mscarry><mn>1</mn><none/></mscarries><mn>424</mn>
        <msrow><mo>+</mo><mn>338</mn></msrow><msline/><mn>762</mn></mstack>
        """

    private func division(_ style: String?) -> String {
        let attribute = style.map { " longdivstyle=\"\($0)\"" } ?? ""
        return """
            <mlongdiv\(attribute)><mn>3</mn><mn>435.3</mn><mn>1306</mn><msgroup position="2" shift="-1">
            <msgroup><mn>12</mn><msline length="2"/></msgroup><msgroup><mn>10</mn><mn>9</mn><msline length="2"/></msgroup>
            <msgroup><mn>16</mn><mn>15</mn><msline length="2"/><mn>1.0</mn></msgroup></msgroup></mlongdiv>
            """
    }

    func testStacksLayOutInDigitColumns() throws {
        let stack = try layout(addition)
        XCTAssertNotNil(ink(stack))
        // Three digit columns and the operator's, four rows and a line: far from one row of text.
        let digits = try layout("<mn>424</mn>")
        XCTAssertGreaterThan(stack.width, digits.width)
        XCTAssertLessThan(stack.width, digits.width * 3)
        XCTAssertGreaterThan(height(stack), height(digits) * 3.5)
        // Digits sit in columns: widening one row's number widens nothing else.
        let wider = try layout(addition.replacingOccurrences(of: "<mn>762</mn>", with: "<mn>1762</mn>"))
        XCTAssertEqual(wider.width, stack.width, accuracy: digits.width / 3 + 2)
        let drawn = try XCTUnwrap(ink(stack))
        XCTAssertGreaterThanOrEqual(drawn.minX, -0.5)
        XCTAssertLessThanOrEqual(drawn.maxX, stack.width + 0.5)
        XCTAssertLessThanOrEqual(drawn.maxY, stack.ascent + 0.5)
        XCTAssertGreaterThanOrEqual(drawn.minY, -stack.descent - 0.5)
        XCTAssertGreaterThan(try layout("<mi>x</mi><mo>=</mo>\(addition)").width, stack.width, "a stack sits in a row like any element")
    }

    func testEveryLongDivisionStyleLaysOutAsItsOwn() throws {
        let styles = ["lefttop", "stackedrightright", "mediumstackedrightright", "shortstackedrightright", "righttop",
                      "left/\\right", "left)(right", ":right=right", "stackedleftleft", "stackedleftlinetop"]
        var drawings: [String: Bitmap] = [:]
        for name in styles {
            let result = try layout(division(name))
            let drawn = try XCTUnwrap(ink(result), name)
            XCTAssertGreaterThanOrEqual(drawn.minX, -0.5, name)
            XCTAssertLessThanOrEqual(drawn.maxX, result.width + 0.5, name)
            XCTAssertLessThanOrEqual(drawn.maxY, result.ascent + 0.5, name)
            XCTAssertGreaterThanOrEqual(drawn.minY, -result.descent - 0.5, name)
            drawings[name] = bitmap(width: 500, height: 500) { result.draw(in: $0, baselineOrigin: CGPoint(x: 120, y: 250)) }
        }
        for (index, first) in styles.enumerated() {
            for second in styles[(index + 1)...] {
                XCTAssertNotEqual(drawings[first], drawings[second], "\(first) draws the same as \(second)")
            }
        }
        // The default is lefttop.
        let standard = try layout(division(nil))
        XCTAssertEqual(bitmap(width: 500, height: 500) { standard.draw(in: $0, baselineOrigin: CGPoint(x: 120, y: 250)) },
                       drawings["lefttop"])
    }

    func testElementaryMathIsReadRowByRow() throws {
        /// Where each of `parts` first appears in `text`, ignoring spaces; nil when one is missing.
        func positions(of parts: [String], in text: String) -> [Int]? {
            let compact = text.replacingOccurrences(of: " ", with: "")
            var found: [Int] = []
            for part in parts {
                guard let range = compact.range(of: part.replacingOccurrences(of: " ", with: "")) else { return nil }
                found.append(compact.distance(from: compact.startIndex, to: range.lowerBound))
            }
            return found
        }
        let sum = try node(addition).accessibilityDescription
        let rows = try XCTUnwrap(positions(of: ["row 1: column minus 3: four column minus 2: two column minus 1: four", "row 2: column minus 4: plus column minus 3: three column minus 2: three column minus 1: eight", "row 3: column minus 3: seven column minus 2: six column minus 1: two"], in: sum), sum)
        XCTAssertEqual(rows, rows.sorted(), sum)
        XCTAssertTrue(sum.contains("plus"), sum)
        XCTAssertGreaterThan(sum.split(separator: " ").count, 8, "rows, the carry and the line are announced: \(sum)")

        let quotient = try node(division("lefttop")).accessibilityDescription
        let parts = try XCTUnwrap(positions(of: ["divisor: three", "dividend: column minus 4: one column minus 3: three column minus 2: zero column minus 1: six", "row 1:", "row 2:", "row 3:", "row 4:", "row 5:"], in: quotient), quotient)
        XCTAssertEqual(parts, parts.sorted(), quotient)
        XCTAssertTrue(quotient.contains("result: column minus 3: four column minus 2: three column minus 1: five column 0: point column 1: three"), quotient)
        // Localized like everything else.
        let french = try node(addition).accessibilityDescription(locale: Locale(identifier: "fr"))
        XCTAssertEqual(french.language, "fr")
        XCTAssertNotEqual(french.text, sum)
        XCTAssertFalse(french.text.contains("row"), french.text)
        let frenchRows = try XCTUnwrap(positions(of: ["ligne 1 : colonne moins 3: quatre colonne moins 2: deux colonne moins 1: quatre", "ligne 2 : colonne moins 4: plus colonne moins 3: trois colonne moins 2: trois colonne moins 1: huit", "ligne 3 : colonne moins 3: sept colonne moins 2: six colonne moins 1: deux"], in: french.text), french.text)
        XCTAssertEqual(frenchRows, frenchRows.sorted(), french.text)
    }

    // MARK: Localized readings

    func testReadingsNameTheLanguageTheyAreWrittenIn() throws {
        let formula = try node("<msup><mi>x</mi><mn>2</mn></msup><mo>+</mo><mfrac><mn>1</mn><mi>y</mi></mfrac><mo>=</mo><msqrt><mi>z</mi></msqrt>")
        let english = formula.accessibilityDescription
        XCTAssertEqual(english, "x squared plus 1 over y equals the square root of z", "the English property is unchanged")
        XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: "en")), MathReading(text: english, language: "en"))
        XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: "en_GB")).language, "en")

        var seen: Set<String> = [english]
        for language in ["fr", "de", "es", "it"] {
            XCTAssertTrue(MathReading.languages.contains(language), language)
            let reading = formula.accessibilityDescription(locale: Locale(identifier: language))
            XCTAssertEqual(reading.language, language)
            XCTAssertTrue(seen.insert(reading.text).inserted, "\(language) reads the same as another language: \(reading.text)")
            for word in ["squared", "over", "equals", "square root"] {
                XCTAssertFalse(reading.text.contains(word), "\(language) leaks English: \(reading.text)")
            }
            XCTAssertTrue(reading.text.contains("x") && reading.text.contains("y") && reading.text.contains("z"))
        }
        XCTAssertTrue(MathReading.languages.contains("en"))
        // Regions use their language's vocabulary.
        XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: "fr_CA")),
                       formula.accessibilityDescription(locale: Locale(identifier: "fr")))
        XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: "de-AT")).language, "de")
        // No vocabulary: English, and tagged as English so the voice matches the words.
        for unknown in ["ja", "ar_EG", "zz"] {
            XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: unknown)),
                           MathReading(text: english, language: "en"), unknown)
        }
    }
}

/// The sources an image provider was asked for, from any thread.
private final class Requests: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func add(_ source: String) { lock.lock(); values.append(source); lock.unlock() }
    var sources: [String] { lock.lock(); defer { lock.unlock() }; return values }
}
