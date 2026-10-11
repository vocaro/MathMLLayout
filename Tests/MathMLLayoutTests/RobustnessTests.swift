import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

/// Untrusted input (README, "Bounds"): whatever the markup, layout either succeeds within its
/// bounds or throws a `MathLayoutError`. It never crashes, hangs or draws without limit.
final class RobustnessTests: XCTestCase {
    private enum Outcome: Equatable { case laidOut, threw(MathLayoutError) }

    /// Lays `root` out and draws it, failing the test on anything but a bounded layout or a
    /// `MathLayoutError`.
    @discardableResult
    private func survive(_ root: MathMLNode, size: CGFloat = 17, display: Bool = true, _ label: @autoclosure () -> String,
                         file: StaticString = #filePath, line: UInt = #line) -> Outcome {
        do {
            let layout = try MathLayout(root, style: MathStyle(fontSize: size, color: black, isDisplay: display))
            for value in [layout.width, layout.ascent, layout.descent] {
                XCTAssertTrue(value.isFinite && value >= 0 && value <= MathLimits.extent, "\(label()): \(value)", file: file, line: line)
            }
            let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            layout.draw(in: context, baselineOrigin: CGPoint(x: 8, y: 24))
            return .laidOut
        } catch let error as MathLayoutError {
            return .threw(error)
        } catch {
            XCTFail("\(label()): threw \(error), not a MathLayoutError", file: file, line: line)
            return .threw(.invalidMarkup("\(error)"))
        }
    }

    @discardableResult
    private func survive(_ body: String, size: CGFloat = 17, display: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> Outcome {
        guard let root = try? mathML(body, display: display) else { XCTFail("test markup does not parse: \(body.prefix(120))", file: file, line: line); return .laidOut }
        return survive(root, size: size, display: display, String(body.prefix(160)), file: file, line: line)
    }

    private func nested(_ levels: Int, _ wrap: (MathMLNode) -> MathMLNode) -> MathMLNode { (0..<levels).reduce(mi("x")) { inner, _ in wrap(inner) } }

    // MARK: Degenerate and hostile markup

    func testDegenerateMarkupLaysOutOrThrows() {
        // Shapes from the web-platform-tests MathML crash tests and their kin.
        let bodies = [
            // Empty elements, alone.
            "<mrow/>", "<mtable/>", "<munder/>", "<ms/>", "<mstyle/>", "<mfenced/>", "<msqrt/>", "<menclose/>", "<mpadded/>", "<mphantom/>", "<merror/>",
            "<maction/>", "<semantics/>", "<mmultiscripts/>", "<mfrac/>", "<mroot/>", "<msub/>", "<mover/>", "<munderover/>", "<mtr/>", "<mtd/>", "<mlabeledtr/>",
            // Wrong numbers of children, and empty children where content is expected.
            "<mroot><mi>x</mi></mroot>", "<msub><mi>x</mi></msub>", "<munderover><mi>x</mi><mi>y</mi></munderover>", "<mfrac><mi>x</mi></mfrac>",
            "<mfrac><mmultiscripts/><mi/></mfrac>", "<msubsup><mtable/><mstyle/><mrow/></msubsup>", "<mover><mrow/><mn/></mover>", "<mfrac><mrow/><mrow/></mfrac>",
            "<mroot><mrow/><mrow/></mroot>", "<msqrt><mrow/></msqrt>", "<munderover><mo/><mo/><mo/></munderover>", "<msubsup><none/><none/><none/></msubsup>",
            "<mmultiscripts><mi>x</mi><mprescripts/><mprescripts/><mi>a</mi><mi>b</mi></mmultiscripts>", "<mmultiscripts><mprescripts/></mmultiscripts>",
            "<mmultiscripts><mmultiscripts><mi>x</mi><mprescripts/><mi>a</mi><mi>b</mi></mmultiscripts><mprescripts/><mi>c</mi><mi>d</mi></mmultiscripts>",
            // Tables put together wrongly.
            "<mtd><mtable><mtr/></mtable></mtd>", "<mtr><mtable><mtr><mtd><mi>x</mi></mtd></mtr></mtable></mtr>", "<mtable><mtr><mtr><mtd><mi>x</mi></mtd></mtr></mtr></mtable>",
            "<mtable><mtd><mtr><mi>x</mi></mtr></mtd></mtable>", "<mtable><mtr><mtd rowspan=\"0\" columnspan=\"0\"><mi>x</mi></mtd></mtr></mtable>",
            "<mtable><mtr><mtd rowspan=\"-2\" columnspan=\"1073741825\"><mi>x</mi></mtd></mtr></mtable>", "<mtable><mlabeledtr><mtd/></mlabeledtr><mlabeledtr/></mtable>",
            "<mtable align=\"baseline 99999999999999999999\"><mtr><mtd><mi>x</mi></mtd></mtr></mtable>",
            "<mtable align=\"axis -9223372036854775808\"><mtr><mtd><mi>x</mi></mtd></mtr></mtable>",
            "<mtable align=\"top 9223372036854775807\"><mtr><mtd><mi>x</mi></mtd></mtr></mtable>", "<mtable align=\"center -1\"/>",
            "<mtable columnalign=\"\" rowspacing=\"\" columnspacing=\"\" rowlines=\"\" columnlines=\"\" frame=\"\" framespacing=\"\" align=\"\" side=\"\"><mtr><mtd><mi>x</mi></mtd></mtr></mtable>",
            // Negative and nonsensical lengths.
            "<mspace width=\"-1px\"/>", "<mspace height=\"-1px\"/>", "<mspace depth=\"-1px\"/>", "<mspace width=\"-10px\" height=\"-10px\" depth=\"10px\"/>",
            "<mi>a</mi><mspace width=\"-50em\"/><mi>b</mi>", "<mpadded width=\"-100px\" height=\"-100px\" depth=\"-100px\" lspace=\"-100px\" voffset=\"-100px\"><mi>x</mi></mpadded>",
            "<mpadded height=\"20 10\"><mi>x</mi></mpadded>", "<mpadded width=\"1e999px\" height=\"0x10\" depth=\"١em\"><mi>x</mi></mpadded>",
            "<mfrac linethickness=\"-999em\"><mi>a</mi><mi>b</mi></mfrac>", "<mfrac linethickness=\"999999em\"><mi>a</mi><mi>b</mi></mfrac>",
            "<mi>a</mi><mo lspace=\"-999em\" rspace=\"-999em\">+</mo><mi>b</mi>", "<mo minsize=\"-5em\" maxsize=\"-5em\">(</mo><mi>x</mi><mo maxsize=\"0\">)</mo>",
            "<mo minsize=\"99999em\">(</mo><mfrac><mi>a</mi><mi>b</mi></mfrac><mo minsize=\"99999em\">)</mo>", "<mtable rowspacing=\"-99em\" columnspacing=\"-99em\" framespacing=\"-99em -99em\" frame=\"solid\" minlabelspacing=\"-99em\"><mlabeledtr><mtd><mi>l</mi></mtd><mtd><mi>x</mi></mtd></mlabeledtr></mtable>",
            // Extreme style values.
            "<mstyle scriptlevel=\"101\"><mstyle scriptlevel=\"-204\"><mi>x</mi></mstyle></mstyle>", "<mstyle scriptlevel=\"127\"><mstyle scriptlevel=\"+2147483645\"><mi>x</mi></mstyle></mstyle>",
            "<mstyle scriptlevel=\"-2147483648\"><msup><mi>x</mi><mn>2</mn></msup></mstyle>", "<mstyle scriptsizemultiplier=\"8205\"><msup><mi>x</mi><mn>2</mn></msup></mstyle>",
            "<mstyle scriptsizemultiplier=\"10\" scriptlevel=\"16\"><mi>x</mi></mstyle>", "<mstyle scriptsizemultiplier=\"0.11\" scriptminsize=\"0\" scriptlevel=\"16\"><mi>x</mi></mstyle>",
            "<mstyle scriptsizemultiplier=\"NaN\" scriptminsize=\"-1em\"><msup><mi>x</mi><mn>2</mn></msup></mstyle>", "<mstyle mathsize=\"0.00001px\"><mfrac><mi>a</mi><msqrt><mi>b</mi></msqrt></mfrac></mstyle>",
            "<mstyle mathsize=\"99999em\"><mi>x</mi></mstyle>", "<mstyle mathsize=\"1000\"><mstyle mathsize=\"1000\"><mi>x</mi></mstyle></mstyle>",
            "<mstyle mathsize=\"0.001\"><mo>(</mo><mstyle mathsize=\"100000\"><mi>x</mi></mstyle><mo>)</mo></mstyle>",
            "<mi mathcolor=\"#\" mathbackground=\"#gggggg\" mathvariant=\"\" mathsize=\"\">x</mi>", "<maction selection=\"99999999999999999999999\"><mi>x</mi></maction>",
            "<maction selection=\"-9223372036854775807\"><mi>x</mi></maction>", "<maction selection=\"9223372036854775807\"><mi>x</mi></maction>",
            // Stretching with nothing sensible to cover.
            "<mo>(</mo><mo>⨂</mo><mo>)</mo>", "<mover><mo>↠</mo><mspace width=\"500px\"/></mover>", "<mover><mo>↡</mo><mspace height=\"500px\"/></mover>",
            "<mo>(</mo><mspace height=\"40000px\"/><mo>)</mo><mi>x</mi>", "<munder><mo>⏟</mo><mspace width=\"40000px\"/></munder>", "<mover><mo>→</mo><mo>→</mo></mover>",
            "<munderover><mo>⏞</mo><mo>⏟</mo><mo>¯</mo></munderover>", "<msqrt><mspace height=\"30000px\" depth=\"15000px\"/></msqrt>",
            "<mo stretchy=\"true\">abc</mo><mfrac><mi>a</mi><mi>b</mi></mfrac>", "<mo stretchy=\"true\" largeop=\"true\" movablelimits=\"true\" accent=\"true\">\u{0332}</mo><mfrac><mi>a</mi><mi>b</mi></mfrac>",
            // Token text.
            "<mo> -</mo>", "<mo>\u{0332}</mo>", "<mi>\u{0332}</mi>", "<mi>א</mi><mo>+</mo><mi>ب</mi>", "<mi>👩‍👩‍👧‍👦</mi><msup><mi>🧮</mi><mn>2</mn></msup>", "<mtext>\u{202E}reversed\u{202C}</mtext>",
            "<mi mathvariant=\"bold\">👍</mi>", "<mn>１２３</mn>", "<mi>x\u{0301}\u{0302}\u{0303}\u{0304}\u{0305}\u{0306}\u{0307}\u{0308}</mi>", "<ms lquote=\"\u{0301}\" rquote=\"\u{0301}\">\u{0301}</ms>",
            "<msup><mi>x</mi><mtext>\(String(repeating: "long script ", count: 400))</mtext></msup>",
            // Fences and enclosures.
            "<mfenced open=\"\(String(repeating: "(", count: 3000))\" close=\"\(String(repeating: ")", count: 3000))\" separators=\"\(String(repeating: ";", count: 3000))\"><mi>a</mi><mi>b</mi></mfenced>",
            "<mfenced open=\"&lt;&amp;\" close=\"\u{0301}\" separators=\"\u{0301}\u{200D}\"><mi>a</mi><mi>b</mi><mi>c</mi></mfenced>",
            "<menclose notation=\"\(String(repeating: "box circle updiagonalarrow radical longdiv ", count: 2000))\"><mi>x</mi></menclose>",
            "<menclose notation=\"radical radical circle\"><mspace/></menclose>", "<menclose notation=\"updiagonalarrow\"><mspace/></menclose>",
            "<mtable columnalign=\"\(String(repeating: "left right ", count: 5000))\" rowlines=\"\(String(repeating: "solid dashed ", count: 5000))\"><mtr><mtd><mi>x</mi></mtd></mtr></mtable>",
        ]
        for body in bodies { survive(body); survive(body, size: 1, display: false) }
    }

    func testHostileHandBuiltNodesLayOutOrThrow() {
        // A tree built from a host's own DOM has not been through the XML parser.
        let strange = ["\u{0}", "\u{FFFF}", "\u{FFFE}\u{FEFF}", "\u{1F}\u{7F}", "\u{E000}\u{10FFFF}", "\u{2028}\u{2029}", "\r\n\t", String(repeating: "\u{0301}", count: 2000),
                       String(repeating: "\u{200D}", count: 2000), "a\u{0}b"]
        for text in strange {
            for name in ["mi", "mn", "mo", "mtext", "ms"] {
                let label = "\(name) with \(text.unicodeScalars.prefix(3).map { "U+\(String($0.value, radix: 16))" })"
                survive(math(MathMLNode(name: name, text: text)), label)
                survive(math(mo("("), MathMLNode(name: name, text: text), mo(")")), label)
            }
            survive(math(MathMLNode(name: "mfenced", attributes: ["open": text, "close": text, "separators": text], children: [mi("a"), mi("b")])), "mfenced \(text.count)")
            survive(math(MathMLNode(name: "mi", attributes: ["mathvariant": text, "mathcolor": text, "mathsize": text, "mathbackground": text], text: "x")), "attributes")
        }
        // Names, attributes and structure no parser would produce.
        survive(MathMLNode(name: ""), "an element with no name")
        survive(MathMLNode(name: "math", text: "text on a non-token"), "text on math")
        survive(math(MathMLNode(name: "mi", children: [mi("a"), MathMLNode(name: "mfrac")], text: "x")), "a token with element children")
        survive(math(MathMLNode(name: "mspace", children: [mi("a")], text: "x")), "an mspace with content")
        survive(math(MathMLNode(name: "none", children: [MathMLNode(name: "no-such-element")])), "children of none are not laid out")
        survive(math(MathMLNode(name: "mtable", children: [MathMLNode(name: "mtr", children: [MathMLNode(name: "mtr"), MathMLNode(name: "mtable"), MathMLNode(name: "mlabeledtr")])])), "rows in rows")
    }

    func testFontSizesOfAnyValueAreBounded() throws {
        let formula = try mathML("<mfrac><mi>a</mi><msqrt><mi>b</mi></msqrt></mfrac><mo>(</mo><munderover><mo>∑</mo><mi>i</mi><mi>n</mi></munderover><mo>)</mo>")
        for size in [CGFloat.infinity, -.infinity, 0, -17, 1e-300, 1e-6, 0.5, 1e6, 1e300, .greatestFiniteMagnitude, .leastNonzeroMagnitude, -0.0] {
            XCTAssertEqual(survive(formula, size: size, "font size \(size)"), .laidOut, "font size \(size)")
            let layout = try MathLayout(formula, style: MathStyle(fontSize: size, color: black))
            XCTAssertGreaterThan(layout.width, 0, "font size \(size)"); XCTAssertGreaterThan(layout.ascent + layout.descent, 0, "font size \(size)")
        }
        // Sizes are clamped to 1...1000 points.
        let one = try MathLayout(formula, style: MathStyle(fontSize: 1, color: black)), thousand = try MathLayout(formula, style: MathStyle(fontSize: 1000, color: black))
        XCTAssertEqual(try MathLayout(formula, style: MathStyle(fontSize: 0.001, color: black)).width, one.width)
        XCTAssertEqual(try MathLayout(formula, style: MathStyle(fontSize: -5, color: black)).width, one.width)
        XCTAssertEqual(try MathLayout(formula, style: MathStyle(fontSize: 1e9, color: black)).width, thousand.width)
        XCTAssertEqual(try MathLayout(formula, style: MathStyle(fontSize: .infinity, color: black)).width, thousand.width)
    }

    /// A size that is not a number used to slip through the clamp. The result must be a usable
    /// layout (the smallest size, like any other size that is not positive) or an error, not a
    /// formula that measures nothing.
    func testANaNFontSizeIsClampedOrRefused() throws {
        let formula = try mathML("<mfrac><mi>a</mi><msqrt><mi>b</mi></msqrt></mfrac>")
        guard survive(formula, size: .nan, "font size NaN") == .laidOut else { return }
        let layout = try MathLayout(formula, style: MathStyle(fontSize: .nan, color: black))
        XCTAssertGreaterThan(layout.width, 0, "a NaN font size laid out with no width")
        XCTAssertGreaterThan(layout.ascent + layout.descent, 0, "a NaN font size laid out with no height")
    }

    // MARK: Former crashes

    /// `selection - 1` overflowed for the smallest integer.
    func testActionSelectionAtTheIntegerLimitDoesNotCrash() throws {
        XCTAssertEqual(survive("<maction selection=\"-9223372036854775808\"><mi>x</mi><mi>y</mi></maction>"), .laidOut)
    }

    /// `scriptlevel="+n"` was added to the current level without a bound (the shape of WPT's
    /// `mathml/crashtests/math-depth-overflow`, at this platform's integer width).
    func testRelativeScriptLevelAtTheIntegerLimitDoesNotCrash() throws {
        XCTAssertEqual(survive("<msup><mi>x</mi><mstyle scriptlevel=\"+9223372036854775807\"><mi>y</mi></mstyle></msup>"), .laidOut)
        XCTAssertEqual(survive("<mstyle scriptlevel=\"-1\"><mstyle scriptlevel=\"-9223372036854775808\"><mi>y</mi></mstyle></mstyle>"), .laidOut)
        XCTAssertEqual(survive("<mstyle scriptlevel=\"5\"><mstyle scriptlevel=\"+9223372036854775803\"><mi>y</mi></mstyle></mstyle>"), .laidOut)
    }

    /// The spoken reading is bounded like layout. `isSimple` once recursed without a depth
    /// bound, so a deep hand-built tree under `msqrt`, `mfrac` or `msup` overflowed the stack:
    /// about 2,000 levels on a secondary thread's 512 KB stack, about 30,000 on the main thread.
    ///
    /// Swift frees a tree of values level by level on the stack of whichever thread lets go of
    /// it last, and 5,000 levels do not fit in 512 KB either. So the thread only borrows the
    /// tree: it gives its reference up before it says it has finished, and this thread, with the
    /// stack for it, keeps its own until then. An optimized build otherwise drops this thread's
    /// reference first, and the test ends the process for a reason that is not the reading.
    func testSpeechOfADeepTreeDoesNotOverflowTheStack() throws {
        let deep = nested(5_000) { MathMLNode(name: "mrow", children: [$0]) }
        let roots = [MathMLNode(name: "msqrt", children: [deep]), MathMLNode(name: "mfrac", children: [deep, deep]), MathMLNode(name: "msup", children: [mi("x"), deep])]
        nonisolated(unsafe) var lent: [MathMLNode]? = roots
        let finished = expectation(description: "read on a secondary thread")
        let thread = Thread {
            for root in lent ?? [] { _ = root.accessibilityDescription }
            lent = nil
            finished.fulfill()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        withExtendedLifetime(roots) { wait(for: [finished], timeout: 60) }
    }

    // MARK: The documented bounds, at their edges

    func testDepthBoundForEveryNestingElement() {
        // Nesting well inside the bound lays out; nesting far beyond it throws limitExceeded,
        // whatever the element (each recursion is one more stack frame).
        let wrappers: [(String, Int, (MathMLNode) -> MathMLNode)] = [
            ("mrow", 1, { MathMLNode(name: "mrow", children: [$0]) }), ("mstyle", 1, { MathMLNode(name: "mstyle", children: [$0]) }),
            ("msqrt", 1, { MathMLNode(name: "msqrt", children: [$0]) }), ("mroot index", 1, { MathMLNode(name: "mroot", children: [mi("r"), $0]) }),
            ("mfrac numerator", 1, { MathMLNode(name: "mfrac", children: [$0, mn("1")]) }), ("mfrac denominator", 1, { MathMLNode(name: "mfrac", children: [mn("1"), $0]) }),
            ("msup base", 1, { MathMLNode(name: "msup", children: [$0, mn("2")]) }), ("msub script", 1, { MathMLNode(name: "msub", children: [mi("a"), $0]) }),
            ("msubsup", 1, { MathMLNode(name: "msubsup", children: [mi("a"), mn("1"), $0]) }), ("mmultiscripts", 1, { MathMLNode(name: "mmultiscripts", children: [$0, mn("1"), mn("2")]) }),
            ("mover", 1, { MathMLNode(name: "mover", children: [$0, mo("¯")]) }), ("munder script", 1, { MathMLNode(name: "munder", children: [mi("a"), $0]) }),
            ("munderover", 1, { MathMLNode(name: "munderover", children: [mo("∑"), $0, mn("1")]) }), ("mpadded", 1, { MathMLNode(name: "mpadded", children: [$0]) }),
            ("mphantom", 1, { MathMLNode(name: "mphantom", children: [$0]) }), ("menclose", 1, { MathMLNode(name: "menclose", attributes: ["notation": "box"], children: [$0]) }),
            ("merror", 1, { MathMLNode(name: "merror", children: [$0]) }), ("semantics", 1, { MathMLNode(name: "semantics", children: [$0]) }),
            ("maction", 1, { MathMLNode(name: "maction", children: [$0]) }), ("mfenced", 2, { MathMLNode(name: "mfenced", children: [$0, mi("b")]) }),
            ("fenced row", 1, { MathMLNode(name: "mrow", children: [mo("("), $0, mo(")")]) }),
            ("mtable", 3, { MathMLNode(name: "mtable", children: [MathMLNode(name: "mtr", children: [MathMLNode(name: "mtd", children: [$0])])]) }),
        ]
        for (name, levelsEach, wrap) in wrappers {
            let shallow = MathMLNode(name: "math", children: [nested(48 / levelsEach, wrap)])
            XCTAssertEqual(survive(shallow, size: 12, "\(name) nested \(48 / levelsEach) deep"), .laidOut, "\(name) nested \(48 / levelsEach) deep")
            for levels in [100, 5_000] {
                XCTAssertEqual(survive(MathMLNode(name: "math", children: [nested(levels, wrap)]), size: 12, "\(name) nested \(levels) deep"), .threw(.limitExceeded),
                               "\(name) nested \(levels) deep")
            }
        }
    }

    func testNodeBoundIsExactlyTwentyThousand() {
        // At 1 point the row stays inside the extent bound, so only the node count decides.
        func row(_ nodes: Int) -> MathMLNode { MathMLNode(name: "math", children: Array(repeating: mi("x"), count: nodes - 1)) }
        XCTAssertEqual(survive(row(MathLimits.nodes), size: 1, "\(MathLimits.nodes) nodes"), .laidOut)
        XCTAssertEqual(survive(row(MathLimits.nodes + 1), size: 1, "\(MathLimits.nodes + 1) nodes"), .threw(.limitExceeded))
        XCTAssertEqual(survive(row(500_000), size: 1, "500,000 nodes"), .threw(.limitExceeded))
        // Nodes of every kind count, laid out or not: nested rows, spaces, empty elements.
        let spaces = MathMLNode(name: "math", children: Array(repeating: MathMLNode(name: "mspace"), count: MathLimits.nodes + 10))
        XCTAssertEqual(survive(spaces, size: 1, "spaces"), .threw(.limitExceeded))
        let rows = MathMLNode(name: "math", children: Array(repeating: MathMLNode(name: "mrow", children: [MathMLNode(name: "mrow")]), count: MathLimits.nodes / 2 + 10))
        XCTAssertEqual(survive(rows, size: 1, "nested rows"), .threw(.limitExceeded))
    }

    /// README: "A formula … larger than 20,000 nodes … throws `MathLayoutError.limitExceeded`."
    /// Table rows are nodes too.
    func testTableRowsCountTowardTheNodeBound() {
        let rows = MathMLNode(name: "mtable", attributes: ["rowspacing": "0"], children: Array(repeating: MathMLNode(name: "mtr"), count: 5 * MathLimits.nodes))
        XCTAssertEqual(survive(MathMLNode(name: "math", children: [rows]), "100,000 empty table rows"), .threw(.limitExceeded))
        let labeled = MathMLNode(name: "mtable", attributes: ["rowspacing": "0"],
                                 children: Array(repeating: MathMLNode(name: "mlabeledtr"), count: 5 * MathLimits.nodes))
        XCTAssertEqual(survive(MathMLNode(name: "math", children: [labeled]), "100,000 empty labeled rows"), .threw(.limitExceeded))
    }

    func testTextBoundIsExactlyFiftyThousandUnits() {
        func text(_ units: Int, in name: String = "mtext") -> MathMLNode { math(MathMLNode(name: name, text: String(repeating: "a", count: units))) }
        XCTAssertEqual(survive(text(MathLimits.textLength), size: 1, "50,000 units"), .laidOut)
        XCTAssertEqual(survive(text(MathLimits.textLength + 1), size: 1, "50,001 units"), .threw(.limitExceeded))
        // The bound is on the whole formula, in UTF-16 units, across every kind of token.
        let half = String(repeating: "a", count: MathLimits.textLength / 2)
        XCTAssertEqual(survive(math(MathMLNode(name: "mtext", text: half), MathMLNode(name: "mtext", text: half)), size: 1, "two halves"), .laidOut)
        XCTAssertEqual(survive(math(MathMLNode(name: "mtext", text: half), mi(half + "a")), size: 1, "two halves and one"), .threw(.limitExceeded))
        XCTAssertEqual(survive(math(mn(half), mo(half + "a")), size: 1, "number and operator"), .threw(.limitExceeded))
        let astral = String(repeating: "𝑥", count: MathLimits.textLength / 2 + 1)
        XCTAssertEqual(survive(math(MathMLNode(name: "mtext", text: astral)), size: 1, "25,001 astral characters"), .threw(.limitExceeded))
        // A string's quotes are text too.
        XCTAssertEqual(survive(math(MathMLNode(name: "ms", text: String(repeating: "a", count: MathLimits.textLength - 1))), size: 1, "ms"), .threw(.limitExceeded))
    }

    func testExtentBoundInEachDimension() {
        func spaces(_ attribute: String, _ count: Int) -> String { String(repeating: "<mspace \(attribute)=\"16000px\"/>", count: count) }
        // 17pt lengths are bounded at 1000em each, so several are needed to pass 50,000 points.
        XCTAssertEqual(survive(spaces("width", 3)), .laidOut); XCTAssertEqual(survive(spaces("width", 4)), .threw(.limitExceeded))
        func column(_ attribute: String, _ count: Int) -> String { "<mtable rowspacing=\"0\">" + String(repeating: "<mtr><mtd><mspace \(attribute)=\"16000px\"/></mtd></mtr>", count: count) + "</mtable>" }
        XCTAssertEqual(survive(column("height", 3)), .laidOut); XCTAssertEqual(survive(column("height", 7)), .threw(.limitExceeded))
        XCTAssertEqual(survive(column("depth", 3)), .laidOut); XCTAssertEqual(survive(column("depth", 7)), .threw(.limitExceeded))
        XCTAssertEqual(survive("<mspace height=\"16000px\"/>" + spaces("width", 3)), .laidOut)
        // Ink that leaves the box counts as well: a huge negative space pulls what follows far to the left.
        XCTAssertEqual(survive("<mi>a</mi>" + String(repeating: "<mspace width=\"-16000px\"/>", count: 4) + "<mi>b</mi>"), .threw(.limitExceeded))
    }

    func testTheLargestFormulasFinish() throws {
        // The worst cases the bounds allow, as a guard against layout that hangs. In an
        // unoptimized build each takes a fraction of a second, where a row of stretchy fences once
        // took eight. Nested rows of space-like children are the exception, at several seconds,
        // until https://github.com/vocaro/MathMLLayout/issues/34 is fixed.
        let many = MathLimits.nodes - 2
        let slow: Set = ["nested rows of spaces"]
        let cases: [(String, MathMLNode)] = [
            ("identifiers", MathMLNode(name: "math", children: Array(repeating: mi("x"), count: many))),
            ("fences", MathMLNode(name: "math", children: Array(repeating: mo("("), count: many - 1) + [mi("x")])),
            ("fences and identifiers", MathMLNode(name: "math", children: (0..<many / 2).flatMap { _ in [mo("("), mi("x")] })),
            ("operators", MathMLNode(name: "math", children: (0..<many / 2).flatMap { _ in [mi("a"), mo("+")] })),
            ("spaces around an operator", MathMLNode(name: "math", children: Array(repeating: MathMLNode(name: "mspace"), count: many - 1) + [mo("=")])),
            ("one long text", math(MathMLNode(name: "mtext", text: String(repeating: "word ", count: MathLimits.textLength / 5)))),
            ("table", math(MathMLNode(name: "mtable", attributes: ["rowspacing": "0", "frame": "solid", "rowlines": "solid", "columnlines": "solid"],
                                      children: (0..<90).map { _ in MathMLNode(name: "mtr", children: (0..<70).map { _ in MathMLNode(name: "mtd", children: [mn("1")]) }) }))),
            ("nested scripts", math(nested(60) { MathMLNode(name: "msup", children: [mi("x"), $0]) })),
            ("nested fences", math(nested(60) { MathMLNode(name: "mrow", children: [mo("("), $0, mo(")")]) })),
            ("nested rows of spaces", math(nested(60) { MathMLNode(name: "mrow", children: Array(repeating: MathMLNode(name: "mtext"), count: 300) + [$0]) })),
        ]
        for (name, root) in cases {
            let clock = ContinuousClock()
            let elapsed = clock.measure { survive(root, size: 1, name) }
            XCTAssertLessThan(elapsed, .seconds(slow.contains(name) ? 20 : 5), "\(name) took \(elapsed)")
        }
    }

    // MARK: Mutated input

    /// Corpus formulas with bytes changed, dropped and repeated: whatever the parser accepts,
    /// layout bounds or refuses.
    func testMutatedMarkupNeverCrashes() {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        let fragments = ["<", ">", "/", "\"", "=", "&", ";", " ", "-", "+", "9", "e", "%", "em", "<mrow>", "</mrow>", "<mo>(</mo>", "<mfrac>", "</mfrac>", "<mtable>", "<mtr>",
                         "<none/>", "<mprescripts/>", " stretchy=\"true\"", " scriptlevel=\"+9\"", " mathsize=\"900%\"", " width=\"-9em\"", " selection=\"3\"", " linethickness=\"0\"",
                         " display=\"block\"", " notation=\"box circle\"", " align=\"axis 3\"", "\u{0301}", "∑", "𝑥", "&#x221E;", "&#0;", "<!--", "-->", "<![CDATA[", "]]>"]
        var parsed = 0, laidOut = 0
        for iteration in 0..<1_500 {
            let formula = FormulaCorpus.all[iteration % FormulaCorpus.all.count]
            var bytes = Array("<math xmlns=\"http://www.w3.org/1998/Math/MathML\">\(formula.markup)</math>".utf8)
            for _ in 0...next(3) {
                let position = next(bytes.count)
                switch next(5) {
                case 0: bytes.remove(at: position)
                case 1: bytes.insert(contentsOf: Array(fragments[next(fragments.count)].utf8), at: position)
                case 2: bytes[position] = UInt8(next(256))
                case 3:
                    let end = min(bytes.count, position + 1 + next(40))
                    bytes.insert(contentsOf: bytes[position..<end], at: position)
                default:
                    let end = min(bytes.count, position + 1 + next(40))
                    bytes.removeSubrange(position..<end)
                }
            }
            guard let root = try? MathMLNode.parse(xml: Data(bytes)) else { continue }
            parsed += 1
            if survive(root, size: 14, display: iteration % 2 == 0, "mutation \(iteration) of \(formula.name)") == .laidOut { laidOut += 1 }
            _ = root.accessibilityDescription
        }
        // The mutations are mild enough that many still parse, so layout is really exercised.
        XCTAssertGreaterThan(parsed, 100); XCTAssertGreaterThan(laidOut, 50)
    }

    // MARK: Concurrency

    func testFontCachesSurviveManySizesAndNamesAtOnce() throws {
        // More sizes and font names than the caches hold, from many threads.
        let node = try mathML("<mfrac><mi>a</mi><msup><mi>b</mi><mn>2</mn></msup></mfrac><mo>(</mo><munderover><mo>∑</mo><mi>i</mi><mi>n</mi></munderover><mo>)</mo>", display: true)
        let reference = try MathLayout(node, style: MathStyle(fontSize: 16, color: black, isDisplay: true))
        let count = 600
        let widths = UnsafeMutableBufferPointer<CGFloat>.allocate(capacity: count)
        defer { widths.deallocate() }
        let shared = Widths(buffer: widths)
        DispatchQueue.concurrentPerform(iterations: count) { index in
            let size = CGFloat(8 + index % 300) / 4 + 8, name: String? = index % 3 == 0 ? "NoSuchFont-\(index % 40)" : nil
            shared.buffer[index] = (try? MathLayout(node, style: MathStyle(fontSize: size, color: black, isDisplay: true, fontName: name)))?.width ?? -1
        }
        for index in 0..<count {
            let size = CGFloat(8 + index % 300) / 4 + 8
            XCTAssertEqual(widths[index], reference.width * size / 16, accuracy: 0.02 * reference.width * size / 16 + 0.05, "size \(size)")
        }
        // An unknown font name is the platform's math font, every time.
        for index in 0..<40 { XCTAssertEqual(try MathLayout(node, style: MathStyle(fontSize: 16, color: black, isDisplay: true, fontName: "NoSuchFont-\(index)")).width, reference.width) }
    }
}

private struct Widths: @unchecked Sendable {
    let buffer: UnsafeMutableBufferPointer<CGFloat>
}
