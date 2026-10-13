import Foundation
import MathMLLayout
import XCTest

// qaa is in BCP 47's private-use range. These sentinel words exercise a COMPLETE new-language
// provider, not a translation or a claim to support another natural language.
enum FixtureVocabulary: MathVocabulary {
    static let language = "qaa"
    static let symbols = MathSymbols(
        plus: "qa-plus",
        minus: "qa-minus",
        plusOrMinus: "qa-plusOrMinus",
        minusOrPlus: "qa-minusOrPlus",
        times: "qa-times",
        dividedBy: "qa-dividedBy",
        slash: "qa-slash",
        equals: "qa-equals",
        notEqual: "qa-notEqual",
        less: "qa-less",
        greater: "qa-greater",
        lessOrEqual: "qa-lessOrEqual",
        greaterOrEqual: "qa-greaterOrEqual",
        approximately: "qa-approximately",
        equivalent: "qa-equivalent",
        similar: "qa-similar",
        proportional: "qa-proportional",
        rightArrow: "qa-rightArrow",
        leftArrow: "qa-leftArrow",
        implies: "qa-implies",
        ifAndOnlyIf: "qa-ifAndOnlyIf",
        element: "qa-element",
        notElement: "qa-notElement",
        subset: "qa-subset",
        subsetOrEqual: "qa-subsetOrEqual",
        union: "qa-union",
        intersection: "qa-intersection",
        sum: "qa-sum",
        product: "qa-product",
        integral: "qa-integral",
        contourIntegral: "qa-contourIntegral",
        partial: "qa-partial",
        nabla: "qa-nabla",
        squareRoot: "qa-squareRoot",
        prime: "qa-prime",
        doublePrime: "qa-doublePrime",
        factorial: "qa-factorial",
        percent: "qa-percent",
        degrees: "qa-degrees",
        infinity: "qa-infinity",
        openParen: "qa-openParen",
        closeParen: "qa-closeParen",
        openBracket: "qa-openBracket",
        closeBracket: "qa-closeBracket",
        openBrace: "qa-openBrace",
        closeBrace: "qa-closeBrace",
        verticalBar: "qa-verticalBar",
        doubleVerticalBar: "qa-doubleVerticalBar",
        openAngle: "qa-openAngle",
        closeAngle: "qa-closeAngle",
        ellipsis: "qa-ellipsis",
        forAll: "qa-forAll",
        exists: "qa-exists",
        not: "qa-not",
        and: "qa-and",
        or: "qa-or")
    static let accents = MathAccents(
        hat: .after("qa-hat"),
        tilde: .after("qa-tilde"),
        bar: .after("qa-bar"),
        underbar: .after("qa-underbar"),
        dot: .after("qa-dot"),
        doubleDot: .after("qa-doubleDot"),
        vector: .after("qa-vector"),
        check: .after("qa-check"),
        breve: .after("qa-breve"),
        overbrace: .after("qa-overbrace"),
        underbrace: .after("qa-underbrace"))
    static let ordinalRoots = ["4": "qa-fourth"]
    static let spatial = MathSpatialWords(
        digits: (0..<10).map { "qa-digit-\($0)" }, point: "qa-point", comma: "qa-comma",
        space: "qa-space", colon: "qa-colon", semicolon: "qa-semicolon", column: "qa-column",
        alignment: "qa-alignment", fullWidth: "qa-full", carriesOrBorrows: "qa-carries",
        alignments: Dictionary(uniqueKeysWithValues: MathStackAlignment.allCases.map { ($0, "qa-" + $0.rawValue) }),
        locations: Dictionary(uniqueKeysWithValues: CarryLocation.allCases.map { ($0, "qa-" + $0.rawValue) }),
        strikes: Dictionary(uniqueKeysWithValues: ["updiagonalstrike", "downdiagonalstrike", "verticalstrike", "horizontalstrike"].map { ($0, "qa-" + $0) }),
        frames: Dictionary(uniqueKeysWithValues: LongDivision.allCases.map { ($0, "qa-" + $0.rawValue) }))
    static func phrase(_ parts: [String]) -> String { parts.filter { !$0.isEmpty }.joined(separator: "|") }
    static func accent(_ accent: MathAccent, on base: String) -> String { "qa-accent[" + accent.reading(on: "") + ";" + base + "]" }
    static func column(_ number: Int) -> String { "qa-column[\(number)]" }
    static func alignment(_ alignment: MathStackAlignment) -> String { "qa-align[" + alignment.rawValue + "]" }
    static func ordinalRoot(_ radicand: String, ordinal: String) -> String { "qa-ordinal[" + ordinal + ";" + radicand + "]" }
    static func fraction(_ numerator: String, _ denominator: String, simple: Bool) -> String {
        "qa-fraction[" + numerator + ";" + denominator + (simple ? "]" : ";qa-close]")
    }
    static func squared(_ base: String) -> String { "qa-square[" + base + "]" }
    static func cubed(_ base: String) -> String { "qa-cube[" + base + "]" }
    static func primed(_ base: String, count: Int) -> String { "qa-prime[\(count);" + base + "]" }
    static func power(_ base: String, _ exponent: String, simple: Bool) -> String { "qa-power[" + base + ";" + exponent + (simple ? "]" : ";qa-close]") }
    static func subscripted(_ base: String, _ script: String) -> String { "qa-sub[" + base + ";" + script + "]" }
    static func squareRoot(_ radicand: String, closed: Bool) -> String { "qa-root[" + radicand + (closed ? ";qa-close]" : "]") }
    static func cubeRoot(_ radicand: String) -> String { "qa-cuberoot[" + radicand + "]" }
    static func root(_ radicand: String, index: String) -> String { "qa-index[" + index + ";" + radicand + "]" }
    static func under(_ base: String, _ script: String) -> String { "qa-under[" + base + ";" + script + "]" }
    static func over(_ base: String, _ script: String) -> String { "qa-over[" + base + ";" + script + "]" }
    static func limits(_ base: String, from lower: String, to upper: String) -> String { "qa-limits[" + base + ";" + lower + ";" + upper + "]" }
    static func script(_ script: String, position: MathScriptPosition, simple: Bool) -> String { "qa-script[\(position);" + script + (simple ? "]" : ";qa-close]") }
    static func table(rows: Int) -> String { rows == 1 ? "qa-table-single[1]" : "qa-table-plural[\(rows)]" }
    static func row(_ number: Int) -> String { "qa-row[\(number)]" }
    static func stack(rows: Int) -> String { "qa-stack[\(rows)]" }
    static let endStack = "qa-end-stack"
    static let line = "qa-line"
    static func carries(_ carries: String) -> String { "qa-carries[" + carries + "]" }
    static let blank = "qa-blank"
    static func crossedOut(_ carry: String) -> String { "qa-crossed[" + carry + "]" }
    static func longDivision(rows: Int) -> String { "qa-division[\(rows)]" }
    static func divisor(_ divisor: String) -> String { "qa-divisor[" + divisor + "]" }
    static func dividend(_ dividend: String) -> String { "qa-dividend[" + dividend + "]" }
    static func result(_ result: String) -> String { "qa-result[" + result + "]" }
    static let endLongDivision = "qa-end-division"
}

enum FixtureRegion: MathRegionalVocabulary {
    typealias Base = FixtureVocabulary
    static let language = "QAA_zz"
    static var symbols: MathSymbols { var words = Base.symbols; words.plus = "qa-regional-plus"; return words }
    static func squared(_ base: String) -> String { "qa-regional-square[" + base + "]" }
    static func primed(_ base: String, count: Int) -> String { "qa-regional-prime[\(count);" + base + "]" }
    static func carries(_ carries: String) -> String { "qa-regional-carries[" + carries + "]" }
}
private enum DuplicateFixture: MathRegionalVocabulary {
    typealias Base = FixtureVocabulary
    static let language = "qaa"
    static func squared(_ base: String) -> String { "wrong duplicate" }
}
private enum ScriptFixture: MathRegionalVocabulary {
    typealias Base = FixtureVocabulary
    static let language = "qaa-Latn-ZZ"
}
private enum InvalidFixture: MathRegionalVocabulary {
    typealias Base = FixtureVocabulary
    static let language = "bad--tag"
}
private enum IncompleteFixture: MathRegionalVocabulary {
    typealias Base = FixtureVocabulary
    static let language = "qab"
    static var symbols: MathSymbols { var words = Base.symbols; words.plus = ""; return words }
}
private enum IncompleteSpatialFixture: MathRegionalVocabulary {
    typealias Base = FixtureVocabulary
    static let language = "qac"
    static var spatial: MathSpatialWords {
        let s = Base.spatial
        return MathSpatialWords(digits: [], point: s.point, comma: s.comma, space: s.space,
            colon: s.colon, semicolon: s.semicolon, column: s.column, alignment: s.alignment,
            fullWidth: s.fullWidth, carriesOrBorrows: s.carriesOrBorrows,
            alignments: s.alignments, locations: s.locations, strikes: s.strikes, frames: s.frames)
    }
}

final class SpeechVocabularyAPITests: XCTestCase {
    private let catalog = MathVocabularyCatalog(vocabularies: [FixtureVocabulary.self, FixtureRegion.self,
        DuplicateFixture.self, ScriptFixture.self, InvalidFixture.self, IncompleteFixture.self, IncompleteSpatialFixture.self])
    private func node(_ body: String) throws -> MathMLNode { try MathMLNode.parse(xml: Data(("<math>" + body + "</math>").utf8)) }
    private func read(_ body: String, _ locale: String) throws -> MathReading {
        try node(body).accessibilityDescription(locale: Locale(identifier: locale), vocabularies: catalog)
    }

    func testSelectedVoiceTagAndDeterministicFallback() throws {
        let body = "<msup><mi>x</mi><mn>2</mn></msup><mo>+</mo><mn>1</mn>"
        XCTAssertEqual(try read(body, "qaa-ZZ"), MathReading(text: "qa-regional-square[x]|qa-regional-plus|1", language: "qaa-ZZ"))
        XCTAssertEqual(try read(body, "qaa-AA"), MathReading(text: "qa-square[x]|qa-plus|1", language: "qaa"))
        XCTAssertEqual(try read(body, "qaa"), MathReading(text: "qa-square[x]|qa-plus|1", language: "qaa"))
        XCTAssertEqual(try read(body, "ja-JP"), MathReading(text: "x squared plus 1", language: "en"))
        XCTAssertEqual(try read(body, "qab"), MathReading(text: "x squared plus 1", language: "en"))
        XCTAssertEqual(try read(body, "qac"), MathReading(text: "x squared plus 1", language: "en"))
        XCTAssertEqual(try read(body, "qaa-Latn-ZZ").language, "qaa-Latn-ZZ")
        XCTAssertEqual(try read(body, "qaa-Cyrl-ZZ").language, "qaa")
        XCTAssertEqual(try read(body, "qaa-ZZ-u-nu-latn").language, "qaa-ZZ")
        XCTAssertEqual(try read(body, "qaa_ZZ@calendar=gregorian").language, "qaa-ZZ")
        XCTAssertEqual(try read(body, "").language, "en")
        XCTAssertEqual(catalog.languages, ["qaa", "qaa-ZZ", "qaa-Latn-ZZ", "en", "fr", "de", "es", "it", "en-GB"])
        // Registration is per-call: the standard catalog has no synthetic language.
        XCTAssertEqual(try node(body).accessibilityDescription(locale: Locale(identifier: "qaa-ZZ")).language, "en")
    }

    func testRegionalBracketTermsAndUnqualifiedDefaults() throws {
        let formula = try node("<mfenced><msqrt><mi>x</mi></msqrt></mfenced><mo>[</mo><mo>]</mo><mo>{</mo><mo>}</mo>")
        XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: "en_GB")), MathReading(
            text: "open round bracket the square root of x close round bracket open square bracket close square bracket open curly bracket close curly bracket", language: "en-GB"))
        XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: "en")).text, formula.accessibilityDescription)
        XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: "en-AU")).language, "en")
        XCTAssertEqual(MathReading.languages, ["en", "fr", "de", "es", "it"])
        XCTAssertEqual(MathReading.supportedLocales, ["en", "fr", "de", "es", "it", "en-GB"])
    }

    func testPrimeSequencesAndCarryGroupsUseCompositionHooks() throws {
        XCTAssertEqual(try read("<msup><mi>x</mi><mo>′</mo></msup>", "qaa").text, "qa-prime[1;x]")
        XCTAssertEqual(try read("<msup><mi>x</mi><mo>′″</mo></msup>", "qaa").text, "qa-prime[3;x]")
        XCTAssertEqual(try read("<msup><mi>x</mi><mo>⁗</mo></msup>", "qaa-ZZ").text, "qa-regional-prime[4;x]")
        let body = "<mstack><mscarries><mn>1</mn></mscarries><mn>2</mn></mstack>"
        XCTAssertEqual(try read(body, "qaa").text,
            "qa-stack[1]|qa-align[decimalpoint]|qa-carries[qa-column[-1]|qa-n|qa-digit-1]|qa-row[1]|qa-column[-1]|qa-digit-2|qa-end-stack")
        XCTAssertEqual(try read(body, "qaa-ZZ").text,
            "qa-stack[1]|qa-align[decimalpoint]|qa-regional-carries[qa-column[-1]|qa-n|qa-digit-1]|qa-row[1]|qa-column[-1]|qa-digit-2|qa-end-stack")
    }

    func testCompleteProviderNestedCompositionAndLiteralAuthorWords() throws {
        let body = "<msqrt><mfrac><msup><mi>x</mi><mn>2</mn></msup><mrow><mi>a</mi><mo>+</mo><mi>b</mi></mrow></mfrac></msqrt>"
        XCTAssertEqual(try read(body, "qaa").text, "qa-root[qa-fraction[qa-square[x];a|qa-plus|b;qa-close];qa-close]")
        XCTAssertEqual(try read("<mover><mi>x</mi><mo>˙</mo></mover>", "qaa").text, "qa-accent[qa-dot;x]")
        XCTAssertEqual(try read("<mroot><mi>x</mi><mn>4</mn></mroot>", "qaa").text, "qa-ordinal[qa-fourth;x]")
        XCTAssertEqual(try read("<mtable><mtr><mtd><mi>x</mi></mtd></mtr><mtr><mtd><mi>y</mi></mtd></mtr></mtable>", "qaa").text, "qa-table-plural[2]|qa-row[1]|x|qa-row[2]|y")
        XCTAssertEqual(try read("<mtable><mtr><mtd><mi>x</mi></mtd></mtr></mtable>", "qaa").text, "qa-table-single[1]|qa-row[1]|x")
        XCTAssertEqual(try read("<mtext>author plus au carré</mtext><mglyph alt='my diagram'/><ms>left side</ms>", "qaa").text,
                       "author plus au carré|my diagram|left side")
        let fallback = try node(body).accessibilityDescription
        XCTAssertEqual(try read(body, "zz-ZZ"), MathReading(text: fallback, language: "en"))
        // Complete geometry tables and hooks work inside another expression.
        let stack = try read("<msqrt><mstack><mn>2</mn><msline length='1'/></mstack></msqrt>", "qaa").text
        XCTAssertEqual(stack, "qa-root[qa-stack[1]|qa-align[decimalpoint]|qa-row[1]|qa-column[-1]|qa-digit-2|qa-line|qa-column[-1]|qa-column[-1]|qa-end-stack;qa-close]")
    }
}
