/// German, as it is read aloud in class: "x Quadrat", "a durch b", "Quadratwurzel aus x",
/// "Klammer auf", and a stack as the "schriftliche Rechnung" pupils learn.
enum GermanVocabulary: MathVocabulary {
    static let language = "de"

    static let symbols = MathSymbols(
        plus: "plus", minus: "minus", plusOrMinus: "plus minus", minusOrPlus: "minus plus", times: "mal",
        dividedBy: "geteilt durch", slash: "durch", equals: "gleich", notEqual: "ungleich", less: "kleiner als",
        greater: "größer als", lessOrEqual: "kleiner oder gleich", greaterOrEqual: "größer oder gleich",
        approximately: "ungefähr gleich", equivalent: "äquivalent zu", similar: "ähnlich zu",
        proportional: "proportional zu", rightArrow: "gegen", leftArrow: "Pfeil nach links", implies: "impliziert",
        ifAndOnlyIf: "genau dann wenn", element: "Element von", notElement: "kein Element von",
        subset: "Teilmenge von", subsetOrEqual: "Teilmenge von oder gleich", union: "vereinigt mit",
        intersection: "geschnitten mit", sum: "die Summe", product: "das Produkt", integral: "das Integral",
        contourIntegral: "das Ringintegral", partial: "del", nabla: "Nabla", squareRoot: "Quadratwurzel",
        prime: "Strich", doublePrime: "zwei Strich", factorial: "Fakultät", percent: "Prozent", degrees: "Grad",
        infinity: "unendlich", openParen: "Klammer auf", closeParen: "Klammer zu",
        openBracket: "eckige Klammer auf", closeBracket: "eckige Klammer zu", openBrace: "geschweifte Klammer auf",
        closeBrace: "geschweifte Klammer zu", verticalBar: "senkrechter Strich",
        doubleVerticalBar: "doppelter senkrechter Strich", openAngle: "spitze Klammer auf",
        closeAngle: "spitze Klammer zu", ellipsis: "Punkt Punkt Punkt", forAll: "für alle", exists: "es existiert",
        not: "nicht", and: "und", or: "oder")

    static let accents = MathAccents(
        hat: .after("Dach"), tilde: .after("Tilde"), bar: .after("quer"), underbar: .after("unterstrichen"),
        dot: .after("Punkt"), doubleDot: .after("zwei Punkt"), vector: .before("Vektor"), check: .after("Hatschek"),
        breve: .after("Breve"), overbrace: .after("mit Klammer darüber"), underbrace: .after("mit Klammer darunter"))

    static func fraction(_ numerator: String, _ denominator: String, simple: Bool) -> String {
        simple ? phrase(numerator, "durch", denominator)
            : phrase("Anfang Bruch", numerator, "durch", denominator, "Ende Bruch")
    }
    static func squared(_ base: String) -> String { phrase(base, "Quadrat") }
    static func cubed(_ base: String) -> String { phrase(base, "hoch 3") }
    static func primed(_ base: String) -> String { phrase(base, "Strich") }
    static func power(_ base: String, _ exponent: String, simple: Bool) -> String {
        phrase(base, "hoch", exponent, simple ? "" : "Ende Exponent")
    }
    static func subscripted(_ base: String, _ script: String) -> String { phrase(base, "Index", script) }
    static func squareRoot(_ radicand: String, closed: Bool) -> String {
        phrase("Quadratwurzel aus", radicand, closed ? "Ende Wurzel" : "")
    }
    static func cubeRoot(_ radicand: String) -> String { phrase("Kubikwurzel aus", radicand, "Ende Wurzel") }
    static func root(_ radicand: String, index: String) -> String {
        phrase("Wurzel mit Wurzelexponent", index, "aus", radicand, "Ende Wurzel")
    }
    static func under(_ base: String, _ script: String) -> String { phrase(base, "darunter", script) }
    static func over(_ base: String, _ script: String) -> String { phrase(base, "darüber", script) }
    static func limits(_ base: String, from lower: String, to upper: String) -> String {
        phrase(base, "von", lower, "bis", upper)
    }
    static func script(_ script: String) -> String { phrase("Index", script) }
    static func table(rows: Int) -> String { "Tabelle mit \(rows) \(rows == 1 ? "Zeile" : "Zeilen")" }
    static func row(_ number: Int) -> String { "Zeile \(number):" }

    static func stack(rows: Int) -> String { "schriftliche Rechnung mit \(rows) \(rows == 1 ? "Zeile" : "Zeilen")" }
    static let endStack = "Ende der Rechnung"
    static let line = "Strich"
    static func carries(_ carries: String) -> String { phrase("Überträge:", carries) }
    static let blank = "leer"
    static func crossedOut(_ carry: String) -> String { phrase(carry, "mit durchgestrichener Ziffer darunter") }
    static func longDivision(rows: Int) -> String {
        rows == 0 ? "schriftliche Division"
            : "schriftliche Division mit \(rows) \(rows == 1 ? "Rechenzeile" : "Rechenzeilen")"
    }
    static func divisor(_ divisor: String) -> String { phrase("Divisor:", divisor) }
    static func dividend(_ dividend: String) -> String { phrase("Dividend:", dividend) }
    static func result(_ result: String) -> String { phrase("Ergebnis:", result) }
    static let endLongDivision = "Ende der Division"
}
