import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

/// `mo` (MathML 3, 3.2.5): the operator dictionary, form, spacing, stretching and large
/// operators.
final class OperatorTests: XCTestCase {
    /// The operator spacing a row adds, in eighteenths of an em: the row's width less the
    /// widths its children have alone.
    private func spacing(_ children: [MathMLNode], wrap: (([MathMLNode]) -> MathMLNode)? = nil, unit: CGFloat = em) throws -> CGFloat {
        let wrap = wrap ?? { MathMLNode(name: "math", children: $0) }
        let whole = try innerBox(wrap(children)).width
        // A child's own width is its width alone. An operator alone has no space from the dictionary
        // but keeps what its `lspace` and `rspace` say, so it is measured with those at nothing.
        func unspaced(_ node: MathMLNode) -> MathMLNode {
            guard node.name == "mo" else { return node }
            var node = node
            node.attributes["lspace"] = "0"; node.attributes["rspace"] = "0"
            return node
        }
        let parts = try children.reduce(CGFloat(0)) { $0 + (try innerBox(wrap([unspaced($1)])).width) }
        return (whole - parts) * 18 / unit
    }

    private func assertSpacing(_ children: [MathMLNode], _ expected: CGFloat, _ message: String = "",
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let label = message.isEmpty ? children.map { $0.text.isEmpty ? $0.name : $0.text }.joined(separator: " ") : message
        XCTAssertEqual(try spacing(children), expected, accuracy: 0.05, label, file: file, line: line)
    }

    private let a = mi("a"), b = mi("b"), x = mi("x")

    // MARK: The dictionary

    func testSpacingFollowsEachOperatorsClass() throws {
        // Eighteenths of an em each side, between two identifiers: thick for relations and
        // arrows, medium for binary operators, thin after punctuation and around large
        // operators, none for fences, ordinary symbols and invisible operators.
        let classes: [(String, CGFloat)] = [
            ("=<>≤≥≠≈≡∼≅∝∈∉⊂⊆⊃⊥∥:→←↔⇒⇔↦↑↓", 10),
            ("+−±∓×÷·⋅∗∘∙⊕⊗∪∩∧∨∖*", 8),
            (",;", 3),
            ("∑∏∐⋃⋂∫∮", 6),
            ("/!.…⋯′%°([{⌈⌊⟨)]}⌉⌋⟩|‖¬∂∇∀∃\u{2062}\u{2063}\u{2064}", 0),
        ]
        for (operators, expected) in classes {
            for scalar in operators.unicodeScalars {
                try assertSpacing([a, mo(String(scalar)), b], expected, "a \(scalar) b (U+\(String(scalar.value, radix: 16)))")
            }
        }
        try assertSpacing([a, mo("-"), b], 8, "a hyphen-minus is the minus sign")
        // An operator the dictionary does not know gets thick spaces, as in MathML Core.
        for unknown in ["⌘", "foo", ":=", "&&", "mod"] { try assertSpacing([a, mo(unknown), b], 10, unknown) }
        // A named function is a prefix operator: a thin space after it.
        for name in ["lim", "max", "min", "sup", "inf", "det", "gcd", "Pr", "lim sup"] { try assertSpacing([mo(name), x], 3, name) }
    }

    func testDictionaryLookupFallsBackAcrossForms() {
        let fence: OperatorFlags = [.stretchy, .symmetric, .fence]
        XCTAssertEqual(OperatorDictionary.entry("(", form: .prefix).flags, fence)
        XCTAssertEqual(OperatorDictionary.entry("(", form: .infix).flags, fence, "only a prefix entry: used for every form")
        XCTAssertEqual(OperatorDictionary.entry(")", form: .prefix).flags, fence)
        XCTAssertEqual(OperatorDictionary.entry("+", form: .prefix), .init(lspace: 0, rspace: 0, flags: []))
        XCTAssertEqual(OperatorDictionary.entry("+", form: .infix), .init(lspace: 4, rspace: 4, flags: [], breakClass: .additive))
        XCTAssertEqual(OperatorDictionary.entry("+", form: .postfix), .init(lspace: 4, rspace: 4, flags: [], breakClass: .additive), "infix before prefix")
        XCTAssertEqual(OperatorDictionary.entry("!", form: .infix), .init(lspace: 0, rspace: 0, flags: []))
        XCTAssertEqual(OperatorDictionary.entry("∑", form: .infix).flags, [.largeop, .movablelimits, .symmetric])
        XCTAssertEqual(OperatorDictionary.entry("∫", form: .prefix).flags, [.largeop, .symmetric])
        XCTAssertEqual(OperatorDictionary.entry(",", form: .infix).flags, .separator)
        XCTAssertEqual(OperatorDictionary.entry("^", form: .infix).flags, [.accent, .stretchy])
        XCTAssertEqual(OperatorDictionary.entry("nonsense", form: .infix), OperatorDictionary.unknown)
        for form in [OperatorForm.prefix, .infix, .postfix] { XCTAssertEqual(OperatorDictionary.entry("|", form: form).flags, fence) }
    }

    func testOpeningAndClosingFencesPair() {
        let pairs = zip("([{⟨⟦⟪⟬⟮⦃⦅⦇⦉⦋⦍⦏⦑⦓⦕⦗⌈⌊〈❲⁅".unicodeScalars, ")]}⟩⟧⟫⟭⟯⦄⦆⦈⦊⦌⦎⦐⦒⦔⦖⦘⌉⌋〉❳⁆".unicodeScalars)
        for (open, close) in pairs {
            XCTAssertTrue(OperatorDictionary.entry(String(open), form: .prefix).flags.contains(.fence), "\(open)")
            XCTAssertTrue(OperatorDictionary.entry(String(close), form: .postfix).flags.contains(.fence), "\(close)")
            XCTAssertFalse(OperatorDictionary.isHorizontal(String(open)))
        }
    }

    func testHorizontalOperators() {
        for horizontal in ["→", "←", "↔", "⇒", "⟶", "‾", "¯", "_", "^", "~", "⏞", "⏟", "\u{0302}", "\u{20D7}"] {
            XCTAssertTrue(OperatorDictionary.isHorizontal(horizontal), horizontal)
        }
        for vertical in ["↑", "↓", "↕", "(", "|", "∑", "∫", "+", "→→", ""] { XCTAssertFalse(OperatorDictionary.isHorizontal(vertical), vertical) }
    }

    // MARK: Form

    func testFormComesFromThePositionInTheRow() throws {
        try assertSpacing([mo("+"), a], 0, "a leading + is a sign")
        try assertSpacing([mo("−"), a], 0)
        try assertSpacing([mo("±"), a], 0)
        try assertSpacing([a, mo("!")], 0, "a trailing ! is postfix")
        try assertSpacing([mo("¬"), a], 0)
        try assertSpacing([mo("|"), a, mo("|")], 0, "bars as fences")
        // Space-like children do not count: the minus is still first, the ! still last.
        let space = MathMLNode(name: "mspace", attributes: ["width": "0"]), text = MathMLNode(name: "mtext")
        try assertSpacing([space, mo("−"), a], 0, "space-like before a sign")
        try assertSpacing([a, mo("!"), text], 0, "space-like after a postfix operator")
    }

    func testAnExplicitFormOverridesThePosition() throws {
        try assertSpacing([a, mo("−", ["form": "prefix"]), b], 0, "an infix-position minus marked prefix")
        try assertSpacing([a, mo("+", ["form": " PREFIX "]), b], 0, "the attribute is trimmed and case-insensitive")
        try assertSpacing([a, mo("−", ["form": "bogus"]), b], 8, "an invalid form is ignored")
    }

    func testAnExplicitInfixFormKeepsItsSpacingAtTheStartOfARow() throws {
        // MathML 3, 3.2.5.7: the form attribute, not the position, selects the dictionary entry.
        try assertSpacing([mo("+", ["form": "infix"]), a], 8, "+a with form=infix")
        try assertSpacing([a, mo("="), mo("−", ["form": "infix"]), b], 18, "a = −b with the minus marked infix")
        // It is still an operator to what follows it.
        try assertSpacing([a, mo("+", ["form": "infix"]), mo("−"), b], 8, "a sign after an operator marked infix")
    }

    // MARK: TeX's rule 5: binary operators that are unary

    func testBinaryOperatorsAreUnaryWhereTeXSaysSo() throws {
        let three = mn("3")
        let cases: [([MathMLNode], CGFloat, String)] = [
            ([x, mo("="), mo("−"), three], 10, "x = −3"),
            ([mo("("), mo("−"), three, mo("+"), x, mo(")")], 8, "(−3 + x)"),
            ([a, mo(","), mo("−"), b], 3, "a, −b"),
            ([a, mo("+"), mo("−"), b], 8, "a + −b"),
            ([a, mo("×"), mo("−"), b], 8, "a × −b"),
            ([x, mo("→"), mo("−"), mi("∞")], 10, "x → −∞"),
            ([a, mo("−")], 0, "a trailing minus"),
            ([mo("×"), a], 0, "a leading ×"),
            ([mo("∑"), mo("−"), x], 6, "∑ −x"),
            // And where it stays binary.
            ([a, mo("−"), b], 8, "a − b"),
            ([mn("2"), mo("−"), three], 8, "2 − 3"),
            ([mo("("), a, mo(")"), mo("−"), b], 8, "(a) − b"),
            ([mi("n"), mo("!"), mo("−"), mn("1")], 8, "n! − 1"),
            ([a, mo("…"), mo("+"), b], 8, "a … + b"),
        ]
        for (children, expected, label) in cases { try assertSpacing(children, expected, label) }
    }

    // MARK: lspace and rspace

    func testExplicitSpacingReplacesTheDictionarys() throws {
        try assertSpacing([a, mo("+", ["lspace": "0", "rspace": "0"]), b], 0)
        try assertSpacing([a, mo("+", ["lspace": "1em", "rspace": "0.5em"]), b], 27)
        try assertSpacing([a, mo("+", ["lspace": "thickmathspace", "rspace": "negativethinmathspace"]), b], 2)
        try assertSpacing([a, mo("+", ["lspace": "0"]), b], 4, "the other side keeps the dictionary's")
        try assertSpacing([a, mo("+", ["rspace": "9px"]), b], 4 + 9 * 18 / em)
        try assertSpacing([a, mo("(", ["lspace": "6px", "rspace": "6px"]), b], 12 * 18 / em, "a fence given spacing")
        try assertSpacing([a, mo("+", ["lspace": "bogus"]), b], 8, "an invalid length is ignored")
        // An operator with its own spacing is no longer a candidate for a unary sign.
        try assertSpacing([a, mo("="), mo("−", ["lspace": "1em"]), b], 10 + 18 + 4)
    }

    /// An operator with nothing beside it, in `math`, a table cell, a radicand or a fraction's
    /// part, has no row around it to space it. It is not padded by the dictionary there, as TeX
    /// sets a lone atom (`MathMLLayoutTests.testOperatorBetweenTextOperandsKeepsItsSpacing`),
    /// but a space its author wrote on it is the author's to have.
    func testAnOperatorAloneKeepsTheSpaceItsAuthorGaveIt() throws {
        let bare = try innerBox("<mo>=</mo>").width
        func width(_ attributes: String, in wrap: (String) -> String = { $0 }) throws -> CGFloat { try innerBox(wrap("<mo \(attributes)>=</mo>")).width }
        XCTAssertEqual(try width("lspace='1em' rspace='1em'"), bare + 2 * em, accuracy: 0.01)
        XCTAssertEqual(try width("lspace='1em'"), bare + em, accuracy: 0.01, "one side: the other has none of the dictionary's")
        XCTAssertEqual(try width("rspace='0.5em'"), bare + em / 2, accuracy: 0.01)
        XCTAssertEqual(try width("lspace='0' rspace='0'"), bare, accuracy: 0.01)
        XCTAssertEqual(try width("lspace='bogus' rspace=''"), bare, accuracy: 0.01, "an invalid length is no space of the author's")
        XCTAssertEqual(try width("lspace='-0.25em'"), bare - em / 4, accuracy: 0.01)
        // Wherever a row lays it out, by how much each adds over the same with no space.
        let wraps: [(String, CGFloat, (String) -> String)] = [
            ("mrow", em, { "<mrow>\($0)</mrow>" }), ("mtd", em, { "<mtable><mtr><mtd>\($0)</mtd></mtr></mtable>" }), ("msqrt", em, { "<msqrt>\($0)</msqrt>" }),
            ("menclose", em, { "<menclose notation='box'>\($0)</menclose>" }), ("mstyle", em, { "<mstyle mathcolor='red'>\($0)</mstyle>" }),
            ("a numerator", constant(\.scriptPercentScaleDown, size: 1) / 100 * em, { "<mfrac>\($0)<mi>b</mi></mfrac>" }),
        ]
        for (name, unit, wrap) in wraps {
            XCTAssertEqual(try width("lspace='1em' rspace='1em'", in: wrap) - (try width("lspace='0' rspace='0'", in: wrap)), 2 * unit, accuracy: 0.01, name)
            XCTAssertEqual(try width("", in: wrap), try width("lspace='0' rspace='0'", in: wrap), accuracy: 0.01, "\(name): none of the dictionary's")
        }
        // Once: a row around it hands the space up, and the row that has neighbours applies it.
        let between = try innerBox("<mi>a</mi><mo lspace='1em' rspace='1em'>=</mo><mi>b</mi>").width
        XCTAssertEqual(try innerBox("<mi>a</mi><mrow><mo lspace='1em' rspace='1em'>=</mo></mrow><mi>b</mi>").width, between, accuracy: 0.01)
        XCTAssertEqual(try innerBox("<mrow><mrow><mo lspace='1em' rspace='1em'>=</mo></mrow></mrow>").width, bare + 2 * em, accuracy: 0.01)
        // An embellished operator alone, likewise.
        XCTAssertEqual(try innerBox("<msub><mo lspace='1em'>=</mo><mn>2</mn></msub>").width, try innerBox("<msub><mo lspace='0'>=</mo><mn>2</mn></msub>").width + em, accuracy: 0.01)
    }

    func testSpacingIsDroppedInScriptsExceptForLargeOperators() throws {
        func script(_ children: [MathMLNode]) -> MathMLNode {
            math(MathMLNode(name: "mstyle", attributes: ["scriptlevel": "1"], children: children))
        }
        let scriptEm = 0.7 * em
        for op in ["+", "=", ",", "foo"] {
            XCTAssertEqual(try spacing([a, mo(op), b], wrap: script, unit: scriptEm), 0, accuracy: 0.05, "script-level \(op)")
        }
        XCTAssertEqual(try spacing([a, mo("∑"), b], wrap: script, unit: scriptEm), 6, accuracy: 0.05, "a large operator keeps its space")
        XCTAssertEqual(try spacing([a, mo("+", ["lspace": "1em"]), b], wrap: script, unit: scriptEm), 18, accuracy: 0.05,
                       "explicit spacing is kept, in the script's own em")
        // In a superscript proper.
        let exponent = try innerBox("<msup><mi>x</mi><mrow><mi>a</mi><mo>+</mo><mi>b</mi></mrow></msup>").width
        let unspaced = try innerBox("<msup><mi>x</mi><mrow><mi>a</mi><mo lspace=\"0\" rspace=\"0\">+</mo><mi>b</mi></mrow></msup>").width
        XCTAssertEqual(exponent, unspaced, accuracy: 0.01)
    }

    // MARK: Invisible operators and substitutions

    func testInvisibleOperatorsTakeNoRoom() throws {
        for invisible in ["\u{2061}", "\u{2062}", "\u{2063}", "\u{2064}", ""] {
            let box = try innerBox(math(mo(invisible)))
            XCTAssertEqual(box.width, 0, "U+\(invisible.unicodeScalars.first.map { String($0.value, radix: 16) } ?? "empty")")
            XCTAssertNil(box.inkBounds)
        }
        try assertSpacing([x, mo("\u{2062}"), mi("y")], 0, "invisible times")
        try assertSpacing([mn("1"), mo("\u{2064}"), MathMLNode(name: "mfrac", children: [mn("1"), mn("2")])], 0, "invisible plus")
        try assertSpacing([a, mo("\u{2063}"), b], 0, "invisible separator")
    }

    func testFunctionApplicationPutsAThinSpaceBeforeABareArgument() throws {
        let sin = mi("sin"), apply = mo("\u{2061}")
        try assertSpacing([sin, apply, x], 3, "sin x")
        try assertSpacing([sin, apply, mo("("), x, mo(")")], 0, "sin(x)")
        try assertSpacing([sin, apply, MathMLNode(name: "mfenced", children: [x])], 0, "sin(x) as mfenced")
        try assertSpacing([sin, apply, MathMLNode(name: "mrow", children: [mo("("), x, mo(")")])], 0, "sin(x) in an mrow")
        try assertSpacing([sin, apply, MathMLNode(name: "mrow", children: [x])], 3)
        func script(_ children: [MathMLNode]) -> MathMLNode {
            math(MathMLNode(name: "mstyle", attributes: ["scriptlevel": "1"], children: children))
        }
        XCTAssertEqual(try spacing([sin, apply, x], wrap: script), 0, accuracy: 0.05, "no thin space in a script")
    }

    func testHyphenAndApostropheDrawAsMinusAndPrime() throws {
        for (typed, drawn) in [("-", "−"), ("'", "′")] {
            let first = try innerBox(math(mo(typed))), second = try innerBox(math(mo(drawn)))
            XCTAssertEqual(first.width, second.width, accuracy: 0.001, typed)
            XCTAssertEqual(first.inkBounds, second.inkBounds, typed)
        }
        // Only an operator that is exactly a hyphen: a number keeps its hyphen.
        XCTAssertNotEqual(try innerBox(math(mn("-"))).inkBounds, try innerBox(math(mo("-"))).inkBounds)
        XCTAssertNotEqual(try innerBox(math(mo("--"))).width, try innerBox(math(mo("−−"))).width)
    }

    // MARK: Vertical stretching

    /// Black fences around red content: the fences' ink and the content's.
    private func fenced(_ open: String, _ close: String, content: String, attributes: String = "", display: Bool = true)
        throws -> (fences: CGRect, content: CGRect) {
        let found = try inks("<mo \(attributes)>\(open)</mo><mrow mathcolor=\"red\">\(content)</mrow><mo \(attributes)>\(close)</mo>",
                             display: display)
        return (try XCTUnwrap(found[.black]), try XCTUnwrap(found[.red]))
    }

    private let tall = "<mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mfrac><mi>c</mi><mi>d</mi></mfrac></mfrac>"

    func testFencesCoverTheirContentCentredOnTheAxis() throws {
        let axis = constant(\.axisHeight)
        for (open, close) in [("(", ")"), ("[", "]"), ("{", "}"), ("|", "|"), ("‖", "‖"), ("⌈", "⌉"), ("⌊", "⌋"), ("⟨", "⟩")] {
            let (fences, content) = try fenced(open, close, content: tall)
            // The symmetric extent to cover, and TeX's allowance: 90.1% of it, or 5pt (em/2) short.
            let extent = 2 * max(content.maxY - axis, axis - content.minY)
            XCTAssertGreaterThanOrEqual(fences.height, min(extent * 0.901, extent - em / 2) - 1, "\(open) \(close) height")
            XCTAssertLessThanOrEqual(fences.height, extent * 1.25 + 2, "\(open) \(close) is not oversized")
            XCTAssertEqual(fences.midY, axis, accuracy: 1, "\(open) \(close) centre")
            XCTAssertLessThan(fences.minX, content.minX, "\(open) is left of the content")
            XCTAssertGreaterThan(fences.maxX, content.maxX, "\(close) is right of the content")
        }
    }

    func testBothFencesOfAPairAreTheSameSize() throws {
        // Even when the tall part is nearer one of them.
        for body in ["<mo mathcolor=\"red\">(</mo>\(tall)<mi>x</mi><mo mathcolor=\"blue\">)</mo>",
                     "<mo mathcolor=\"red\">[</mo><mi>x</mi>\(tall)<mo mathcolor=\"blue\">]</mo>"] {
            let found = try inks(body, display: true)
            let open = try XCTUnwrap(found[.red]), close = try XCTUnwrap(found[.blue])
            XCTAssertEqual(open.height, close.height, accuracy: 0.5, body)
            XCTAssertEqual(open.midY, close.midY, accuracy: 0.5, body)
        }
    }

    func testSmallContentKeepsOrdinaryFences() throws {
        // TeX's delimiter shortfall: f(x) and (x + y) keep the font's plain parentheses.
        let natural = try XCTUnwrap(try innerBox(math(mo("("))).inkBounds)
        for content in ["<mi>x</mi>", "<mi>x</mi><mo>+</mo><mi>y</mi>", "<mi>f</mi>", "<mi>a</mi><mi>b</mi><mo>−</mo><mn>1</mn>"] {
            let (fences, _) = try fenced("(", ")", content: content)
            XCTAssertEqual(fences.height, natural.height, accuracy: 0.5, content)
        }
    }

    func testStretchyFalseKeepsTheNaturalSize() throws {
        let natural = try XCTUnwrap(try innerBox(math(mo("("))).inkBounds)
        let (fences, content) = try fenced("(", ")", content: tall, attributes: "stretchy=\"false\"")
        XCTAssertEqual(fences.height, natural.height, accuracy: 0.5)
        XCTAssertGreaterThan(content.height, 2 * fences.height)
    }

    func testAsymmetricStretchCoversOnlyTheContent() throws {
        // Content that only rises: a symmetric fence grows as far below the axis as above it.
        let rising = "<mspace width=\"1em\" height=\"3em\" mathbackground=\"red\"/>"
        let (symmetric, _) = try fenced("(", ")", content: rising)
        let (asymmetric, content) = try fenced("(", ")", content: rising, attributes: "symmetric=\"false\"")
        XCTAssertLessThan(symmetric.minY, -1.5 * em, "symmetric: mirrored below the axis")
        XCTAssertGreaterThan(asymmetric.minY, -0.5 * em, "asymmetric: stops near the baseline")
        XCTAssertGreaterThanOrEqual(asymmetric.maxY, content.maxY - em / 2 - 0.5)
        XCTAssertLessThan(asymmetric.height, symmetric.height * 0.75)
    }

    func testMinsizeAndMaxsizeBoundTheStretch() throws {
        let natural = try XCTUnwrap(try innerBox(math(mo("("))).inkBounds).height
        let free = try fenced("(", ")", content: tall).fences.height
        // maxsize
        XCTAssertEqual(try fenced("(", ")", content: tall, attributes: "maxsize=\"1\"").fences.height, natural, accuracy: 0.5,
                       "maxsize=1 is the natural size")
        let capped = try fenced("(", ")", content: tall, attributes: "maxsize=\"2em\"").fences.height
        XCTAssertLessThan(capped, free - 2)
        XCTAssertLessThanOrEqual(capped, 2.6 * em, "the nearest size variant to 2em")
        XCTAssertEqual(try fenced("(", ")", content: tall, attributes: "maxsize=\"infinity\"").fences.height, free, accuracy: 0.5)
        // minsize
        let small = "<mi>x</mi>"
        XCTAssertGreaterThanOrEqual(try fenced("(", ")", content: small, attributes: "minsize=\"3em\"").fences.height, 3 * em - 1)
        XCTAssertGreaterThanOrEqual(try fenced("(", ")", content: small, attributes: "minsize=\"2\"").fences.height, 2 * natural - 1,
                                    "a bare number is a multiple of the natural size")
        XCTAssertGreaterThanOrEqual(try fenced("(", ")", content: small, attributes: "minsize=\"300%\"").fences.height, 3 * natural - 1)
        // minsize wins over a maxsize less than it: MathML Core 3.2.4.3 takes such a maxsize to be the minsize.
        XCTAssertGreaterThanOrEqual(try fenced("(", ")", content: tall, attributes: "minsize=\"8em\" maxsize=\"2em\"").fences.height, 8 * em - 1)
        XCTAssertGreaterThanOrEqual(try fenced("(", ")", content: small, attributes: "minsize=\"8em\" maxsize=\"2em\"").fences.height, 8 * em - 1)
        // A negative minsize is zero: it bounds nothing, and is no minsize for a maxsize to be less than.
        XCTAssertEqual(try fenced("(", ")", content: tall, attributes: "minsize=\"-10em\"").fences.height, free, accuracy: 0.5)
        XCTAssertEqual(try fenced("(", ")", content: tall, attributes: "minsize=\"-10em\" maxsize=\"2em\"").fences.height, capped, accuracy: 0.5)
        XCTAssertEqual(try fenced("(", ")", content: tall, attributes: "minsize=\"-10em\" maxsize=\"-20em\"").fences.height, natural, accuracy: 0.5)
    }

    func testOperatorsWithNothingToCoverKeepTheirSize() throws {
        let natural = try XCTUnwrap(try innerBox(math(mo("("))).inkBounds)
        XCTAssertEqual(try innerBox(math(mo("("), mo(")"))).height, natural.height, accuracy: 0.01, "a row of only stretchy operators")
        XCTAssertEqual(try innerBox("<mrow><mo>(</mo></mrow>", display: true).height, natural.height, accuracy: 0.01)
        XCTAssertEqual(try innerBox("<mo>(</mo><mspace width=\"1em\"/><mo>)</mo>").height, natural.height, accuracy: 0.01)
    }

    func testVerticalArrowsStretchAndHorizontalOnesDoNot() throws {
        let column = "<mrow mathcolor=\"red\"><mspace width=\"1em\" height=\"3em\" depth=\"2em\" mathbackground=\"red\"/><mi>x</mi></mrow>"
        for arrow in ["↑", "↓", "↕", "⇑", "⇓"] {
            let ink = try XCTUnwrap(try inks("<mo>\(arrow)</mo>\(column)")[.black])
            XCTAssertGreaterThanOrEqual(ink.height, 5 * em * 0.9 - em / 2, arrow)
            XCTAssertGreaterThanOrEqual(ink.maxY, 3 * em - em / 2 - 1, "\(arrow) covers the ascent, not a symmetric extent")
            XCTAssertLessThanOrEqual(ink.minY, -2 * em + em / 2 + 1, arrow)
        }
        for arrow in ["→", "⇒", "↔"] {
            let natural = try XCTUnwrap(try innerBox(math(mo(arrow))).inkBounds)
            let ink = try XCTUnwrap(try inks("<mi>a</mi><mo>\(arrow)</mo>\(column)")[.black])
            XCTAssertLessThan(ink.height, natural.height + em, arrow)
        }
        // Stretchiness can be given and taken away.
        let slash = try XCTUnwrap(try inks("<mo stretchy=\"true\">/</mo>\(column)")[.black])
        XCTAssertGreaterThan(slash.height, 3 * em)
        let plain = try XCTUnwrap(try inks("<mo>/</mo>\(column)")[.black])
        XCTAssertLessThan(plain.height, 1.5 * em)
        let integral = try XCTUnwrap(try inks("<mo>∫</mo>\(column)")[.black])
        XCTAssertLessThan(integral.height, 2 * em, "an integral is a large operator, not a stretchy one")
    }

    /// MathML 3, 3.2.5.8.2 and MathML Core 3.3.1.2: a stretchy operator covers the other
    /// children of its row, and a strut made of `mspace` is one of them.
    func testAStretchyOperatorCoversASpaceLikeStrut() throws {
        let strut = "<mspace width=\"1em\" height=\"3em\" depth=\"2em\"/>"
        for (op, body) in [("(", "<mo>(</mo>\(strut)"), (")", "\(strut)<mo>)</mo>"), ("|", "<mrow><mo>|</mo>\(strut)</mrow>"),
                           ("↑", "<mo>↑</mo>\(strut)"), ("[", "<mtext>&#xA0;</mtext><mo>[</mo>\(strut)")] {
            let ink = try XCTUnwrap(try inks(body)[.black], op)
            XCTAssertGreaterThanOrEqual(ink.height, 4 * em, "\(op) beside a 3em + 2em strut")
        }
        // The same strut already works once the row has a second operator or an identifier.
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(try inks("<mo>(</mo>\(strut)<mo>)</mo>")[.black]).height, 4 * em)
        // A strut wrapped in what is itself space-like, and an operator with a script of its own.
        for body in ["<mo>|</mo><mpadded>\(strut)</mpadded>", "<mphantom>\(strut)</mphantom><mo>|</mo>", "<mstyle><mo>|</mo>\(strut)</mstyle>",
                     "<msub><mo>|</mo><mn mathcolor=\"red\">0</mn></msub>\(strut)", "<mrow><mrow><mo>|</mo></mrow>\(strut)</mrow>"] {
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(try inks(body)[.black], body).height, 4 * em, body)
        }
    }

    /// A row whose one child in flow is an operator is an operator to the row around it, which
    /// has it cover what stands beside it there. Its operator covers that and its own neighbours.
    func testTheOperatorOfARowCoversWhatIsBesideItAndBesideTheRow() throws {
        let strut = "<mspace width=\"1em\" height=\"3em\" depth=\"2em\"/>", short = "<mspace width=\"1em\" height=\"1em\"/>"
        let alone = try XCTUnwrap(try inks("<mo>|</mo>\(strut)")[.black])
        for body in ["<mrow><mo>|</mo>\(short)</mrow>\(strut)", "<mrow><mo>|</mo>\(strut)</mrow>\(short)", "<mrow><mo>|</mo>\(strut)</mrow>\(strut)",
                     "<mrow><mo>|</mo>\(short)</mrow><mfrac mathcolor=\"red\"><mi>a</mi><mi>b</mi></mfrac>\(strut)"] {
            let ink = try XCTUnwrap(try inks(body)[.black], body)
            XCTAssertEqual(ink.height, alone.height, accuracy: 0.5, body)
            XCTAssertEqual(ink.midY, alone.midY, accuracy: 0.5, body)
        }
        // And no more than those: beside nothing taller, the short strut is all there is to cover.
        let low = try XCTUnwrap(try inks("<mo>|</mo>\(short)")[.black])
        XCTAssertLessThan(low.height, alone.height / 2)
        XCTAssertEqual(try XCTUnwrap(try inks("<mrow><mo>|</mo>\(short)</mrow><mi mathcolor=\"red\">x</mi>")[.black]).height, low.height, accuracy: 0.5)
    }

    /// MathML Core 3.3.1.2 and 3.2.4.3, checked by WPT operators/mo-minsize-maxsize-001: stretchy
    /// operators with nothing to cover stretch to a size of zero, which a `minsize` raises, half
    /// each side of the axis. MathML 3 (3.2.5.8.4) would leave them at their natural size, and
    /// with it TeX's `\big(`, which converters write as an `mo` whose two sizes are both 1.2em.
    func testMinsizeSizesAnOperatorWithNothingToCover() throws {
        let axis = constant(\.axisHeight)
        let natural = try XCTUnwrap(try innerBox(math(mo("("))).inkBounds)
        func ink(_ body: String) throws -> CGRect { try XCTUnwrap(try inks(body)[.red], body) }
        let sized = "<mo mathcolor=\"red\" minsize=\"3em\">(</mo>"
        let beside = try ink("\(sized)<mi>x</mi>")
        XCTAssertGreaterThanOrEqual(beside.height, 3 * em - 1)
        for body in [sized, "<mrow>\(sized)</mrow>", "<mrow><mstyle>\(sized)</mstyle></mrow>", "\(sized)<mo mathcolor=\"red\" minsize=\"3em\">)</mo>",
                     "\(sized)<mspace width=\"1em\"/>", "<mtext>&#xA0;</mtext>\(sized)", "<msqrt>\(sized)</msqrt>", "<menclose notation=\"box\">\(sized)</menclose>",
                     "<mtable><mtr><mtd>\(sized)</mtd></mtr></mtable>", "<msup>\(sized)<mn>2</mn></msup>"] {
            let found = try ink(body)
            XCTAssertEqual(found.height, beside.height, accuracy: 0.5, "\(body): as tall as beside an identifier")
            XCTAssertEqual(found.midY, axis, accuracy: 1, "\(body): half above the axis and half below")
        }
        // An operator that is not symmetric has nothing but the axis to be centred on either.
        let lopsided = "<mo mathcolor=\"red\" minsize=\"3em\" symmetric=\"false\">|</mo>"
        for body in [lopsided, "<mo mathcolor=\"red\" minsize=\"3em\">↑</mo>", "\(lopsided)<mspace width=\"1em\"/>", "\(lopsided)<mspace width=\"1em\"/>\(lopsided)"] {
            let found = try ink(body)
            XCTAssertGreaterThanOrEqual(found.height, 3 * em - 1, body)
            XCTAssertEqual(found.midY, axis, accuracy: 1, body)
        }
        // A bare number or a percentage is still of the natural size, and maxsize still bounds.
        XCTAssertGreaterThanOrEqual(try ink("<mo mathcolor=\"red\" minsize=\"2\">(</mo>").height, 2 * natural.height - 1)
        XCTAssertGreaterThanOrEqual(try ink("<mo mathcolor=\"red\" minsize=\"300%\">(</mo>").height, 3 * natural.height - 1)
        XCTAssertEqual(try ink("<mo mathcolor=\"red\" maxsize=\"3em\">(</mo>").height, natural.height, accuracy: 0.5, "a maxsize alone asks for nothing")
        // TeX's \big( and \Bigg(: the same alone as in a row with something in it.
        for size in ["1.2em", "3em"] {
            let big = "<mo mathcolor=\"red\" minsize=\"\(size)\" maxsize=\"\(size)\">(</mo>"
            let alone = try ink(big), inRow = try ink("<mi>f</mi>\(big)<mi>x</mi>")
            XCTAssertGreaterThan(alone.height, natural.height + 2, size)
            XCTAssertEqual(alone.height, inRow.height, accuracy: 0.5, size)
            XCTAssertEqual(alone.midY, inRow.midY, accuracy: 0.5, size)
        }
        // Only a row gives an operator a size to stretch to: a denominator has none, and no minsize.
        XCTAssertEqual(try ink("<mfrac><mi>x</mi>\(sized)</mfrac>").height, try ink("<mfrac><mi>x</mi><mo mathcolor=\"red\">(</mo></mfrac>").height, accuracy: 0.5)
    }

    func testAnEmbellishedFenceStretchesWithItsScript() throws {
        // (…)² written with the closing parenthesis as the base of the power.
        let found = try inks("<mo mathcolor=\"lime\">(</mo>\(tall)<msup><mo mathcolor=\"red\">)</mo><mn mathcolor=\"blue\">2</mn></msup>",
                             display: true)
        let open = try XCTUnwrap(found[.green]), close = try XCTUnwrap(found[.red]), power = try XCTUnwrap(found[.blue])
        XCTAssertGreaterThan(close.height, 2.5 * em)
        XCTAssertEqual(close.height, open.height, accuracy: 1)
        XCTAssertEqual(close.midY, open.midY, accuracy: 1)
        XCTAssertGreaterThan(power.minY, close.midY, "the exponent sits at the top of the stretched fence")
        XCTAssertGreaterThanOrEqual(power.minX, close.maxX - 2)
    }

    func testStretchedFencesGrowWithTheirContent() throws {
        var last: CGFloat = 0
        for rows in [1, 2, 4, 8, 16] {
            let cells = (1...rows).map { "<mtr><mtd><mn>\($0)</mn></mtd></mtr>" }.joined()
            let (fences, content) = try fenced("[", "]", content: "<mtable>\(cells)</mtable>", display: false)
            XCTAssertGreaterThan(fences.height, last, "\(rows) rows")
            XCTAssertGreaterThanOrEqual(fences.height, content.height - em / 2 - 1, "\(rows) rows")
            XCTAssertLessThanOrEqual(fences.height, content.height + 2 * em, "\(rows) rows")
            last = fences.height
        }
    }

    // MARK: Large operators

    func testLargeOperatorsGrowInDisplayStyleAndCentreOnTheAxis() throws {
        let axis = constant(\.axisHeight), minimum = constant(\.displayOperatorMinHeight)
        for op in ["∑", "∏", "∐", "⋃", "⋂", "∫", "∬", "∮", "⨁", "⨂"] {
            let text = try XCTUnwrap(Rendering(try typeset("<mo>\(op)</mo>")).bounds())
            let display = try XCTUnwrap(Rendering(try typeset("<mo>\(op)</mo>", display: true)).bounds())
            XCTAssertGreaterThan(display.height, text.height * 1.25, op)
            if "∫∬∮".contains(op) { XCTAssertGreaterThanOrEqual(display.height, minimum - 1, "\(op) reaches DisplayOperatorMinHeight") }
            XCTAssertEqual(display.midY, axis, accuracy: 1, "\(op) in display style")
            XCTAssertEqual(text.midY, axis, accuracy: 1, "\(op) in text style")
        }
    }

    func testLargeopAndDisplayStyleAttributes() throws {
        let text = try typeset("<mo>∑</mo>"), display = try typeset("<mo>∑</mo>", display: true)
        XCTAssertEqual(height(try typeset("<mo largeop=\"false\">∑</mo>", display: true)), height(text), accuracy: 0.5)
        XCTAssertEqual(height(try typeset("<mstyle displaystyle=\"true\"><mo>∑</mo></mstyle>")), height(display), accuracy: 0.01)
        XCTAssertEqual(height(try typeset("<mstyle displaystyle=\"false\"><mo>∑</mo></mstyle>", display: true)), height(text), accuracy: 0.01)
        XCTAssertEqual(height(try MathLayout(mathML("<mo>∑</mo>", attributes: "displaystyle=\"true\""), style: MathStyle(fontSize: em, color: black))),
                       height(display), accuracy: 0.01, "displaystyle on the math element")
        // An ordinary operator made large grows when the font has a larger form of it.
        XCTAssertGreaterThanOrEqual(height(try typeset("<mo largeop=\"true\">⊕</mo>", display: true)), height(try typeset("<mo>⊕</mo>", display: true)))
    }

    func testOperatorAttributesOverrideTheDictionary() {
        let engine = LayoutEngine(fontName: nil)
        XCTAssertEqual(engine.operatorFlags(mo("("), form: .prefix), [.stretchy, .symmetric, .fence])
        XCTAssertEqual(engine.operatorFlags(mo("(", ["stretchy": "false", "symmetric": "false"]), form: .prefix), [.fence])
        XCTAssertEqual(engine.operatorFlags(mo("∑", ["movablelimits": "false", "largeop": "false"]), form: .prefix), [.symmetric])
        XCTAssertEqual(engine.operatorFlags(mo("x", ["largeop": "true", "movablelimits": "true", "accent": "true", "separator": "true",
                                                     "fence": "true", "stretchy": "true", "symmetric": "true"]), form: .infix),
                       [.stretchy, .symmetric, .fence, .separator, .largeop, .movablelimits, .accent])
        XCTAssertEqual(engine.operatorFlags(mo("(", ["stretchy": "maybe"]), form: .prefix), [.stretchy, .symmetric, .fence], "an invalid boolean is ignored")
    }

    func testEmbellishedCoreAndSpaceLike() {
        let engine = LayoutEngine(fontName: nil)
        let plus = mo("+"), space = MathMLNode(name: "mspace"), text = MathMLNode(name: "mtext", text: "t")
        func element(_ name: String, _ children: MathMLNode...) -> MathMLNode { MathMLNode(name: name, children: children) }
        XCTAssertEqual(engine.embellishedCore(plus), plus)
        for name in ["msub", "msup", "msubsup", "munder", "mover", "munderover", "mmultiscripts", "mfrac", "semantics", "maction"] {
            XCTAssertEqual(engine.embellishedCore(element(name, plus, a, b)), plus, name)
            XCTAssertNil(engine.embellishedCore(element(name, a, plus, plus)), "\(name): only the first child counts")
        }
        for name in ["mrow", "mstyle", "mphantom", "mpadded"] {
            XCTAssertEqual(engine.embellishedCore(element(name, space, plus, text)), plus, "\(name) with space-like siblings")
            XCTAssertNil(engine.embellishedCore(element(name, plus, a)), name)
            XCTAssertNil(engine.embellishedCore(element(name)), name)
            XCTAssertTrue(engine.isSpaceLike(element(name, space, text)), name)
            XCTAssertFalse(engine.isSpaceLike(element(name, space, a)), name)
        }
        XCTAssertEqual(engine.embellishedCore(element("msup", element("mrow", element("munder", plus, a)), b)), plus, "nested")
        for name in ["mi", "mn", "msqrt", "mroot", "mtable", "menclose", "mfenced"] { XCTAssertNil(engine.embellishedCore(element(name, plus)), name) }
        XCTAssertTrue(engine.isSpaceLike(space)); XCTAssertTrue(engine.isSpaceLike(text))
        XCTAssertTrue(engine.isSpaceLike(element("maction", space, a)), "an maction is as space-like as its first child")
        for node in [a, plus, element("mfrac", space, space), element("msqrt", space)] { XCTAssertFalse(engine.isSpaceLike(node), node.name) }
    }

    /// An `maction` stands for the child `selection` names and a `semantics` for its first child
    /// that is not an annotation: the child that is drawn. What looks ahead of layout takes the
    /// same child, or an operator that is drawn would not be spaced or stretched as one.
    func testAnActionAndSemanticsAreWhatTheChildThatIsDrawnIs() throws {
        let engine = LayoutEngine(fontName: nil)
        let plus = mo("+"), space = MathMLNode(name: "mspace"), note = MathMLNode(name: "annotation", text: "+")
        func action(_ selection: String?, _ children: MathMLNode...) -> MathMLNode {
            MathMLNode(name: "maction", attributes: selection.map { ["selection": $0] } ?? [:], children: children)
        }
        func semantics(_ children: MathMLNode...) -> MathMLNode { MathMLNode(name: "semantics", children: children) }
        XCTAssertEqual(engine.embellishedCore(action("2", a, plus)), plus)
        XCTAssertNil(engine.embellishedCore(action("2", plus, a)))
        XCTAssertEqual(engine.embellishedCore(action("9", plus, a)), plus, "a selection that names no child is the first")
        XCTAssertEqual(engine.embellishedCore(semantics(note, plus, a)), plus)
        XCTAssertNil(engine.embellishedCore(semantics(note)))
        XCTAssertEqual(engine.embellishedCore(action("2", a, semantics(note, MathMLNode(name: "msup", children: [plus, b])))), plus, "nested")
        XCTAssertTrue(engine.isSpaceLike(action("2", a, space))); XCTAssertFalse(engine.isSpaceLike(action("2", space, a)))
        XCTAssertTrue(engine.isSpaceLike(semantics(note, space, a))); XCTAssertFalse(engine.isSpaceLike(semantics(note)))
        XCTAssertFalse(engine.isSpaceLike(action(nil)))
        // One list of children under two actions that show different ones: neither answer is the list's.
        let shared = [space, a]
        for _ in 1...2 {
            XCTAssertTrue(engine.isSpaceLike(MathMLNode(name: "maction", children: shared)))
            XCTAssertFalse(engine.isSpaceLike(MathMLNode(name: "maction", attributes: ["selection": "2"], children: shared)))
        }
        // Laid out, the operator that is drawn is spaced and stretched as it is when written plainly.
        let tall = "<mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mi>c</mi></mfrac>"
        let plain = try innerBox("<mo>(</mo>\(tall)<mo>)</mo>", display: true)
        for wrapped in ["<maction selection='2'><mi>a</mi><mo>(</mo></maction>", "<semantics><annotation>(</annotation><mo>(</mo></semantics>"] {
            let box = try innerBox("\(wrapped)\(tall)<mo>)</mo>", display: true)
            XCTAssertEqual(box.width, plain.width, accuracy: 0.01, wrapped); XCTAssertEqual(box.ascent, plain.ascent, accuracy: 0.01, wrapped)
            XCTAssertEqual(box.descent, plain.descent, accuracy: 0.01, wrapped)
        }
        try assertSpacing([a, action("2", b, mo("=")), b], 10, "an operator an maction shows keeps its spacing")
    }

    /// What a list of children is found to be is kept by the list, so that no row reads it again.
    /// It is what the list is, not what any element that has it is, and it is the list's alone.
    func testWhatIsKeptOfAListOfChildrenIsTheListsOwn() {
        let engine = LayoutEngine(fontName: nil)
        let plus = mo("+"), space = MathMLNode(name: "mspace"), text = MathMLNode(name: "mtext", text: "t")
        // One list under several elements, asked twice: the second answers are the kept ones.
        let shared = [space, text]
        for pass in 1...2 {
            XCTAssertEqual(engine.spaceLike(MathMLNode(name: "mrow", children: shared)), true, "pass \(pass)")
            XCTAssertEqual(engine.spaceLike(MathMLNode(name: "mphantom", children: shared)), false, "pass \(pass): what a phantom hides says nothing")
            XCTAssertEqual(engine.spaceLike(MathMLNode(name: "maction", children: shared)), false, "pass \(pass): its first child alone")
            XCTAssertNil(engine.spaceLike(MathMLNode(name: "mfrac", children: shared)), "pass \(pass)")
            XCTAssertEqual(engine.spaceLike(MathMLNode(name: "mrow", children: [MathMLNode(name: "mphantom", children: shared), space])), false, "pass \(pass)")
            XCTAssertEqual(engine.spaceLike(MathMLNode(name: "mrow", children: [MathMLNode(name: "mphantom", children: shared), MathMLNode(name: "mstyle", children: shared)])), true,
                           "pass \(pass)")
            XCTAssertNil(engine.embellishedCore(MathMLNode(name: "mrow", children: shared)), "pass \(pass)")
            XCTAssertEqual(engine.embellishedCore(MathMLNode(name: "mrow", children: [MathMLNode(name: "mpadded", children: shared), plus, MathMLNode(name: "mrow", children: shared)])),
                           plus, "pass \(pass)")
        }
        // Lists that come and go, each likely to be given the storage of the one before: every one
        // is what it is itself.
        for index in 0..<600 {
            let children = [[space, plus], [space, text], [space, space], [a, plus]][index % 4]
            let row = MathMLNode(name: "mrow", children: children.map { MathMLNode(name: $0.name, text: $0.text) })
            XCTAssertEqual(engine.spaceLike(row), [nil, true, false, nil][index % 4], "\(index)")
            XCTAssertEqual(engine.embellishedCore(row), index % 4 == 0 ? plus : nil, "\(index)")
        }
        // The look-ahead says what a subtree is however deep it is. Layout is what refuses one too deep.
        let deep = (0..<200).reduce(text) { inner, _ in MathMLNode(name: "mrow", children: [space, inner]) }
        XCTAssertEqual(engine.spaceLike(deep), true)
        XCTAssertNil(engine.spaceLike((0..<200).reduce(a) { inner, _ in MathMLNode(name: "mrow", children: [space, inner]) }))
        XCTAssertThrowsError(try innerBox(math(deep))) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded) }
    }
}
