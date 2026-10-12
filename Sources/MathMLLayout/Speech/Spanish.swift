// Selected wording adapted from MathCAT (MIT) and Speech Rule Engine (Apache-2.0).
// Modified for MathMLLayout's phrase templates; see THIRD_PARTY_NOTICES.md and
// Documentation/SpeechWordingAudit.md for sources, decisions and remaining uncertainty.
/// Spanish formula readings; regional terminology has not been verified.
enum SpanishVocabulary: MathVocabulary {
    static let language = "es"

    static let symbols = MathSymbols(
        plus: "más", minus: "menos", plusOrMinus: "más o menos", minusOrPlus: "menos o más", times: "por",
        dividedBy: "dividido entre", slash: "sobre", equals: "igual a", notEqual: "es distinto de",
        less: "es menor que", greater: "es mayor que", lessOrEqual: "es menor o igual que",
        greaterOrEqual: "es mayor o igual que", approximately: "es aproximadamente igual a",
        equivalent: "es equivalente a", similar: "es semejante a", proportional: "es proporcional a",
        rightArrow: "tiende a", leftArrow: "flecha hacia la izquierda", implies: "implica",
        ifAndOnlyIf: "si y solo si", element: "pertenece a", notElement: "no pertenece a",
        subset: "es subconjunto de", subsetOrEqual: "es subconjunto de o igual a", union: "unión",
        intersection: "intersección", sum: "la suma", product: "el producto", integral: "la integral",
        contourIntegral: "la integral de contorno", partial: "parcial", nabla: "nabla", squareRoot: "raíz cuadrada",
        prime: "prima", doublePrime: "doble prima", factorial: "factorial", percent: "por ciento",
        degrees: "grados", infinity: "infinito", openParen: "abre paréntesis", closeParen: "cierra paréntesis",
        openBracket: "abre corchete", closeBracket: "cierra corchete", openBrace: "abre llave",
        closeBrace: "cierra llave", verticalBar: "barra vertical", doubleVerticalBar: "doble barra vertical",
        openAngle: "abre corchete angular", closeAngle: "cierra corchete angular", ellipsis: "puntos suspensivos",
        forAll: "para todo", exists: "existe", not: "no", and: "y", or: "o")

    static let accents = MathAccents(
        hat: .after("circunflejo"), tilde: .after("tilde"), bar: .after("barra"), underbar: .after("subrayado"),
        dot: .after("punto"), doubleDot: .after("diéresis"), vector: .before("vector"), check: .after("carón"),
        breve: .after("breve"), overbrace: .after("con llave encima"), underbrace: .after("con llave debajo"))

    static func fraction(_ numerator: String, _ denominator: String, simple: Bool) -> String {
        simple ? phrase(numerator, "sobre", denominator)
            : phrase("inicio de fracción", numerator, "sobre", denominator, "fin de fracción")
    }
    static func squared(_ base: String) -> String { phrase(base, "al cuadrado") }
    static func cubed(_ base: String) -> String { phrase(base, "al cubo") }
    static func primed(_ base: String) -> String { phrase(base, "prima") }
    static func power(_ base: String, _ exponent: String, simple: Bool) -> String {
        phrase(base, "elevado a", exponent, simple ? "" : "fin de exponente")
    }
    static func subscripted(_ base: String, _ script: String) -> String { phrase(base, "sub", script) }
    static func squareRoot(_ radicand: String, closed: Bool) -> String {
        phrase("raíz cuadrada de", radicand, closed ? "fin de raíz" : "")
    }
    static func cubeRoot(_ radicand: String) -> String { phrase("raíz cúbica de", radicand, "fin de raíz") }
    static func root(_ radicand: String, index: String) -> String {
        phrase("raíz de índice", index, "de", radicand, "fin de raíz")
    }
    static func under(_ base: String, _ script: String) -> String { phrase(base, "y debajo", script) }
    static func over(_ base: String, _ script: String) -> String { phrase(base, "y encima", script) }
    static func limits(_ base: String, from lower: String, to upper: String) -> String {
        phrase(base, "desde", lower, "hasta", upper)
    }
    static func script(_ script: String) -> String { phrase("índice", script) }
    static func table(rows: Int) -> String { "tabla de \(rows) \(rows == 1 ? "fila" : "filas")" }
    static func row(_ number: Int) -> String { "fila \(number):" }

    static func stack(rows: Int) -> String { "operación en columna de \(rows) \(rows == 1 ? "fila" : "filas")" }
    static let endStack = "fin de la operación"
    static let line = "línea"
    static func carries(_ carries: String) -> String { phrase("acarreos:", carries) }
    static let blank = "vacío"
    static func crossedOut(_ carry: String) -> String { phrase(carry, "con la cifra de abajo tachada") }
    static func longDivision(rows: Int) -> String {
        rows == 0 ? "división larga" : "división larga con \(rows) \(rows == 1 ? "fila" : "filas") de cálculo"
    }
    static func divisor(_ divisor: String) -> String { phrase("divisor:", divisor) }
    static func dividend(_ dividend: String) -> String { phrase("dividendo:", dividend) }
    static func result(_ result: String) -> String { phrase("resultado:", result) }
    static let endLongDivision = "fin de la división"
}
