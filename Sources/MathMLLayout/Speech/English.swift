// Selected multiscript wording adapted from MathCAT (MIT) and Speech Rule Engine
// (Apache-2.0), modified for explicit sides and compound closure in MathMLLayout.
// See doc/licenses/THIRD_PARTY_NOTICES.md and doc/speech-wording-audit.md for sources.
/// English, and the reading of every locale without a vocabulary of its own.
/// Structural speech follows the policies in doc/speech.md.
public enum EnglishVocabulary: MathVocabulary {
    public static let language = "en"

    public static let symbols = MathSymbols(
        plus: "plus", minus: "minus", plusOrMinus: "plus or minus", minusOrPlus: "minus or plus", times: "times",
        dividedBy: "divided by", slash: "over", equals: "equals", notEqual: "is not equal to", less: "is less than",
        greater: "is greater than", lessOrEqual: "is less than or equal to",
        greaterOrEqual: "is greater than or equal to", approximately: "is approximately equal to",
        equivalent: "is equivalent to", similar: "is similar to", proportional: "is proportional to",
        rightArrow: "goes to", leftArrow: "left arrow", implies: "implies", ifAndOnlyIf: "if and only if",
        element: "is in", notElement: "is not in", subset: "is a subset of",
        subsetOrEqual: "is a subset of or equal to", union: "union", intersection: "intersection", sum: "the sum",
        product: "the product", integral: "the integral", contourIntegral: "the contour integral",
        partial: "partial", nabla: "nabla", squareRoot: "square root", prime: "prime", doublePrime: "double prime",
        factorial: "factorial", percent: "percent", degrees: "degrees", infinity: "infinity",
        openParen: "open paren", closeParen: "close paren", openBracket: "open bracket",
        closeBracket: "close bracket", openBrace: "open brace", closeBrace: "close brace",
        verticalBar: "vertical bar", doubleVerticalBar: "double vertical bar", openAngle: "open angle bracket",
        closeAngle: "close angle bracket", ellipsis: "dot dot dot", forAll: "for all", exists: "there exists",
        not: "not", and: "and", or: "or")

    public static let accents = MathAccents(
        hat: .after("hat"), tilde: .after("tilde"), bar: .after("bar"), underbar: .after("underbar"),
        dot: .after("dot"), doubleDot: .after("double dot"), vector: .after("vector"), check: .after("check"),
        breve: .after("breve"), overbrace: .after("top brace"), underbrace: .after("bottom brace"))

    public static func fraction(_ numerator: String, _ denominator: String, simple: Bool) -> String {
        simple ? phrase(numerator, "over", denominator)
            : phrase("start fraction", numerator, "over", denominator, "end fraction")
    }
    public static func squared(_ base: String) -> String { phrase(base, "squared") }
    public static func cubed(_ base: String) -> String { phrase(base, "cubed") }
    public static func primed(_ base: String, count: Int) -> String {
        phrase([base] + Array(repeating: symbols.prime, count: max(0, count)))
    }
    public static func power(_ base: String, _ exponent: String, simple: Bool) -> String {
        phrase(base, "to the power of", exponent, simple ? "" : "end power")
    }
    public static func subscripted(_ base: String, _ script: String) -> String { phrase(base, "sub", script) }
    public static func squareRoot(_ radicand: String, closed: Bool) -> String {
        phrase("the square root of", radicand, closed ? "end root" : "")
    }
    public static func cubeRoot(_ radicand: String) -> String { phrase("the cube root of", radicand, "end root") }
    public static func root(_ radicand: String, index: String) -> String {
        phrase("the root with index", index, "of", radicand, "end root")
    }
    public static func under(_ base: String, _ script: String) -> String { phrase(base, "under", script) }
    public static func over(_ base: String, _ script: String) -> String { phrase(base, "over", script) }
    public static func limits(_ base: String, from lower: String, to upper: String) -> String {
        phrase(base, "from", lower, "to", upper)
    }
    // Positional script names adapted from pinned MathCAT/SRE; compound closing
    // phrases composed for MathMLLayout. See doc/speech-wording-audit.md.
    public static func script(_ script: String, position: MathScriptPosition, simple: Bool) -> String {
        let label: String, end: String
        switch position {
        case .rightSubscript: label = "right subscript"; end = "end subscript"
        case .rightSuperscript: label = "right superscript"; end = "end superscript"
        case .leftSubscript: label = "left subscript"; end = "end subscript"
        case .leftSuperscript: label = "left superscript"; end = "end superscript"
        }
        return phrase(label, script, simple ? "" : end)
    }
    public static func table(rows: Int) -> String { rows == 1 ? "table with 1 row" : "table with \(rows) rows" }
    public static func row(_ number: Int) -> String { "row \(number):" }

    public static func stack(rows: Int) -> String { rows == 1 ? "stack with 1 row" : "stack with \(rows) rows" }
    public static let endStack = "end stack"
    public static let line = "line"
    public static func carries(_ carries: String) -> String { phrase(spatial.carriesOrBorrows, carries) }
    public static let blank = "blank"
    public static func crossedOut(_ carry: String) -> String { phrase(carry, "with the column's digit crossed out") }
    public static func longDivision(rows: Int) -> String {
        rows == 0 ? "long division" : "long division with \(rows) working \(rows == 1 ? "row" : "rows")"
    }
    public static func divisor(_ divisor: String) -> String { phrase("divisor:", divisor) }
    public static func dividend(_ dividend: String) -> String { phrase("dividend:", dividend) }
    public static func result(_ result: String) -> String { phrase("result:", result) }
    public static let endLongDivision = "end long division"
    public static let spatial = MathSpatialWords(
        digits: ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"],
        point: "point", comma: "comma", space: "space", colon: "colon", semicolon: "semicolon",
        column: "column", alignment: "alignment", fullWidth: "across the whole stack", carriesOrBorrows: "carries or borrows:",
        alignments: [
            .left: "left",
            .center: "center",
            .right: "right",
            .decimalPoint: "decimal point",
        ],
        locations: [
            .w: "left",
            .nw: "above left",
            .n: "above",
            .ne: "above right",
            .e: "right",
            .se: "below right",
            .s: "below",
            .sw: "below left",
        ],
        strikes: [
            "updiagonalstrike": "upward diagonal strike",
            "downdiagonalstrike": "downward diagonal strike",
            "verticalstrike": "vertical strike",
            "horizontalstrike": "horizontal strike",
        ],
        frames: [
            .leftTop: "divisor left, result above",
            .stackedRightRight: "divisor and result stacked right, full vertical line",
            .mediumStackedRightRight: "divisor and result stacked right, medium vertical line",
            .shortStackedRightRight: "divisor and result stacked right, short vertical line",
            .rightTop: "divisor right, result above",
            .leftSlashRight: "divisor left of slash, result right of backslash",
            .leftParenRight: "divisor left of closing parenthesis, result right of opening parenthesis",
            .colonRightEqualsRight: "divisor right of colon, result right of equals",
            .stackedLeftLeft: "divisor and result stacked left",
            .stackedLeftLineTop: "divisor left, result above with left vertical line",
        ])

    // Bounded ordinal names adapted from pinned SRE number and root rules.
    // See doc/speech-wording-audit.md; compound indices retain explicit labels.
    public static let ordinalRoots = ["1": "first", "4": "fourth", "5": "fifth", "6": "sixth", "7": "seventh", "8": "eighth", "9": "ninth", "10": "tenth", "n": "n-th"]
    public static func ordinalRoot(_ radicand: String, ordinal: String) -> String {
        phrase("the", ordinal, "root of", radicand, "end root")
    }

}
