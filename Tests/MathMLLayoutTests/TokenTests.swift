import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

/// Token elements (MathML 3, 3.2): `mi`, `mn`, `mtext`, `ms`, `mspace`, their whitespace, and
/// the attributes every token takes: `mathvariant`, `mathsize`, `mathcolor`, `mathbackground`.
final class TokenTests: XCTestCase {
    private func assertSameLayout(_ a: String, _ b: String, display: Bool = false, accuracy: CGFloat = 0.01,
                                  _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
        let first = try typeset(a, display: display), second = try typeset(b, display: display)
        let label = message.isEmpty ? "\(a) vs \(b)" : message
        XCTAssertEqual(first.width, second.width, accuracy: accuracy, "width: \(label)", file: file, line: line)
        XCTAssertEqual(first.ascent, second.ascent, accuracy: accuracy, "ascent: \(label)", file: file, line: line)
        XCTAssertEqual(first.descent, second.descent, accuracy: accuracy, "descent: \(label)", file: file, line: line)
    }

    // MARK: Whitespace (MathML 3, 2.1.7: trimmed at the ends and collapsed inside)

    func testNormalizedTrimsAndCollapsesXMLWhitespace() {
        // Fails until https://github.com/vocaro/MathMLLayout/issues/5 is fixed.
        XCTAssertEqual(LayoutEngine.normalized("x"), "x")
        XCTAssertEqual(LayoutEngine.normalized(" x"), "x")
        XCTAssertEqual(LayoutEngine.normalized("x "), "x", "trailing space")
        XCTAssertEqual(LayoutEngine.normalized("\n\t x \r\n"), "x", "trailing line break")
        XCTAssertEqual(LayoutEngine.normalized("a  \n b"), "a b")
        XCTAssertEqual(LayoutEngine.normalized(" \t\n"), "")
        XCTAssertEqual(LayoutEngine.normalized("a\u{A0}\u{A0}b"), "a\u{A0}\u{A0}b", "a no-break space is not XML whitespace")
        XCTAssertEqual(LayoutEngine.normalized("  a   b  ", trimming: false), " a b ")
    }

    func testWhitespaceAroundAnIdentifierOrNumberDoesNotChangeIt() throws {
        // Fails until https://github.com/vocaro/MathMLLayout/issues/5 is fixed.
        // A single-letter `mi` is italic however the markup is indented.
        try assertSameLayout("<mi> x </mi>", "<mi>x</mi>")
        try assertSameLayout("<mi>x </mi>", "<mi>x</mi>")
        try assertSameLayout("<mi>\n    x\n  </mi>", "<mi>x</mi>")
        try assertSameLayout("<mn> 12 </mn>", "<mn>12</mn>")
        try assertSameLayout("<msup><mi> x </mi><mn> 2 </mn></msup>", "<msup><mi>x</mi><mn>2</mn></msup>")
    }

    func testWhitespaceAroundAnOperatorDoesNotChangeIt() throws {
        // Fails until https://github.com/vocaro/MathMLLayout/issues/5 is fixed.
        // The operator dictionary is keyed on the trimmed text: spacing, fences and stretching.
        try assertSameLayout("<mi>a</mi><mo> + </mo><mi>b</mi>", "<mi>a</mi><mo>+</mo><mi>b</mi>")
        try assertSameLayout("<mi>a</mi><mo>\n=\n</mo><mi>b</mi>", "<mi>a</mi><mo>=</mo><mi>b</mi>")
        let tall = "<mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mi>c</mi></mfrac>"
        try assertSameLayout("<mo> ( </mo>\(tall)<mo> ) </mo>", "<mo>(</mo>\(tall)<mo>)</mo>", display: true)
        try assertSameLayout("<munderover><mo> ∑ </mo><mi>i</mi><mi>n</mi></munderover>",
                             "<munderover><mo>∑</mo><mi>i</mi><mi>n</mi></munderover>", display: true)
    }

    func testInteriorWhitespaceCollapsesToOneSpace() throws {
        let one = try typeset("<mtext>a b</mtext>").width
        XCTAssertEqual(try typeset("<mtext>a   b</mtext>").width, one, accuracy: 0.01)
        XCTAssertEqual(try typeset("<mtext>a\n\t b</mtext>").width, one, accuracy: 0.01)
        XCTAssertGreaterThan(one, try typeset("<mtext>ab</mtext>").width + 2)
        XCTAssertGreaterThan(try typeset("<mtext>a&#xA0;&#xA0;&#xA0;b</mtext>").width, one + 4, "no-break spaces do not collapse")
    }

    // MARK: Identifiers and numbers

    func testSingleCharacterIdentifiersUseMathItalic() throws {
        try assertSameLayout("<mi>x</mi>", "<mi mathvariant=\"italic\">x</mi>")
        try assertSameLayout("<mi>x</mi>", "<mi mathvariant=\"normal\">𝑥</mi>", "the italic x is U+1D465")
        try assertSameLayout("<mi>h</mi>", "<mi mathvariant=\"normal\">ℎ</mi>", "italic h is the Planck constant")
        try assertSameLayout("<mi>α</mi>", "<mi mathvariant=\"normal\">𝛼</mi>")
        try assertSameLayout("<mi>Γ</mi>", "<mi mathvariant=\"normal\">𝛤</mi>")
        // Characters with no italic form are unchanged.
        try assertSameLayout("<mi>∞</mi>", "<mi mathvariant=\"normal\">∞</mi>")
        try assertSameLayout("<mi>ℝ</mi>", "<mi mathvariant=\"normal\">ℝ</mi>")
    }

    func testMultiCharacterIdentifiersAndNumbersAreUpright() throws {
        try assertSameLayout("<mi>sin</mi>", "<mi mathvariant=\"normal\">sin</mi>")
        try assertSameLayout("<mi>sin</mi>", "<mtext>sin</mtext>")
        try assertSameLayout("<mn>3.14</mn>", "<mtext>3.14</mtext>")
        XCTAssertNotEqual(try typeset("<mi mathvariant=\"italic\">sin</mi>").width, try typeset("<mi>sin</mi>").width)
    }

    func testEveryMathVariantIsDrawnWithItsUnicodeStyle() throws {
        let styled: [(String, String)] = [
            ("bold", "𝐑"), ("italic", "𝑅"), ("bold-italic", "𝑹"), ("double-struck", "ℝ"), ("bold-fraktur", "𝕽"),
            ("script", "ℛ"), ("bold-script", "𝓡"), ("fraktur", "ℜ"), ("sans-serif", "𝖱"), ("bold-sans-serif", "𝗥"),
            ("sans-serif-italic", "𝘙"), ("sans-serif-bold-italic", "𝙍"), ("monospace", "𝚁"),
        ]
        for (variant, literal) in styled {
            XCTAssertEqual(MathVariant(attribute: variant)?.apply(to: "R"), literal, variant)
            try assertSameLayout("<mi mathvariant=\"\(variant)\">R</mi>", "<mi mathvariant=\"normal\">\(literal)</mi>", variant)
        }
        try assertSameLayout("<mn mathvariant=\"bold\">12</mn>", "<mn>𝟏𝟐</mn>")
        try assertSameLayout("<mi mathvariant=\" Bold \">R</mi>", "<mi mathvariant=\"bold\">R</mi>", "trimmed and case-insensitive")
        try assertSameLayout("<mi mathvariant=\"no-such-variant\">x</mi>", "<mi>x</mi>", "an unknown value is ignored")
        for legacy in ["initial", "tailed", "looped", "stretched"] {
            try assertSameLayout("<mi mathvariant=\"\(legacy)\">R</mi>", "<mi mathvariant=\"normal\">R</mi>", legacy)
        }
    }

    func testMathVariantIsInherited() throws {
        try assertSameLayout("<mstyle mathvariant=\"bold\"><mi>x</mi><mn>1</mn></mstyle>",
                             "<mi mathvariant=\"bold\">x</mi><mn mathvariant=\"bold\">1</mn>")
        try assertSameLayout("<mstyle mathvariant=\"bold\"><mi mathvariant=\"normal\">x</mi></mstyle>", "<mi mathvariant=\"normal\">x</mi>",
                             "a token's own value wins")
        try assertSameLayout("<math mathvariant=\"double-struck\"><mi>R</mi></math>", "<mi mathvariant=\"double-struck\">R</mi>")
    }

    func testDeprecatedFontAttributesMapToVariants() throws {
        try assertSameLayout("<mi fontweight=\"bold\">x</mi>", "<mi mathvariant=\"bold\">x</mi>")
        try assertSameLayout("<mi fontstyle=\"italic\">sin</mi>", "<mi mathvariant=\"italic\">sin</mi>")
        try assertSameLayout("<mi fontweight=\"bold\" fontstyle=\"italic\">x</mi>", "<mi mathvariant=\"bold-italic\">x</mi>")
        try assertSameLayout("<mi fontstyle=\"normal\">x</mi>", "<mi mathvariant=\"normal\">x</mi>")
        try assertSameLayout("<mi fontweight=\"bold\" mathvariant=\"script\">L</mi>", "<mi mathvariant=\"script\">L</mi>", "mathvariant wins")
        try assertSameLayout("<mi fontsize=\"40px\">x</mi>", "<mi mathsize=\"40px\">x</mi>")
        XCTAssertEqual(Rendering(try typeset("<mi color=\"red\">x</mi>")).bounds(.black), nil)
    }

    /// Every style maps every letter, digit and Greek symbol it covers to an assigned character
    /// that still is that letter: its compatibility decomposition is the original's.
    func testMathVariantMappingsPreserveTheCharacter() {
        let variants: [(MathVariant, String)] = [
            (.bold, "BOLD"), (.italic, "ITALIC"), (.boldItalic, "BOLD ITALIC"), (.script, "SCRIPT"),
            (.boldScript, "BOLD SCRIPT"), (.fraktur, "FRAKTUR"), (.doubleStruck, "DOUBLE-STRUCK"),
            (.boldFraktur, "BOLD FRAKTUR"), (.sansSerif, "SANS-SERIF"), (.boldSansSerif, "SANS-SERIF BOLD"),
            (.sansSerifItalic, "SANS-SERIF ITALIC"), (.sansSerifBoldItalic, "SANS-SERIF BOLD ITALIC"), (.monospace, "MONOSPACE"),
        ]
        let latin = (0x41...0x5A).map { $0 } + (0x61...0x7A).map { $0 }
        let digits = Array(0x30...0x39)
        let greek = Array(0x391...0x3A1) + Array(0x3A3...0x3A9) + Array(0x3B1...0x3C9) + [0x3F4, 0x2207, 0x2202, 0x3F5, 0x3D1, 0x3F0, 0x3D5, 0x3F1, 0x3D6]
        let kinds = ["CAPITAL", "SMALL", "DIGIT", "NABLA", "PARTIAL", "EPSILON", "THETA", "KAPPA", "PHI", "RHO", "PI"]
        var mappedCount = 0
        for (variant, style) in variants {
            for value in latin + digits + greek {
                let original = Unicode.Scalar(UInt32(value))!
                let mapped = variant.apply(to: original)
                guard mapped != original else { continue }
                mappedCount += 1
                let label = "\(variant) U+\(String(value, radix: 16)) -> U+\(String(mapped.value, radix: 16))"
                XCTAssertNotEqual(mapped.properties.generalCategory, .unassigned, label)
                XCTAssertEqual(String(mapped).decomposedStringWithCompatibilityMapping,
                               String(original).decomposedStringWithCompatibilityMapping, label)
                // Inside the Mathematical Alphanumeric Symbols block the name states the style.
                if (0x1D400...0x1D7FF).contains(mapped.value), let name = mapped.properties.name {
                    XCTAssertTrue(kinds.contains { name.hasPrefix("MATHEMATICAL \(style) \($0)") }, "\(label) is \(name)")
                }
            }
            // Every style has the 52 Latin letters.
            for value in latin { XCTAssertNotEqual(variant.apply(to: Unicode.Scalar(UInt32(value))!).value, UInt32(value), "\(variant)") }
        }
        // 13 Latin alphabets, 5 digit sets and 5 Greek sets.
        XCTAssertEqual(mappedCount, 13 * 52 + 5 * 10 + 5 * 58)
        XCTAssertEqual(MathVariant.italic.apply(to: "ıȷ"), "𝚤𝚥")
        XCTAssertEqual(MathVariant.normal.apply(to: "xR1α"), "xR1α")
        XCTAssertEqual(MathVariant.script.apply(to: "α1+"), "α1+", "no script Greek or digits")
        XCTAssertEqual(MathVariant.bold.apply(to: "ϴ∇∂ϵϑϰϕϱϖ"), "𝚹𝛁𝛛𝛜𝛝𝛞𝛟𝛠𝛡")
    }

    // MARK: Strings and spaces

    func testStringLiteralsAreQuoted() throws {
        try assertSameLayout("<ms>ab</ms>", "<mtext>\"ab\"</mtext>")
        try assertSameLayout("<ms lquote=\"«\" rquote=\"»\">ab</ms>", "<mtext>«ab»</mtext>")
        try assertSameLayout("<ms lquote=\"\" rquote=\"\">ab</ms>", "<mtext>ab</mtext>")
    }

    func testSpaceHasExactlyItsAttributesAndNoInk() throws {
        let space = try typeset("<mspace width=\"10px\" height=\"6px\" depth=\"4px\"/>")
        XCTAssertEqual(space.width, 10, accuracy: 0.001)
        XCTAssertEqual(space.ascent, 6, accuracy: 0.001)
        XCTAssertEqual(space.descent, 4, accuracy: 0.001)
        XCTAssertNil(Rendering(space).bounds())
        let empty = try typeset("<mspace/>")
        XCTAssertEqual([empty.width, empty.ascent, empty.descent], [0, 0, 0])
        XCTAssertEqual(try typeset("<mspace width=\"2em\"/>").width, 2 * em, accuracy: 0.001)
        XCTAssertEqual(try typeset("<mspace width=\"2em\"/>", size: 11).width, 22, accuracy: 0.001)
        XCTAssertEqual(try typeset("<mspace width=\"12pt\"/>").width, 16, accuracy: 0.001, "a CSS point is 4/3 px")
        XCTAssertEqual(try typeset("<mspace width=\"thickmathspace\"/>").width, 5 * em / 18, accuracy: 0.001)
        XCTAssertEqual(try typeset("<mspace width=\" 1em \"/>").width, em, accuracy: 0.001, "surrounding space is trimmed")
        XCTAssertEqual(height(try typeset("<mspace width=\"bogus\" height=\"1e3px\"/>")), 0, "invalid lengths are ignored")
        // An ex is the font's x-height; an em follows the current size.
        let ex = try typeset("<mspace width=\"1ex\"/>").width
        XCTAssertEqual(ex, try typeset("<mi mathvariant=\"normal\">x</mi>").ascent, accuracy: 1)
        XCTAssertEqual(try typeset("<mstyle scriptlevel=\"1\"><mspace width=\"1em\"/></mstyle>").width, 0.7 * em, accuracy: 0.01)
        XCTAssertEqual(try typeset("<mstyle mathsize=\"30px\"><mspace width=\"1em\"/></mstyle>").width, 30, accuracy: 0.01)
        // Space separates its neighbours by exactly its width.
        let a = try innerBox("<mi>a</mi>").width, b = try innerBox("<mi>b</mi>").width
        XCTAssertEqual(try innerBox("<mi>a</mi><mspace width=\"7px\"/><mi>b</mi>").width, a + 7 + b, accuracy: 0.001)
    }

    // MARK: Size

    func testMathSizeScalesTheToken() throws {
        let x = try innerBox("<mi>x</mi>").width
        for (value, factor) in [("200%", 2.0), ("2em", 2), ("40px", 2), ("30pt", 2), ("2", 2), ("normal", 1), ("big", 1.2), ("small", 1 / 1.2),
                                (" BIG ", 1.2)] {
            XCTAssertEqual(try innerBox("<mi mathsize=\"\(value)\">x</mi>").width, x * factor, accuracy: 0.03, "mathsize=\(value)")
        }
        for ignored in ["", "huge", "-2em", "0", "0px", "1e2px", "12 px px"] {
            XCTAssertEqual(try innerBox("<mi mathsize=\"\(ignored)\">x</mi>").width, x, accuracy: 0.001, "mathsize=\(ignored) is ignored")
        }
        // The size is inherited, and percentages compound.
        XCTAssertEqual(try innerBox("<mstyle mathsize=\"200%\"><mi mathsize=\"50%\">x</mi></mstyle>").width, x, accuracy: 0.03)
        XCTAssertEqual(try innerBox("<mstyle mathsize=\"40px\"><mi>x</mi></mstyle>").width, 2 * x, accuracy: 0.03)
    }

    func testLayoutScalesWithTheFontSize() throws {
        let bodies = ["<mi>x</mi><mo>=</mo><mfrac><mn>1</mn><mn>2</mn></mfrac>", "<msqrt><mi>a</mi><mo>+</mo><mi>b</mi></msqrt>",
                      "<msup><mi>x</mi><mn>2</mn></msup>", "<mo>(</mo><mfrac><mi>a</mi><mi>b</mi></mfrac><mo>)</mo>"]
        for body in bodies {
            for display in [false, true] {
                let small = try typeset(body, size: 20, display: display), large = try typeset(body, size: 40, display: display)
                XCTAssertEqual(large.width, 2 * small.width, accuracy: 0.02 * large.width, body)
                XCTAssertEqual(large.ascent, 2 * small.ascent, accuracy: 0.02 * height(large), body)
                XCTAssertEqual(large.descent, 2 * small.descent, accuracy: 0.02 * height(large), body)
            }
        }
    }

    // MARK: Colour

    func testMathColorParsing() {
        func components(_ value: String) -> [CGFloat]? { MathColor.parse(value)?.components.map { $0.map { ($0 * 255).rounded() } } }
        XCTAssertEqual(components("red"), [255, 0, 0, 255])
        XCTAssertEqual(components(" Blue "), [0, 0, 255, 255])
        XCTAssertEqual(components("green"), [0, 128, 0, 255])
        XCTAssertEqual(components("#f00"), [255, 0, 0, 255])
        XCTAssertEqual(components("#1a2"), [0x11, 0xAA, 0x22, 255])
        XCTAssertEqual(components("#ff08"), [255, 255, 0, 0x88])
        XCTAssertEqual(components("#102030"), [0x10, 0x20, 0x30, 255])
        XCTAssertEqual(components("#10203040"), [0x10, 0x20, 0x30, 0x40])
        XCTAssertEqual(components("#ABCDEF"), [0xAB, 0xCD, 0xEF, 255])
        XCTAssertEqual(components("transparent"), [0, 0, 0, 0])
        for invalid in ["", "#", "#12", "#12345", "#1234567", "#123456789", "#ggg", "ff0000", "notacolor", "# f00", "#f 0"] {
            XCTAssertNil(MathColor.parse(invalid), "\"\(invalid)\"")
        }
    }

    func testMathColorRejectsSignedHexDigits() {
        // Fails until https://github.com/vocaro/MathMLLayout/issues/17 is fixed.
        // "+ff" and "-00" are not hexadecimal colours, though integer parsing accepts a sign.
        for invalid in ["#+ff", "#-00", "#+12345", "#-0000000"] { XCTAssertNil(MathColor.parse(invalid), "\"\(invalid)\"") }
    }

    func testMathColorPaintsTheInk() throws {
        for color in ["red", "#f00", "#FF0000", "#ff0000ff"] {
            let rendering = Rendering(try typeset("<mi mathcolor=\"\(color)\">x</mi>"))
            XCTAssertNotNil(rendering.bounds(.red), color)
            XCTAssertNil(rendering.bounds(.black), color)
        }
        // Inherited, overridden, and an invalid value keeps the inherited colour.
        let mixed = Rendering(try typeset("<mstyle mathcolor=\"red\"><mi>a</mi><mi mathcolor=\"blue\">b</mi><mi mathcolor=\"nope\">c</mi></mstyle>"))
        let red = try XCTUnwrap(mixed.bounds(.red)), blue = try XCTUnwrap(mixed.bounds(.blue))
        XCTAssertNil(mixed.bounds(.black))
        XCTAssertLessThan(red.minX, blue.minX)
        XCTAssertGreaterThan(red.maxX, blue.maxX, "c, after b, is red again")
        // The style's colour is the default.
        let styled = try MathLayout(mathML("<mi>x</mi>"), style: MathStyle(fontSize: em, color: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)))
        XCTAssertNotNil(Rendering(styled).bounds(.blue))
        XCTAssertNil(Rendering(styled).bounds(.black))
        XCTAssertNil(Rendering(try typeset("<mi mathcolor=\"transparent\">x</mi>")).bounds())
    }

    func testRulesAndDrawnPartsTakeTheirElementsColor() throws {
        // A fraction's bar, a radical's sign and bar, an enclosure and table lines.
        for body in ["<mfrac mathcolor=\"red\"><mspace width=\"1em\"/><mspace width=\"1em\"/></mfrac>",
                     "<msqrt mathcolor=\"red\"><mspace width=\"1em\" height=\"1ex\"/></msqrt>",
                     "<menclose notation=\"box\" mathcolor=\"red\"><mspace width=\"1em\" height=\"1ex\"/></menclose>",
                     "<mtable frame=\"solid\" mathcolor=\"red\"><mtr><mtd><mspace width=\"1em\" height=\"1ex\"/></mtd></mtr></mtable>",
                     "<mrow mathcolor=\"red\"><mo>(</mo><mspace width=\"1em\" height=\"3em\" depth=\"2em\"/><mo>)</mo></mrow>"] {
            let rendering = Rendering(try typeset(body))
            XCTAssertNotNil(rendering.bounds(.red), body)
            XCTAssertNil(rendering.bounds(.black), body)
        }
        let fraction = Rendering(try typeset("<mfrac><mi mathcolor=\"red\">a</mi><mi mathcolor=\"blue\">b</mi></mfrac>"))
        XCTAssertNotNil(fraction.bounds(.black), "the bar keeps the fraction's colour")
    }

    func testMathBackgroundFillsTheElementsBox() throws {
        let filled = Rendering(try typeset("<mspace width=\"2em\" height=\"1em\" depth=\"0.5em\" mathbackground=\"blue\"/>"))
        let blue = try XCTUnwrap(filled.bounds(.blue))
        XCTAssertEqual(blue.minX, 0, accuracy: 0.5); XCTAssertEqual(blue.width, 2 * em, accuracy: 0.75)
        XCTAssertEqual(blue.maxY, em, accuracy: 0.5); XCTAssertEqual(blue.minY, -0.5 * em, accuracy: 0.5)
        // The background is behind the element's ink and covers it.
        let behind = Rendering(try typeset("<mi mathbackground=\"lime\" mathcolor=\"red\">x</mi>"))
        let green = try XCTUnwrap(behind.bounds(.green)), red = try XCTUnwrap(behind.bounds(.red))
        XCTAssertTrue(green.insetBy(dx: -1.5, dy: -0.5).contains(red), "\(green) should contain \(red)")
        // It does not change the layout, and an invalid or transparent one draws nothing.
        try assertSameLayout("<mi mathbackground=\"lime\">x</mi>", "<mi>x</mi>", accuracy: 0.5)
        for none in ["transparent", "bogus", "#00f0"] {
            XCTAssertNil(Rendering(try typeset("<mspace width=\"1em\" height=\"1em\" mathbackground=\"\(none)\"/>")).bounds(), none)
        }
        let translucent = Rendering(try typeset("<mspace width=\"1em\" height=\"1em\" mathbackground=\"#ff000080\"/>"))
        XCTAssertEqual(translucent.color(at: CGPoint(x: em / 2, y: em / 2)).alpha, 0.5, accuracy: 0.02)
        // A phantom still shows its own background, but nothing of its content.
        let phantom = Rendering(try typeset("<mphantom mathbackground=\"blue\"><mi mathcolor=\"red\">x</mi></mphantom>"))
        XCTAssertNotNil(phantom.bounds(.blue)); XCTAssertNil(phantom.bounds(.red))
    }

    // MARK: Lengths

    func testLengthUnits() {
        func points(_ text: String, reference: CGFloat? = nil) -> CGFloat? { MathLength(text)?.resolve(em: 20, ex: 9, reference: reference) }
        let cases: [(String, CGFloat)] = [
            ("1px", 1), ("3pt", 4), ("1pc", 16), ("1in", 96), ("2.54cm", 96), ("25.4mm", 96), ("101.6q", 96),
            ("1em", 20), ("0.5em", 10), (".5em", 10), ("2ex", 18), ("1EM", 20), (" 1em ", 20), ("0px", 0), ("0em", 0), ("+1em", 20), ("-1em", -20),
            ("veryverythinmathspace", 20.0 / 18), ("verythinmathspace", 40.0 / 18), ("thinmathspace", 60.0 / 18),
            ("mediummathspace", 80.0 / 18), ("thickmathspace", 100.0 / 18), ("verythickmathspace", 120.0 / 18),
            ("veryverythickmathspace", 140.0 / 18), ("negativethinmathspace", -60.0 / 18), ("negativeveryverythickmathspace", -140.0 / 18),
        ]
        for (text, expected) in cases {
            guard let value = points(text) else { XCTFail("\(text) did not parse"); continue }
            XCTAssertEqual(value, expected, accuracy: 0.0001, text)
        }
        // Percentages and bare numbers need a reference.
        XCTAssertNil(points("50%"))
        XCTAssertNil(points("2"))
        XCTAssertEqual(points("50%", reference: 30), 15)
        XCTAssertEqual(points("2", reference: 30), 60)
        XCTAssertEqual(points("-25%", reference: 40), -10)
        for invalid in ["", " ", "em", "px", "1 2em", "1e3px", "1,5em", "--1em", "+-1em", "+ 1em", "1.2.3em", ".", "1furlong", "0x10px",
                        "١em", "1em;", "calc(1em)", "NaN", "infinity", String(repeating: "1", count: 64) + "px"] {
            XCTAssertNil(MathLength(invalid), "\"\(invalid)\"")
        }
        XCTAssertEqual(MathLength("+2em")?.isRelative, true)
        XCTAssertEqual(MathLength("-2em")?.isRelative, true)
        XCTAssertEqual(MathLength("2em")?.isRelative, false)
    }

    func testUnitlessZeroIsALengthWithoutAReference() {
        // Fails until https://github.com/vocaro/MathMLLayout/issues/17 is fixed.
        // "0" is zero whatever it would be a multiple of; attributes with no reference value
        // (mspace, framespacing) must not read it as invalid.
        XCTAssertEqual(MathLength("0")?.resolve(em: 20, ex: 9), 0)
        XCTAssertEqual(MathLength("0.0")?.resolve(em: 20, ex: 9), 0)
        XCTAssertEqual(MathLength("0")?.resolve(em: 20, ex: 9, reference: 30), 0)
    }

    func testLengthsAreBounded() {
        let huge = MathLength(String(repeating: "9", count: 60) + "em")
        XCTAssertEqual(huge?.resolve(em: 20, ex: 9), 20_000, "clamped to 1000 em")
        XCTAssertEqual(MathLength("-" + String(repeating: "9", count: 60) + "px")?.resolve(em: 20, ex: 9), -20_000)
        XCTAssertEqual(MathLength("999999%")?.resolve(em: 20, ex: 9, reference: 1000), 20_000)
    }

    func testPseudoUnits() {
        let content = (width: CGFloat(10), height: CGFloat(6), depth: CGFloat(4))
        func points(_ text: String) -> CGFloat? { MathLength(text)?.resolve(em: 20, ex: 9, reference: 100, content: content) }
        XCTAssertEqual(points("2width"), 20)
        XCTAssertEqual(points("0.5height"), 3)
        XCTAssertEqual(points("3depth"), 12)
        XCTAssertEqual(points("50%width"), 5)
        XCTAssertEqual(points("150%height"), 9)
        XCTAssertEqual(points("25% depth"), 1)
        XCTAssertEqual(points("+50%width"), 5)
        XCTAssertEqual(MathLength("+50%width")?.isRelative, true)
        XCTAssertEqual(points("-2width"), -20)
        XCTAssertNil(MathLength("2width")?.resolve(em: 20, ex: 9), "a pseudo-unit means nothing outside mpadded")
    }

    func testBooleanAttributes() {
        XCTAssertEqual(["a": "true"].flag("a"), true)
        XCTAssertEqual(["a": " TRUE "].flag("a"), true)
        XCTAssertEqual(["a": "false"].flag("a"), false)
        XCTAssertNil(["a": "yes"].flag("a"))
        XCTAssertNil(["a": "1"].flag("a"))
        XCTAssertNil(["a": ""].flag("a"))
        XCTAssertNil(["b": "true"].flag("a"))
    }
}
