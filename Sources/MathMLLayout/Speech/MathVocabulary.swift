/// The four corners of an `mmultiscripts` base, independent of reading order.
public enum MathScriptPosition: CaseIterable, Sendable {
    case rightSubscript, rightSuperscript, leftSubscript, leftSuperscript
}

/// One language's way of reading a formula aloud. The speaker walks the tree and hands each
/// construct's spoken parts to these functions, so every language puts its own words in its own
/// order: "x squared" is "x au carré", "x vector" is "vecteur x". Nothing here is optional: a
/// language that lacked a phrase would otherwise borrow another's in the middle of a reading.
public protocol MathVocabulary: Sendable {
    /// BCP 47 tag of the language.
    static var language: String { get }
    static var symbols: MathSymbols { get }
    static var accents: MathAccents { get }
    static var spatial: MathSpatialWords { get }
    static var ordinalRoots: [String: String] { get }
    /// Join already-read parts. Empty parts represent content omitted by the traversal budgets.
    /// Implementations must not re-read source nodes or automatically translate author text.
    static func phrase(_ parts: [String]) -> String
    /// Compose an accent with its already-read base, allowing language-specific joining.
    static func accent(_ accent: MathAccent, on base: String) -> String
    static func column(_ number: Int) -> String
    static func alignment(_ alignment: MathStackAlignment) -> String
    static func ordinalRoot(_ radicand: String, ordinal: String) -> String

    /// `simple` when both parts are single tokens, which speech need not bracket.
    static func fraction(_ numerator: String, _ denominator: String, simple: Bool) -> String
    static func squared(_ base: String) -> String
    static func cubed(_ base: String) -> String
    /// Compose a bounded sequence of primes in one pass. `count` is positive and at most four
    /// times the already-consumed source-text budget; avoid repeated concatenation of the base.
    static func primed(_ base: String, count: Int) -> String
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
    /// Compose a group of carries or borrows written above the next row, listed left to right.
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

public extension MathVocabulary {
    /// Convenience for one prime; traversal uses the counted composition hook.
    static func primed(_ base: String) -> String { primed(base, count: 1) }
    static func accent(_ accent: MathAccent, on base: String) -> String { accent.reading(on: base) }
    /// The parts that say something, a space apart: an operand the bounds left out leaves no gap.
    static func phrase(_ parts: String...) -> String { phrase(parts) }
    static func phrase(_ parts: [String]) -> String { parts.lazy.filter { !$0.isEmpty }.joined(separator: " ") }
}

/// The names of operators, relations and fences in one language. A struct rather than a table by
/// character: its initializer does not compile with a name missing, and characters that read
/// alike share one, so a language cannot name the minus sign and forget the hyphen.
public struct MathSymbols: Sendable {
    public var plus, minus, plusOrMinus, minusOrPlus, times, dividedBy, slash, equals, notEqual, less, greater: String
    public var lessOrEqual, greaterOrEqual, approximately, equivalent, similar, proportional, rightArrow, leftArrow: String
    public var implies, ifAndOnlyIf, element, notElement, subset, subsetOrEqual, union, intersection, sum, product: String
    public var integral, contourIntegral, partial, nabla, squareRoot, prime, doublePrime, factorial, percent, degrees: String
    public var infinity, openParen, closeParen, openBracket, closeBracket, openBrace, closeBrace, verticalBar: String
    public var doubleVerticalBar, openAngle, closeAngle, ellipsis, forAll, exists, not, and, or: String

    /// The name of an operator's text, or nil for one that is read as written.
    public subscript(text: String) -> String? { Self.names[text].map { self[keyPath: $0] } }

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

    public init(
        plus: String, minus: String, plusOrMinus: String,
        minusOrPlus: String, times: String, dividedBy: String,
        slash: String, equals: String, notEqual: String,
        less: String, greater: String, lessOrEqual: String,
        greaterOrEqual: String, approximately: String, equivalent: String,
        similar: String, proportional: String, rightArrow: String,
        leftArrow: String, implies: String, ifAndOnlyIf: String,
        element: String, notElement: String, subset: String,
        subsetOrEqual: String, union: String, intersection: String,
        sum: String, product: String, integral: String,
        contourIntegral: String, partial: String, nabla: String,
        squareRoot: String, prime: String, doublePrime: String,
        factorial: String, percent: String, degrees: String,
        infinity: String, openParen: String, closeParen: String,
        openBracket: String, closeBracket: String, openBrace: String,
        closeBrace: String, verticalBar: String, doubleVerticalBar: String,
        openAngle: String, closeAngle: String, ellipsis: String,
        forAll: String, exists: String, not: String,
        and: String, or: String
    ) {
        self.plus = plus
        self.minus = minus
        self.plusOrMinus = plusOrMinus
        self.minusOrPlus = minusOrPlus
        self.times = times
        self.dividedBy = dividedBy
        self.slash = slash
        self.equals = equals
        self.notEqual = notEqual
        self.less = less
        self.greater = greater
        self.lessOrEqual = lessOrEqual
        self.greaterOrEqual = greaterOrEqual
        self.approximately = approximately
        self.equivalent = equivalent
        self.similar = similar
        self.proportional = proportional
        self.rightArrow = rightArrow
        self.leftArrow = leftArrow
        self.implies = implies
        self.ifAndOnlyIf = ifAndOnlyIf
        self.element = element
        self.notElement = notElement
        self.subset = subset
        self.subsetOrEqual = subsetOrEqual
        self.union = union
        self.intersection = intersection
        self.sum = sum
        self.product = product
        self.integral = integral
        self.contourIntegral = contourIntegral
        self.partial = partial
        self.nabla = nabla
        self.squareRoot = squareRoot
        self.prime = prime
        self.doublePrime = doublePrime
        self.factorial = factorial
        self.percent = percent
        self.degrees = degrees
        self.infinity = infinity
        self.openParen = openParen
        self.closeParen = closeParen
        self.openBracket = openBracket
        self.closeBracket = closeBracket
        self.openBrace = openBrace
        self.closeBrace = closeBrace
        self.verticalBar = verticalBar
        self.doubleVerticalBar = doubleVerticalBar
        self.openAngle = openAngle
        self.closeAngle = closeAngle
        self.ellipsis = ellipsis
        self.forAll = forAll
        self.exists = exists
        self.not = not
        self.and = and
        self.or = or
    }
}

/// An accent's name and the side of its base it is said on: "x hat", but "vecteur x".
public enum MathAccent: Sendable {
    case after(String), before(String)

    public func reading(on base: String) -> String {
        switch self {
        case .after(let name): base.isEmpty ? name : "\(base) \(name)"
        case .before(let name): base.isEmpty ? name : "\(name) \(base)"
        }
    }
}

/// The recognized over- and under-accents in one language.
public struct MathAccents: Sendable {
    public var hat, tilde, bar, underbar, dot, doubleDot, vector, check, breve, overbrace, underbrace: MathAccent

    /// The accent an `mover`'s script draws, or nil for a script that is not one.
    public subscript(text: String) -> MathAccent? { Self.names[text].map { self[keyPath: $0] } }

    static let names: [String: KeyPath<MathAccents, MathAccent> & Sendable] = [
        "^": \.hat, "ˆ": \.hat, "\u{0302}": \.hat, "~": \.tilde, "˜": \.tilde, "\u{0303}": \.tilde,
        "¯": \.bar, "‾": \.bar, "\u{0305}": \.bar, "_": \.underbar, "\u{0332}": \.underbar, "˙": \.dot, "\u{0307}": \.dot,
        "¨": \.doubleDot, "\u{0308}": \.doubleDot, "→": \.vector, "\u{20D7}": \.vector, "ˇ": \.check,
        "˘": \.breve, "⏞": \.overbrace, "⏟": \.underbrace,
    ]

    public init(
        hat: MathAccent, tilde: MathAccent, bar: MathAccent,
        underbar: MathAccent, dot: MathAccent, doubleDot: MathAccent,
        vector: MathAccent, check: MathAccent, breve: MathAccent,
        overbrace: MathAccent, underbrace: MathAccent
    ) {
        self.hat = hat
        self.tilde = tilde
        self.bar = bar
        self.underbar = underbar
        self.dot = dot
        self.doubleDot = doubleDot
        self.vector = vector
        self.check = check
        self.breve = breve
        self.overbrace = overbrace
        self.underbrace = underbrace
    }
}
