import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

final class MathMLLayoutTests: MathTestCase {
    func testUsesThePlatformMathFont() {
        let font = MathFont.named(nil)
        XCTAssertEqual(CTFontCopyPostScriptName(font.base) as String, "STIXTwoMath-Regular")
        XCTAssertNotNil(font.table)
        XCTAssertEqual(font.constants.scriptPercentScaleDown, 70)
    }

    func testFractionIsTallerThanItsRowAndStraddlesTheAxis() throws {
        let row = try layout("<mi>a</mi><mo>+</mo><mi>b</mi>")
        let fraction = try layout("<mfrac><mi>a</mi><mi>b</mi></mfrac>")
        XCTAssertGreaterThan(fraction.ascent, row.ascent)
        XCTAssertGreaterThan(fraction.descent, row.descent)
        let display = try layout("<mfrac><mi>a</mi><mi>b</mi></mfrac>", display: true)
        XCTAssertGreaterThan(height(display), height(fraction), "display style uses full-size parts and larger shifts")
        // Text-style parts are a script level down.
        XCTAssertLessThan(fraction.width, display.width)
    }

    func testLineThicknessZeroStacksWithoutARule() throws {
        let stack = try layout("<mfrac linethickness=\"0\"><mi>n</mi><mi>k</mi></mfrac>", display: true)
        let fraction = try layout("<mfrac><mi>n</mi><mi>k</mi></mfrac>", display: true)
        XCTAssertGreaterThan(height(stack), 0)
        let thick = try layout("<mfrac linethickness=\"thick\"><mi>n</mi><mi>k</mi></mfrac>", display: true)
        XCTAssertGreaterThanOrEqual(height(thick), height(fraction))
    }

    func testSuperscriptIsRaisedAndShrunk() throws {
        let base = try layout("<mi>x</mi>")
        let power = try layout("<msup><mi>x</mi><mn>2</mn></msup>")
        let two = try layout("<mn>2</mn>")
        XCTAssertGreaterThan(power.ascent, base.ascent + 0.2 * two.ascent)
        let scriptWidth = power.width - base.width - MathFont.named(nil).constants.spaceAfterScript * 20
        XCTAssertEqual(scriptWidth / two.width, 0.7, accuracy: 0.05)
        let subscripted = try layout("<msub><mi>x</mi><mn>2</mn></msub>")
        XCTAssertGreaterThan(subscripted.descent, base.descent + 0.2 * two.ascent)
        XCTAssertLessThan(subscripted.ascent, power.ascent)
    }

    func testSubAndSuperscriptsKeepTheirGap() throws {
        let both = try layout("<msubsup><mi>x</mi><mi>i</mi><mn>2</mn></msubsup>")
        let power = try layout("<msup><mi>x</mi><mn>2</mn></msup>")
        let sub = try layout("<msub><mi>x</mi><mi>i</mi></msub>")
        XCTAssertGreaterThanOrEqual(both.ascent, power.ascent - 0.01)
        XCTAssertGreaterThanOrEqual(both.descent, sub.descent - 0.01)
    }

    func testScriptSizesShrinkToAMinimum() {
        let engine = LayoutEngine(fontName: nil)
        var context = LayoutContext(fontSize: 17, unclampedSize: 17, minSize: min(17, max(8, 17 * 0.6)), display: false,
                                    color: black)
        engine.setScriptLevel(&context, 1)
        XCTAssertEqual(context.fontSize, 17 * 0.7, accuracy: 0.001)
        engine.setScriptLevel(&context, 2)
        XCTAssertEqual(context.fontSize, 17 * 0.6, accuracy: 0.001, "STIX's 55% is clamped to 60%")
        engine.setScriptLevel(&context, 5)
        XCTAssertEqual(context.fontSize, 17 * 0.6, accuracy: 0.001)
        engine.setScriptLevel(&context, 0)
        XCTAssertEqual(context.fontSize, 17, accuracy: 0.001)
    }

    func testRadicalCoversItsRadicand() throws {
        let radicand = try layout("<mfrac><mi>a</mi><mi>b</mi></mfrac>")
        let root = try layout("<msqrt><mfrac><mi>a</mi><mi>b</mi></mfrac></msqrt>")
        XCTAssertGreaterThan(root.ascent, radicand.ascent)
        XCTAssertGreaterThanOrEqual(root.descent, radicand.descent)
        XCTAssertGreaterThan(root.width, radicand.width)
        let indexed = try layout("<mroot><mi>x</mi><mn>3</mn></mroot>")
        let square = try layout("<msqrt><mi>x</mi></msqrt>")
        XCTAssertGreaterThan(indexed.width, square.width - 0.01)
    }

    func testStretchyFencesGrowWithTheirRow() throws {
        let plain = try layout("<mo>(</mo><mi>x</mi><mo>)</mo>")
        let tall = try layout("<mo>(</mo><mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mi>c</mi></mfrac><mo>)</mo>", display: true)
        let content = try layout("<mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mi>c</mi></mfrac>", display: true)
        XCTAssertGreaterThan(height(tall), height(plain) * 1.5)
        XCTAssertGreaterThanOrEqual(height(tall), height(content) * 0.9)
        let unstretched = try layout("<mo stretchy=\"false\">(</mo><mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mi>c</mi></mfrac><mo stretchy=\"false\">)</mo>",
                                     display: true)
        XCTAssertEqual(height(unstretched), height(content), accuracy: 0.01)
    }

    func testVeryTallFencesUseGlyphAssemblies() throws {
        let rows = (1...12).map { "<mtr><mtd><mn>\($0)</mn></mtd></mtr>" }.joined()
        let table = try layout("<mtable>\(rows)</mtable>")
        let fenced = try layout("<mo>{</mo><mtable>\(rows)</mtable><mo>}</mo>")
        XCTAssertGreaterThanOrEqual(height(fenced), height(table) * 0.9)
        let engine = LayoutEngine(fontName: nil)
        let context = LayoutContext(fontSize: 20, unclampedSize: 20, minSize: 12, display: false, color: black)
        let brace = try engine.layout(MathMLNode(name: "mo", text: "{"), context,
                                      Embellishment(form: .prefix, stretch: .vertical(ascent: 200, descent: 190)), depth: 0)
        XCTAssertEqual(brace.height, max(390 * 0.901, 390 - 10), accuracy: 6, "TeX's delimiter factor and shortfall")
        XCTAssertEqual((brace.ascent - brace.descent) / 2, engine.value(\.axisHeight, context), accuracy: 0.5,
                       "symmetric fences center on the math axis")
    }

    func testHorizontalStretchCoversTheBase() throws {
        let label = try layout("<mstyle scriptlevel=\"1\"><mtext>a long arrow label</mtext></mstyle>")
        let arrow = try layout("<mover><mo>→</mo><mtext>a long arrow label</mtext></mover>")
        XCTAssertGreaterThanOrEqual(arrow.width, label.width - 0.01)
        let brace = try layout("<munder><mrow><mi>a</mi><mo>+</mo><mi>b</mi><mo>+</mo><mi>c</mi></mrow><mo>⏟</mo></munder>")
        let row = try layout("<mi>a</mi><mo>+</mo><mi>b</mi><mo>+</mo><mi>c</mi>")
        XCTAssertGreaterThan(brace.descent, row.descent + 2)
        XCTAssertEqual(brace.width, row.width, accuracy: 1)
    }

    func testLimitsGoUnderAndOverInDisplayStyleOnly() throws {
        let sum = "<munderover><mo>∑</mo><mrow><mi>i</mi><mo>=</mo><mn>1</mn></mrow><mi>n</mi></munderover>"
        let display = try layout(sum, display: true)
        let inline = try layout(sum)
        let bare = try layout("<mo>∑</mo>", display: true)
        XCTAssertGreaterThan(display.ascent, bare.ascent)
        XCTAssertGreaterThan(display.descent, bare.descent)
        XCTAssertGreaterThan(height(display), height(inline))
        // In text style the limits become scripts beside the operator.
        let operatorWidth = try layout("<mo>∑</mo>").width
        XCTAssertGreaterThan(inline.width, operatorWidth + 5)
        XCTAssertLessThan(display.width, inline.width + operatorWidth)
        // Integrals do not take movable limits, and are larger in display style.
        let integral = try layout("<mo>∫</mo>", display: true), small = try layout("<mo>∫</mo>")
        XCTAssertGreaterThan(height(integral), height(small) * 1.3)
    }

    func testAccentSitsOnItsBase() throws {
        let base = try layout("<mi>x</mi>")
        let hat = try layout("<mover><mi>x</mi><mo>^</mo></mover>")
        XCTAssertGreaterThan(hat.ascent, base.ascent)
        XCTAssertLessThan(hat.ascent, base.ascent * 2.2)
        let wide = try layout("<mover><mrow><mi>x</mi><mi>y</mi><mi>z</mi></mrow><mo>^</mo></mover>")
        let row = try layout("<mi>x</mi><mi>y</mi><mi>z</mi>")
        XCTAssertGreaterThan(wide.ascent, row.ascent)
        XCTAssertGreaterThanOrEqual(wide.width, row.width - 0.01)
    }

    func testOperatorSpacingFollowsTheDictionaryAndForm() throws {
        let a = try layout("<mi>a</mi>").width, b = try layout("<mi>b</mi>").width
        let plus = try layout("<mo>+</mo>").width
        let sum = try layout("<mi>a</mi><mo>+</mo><mi>b</mi>").width
        XCTAssertEqual(sum - (a + b + plus), 2 * 20 * 4 / 18, accuracy: 0.5, "medium space each side of a binary operator")
        let relation = try layout("<mi>a</mi><mo>=</mo><mi>b</mi>").width - a - b - (try layout("<mo>=</mo>").width)
        XCTAssertEqual(relation, 2 * 20 * 5 / 18, accuracy: 0.5)
        // A prefix minus, and a minus after a relation or an opening fence, are unary.
        let minus = try layout("<mo>−</mo>").width, three = try layout("<mn>3</mn>").width
        XCTAssertEqual(try layout("<mo>−</mo><mn>3</mn>").width, minus + three, accuracy: 0.5)
        let equals = try layout("<mi>x</mi><mo>=</mo><mo>−</mo><mn>3</mn>").width
        XCTAssertEqual(equals, try layout("<mi>x</mi><mo>=</mo><mrow><mo>−</mo><mn>3</mn></mrow>").width, accuracy: 0.01)
        XCTAssertEqual(try layout("<mo>-</mo>").width, minus, accuracy: 0.01, "hyphen-minus draws as the minus sign")
    }

    /// `mtext` is space-like, so an operator between two is its row's only in-flow child: the
    /// row is an embellished operator, and with no enclosing row it must space the operator itself.
    func testOperatorBetweenTextOperandsKeepsItsSpacing() throws {
        let relation: CGFloat = 2 * 20 * 5 / 18
        /// The laid-out width less the widths of the parts laid out alone, as the report measured.
        func space(_ parts: [String], wrap: (String) -> String = { $0 }) throws -> CGFloat {
            try layout(wrap(parts.joined())).width - parts.reduce(0) { try $0 + layout(wrap($1)).width }
        }
        let identifiers = try space(["<mi>a</mi>", "<mo>=</mo>", "<mi>b</mi>"])
        let texts = ["<mtext>future value</mtext>", "<mo>=</mo>", "<mtext>principal</mtext>"]
        XCTAssertEqual(identifiers, relation, accuracy: 0.5)
        XCTAssertEqual(try space(texts), relation, accuracy: 0.01)
        XCTAssertEqual(try space(["<mtext>future value</mtext>", "<mo>=</mo>", "<mi>b</mi>"]), identifiers, accuracy: 0.5)
        XCTAssertEqual(try space(texts, wrap: { "<mtable><mtr><mtd>\($0)</mtd></mtr></mtable>" }), relation, accuracy: 0.01)
        // A binary operator between texts is spaced as one, not drawn as a sign.
        XCTAssertEqual(try space(["<mtext>a</mtext>", "<mo>+</mo>", "<mtext>b</mtext>"]), 2 * 20 * 4 / 18, accuracy: 0.01)

        /// The space an `=` gets where `wrap` puts it: the width it adds over an unspaced one.
        func added(_ wrap: (String) -> String) throws -> CGFloat {
            try layout(wrap("<mo>=</mo>")).width - layout(wrap("<mo lspace=\"0\" rspace=\"0\">=</mo>")).width
        }
        let between = { (operator: String) in "<mtext>a</mtext>\(`operator`)<mtext>b</mtext>" }
        // Wrapped in an mrow, in a cell, as a radicand: still no enclosing row to space it.
        XCTAssertEqual(try added { "<mrow>\(between($0))</mrow>" }, relation, accuracy: 0.01)
        XCTAssertEqual(try added { "<mtable><mtr><mtd><mrow>\(between($0))</mrow></mtd></mtr></mtable>" }, relation, accuracy: 0.01)
        XCTAssertEqual(try added { "<msqrt>\(between($0))</msqrt>" }, relation, accuracy: 0.01)
        XCTAssertEqual(try added { "<msqrt><mrow>\(between($0))</mrow></msqrt>" }, relation, accuracy: 0.01)
        // Split across rows, each side is still spaced exactly once.
        XCTAssertEqual(try added { "<mtext>a</mtext><mrow>\($0)<mtext>b</mtext></mrow>" }, relation, accuracy: 0.01)
        // An enclosing row spaces an embellished row as a whole, once.
        XCTAssertEqual(try added { "<mi>x</mi><mrow>\(between($0))</mrow><mi>y</mi>" }, relation, accuracy: 0.01)
        // Space only towards a neighbor: an operator alone, or at an edge, is not padded there.
        XCTAssertEqual(try added { $0 }, 0, accuracy: 0.01)
        XCTAssertEqual(try added { "<mrow>\($0)</mrow>" }, 0, accuracy: 0.01)
        XCTAssertEqual(try added { "<mtext>a</mtext>\($0)" }, relation / 2, accuracy: 0.01)
        // Scripts drop relation spacing, as before.
        XCTAssertEqual(try added { "<msub><mi>x</mi><mrow>\(between($0))</mrow></msub>" }, 0, accuracy: 0.01)
    }

    /// With two operators the row is no embellished operator, and each takes its form from its
    /// place among the in-flow children, which the texts are not. They are operands all the same.
    func testEveryOperatorOfAWordEquationIsSpaced() throws {
        let medium: CGFloat = 2 * 20 * 4 / 18, thick: CGFloat = 2 * 20 * 5 / 18
        /// The space `symbol` gets in `body`, where `OP` marks it: the width it adds over an unspaced one.
        func added(_ symbol: String, in body: String) throws -> CGFloat {
            try layout(body.replacingOccurrences(of: "OP", with: "<mo>\(symbol)</mo>")).width
                - layout(body.replacingOccurrences(of: "OP", with: "<mo lspace=\"0\" rspace=\"0\">\(symbol)</mo>")).width
        }
        let value = "<mtext>future value</mtext>", principal = "<mtext>principal</mtext>", rate = "<mtext>rate</mtext>"
        // A product after a relation, a sum before one, and a relation last among the operators.
        XCTAssertEqual(try added("×", in: "\(value)<mo>=</mo>\(principal)OP\(rate)"), medium, accuracy: 0.01)
        XCTAssertEqual(try added("=", in: "\(value)OP\(principal)<mo>×</mo>\(rate)"), thick, accuracy: 0.01)
        XCTAssertEqual(try added("−", in: "\(value)OP\(principal)<mo>=</mo>\(rate)"), medium, accuracy: 0.01)
        XCTAssertEqual(try added("+", in: "\(value)OP\(principal)<mo>=</mo>\(rate)"), medium, accuracy: 0.01)
        XCTAssertEqual(try added("=", in: "\(value)<mo>−</mo>\(principal)OP\(rate)"), thick, accuracy: 0.01)
        // Text on one side is operand enough for a product, whatever is on the other.
        XCTAssertEqual(try added("×", in: "\(value)<mo>=</mo>\(principal)OP<msup><mrow><mo>(</mo><mn>1</mn><mo>+</mo><mi>r</mi><mo>)</mo></mrow><mi>n</mi></msup>"),
                       medium, accuracy: 0.01)
        XCTAssertEqual(try added("×", in: "\(value)OP<mi>b</mi><mo>=</mo><mi>c</mi>"), medium, accuracy: 0.01)
        XCTAssertEqual(try added("+", in: "<mn>5</mn><mtext> apples </mtext>OP<mn>3</mn><mtext> pears</mtext>"), medium, accuracy: 0.01)
        // Wrapped text is text; an image glyph and its alt are too.
        XCTAssertEqual(try added("×", in: "<mi>y</mi><mo>=</mo><mstyle mathcolor=\"red\">\(principal)</mstyle>OP<mrow>\(rate)</mrow>"),
                       medium, accuracy: 0.01)
        XCTAssertEqual(try added("×", in: "<mi>y</mi><mo>=</mo><mglyph alt=\"principal\"/>OP<mi>r</mi>"), medium, accuracy: 0.01)
        // A sign stays a sign: before a number or an identifier MathML's forms decide, text or no text,
        // and white space is not an operand.
        XCTAssertEqual(try added("−", in: "<mtext>if </mtext>OP<mi>x</mi><mo>&gt;</mo><mn>0</mn>"), 0, accuracy: 0.01)
        XCTAssertEqual(try added("−", in: "<mtext>Total: </mtext>OP<mn>5</mn>"), 0, accuracy: 0.01)
        XCTAssertEqual(try added("−", in: "<mi>x</mi><mo>=</mo><mtext> </mtext>OP<mn>3</mn>"), 0, accuracy: 0.01)
        XCTAssertEqual(try added("−", in: "<mi>x</mi><mo>=</mo><mspace width=\"1em\"/>OP<mn>3</mn>"), 0, accuracy: 0.01)
        XCTAssertEqual(try added("−", in: "<mi>x</mi><mo>=</mo>OP<mtext>rate</mtext>"), 0, accuracy: 0.01)
        XCTAssertEqual(try added("+", in: "<mi>x</mi>OP"), 0, accuracy: 0.01)
    }

    func testMathVariants() {
        XCTAssertEqual(MathVariant.italic.apply(to: "x"), "𝑥")
        XCTAssertEqual(MathVariant.italic.apply(to: "h"), "ℎ")
        XCTAssertEqual(MathVariant.italic.apply(to: "α"), "𝛼")
        XCTAssertEqual(MathVariant.doubleStruck.apply(to: "RZ1"), "ℝℤ𝟙")
        XCTAssertEqual(MathVariant.bold.apply(to: "v2"), "𝐯𝟐")
        XCTAssertEqual(MathVariant.fraktur.apply(to: "gH"), "𝔤ℌ")
        XCTAssertEqual(MathVariant.script.apply(to: "L"), "ℒ")
        XCTAssertEqual(MathVariant.sansSerifBoldItalic.apply(to: "ω"), "𝟂")
        XCTAssertEqual(MathVariant(attribute: "bold-italic"), .boldItalic)
    }

    func testSingleLetterIdentifiersAreItalic() throws {
        let italic = try layout("<mi>x</mi>"), upright = try layout("<mi mathvariant=\"normal\">x</mi>")
        XCTAssertNotEqual(italic.width, upright.width)
        let function = try layout("<mi>sin</mi>"), text = try layout("<mtext>sin</mtext>")
        XCTAssertEqual(function.width, text.width, accuracy: 0.01, "multi-letter identifiers are upright")
    }

    func testTablesAlignOnTheAxisAndGrow() throws {
        let one = try layout("<mtable><mtr><mtd><mn>1</mn></mtd><mtd><mn>2</mn></mtd></mtr></mtable>")
        let two = try layout("<mtable><mtr><mtd><mn>1</mn></mtd><mtd><mn>2</mn></mtd></mtr><mtr><mtd><mn>3</mn></mtd><mtd><mn>4</mn></mtd></mtr></mtable>")
        XCTAssertGreaterThan(height(two), height(one) * 1.8)
        let axis = MathFont.named(nil).constants.axisHeight * 20
        XCTAssertEqual((two.ascent - two.descent) / 2, axis, accuracy: 0.5)
        let labeled = try layout("<mtable><mlabeledtr><mtd><mtext>(1)</mtext></mtd><mtd><mi>x</mi></mtd></mlabeledtr></mtable>")
        XCTAssertGreaterThan(labeled.width, try layout("<mtext>(1)</mtext>").width + (try layout("<mi>x</mi>").width))
    }

    func testRemainingElementsLayOut() throws {
        let bodies = [
            "<menclose notation=\"box circle roundedbox updiagonalstrike downdiagonalstrike longdiv top bottom left right actuarial madruwb horizontalstrike verticalstrike unknown\"><mi>x</mi></menclose>",
            "<mpadded width=\"+1em\" height=\"2ex\" depth=\"50%\" lspace=\"0.2em\" voffset=\"-0.1em\"><mi>x</mi></mpadded>",
            "<mphantom><mi>x</mi></mphantom>", "<mspace width=\"1em\" height=\"1ex\" depth=\"0.5ex\"/>",
            "<mfenced open=\"[\" close=\"]\" separators=\";,\"><mi>a</mi><mi>b</mi><mi>c</mi></mfenced>",
            "<semantics><mi>x</mi><annotation encoding=\"TeX\">x</annotation></semantics>",
            "<maction actiontype=\"toggle\" selection=\"2\"><mi>a</mi><mi>b</mi></maction>",
            "<merror><mtext>error</mtext></merror>", "<ms>text</ms>",
            "<mstyle mathcolor=\"red\" mathbackground=\"#ff08\" mathsize=\"big\" scriptlevel=\"+1\" displaystyle=\"true\"><mi>x</mi></mstyle>",
            "<mmultiscripts><mi>C</mi><mi>k</mi><none/><mprescripts/><mi>n</mi><none/></mmultiscripts>",
            "<mfrac bevelled=\"true\"><mn>1</mn><mn>2</mn></mfrac>",
            "<munder accentunder=\"true\"><mi>x</mi><mo>_</mo></munder>",
            "<mtable frame=\"dashed\" rowlines=\"solid\" columnlines=\"dashed\" columnalign=\"left right\" align=\"baseline 1\"><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr><mtr><mtd><mi>c</mi></mtd><mtd columnalign=\"center\"><mi>d</mi></mtd></mtr></mtable>",
            "<mi>sin</mi><mo>\u{2061}</mo><mi>x</mi><mo>\u{2062}</mo><mi>y</mi>",
        ]
        for body in bodies {
            let result = try layout(body)
            XCTAssertGreaterThan(result.width, 0, body)
            XCTAssertTrue(result.ascent.isFinite && result.descent.isFinite, body)
        }
        XCTAssertEqual(try layout("<mphantom><mi>x</mi></mphantom>").width, try layout("<mi>x</mi>").width, accuracy: 0.01)
        XCTAssertNil(ink(try layout("<mphantom><mi>x</mi></mphantom>")), "phantoms take space but draw nothing")
    }

    func testUnsupportedAndInvalidMarkupThrow() throws {
        XCTAssertThrowsError(try layout("<mrow><mi>x</mi><mnosuch/></mrow>")) {
            XCTAssertEqual($0 as? MathLayoutError, .unsupported("mnosuch"))
        }
        XCTAssertThrowsError(try layout("<mfrac><mi>x</mi></mfrac>")) {
            XCTAssertEqual($0 as? MathLayoutError, .invalidMarkup("mfrac"))
        }
        XCTAssertThrowsError(try MathMLNode.parse(xml: Data("<math><mi>x</math>".utf8)))
        XCTAssertThrowsError(try MathMLNode.parse(xml: Data(#"<!DOCTYPE m [<!ENTITY a "aaaa">]><math><mi>&a;</mi></math>"#.utf8)))
    }

    func testUntrustedInputIsBounded() throws {
        let deep = String(repeating: "<mrow>", count: 100) + "<mi>x</mi>" + String(repeating: "</mrow>", count: 100)
        XCTAssertThrowsError(try layout(deep)) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded) }
        let deepNode = (0..<10_000).reduce(MathMLNode(name: "mi", text: "x")) { inner, _ in MathMLNode(name: "mrow", children: [inner]) }
        XCTAssertThrowsError(try MathLayout(deepNode, style: MathStyle(fontSize: 17, color: black))) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
        let wide = MathMLNode(name: "math", children: Array(repeating: MathMLNode(name: "mi", text: "x"), count: 30_000))
        XCTAssertThrowsError(try MathLayout(wide, style: MathStyle(fontSize: 17, color: black))) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
        XCTAssertThrowsError(try layout("<mspace width=\"1e9em\"/><mspace width=\"999em\"/><mspace width=\"999em\"/><mspace width=\"999em\"/>")) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
        let long = try layout("<mtext>\(String(repeating: "a", count: 40_000))</mtext>", size: 1)
        XCTAssertLessThanOrEqual(long.width, MathLimits.extent)
        XCTAssertThrowsError(try layout("<mtext>\(String(repeating: "a", count: 60_000))</mtext>", size: 1))
        // Hostile stretch requests stay bounded.
        let rows = String(repeating: "<mtr><mtd><mn>1</mn></mtd></mtr>", count: 400)
        let tall = try layout("<mo>(</mo><mtable>\(rows)</mtable><mo>)</mo>", size: 4)
        XCTAssertLessThan(height(tall), MathLimits.extent)
    }

    func testBoxCoversItsInk() throws {
        let bodies = [
            "<mi>f</mi>", "<msup><mi>f</mi><mn>2</mn></msup>", "<mo>∫</mo>", "<mi>j</mi>",
            "<msubsup><mo>∫</mo><mn>0</mn><mn>1</mn></msubsup>", "<mover><mi>A</mi><mo>~</mo></mover>",
            "<msqrt><mfrac><mi>a</mi><mi>b</mi></mfrac></msqrt>", "<menclose notation=\"circle\"><mi>x</mi></menclose>",
        ]
        for body in bodies {
            for display in [false, true] {
                let result = try layout(body, display: display)
                guard let ink = ink(result) else { XCTFail(body); continue }
                XCTAssertGreaterThanOrEqual(ink.minX, -0.5, body)
                XCTAssertLessThanOrEqual(ink.maxX, result.width + 0.5, body)
                XCTAssertLessThanOrEqual(ink.maxY, result.ascent + 0.5, body)
                XCTAssertGreaterThanOrEqual(ink.minY, -result.descent - 0.5, body)
            }
        }
    }

    func testLayoutIsDeterministicAndThreadSafe() throws {
        let body = "<mi>x</mi><mo>=</mo><mfrac><mrow><mo>−</mo><mi>b</mi><mo>±</mo><msqrt><msup><mi>b</mi><mn>2</mn></msup><mo>−</mo><mn>4</mn><mi>a</mi><mi>c</mi></msqrt></mrow><mrow><mn>2</mn><mi>a</mi></mrow></mfrac>"
        let parsed = try node(body, display: true)
        let reference = try MathLayout(parsed, style: MathStyle(fontSize: 19, color: black, isDisplay: true))
        let results = UnsafeMutableBufferPointer<CGFloat>.allocate(capacity: 64 * 3)
        defer { results.deallocate() }
        let sendable = SendableBuffer(buffer: results)
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            let layout = try? MathLayout(parsed, style: MathStyle(fontSize: 19, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                                                                  isDisplay: true))
            sendable.buffer[index * 3] = layout?.width ?? -1
            sendable.buffer[index * 3 + 1] = layout?.ascent ?? -1
            sendable.buffer[index * 3 + 2] = layout?.descent ?? -1
        }
        for index in 0..<64 {
            XCTAssertEqual(results[index * 3], reference.width)
            XCTAssertEqual(results[index * 3 + 1], reference.ascent)
            XCTAssertEqual(results[index * 3 + 2], reference.descent)
        }
        let again = try MathLayout(parsed, style: MathStyle(fontSize: 19, color: black, isDisplay: true))
        XCTAssertEqual(ink(again), ink(reference))
    }

    func testFallsBackWithoutAMathFont() throws {
        let missing = try layout("<mfrac><mi>a</mi><mi>b</mi></mfrac>", font: "NoSuchFont-Regular")
        let standard = try layout("<mfrac><mi>a</mi><mi>b</mi></mfrac>")
        XCTAssertEqual(missing.width, standard.width, "an unknown font name uses the platform's math font")
        // A text font has no MATH table: fallback constants and drawn fences.
        let plain = try layout("<mo>(</mo><mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mi>c</mi></mfrac><mo>)</mo><msqrt><mi>x</mi></msqrt>",
                               display: true, font: "Helvetica")
        let content = try layout("<mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mi>c</mi></mfrac>", display: true, font: "Helvetica")
        XCTAssertGreaterThanOrEqual(height(plain), height(content) * 0.9)
        XCTAssertNotNil(ink(plain))
    }

    func testParsesNamespacesTokensAndReferences() throws {
        let parsed = try MathMLNode.parse(xml: Data("""
        <m:math xmlns:m="http://www.w3.org/1998/Math/MathML" alttext="x"><m:mrow><m:mi> x </m:mi><m:mo>&#x2212;</m:mo><m:mtext>a<m:malignmark/>b</m:mtext></m:mrow></m:math>
        """.utf8))
        XCTAssertEqual(parsed.name, "math")
        XCTAssertEqual(parsed.attributes["alttext"], "x")
        let row = parsed.children[0]
        XCTAssertEqual(row.children.map(\.name), ["mi", "mo", "mtext"])
        XCTAssertEqual(row.children[1].text, "\u{2212}")
        XCTAssertEqual(row.children[2].text, "ab")
        XCTAssertEqual(row.children[2].children.map(\.name), ["malignmark"])
    }

    func testAccessibilityDescription() throws {
        XCTAssertEqual(try node("<msup><mi>x</mi><mn>2</mn></msup><mo>+</mo><mn>1</mn>").accessibilityDescription,
                       "x squared plus 1")
        XCTAssertEqual(try node("<mfrac><mi>a</mi><mi>b</mi></mfrac>").accessibilityDescription, "a over b")
        XCTAssertEqual(try node("<mfrac><mrow><mi>a</mi><mo>+</mo><mi>b</mi></mrow><mi>c</mi></mfrac>").accessibilityDescription,
                       "start fraction a plus b over c end fraction")
        XCTAssertEqual(try node("<msqrt><mi>x</mi></msqrt>").accessibilityDescription, "the square root of x")
        XCTAssertEqual(try node("<msub><mi>x</mi><mn>1</mn></msub><mo>=</mo><mo>−</mo><mn>3</mn>").accessibilityDescription,
                       "x sub 1 equals minus 3")
    }

    /// The README's usage statements and doc/examples/Drawing.swift, so they keep compiling.
    func testReadmeExample() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let markup = #"<math display="block"><mfrac><mi>a</mi><msup><mi>b</mi><mn>2</mn></msup></mfrac></math>"#
        let formula = try MathMLNode.parse(xml: Data(markup.utf8))
        let layout = try MathLayout(formula, style: MathStyle(
            fontSize: 17, color: CGColor(gray: 0, alpha: 1), isDisplay: true))
        layout.draw(in: context, baselineOrigin: CGPoint(x: 0, y: layout.descent))
        XCTAssertGreaterThan(layout.width, 0)
        XCTAssertGreaterThan(layout.ascent, 0)
        XCTAssertGreaterThan(layout.descent, 0)
        XCTAssertEqual(formula.accessibilityDescription, "start fraction a over b squared end fraction")
    }

    /// The Swift examples in doc/examples for line breaking, images and readings, verbatim.
    func testReadmeFeatureExamples() throws {
        func drawBroken(_ formula: MathMLNode, style: MathStyle, in context: CGContext) throws {
            // A display formula in a 320-point column: every row, stacked under the first row's baseline.
            let block = try MathLayout(formula, style: style, maximumWidth: 320)
            block.draw(in: context, baselineOrigin: CGPoint(x: 0, y: block.descent))

            // An inline formula that starts where 90 points are left on its text line. Each row is a
            // fragment with its own box: place one on each following text line and draw it there.
            let inline = try MathLayout(formula, style: style, maximumWidth: 320, firstRowMaximumWidth: 90)
            var baseline = CGPoint(x: 230, y: 400)
            for row in inline.rows {
                row.draw(in: context, baselineOrigin: baseline)
                baseline = CGPoint(x: 0, y: baseline.y - 24)
            }
        }

        func style(images: [String: CGImage]) -> MathStyle {
            let provider = MathImageProvider { source in images[source] }
            return MathStyle(fontSize: 17, color: CGColor(gray: 0, alpha: 1), imageProvider: provider)
        }

        func reading(of formula: MathMLNode) -> String {
            let reading = formula.accessibilityDescription(locale: Locale(identifier: "fr-CA"))
            // reading.language is "fr": speak reading.text with a French voice.
            return reading.text // "début de fraction a sur b au carré fin de fraction"
        }

        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 500, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let sum = (1...16).map { "<mi>term\($0)</mi>" }.joined(separator: "<mo>+</mo>") + "<mo>+</mo><mi><mglyph src=\"a.png\" alt=\"a\"/></mi>"
        let long = try node("<mi>y</mi><mo>=</mo>" + sum)
        try drawBroken(long, style: style(images: ["a.png": image]), in: context)
        let inline = try MathLayout(long, style: style(images: [:]), maximumWidth: 320, firstRowMaximumWidth: 90)
        XCTAssertGreaterThan(inline.rows.count, 2)
        XCTAssertLessThanOrEqual(inline.rows[0].width, 90)
        let markup = #"<math display="block"><mfrac><mi>a</mi><msup><mi>b</mi><mn>2</mn></msup></mfrac></math>"#
        XCTAssertEqual(reading(of: try MathMLNode.parse(xml: Data(markup.utf8))), "début de fraction a sur b au carré fin de fraction")
        XCTAssertEqual(MathReading.languages, ["en", "fr", "de", "es", "it"])
    }
}

private struct SendableBuffer: @unchecked Sendable {
    let buffer: UnsafeMutableBufferPointer<CGFloat>

}

