// Selected wording adapted from Speech Rule Engine (Apache-2.0).
// Modified for MathMLLayout's phrase templates; see THIRD_PARTY_NOTICES.md and
// Documentation/SpeechWordingAudit.md for sources, decisions and remaining uncertainty.
/// Italian formula readings.
enum ItalianVocabulary: MathVocabulary {
    static let language = "it"

    static let symbols = MathSymbols(
        plus: "più", minus: "meno", plusOrMinus: "più o meno", minusOrPlus: "meno o più", times: "per",
        dividedBy: "diviso", slash: "fratto", equals: "uguale a", notEqual: "è diverso da", less: "è minore di",
        greater: "è maggiore di", lessOrEqual: "è minore o uguale a", greaterOrEqual: "è maggiore o uguale a",
        approximately: "è circa uguale a", equivalent: "è equivalente a", similar: "è simile a",
        proportional: "è proporzionale a", rightArrow: "tende a", leftArrow: "freccia verso sinistra",
        implies: "implica", ifAndOnlyIf: "se e solo se", element: "appartiene a", notElement: "non appartiene a",
        subset: "è sottoinsieme di", subsetOrEqual: "è sottoinsieme di o uguale a", union: "unione",
        intersection: "intersezione", sum: "la sommatoria", product: "la produttoria", integral: "l'integrale",
        contourIntegral: "l'integrale di contorno", partial: "derivata parziale", nabla: "nabla",
        squareRoot: "radice quadrata", prime: "primo", doublePrime: "secondo", factorial: "fattoriale",
        percent: "per cento", degrees: "gradi", infinity: "infinito", openParen: "aperta parentesi",
        closeParen: "chiusa parentesi", openBracket: "aperta parentesi quadra",
        closeBracket: "chiusa parentesi quadra", openBrace: "aperta parentesi graffa",
        closeBrace: "chiusa parentesi graffa", verticalBar: "barra verticale",
        doubleVerticalBar: "doppia barra verticale", openAngle: "aperta parentesi angolare",
        closeAngle: "chiusa parentesi angolare", ellipsis: "puntini", forAll: "per ogni", exists: "esiste",
        not: "non", and: "e", or: "o")

    static let accents = MathAccents(
        hat: .after("accento circonflesso"), tilde: .after("tilde"), bar: .after("barra sopra"), underbar: .after("sottolineato"),
        dot: .after("punto"), doubleDot: .after("dieresi"), vector: .before("vettore"), check: .after("caron"),
        breve: .after("breve"), overbrace: .after("con graffa sopra"), underbrace: .after("con graffa sotto"))

    static func fraction(_ numerator: String, _ denominator: String, simple: Bool) -> String {
        simple ? phrase(numerator, "fratto", denominator)
            : phrase("inizio frazione", numerator, "fratto", denominator, "fine frazione")
    }
    static func squared(_ base: String) -> String { phrase(base, "al quadrato") }
    static func cubed(_ base: String) -> String { phrase(base, "al cubo") }
    static func primed(_ base: String) -> String { phrase(base, "primo") }
    static func power(_ base: String, _ exponent: String, simple: Bool) -> String {
        phrase(base, "elevato a", exponent, simple ? "" : "fine esponente")
    }
    static func subscripted(_ base: String, _ script: String) -> String { phrase(base, "pedice", script) }
    static func squareRoot(_ radicand: String, closed: Bool) -> String {
        phrase("radice quadrata di", radicand, closed ? "fine radice" : "")
    }
    static func cubeRoot(_ radicand: String) -> String { phrase("radice cubica di", radicand, "fine radice") }
    static func root(_ radicand: String, index: String) -> String {
        phrase("radice di indice", index, "di", radicand, "fine radice")
    }
    static func under(_ base: String, _ script: String) -> String { phrase(base, "con sotto", script) }
    static func over(_ base: String, _ script: String) -> String { phrase(base, "con sopra", script) }
    static func limits(_ base: String, from lower: String, to upper: String) -> String {
        phrase(base, "da", lower, "fino a", upper)
    }
    // Positional script names adapted from pinned MathCAT/SRE; compound closing
    // phrases composed for MathMLLayout. See Documentation/SpeechWordingAudit.md.
    static func script(_ script: String, position: MathScriptPosition, simple: Bool) -> String {
        let label: String, end: String
        switch position {
        case .rightSubscript: label = "pedice destro"; end = "fine pedice"
        case .rightSuperscript: label = "apice destro"; end = "fine apice"
        case .leftSubscript: label = "pedice sinistro"; end = "fine pedice"
        case .leftSuperscript: label = "apice sinistro"; end = "fine apice"
        }
        return phrase(label, script, simple ? "" : end)
    }
    static func table(rows: Int) -> String { "tabella di \(rows) \(rows == 1 ? "riga" : "righe")" }
    static func row(_ number: Int) -> String { "riga \(number):" }

    static func stack(rows: Int) -> String { "operazione in colonna di \(rows) \(rows == 1 ? "riga" : "righe")" }
    static let endStack = "fine dell'operazione"
    static let line = "linea"
    static func carries(_ carries: String) -> String { phrase("riporti:", carries) }
    static let blank = "vuoto"
    static func crossedOut(_ carry: String) -> String { phrase(carry, "con la cifra sotto barrata") }
    static func longDivision(rows: Int) -> String {
        rows == 0 ? "divisione in colonna"
            : "divisione in colonna con \(rows) \(rows == 1 ? "riga" : "righe") di calcolo"
    }
    static func divisor(_ divisor: String) -> String { phrase("divisore:", divisor) }
    static func dividend(_ dividend: String) -> String { phrase("dividendo:", dividend) }
    static func result(_ result: String) -> String { phrase("risultato:", result) }
    static let endLongDivision = "fine della divisione"
}
