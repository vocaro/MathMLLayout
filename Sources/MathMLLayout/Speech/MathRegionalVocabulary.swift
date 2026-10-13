/// A regional vocabulary explicitly inherits all terminology and compositions from `Base`.
/// Override only sourced regional differences. Supply `language` as a distinct BCP 47 tag.
/// A new language should implement `MathVocabulary` directly, with every required field and hook.
public protocol MathRegionalVocabulary: MathVocabulary {
    associatedtype Base: MathVocabulary
}

public extension MathRegionalVocabulary {
    static var symbols: MathSymbols { Base.symbols }
    static var accents: MathAccents { Base.accents }
    static var spatial: MathSpatialWords { Base.spatial }
    static var ordinalRoots: [String: String] { Base.ordinalRoots }
    static func phrase(_ parts: [String]) -> String { Base.phrase(parts) }
    static func accent(_ accent: MathAccent, on base: String) -> String { Base.accent(accent, on: base) }
    static func column(_ number: Int) -> String { Base.column(number) }
    static func alignment(_ alignment: MathStackAlignment) -> String { Base.alignment(alignment) }
    static func ordinalRoot(_ radicand: String, ordinal: String) -> String { Base.ordinalRoot(radicand, ordinal: ordinal) }
    static func fraction(_ numerator: String, _ denominator: String, simple: Bool) -> String { Base.fraction(numerator, denominator, simple: simple) }
    static func squared(_ base: String) -> String { Base.squared(base) }
    static func cubed(_ base: String) -> String { Base.cubed(base) }
    static func primed(_ base: String, count: Int) -> String { Base.primed(base, count: count) }
    static func power(_ base: String, _ exponent: String, simple: Bool) -> String { Base.power(base, exponent, simple: simple) }
    static func subscripted(_ base: String, _ script: String) -> String { Base.subscripted(base, script) }
    static func squareRoot(_ radicand: String, closed: Bool) -> String { Base.squareRoot(radicand, closed: closed) }
    static func cubeRoot(_ radicand: String) -> String { Base.cubeRoot(radicand) }
    static func root(_ radicand: String, index: String) -> String { Base.root(radicand, index: index) }
    static func under(_ base: String, _ script: String) -> String { Base.under(base, script) }
    static func over(_ base: String, _ script: String) -> String { Base.over(base, script) }
    static func limits(_ base: String, from lower: String, to upper: String) -> String { Base.limits(base, from: lower, to: upper) }
    static func script(_ script: String, position: MathScriptPosition, simple: Bool) -> String { Base.script(script, position: position, simple: simple) }
    static func table(rows: Int) -> String { Base.table(rows: rows) }
    static func row(_ number: Int) -> String { Base.row(number) }
    static func stack(rows: Int) -> String { Base.stack(rows: rows) }
    static var endStack: String { Base.endStack }
    static var line: String { Base.line }
    static func carries(_ carries: String) -> String { Base.carries(carries) }
    static var blank: String { Base.blank }
    static func crossedOut(_ carry: String) -> String { Base.crossedOut(carry) }
    static func longDivision(rows: Int) -> String { Base.longDivision(rows: rows) }
    static func divisor(_ divisor: String) -> String { Base.divisor(divisor) }
    static func dividend(_ dividend: String) -> String { Base.dividend(dividend) }
    static func result(_ result: String) -> String { Base.result(result) }
    static var endLongDivision: String { Base.endLongDivision }
}
