// Selected wording adapted from MathCAT (MIT) and Speech Rule Engine (Apache-2.0).
// Modified for MathMLLayout; see THIRD_PARTY_NOTICES.md and doc/speech-wording-audit.md.
import Foundation
@testable import MathMLLayout
import XCTest

final class SpeechStructureTests: MathTestCase {
    private func read(_ body: String, _ language: String = "en") throws -> String {
        try node(body).accessibilityDescription(locale: Locale(identifier: language)).text
    }

    func testSideScriptsOnLargeOperatorsReadAsLimitsInEveryLanguage() throws {
        for language in MathReading.languages {
            for op in ["∫", "∮", "∑", "∏"] {
                let scripts = "<msubsup><mstyle><mo>\(op)</mo></mstyle><mn>0</mn><mn>1</mn></msubsup>"
                let limits = "<munderover><mo>\(op)</mo><mn>0</mn><mn>1</mn></munderover>"
                XCTAssertEqual(try read(scripts, language), try read(limits, language))
            }
        }
        XCTAssertEqual(try read("<msubsup><mo largeop='false'>∫</mo><mn>0</mn><mn>1</mn></msubsup>"),
                       "the integral sub 0 to the power of 1")
        XCTAssertEqual(try read("<msubsup><mi>x</mi><mi>i</mi><mrow><mi>n</mi><mo>+</mo><mn>1</mn></mrow></msubsup>"),
                       "x sub i to the power of n plus 1 end power")
    }

    func testUnderAccentsNameTheirPositionAndRespectExplicitFalse() throws {
        for language in MathReading.languages {
            let words = MathReading.vocabularies.first { $0.language == language }!
            for mark in ["_", "¯", "\u{0332}"] {
                XCTAssertEqual(try read("<munder><mi>x</mi><mo>\(mark)</mo></munder>", language), words.accents.underbar.reading(on: "x"))
            }
            XCTAssertEqual(try read("<munder><mi>x</mi><mo>⏟</mo></munder>", language), words.accents.underbrace.reading(on: "x"))
        }
        XCTAssertEqual(try read("<munder accentunder='false'><mi>x</mi><mo>_</mo></munder>"), "x under _")
        XCTAssertEqual(try read("<mover accent='false'><mi>x</mi><mo>^</mo></mover>"), "x over ^")
        XCTAssertEqual(try read("<munderover><mi>x</mi><mo>_</mo><mo>^</mo></munderover>"), "x underbar hat")
        XCTAssertEqual(try read("<munder><mi>x</mi><mo>˙</mo></munder>"), "x under dot")
        XCTAssertEqual(try read("<munder><mi>x</mi><mo accent='false'>_</mo></munder>"), "x under _")
        XCTAssertEqual(try read("<munder accentunder='true'><mi>x</mi><mo accent='false'>_</mo></munder>"), "x underbar")
        XCTAssertEqual(try read("<mover><mi>x</mi><mrow><mo>^</mo><mi>a</mi></mrow></mover>"), "x over ^ a")
    }

    func testRepeatedPrimesAreNeverReadAsAnExponent() throws {
        for language in MathReading.languages {
            let prime = MathReading.vocabularies.first { $0.language == language }!.symbols.prime
            for (mark, count) in [("″", 2), ("′′", 2), ("''", 2), ("‴", 3), ("⁗", 4), ("″″′", 5)] {
                XCTAssertEqual(try read("<msup><mi>f</mi><mo>\(mark)</mo></msup>", language),
                               (["f"] + Array(repeating: prime, count: count)).joined(separator: " "))
            }
        }
        XCTAssertEqual(try read("<msup><mi>f</mi><mo>′+</mo></msup>"), "f to the power of ′+")
    }

    func testFenceSeparatorsFollowMathMLExpansion() throws {
        XCTAssertEqual(try read("<mfenced separators='; +'><mi>a</mi><mi>b</mi><mi>c</mi><mi>d</mi></mfenced>"),
                       "open paren a ; b plus c plus d close paren")
        for separators in ["", " \t \n"] {
            XCTAssertEqual(try read("<mfenced open='' close='' separators='\(separators)'><mi>a</mi><mi>b</mi></mfenced>"), "a b")
        }
        XCTAssertEqual(try read("<mfenced separators='+−'><mi>a</mi></mfenced>"), "open paren a close paren")
    }

    func testIdentifierSymbolsAreLocalizedWithoutTranslatingProseOrAlt() throws {
        for language in MathReading.languages {
            for symbol in ["∞", "∂", "∮", "∇"] {
                XCTAssertEqual(try read("<mi>\(symbol)</mi>", language), try read("<mo>\(symbol)</mo>", language))
            }
            XCTAssertEqual(try read("<mtext>infinity</mtext><mglyph alt='the author’s star'/>", language), "infinity the author’s star")
        }
    }

    func testOrdinalRootsAndFrenchElisionHaveExplicitFallbacks() throws {
        let expected = ["the fourth root of a end root", "racine quatrième d'a fin de racine", "vierte Wurzel aus a Ende Wurzel",
                        "cuarta raíz de a fin de raíz", "radice quarta di a fine radice"]
        for (language, text) in zip(MathReading.languages, expected) {
            XCTAssertEqual(try read("<mroot><mi>a</mi><mn>4</mn></mroot>", language), text)
        }
        XCTAssertEqual(try read("<mroot><mi>x</mi><mrow><mi>n</mi><mo>+</mo><mn>1</mn></mrow></mroot>"),
                       "the root with index n plus 1 of x end root")
        XCTAssertEqual(try read("<mroot><mi>x</mi><mn>123</mn></mroot>"), "the root with index 123 of x end root")
        XCTAssertEqual(try read("<msqrt><mi>a</mi></msqrt>", "fr"), "racine carrée d'a")
        XCTAssertEqual(try read("<msqrt><mi>x</mi></msqrt>", "fr"), "racine carrée de x")
        XCTAssertEqual(try read("<msqrt><mi>h</mi></msqrt>", "fr"), "racine carrée de h")
        XCTAssertEqual(try read("<msqrt><mtext>oui</mtext></msqrt>", "fr"), "racine carrée de oui")
    }

    func testStackColumnsFollowNestedPositionsAndEverySiblingShift() throws {
        XCTAssertEqual(try read("<mstack stackalign='left'><msgroup position='2' shift='1'><mn>12</mn><msline length='2'/><msgroup position='-1'><msrow position='1'><mn>34</mn></msrow></msgroup></msgroup></mstack>"),
                       "stack with 2 rows alignment left row 1: column minus 2: one column minus 1: two line column minus 3: column minus 2: row 2: column minus 4: three column minus 3: four end stack")
    }

    func testDecimalPointAlignmentAndPunctuationAreExplicit() throws {
        XCTAssertEqual(try read("<mstyle decimalpoint=','><mstack><msrow><mo>+</mo><mstyle><mn>12,3</mn></mstyle><none/></msrow><mn>4</mn></mstack></mstyle>"),
                       "stack with 2 rows alignment decimal point row 1: column minus 3: plus column minus 2: one column minus 1: two column 0: comma column 1: three column 2: blank row 2: column minus 1: four end stack")
        XCTAssertEqual(try read("<mstack stackalign='right'><mn>1 234.5</mn></mstack>"),
                       "stack with 1 row alignment right row 1: column minus 7: one column minus 6: space column minus 5: two column minus 4: three column minus 3: four column minus 2: point column minus 1: five end stack")
        XCTAssertEqual(try read("<mstack stackalign='center'><mn>12</mn></mstack>"),
                       "stack with 1 row alignment center row 1: column minus 1: one column 0: two end stack")
    }

    func testCarriesNameColumnsLocationsAndEveryDrawnStrike() throws {
        let body = "<mstack stackalign='left'><mscarries location='se' crossout='updiagonalstrike horizontalstrike'><mn>12</mn><mscarry location='w' crossout='none'><mn>3</mn></mscarry><none/></mscarries><mn>456</mn></mstack>"
        XCTAssertEqual(try read(body), "stack with 1 row alignment left carries or borrows: column 0: below right one two with the column's digit crossed out upward diagonal strike horizontal strike column 1: left three column 2: blank row 1: column 0: four column 1: five column 2: six end stack")
        for language in MathReading.languages {
            for location in CarryLocation.allCases {
                let text = try read("<mstack><mscarries location='\(location.rawValue)'><mn>1</mn></mscarries><mn>2</mn></mstack>", language)
                let words = MathReading.vocabularies.first { $0.language == language }!
                XCTAssertTrue(text.contains(words.spatial.locations[location]!))
                XCTAssertTrue(text.contains(words.spatial.carriesOrBorrows))
            }
        }
    }

    func testEveryDivisionFrameAndUnknownFallbackAreLocalized() throws {
        for words in MathReading.vocabularies {
            for frame in LongDivision.allCases {
                let text = try read("<mlongdiv longdivstyle='\(frame.rawValue)'><mn>3</mn><mn>41</mn><mn>123</mn></mlongdiv>", words.language)
                XCTAssertTrue(text.contains(words.spatial.frames[frame]!))
            }
            XCTAssertEqual(try read("<mlongdiv longdivstyle='unknown'/>", words.language), try read("<mlongdiv/>", words.language))
            XCTAssertEqual(try read("<mlongdiv longdivstyle='mediumrightright'/>", words.language),
                           try read("<mlongdiv longdivstyle='mediumstackedrightright'/>", words.language))
        }
    }

    func testSpatialVocabularyIsCompleteInEveryLanguage() {
        for words in MathReading.vocabularies {
            XCTAssertEqual(words.spatial.digits.count, 10)
            XCTAssertTrue(words.spatial.digits.allSatisfy { !$0.isEmpty })
            for align in MathStackAlignment.allCases { XCTAssertFalse((words.spatial.alignments[align] ?? "").isEmpty) }
            for location in CarryLocation.allCases { XCTAssertFalse((words.spatial.locations[location] ?? "").isEmpty) }
            for frame in LongDivision.allCases { XCTAssertFalse((words.spatial.frames[frame] ?? "").isEmpty) }
            for strike in ["updiagonalstrike", "downdiagonalstrike", "verticalstrike", "horizontalstrike"] {
                XCTAssertFalse((words.spatial.strikes[strike] ?? "").isEmpty)
            }
        }
    }

    func testAttributeSizedLinesAndExtremeShiftsStayBounded() throws {
        let text = try read("<mstack><msgroup position='2147483647' shift='2147483647'><mn>1</mn><msline length='2147483647'/><mn>2</mn></msgroup></mstack>")
        XCTAssertLessThan(text.count, 400)
        XCTAssertTrue(text.contains("column minus 6442450942: two"))
    }

    func testSilentShortcutChildrenConsumeNodeAndTextBudgets() {
        for name in ["msup", "mover", "mroot"] {
            let special = MathMLNode(name: name, children: [MathMLNode(name: "mi", text: "x"), MathMLNode(name: name == "mover" ? "mo" : "mn", text: name == "mover" ? "^" : "2")])
            let root = MathMLNode(name: "math", children: Array(repeating: special, count: MathLimits.nodes))
            XCTAssertLessThanOrEqual(root.accessibilityDescription.split(separator: " ").count { $0 == "x" }, (MathLimits.nodes - 1) / 3 + 1)
        }
        let huge = MathMLNode(name: "mn", text: String(repeating: "1", count: MathLimits.textLength + 1))
        let stack = MathMLNode(name: "mstack", children: [huge, MathMLNode(name: "mi", text: "past")])
        XCTAssertFalse(stack.accessibilityDescription.contains("past"))
        XCTAssertLessThan(stack.accessibilityDescription.count, 100)
    }
    func testLastAllowedShortcutDoesNotSynthesizeAnOmittedScript() {
        for (name, kind, value) in [("msup", "mn", "2"), ("mover", "mo", "^"), ("mroot", "mn", "2")] {
            let last = MathMLNode(name: name, children: [MathMLNode(name: "mi", text: "last"), MathMLNode(name: kind, text: value)])
            let placeholders = Array(repeating: MathMLNode(name: "none"), count: MathLimits.nodes - 3)
            let root = MathMLNode(name: "math", children: placeholders + [last])
            for language in MathReading.languages {
                XCTAssertEqual(root.accessibilityDescription(locale: Locale(identifier: language)).text, "last", name)
            }
        }
    }

    func testDivisionGroupOperandsRetainPositions() throws {
        let text = try read("<mlongdiv stackalign='left'><mn>3</mn><msgroup position='1' shift='1'><mn>12</mn><mn>34</mn></msgroup><mn>123</mn></mlongdiv>")
        XCTAssertTrue(text.contains("result: row 1: column minus 1: one column 0: two row 2: column minus 2: three column minus 1: four"))
    }

    func testDepthTruncationDoesNotTurnACompoundCellIntoBlank() {
        let hidden = (0..<MathLimits.depth).reduce(MathMLNode(name: "mi", text: "hidden")) { child, _ in
            MathMLNode(name: "mrow", children: [child])
        }
        let root = MathMLNode(name: "mstack", children: [hidden, MathMLNode(name: "none")])
        let text = root.accessibilityDescription
        XCTAssertFalse(text.contains("row 1:"))
        XCTAssertFalse(text.contains("hidden"))
        XCTAssertTrue(text.contains("row 2: column minus 1: blank"))
    }

}
