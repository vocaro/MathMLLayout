// Selected wording adapted from MathCAT (MIT) and Speech Rule Engine (Apache-2.0).
// Modified for MathMLLayout's phrase templates; see doc/licenses/THIRD_PARTY_NOTICES.md and
// doc/speech-wording-audit.md for sources, decisions and remaining uncertainty.
/// German formula readings.
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
        contourIntegral: "das Randintegral", partial: "partielle Ableitung", nabla: "Nabla", squareRoot: "Quadratwurzel",
        prime: "Strich", doublePrime: "zwei Strich", factorial: "Fakultät", percent: "Prozent", degrees: "Grad",
        infinity: "unendlich", openParen: "Klammer auf", closeParen: "Klammer zu",
        openBracket: "eckige Klammer auf", closeBracket: "eckige Klammer zu", openBrace: "geschweifte Klammer auf",
        closeBrace: "geschweifte Klammer zu", verticalBar: "senkrechter Strich",
        doubleVerticalBar: "doppelter senkrechter Strich", openAngle: "spitze Klammer auf",
        closeAngle: "spitze Klammer zu", ellipsis: "Punkt Punkt Punkt", forAll: "für alle", exists: "es existiert",
        not: "nicht", and: "und", or: "oder")

    static let accents = MathAccents(
        hat: .after("Zirkumflex"), tilde: .after("Tilde"), bar: .after("Überstrich"), underbar: .after("Unterstrich"),
        dot: .after("Punkt"), doubleDot: .after("diaeresis"), vector: .before("Vektor"), check: .after("Caron"),
        breve: .after("Breve"), overbrace: .after("Obere geschweifte Klammer"), underbrace: .after("Untere geschweifte Klammer"))

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
    // Positional script names adapted from pinned MathCAT/SRE; compound closing
    // phrases composed for MathMLLayout. See doc/speech-wording-audit.md.
    static func script(_ script: String, position: MathScriptPosition, simple: Bool) -> String {
        let label: String, end: String
        switch position {
        case .rightSubscript: label = "rechter unterer Index"; end = "Ende Index"
        case .rightSuperscript: label = "rechter oberer Index"; end = "Ende Index"
        case .leftSubscript: label = "linker unterer Index"; end = "Ende Index"
        case .leftSuperscript: label = "linker oberer Index"; end = "Ende Index"
        }
        return phrase(label, script, simple ? "" : end)
    }
    static func table(rows: Int) -> String { "Tabelle mit \(rows) \(rows == 1 ? "Zeile" : "Zeilen")" }
    static func row(_ number: Int) -> String { "Zeile \(number):" }

    static func stack(rows: Int) -> String { "schriftliche Rechnung mit \(rows) \(rows == 1 ? "Zeile" : "Zeilen")" }
    static let endStack = "Ende der Rechnung"
    static let line = "Strich"
    static func carries(_ carries: String) -> String { phrase("Überträge:", carries) }
    static let blank = "leer"
    static func crossedOut(_ carry: String) -> String { phrase(carry, "mit durchgestrichener Ziffer in dieser Spalte") }
    static func longDivision(rows: Int) -> String {
        rows == 0 ? "schriftliche Division"
            : "schriftliche Division mit \(rows) \(rows == 1 ? "Rechenzeile" : "Rechenzeilen")"
    }
    static func divisor(_ divisor: String) -> String { phrase("Divisor:", divisor) }
    static func dividend(_ dividend: String) -> String { phrase("Dividend:", dividend) }
    static func result(_ result: String) -> String { phrase("Ergebnis:", result) }
    static let endLongDivision = "Ende der Division"
    static let spatial = MathSpatialWords(
        digits: ["null", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun"],
        point: "Punkt", comma: "Komma", space: "Leerzeichen", colon: "Doppelpunkt", semicolon: "Strichpunkt",
        column: "Spalte", alignment: "Ausrichtung", fullWidth: "über die gesamte Rechnung", carriesOrBorrows: "Überträge oder Entlehnungen:",
        alignments: [
            .left: "links",
            .center: "mittig",
            .right: "rechts",
            .decimalPoint: "am Dezimaltrennzeichen",
        ],
        locations: [
            .w: "links",
            .nw: "oben links",
            .n: "oben",
            .ne: "oben rechts",
            .e: "rechts",
            .se: "unten rechts",
            .s: "unten",
            .sw: "unten links",
        ],
        strikes: [
            "updiagonalstrike": "aufsteigender diagonaler Strich",
            "downdiagonalstrike": "absteigender diagonaler Strich",
            "verticalstrike": "senkrechter Strich",
            "horizontalstrike": "waagerechter Strich",
        ],
        frames: [
            .leftTop: "Divisor links, Ergebnis oben",
            .stackedRightRight: "Divisor und Ergebnis rechts, volle senkrechte Linie",
            .mediumStackedRightRight: "Divisor und Ergebnis rechts, mittlere senkrechte Linie",
            .shortStackedRightRight: "Divisor und Ergebnis rechts, kurze senkrechte Linie",
            .rightTop: "Divisor rechts, Ergebnis oben",
            .leftSlashRight: "Divisor links vom Schrägstrich, Ergebnis rechts vom umgekehrten Schrägstrich",
            .leftParenRight: "Divisor links von der schließenden Klammer, Ergebnis rechts von der öffnenden Klammer",
            .colonRightEqualsRight: "Divisor rechts vom Doppelpunkt, Ergebnis rechts vom Gleichheitszeichen",
            .stackedLeftLeft: "Divisor und Ergebnis links",
            .stackedLeftLineTop: "Divisor links, Ergebnis oben mit linker senkrechter Linie",
        ])

    // Bounded ordinal names adapted from pinned SRE number rules and MathCAT root rules.
    // See doc/speech-wording-audit.md; compound indices retain explicit labels.
    static let ordinalRoots = ["1": "erste", "4": "vierte", "5": "fünfte", "6": "sechste", "7": "siebte", "8": "achte", "9": "neunte", "10": "zehnte", "n": "n-te"]
    static func ordinalRoot(_ radicand: String, ordinal: String) -> String {
        phrase(ordinal, "Wurzel aus", radicand, "Ende Wurzel")
    }

}
