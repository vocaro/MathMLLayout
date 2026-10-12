/// The four corners of an `mmultiscripts` base, independent of reading order.
enum MathScriptPosition: CaseIterable, Sendable {
    case rightSubscript, rightSuperscript, leftSubscript, leftSuperscript
}

/// One language's way of reading a formula aloud. The speaker walks the tree and hands each
/// construct's spoken parts to these functions, so every language puts its own words in its own
/// order: "x squared" is "x au carré", "x vector" is "vecteur x". Nothing here is optional: a
/// language that lacked a phrase would otherwise borrow another's in the middle of a reading.
protocol MathVocabulary: Sendable {
    /// BCP 47 tag of the language.
    static var language: String { get }
    static var symbols: MathSymbols { get }
    static var accents: MathAccents { get }
    static var spatial: MathSpatialWords { get }
    static var ordinalRoots: [String: String] { get }
    static func ordinalRoot(_ radicand: String, ordinal: String) -> String

    /// `simple` when both parts are single tokens, which speech need not bracket.
    static func fraction(_ numerator: String, _ denominator: String, simple: Bool) -> String
    static func squared(_ base: String) -> String
    static func cubed(_ base: String) -> String
    static func primed(_ base: String) -> String
    /// `simple` when the exponent is a single token, so the listener hears where it ends.
    static func power(_ base: String, _ exponent: String, simple: Bool) -> String
    static func subscripted(_ base: String, _ script: String) -> String
    /// `closed` marks the end of a radicand that is more than a single token.
    static func squareRoot(_ radicand: String, closed: Bool) -> String
    static func cubeRoot(_ radicand: String) -> String
    static func root(_ radicand: String, index: String) -> String
    static func under(_ base: String, _ script: String) -> String
    static func over(_ base: String, _ script: String) -> String
    static func limits(_ base: String, from lower: String, to upper: String) -> String
    /// One script at a named corner; compound readings explicitly mark their end.
    static func script(_ script: String, position: MathScriptPosition, simple: Bool) -> String
    static func table(rows: Int) -> String
    /// Introduces row `number`, from 1, of a table or of a stack.
    static func row(_ number: Int) -> String

    // Elementary math: a stack of digit rows, or a long division, read row by row.

    /// Opens an `mstack` of `rows` digit rows; its lines and carries are announced but not counted.
    static func stack(rows: Int) -> String
    static var endStack: String { get }
    /// An `msline`.
    static var line: String { get }
    /// Introduces the carries (or borrows) written above the next row, listed left to right.
    static func carries(_ carries: String) -> String
    /// A column without a carry, or a row without digits.
    static var blank: String { get }
    /// A carry whose `crossout` strikes the annotated column’s digit.
    static func crossedOut(_ carry: String) -> String
    /// Opens an `mlongdiv` with `rows` digit rows of working under its dividend.
    static func longDivision(rows: Int) -> String
    static func divisor(_ divisor: String) -> String
    static func dividend(_ dividend: String) -> String
    static func result(_ result: String) -> String
    static var endLongDivision: String { get }
}

extension MathVocabulary {
    /// The parts that say something, a space apart: an operand the bounds left out leaves no gap.
    static func phrase(_ parts: String...) -> String { phrase(parts) }
    static func phrase(_ parts: [String]) -> String { parts.lazy.filter { !$0.isEmpty }.joined(separator: " ") }
}

/// The names of operators, relations and fences in one language. A struct rather than a table by
/// character: its initializer does not compile with a name missing, and characters that read
/// alike share one, so a language cannot name the minus sign and forget the hyphen.
struct MathSymbols: Sendable {
    var plus, minus, plusOrMinus, minusOrPlus, times, dividedBy, slash, equals, notEqual, less, greater: String
    var lessOrEqual, greaterOrEqual, approximately, equivalent, similar, proportional, rightArrow, leftArrow: String
    var implies, ifAndOnlyIf, element, notElement, subset, subsetOrEqual, union, intersection, sum, product: String
    var integral, contourIntegral, partial, nabla, squareRoot, prime, doublePrime, factorial, percent, degrees: String
    var infinity, openParen, closeParen, openBracket, closeBracket, openBrace, closeBrace, verticalBar: String
    var doubleVerticalBar, openAngle, closeAngle, ellipsis, forAll, exists, not, and, or: String

    /// The name of an operator's text, or nil for one that is read as written.
    subscript(text: String) -> String? { Self.names[text].map { self[keyPath: $0] } }

    static let names: [String: KeyPath<MathSymbols, String> & Sendable] = [
        "+": \.plus, "\u{2212}": \.minus, "-": \.minus, "±": \.plusOrMinus, "∓": \.minusOrPlus, "×": \.times,
        "·": \.times, "⋅": \.times, "∗": \.times, "*": \.times, "÷": \.dividedBy, "/": \.slash, "=": \.equals,
        "≠": \.notEqual, "<": \.less, ">": \.greater, "≤": \.lessOrEqual, "≥": \.greaterOrEqual,
        "≈": \.approximately, "≡": \.equivalent, "∼": \.similar, "∝": \.proportional, "→": \.rightArrow,
        "←": \.leftArrow, "⇒": \.implies, "⇔": \.ifAndOnlyIf, "∈": \.element, "∉": \.notElement,
        "⊂": \.subset, "⊆": \.subsetOrEqual, "∪": \.union, "∩": \.intersection, "∑": \.sum, "∏": \.product,
        "∫": \.integral, "∮": \.contourIntegral, "∂": \.partial, "∇": \.nabla, "√": \.squareRoot,
        "′": \.prime, "″": \.doublePrime, "!": \.factorial, "%": \.percent, "°": \.degrees, "∞": \.infinity,
        "(": \.openParen, ")": \.closeParen, "[": \.openBracket, "]": \.closeBracket, "{": \.openBrace,
        "}": \.closeBrace, "|": \.verticalBar, "‖": \.doubleVerticalBar, "⟨": \.openAngle, "⟩": \.closeAngle,
        "…": \.ellipsis, "⋯": \.ellipsis, "∀": \.forAll, "∃": \.exists, "¬": \.not, "∧": \.and, "∨": \.or,
    ]
}

/// An accent's name and the side of its base it is said on: "x hat", but "vecteur x".
enum MathAccent: Sendable {
    case after(String), before(String)

    func reading(on base: String) -> String {
        switch self {
        case .after(let name): base.isEmpty ? name : "\(base) \(name)"
        case .before(let name): base.isEmpty ? name : "\(name) \(base)"
        }
    }
}

/// The recognized over- and under-accents in one language.
struct MathAccents: Sendable {
    var hat, tilde, bar, underbar, dot, doubleDot, vector, check, breve, overbrace, underbrace: MathAccent

    /// The accent an `mover`'s script draws, or nil for a script that is not one.
    subscript(text: String) -> MathAccent? { Self.names[text].map { self[keyPath: $0] } }

    static let names: [String: KeyPath<MathAccents, MathAccent> & Sendable] = [
        "^": \.hat, "ˆ": \.hat, "\u{0302}": \.hat, "~": \.tilde, "˜": \.tilde, "\u{0303}": \.tilde,
        "¯": \.bar, "‾": \.bar, "\u{0305}": \.bar, "_": \.underbar, "\u{0332}": \.underbar, "˙": \.dot, "\u{0307}": \.dot,
        "¨": \.doubleDot, "\u{0308}": \.doubleDot, "→": \.vector, "\u{20D7}": \.vector, "ˇ": \.check,
        "˘": \.breve, "⏞": \.overbrace, "⏟": \.underbrace,
    ]
}
