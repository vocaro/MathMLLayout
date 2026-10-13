// Selected wording adapted from Speech Rule Engine (Apache-2.0).
// Modified for MathMLLayout's phrase templates; see THIRD_PARTY_NOTICES.md and
// doc/speech-wording-audit.md for sources, decisions and remaining uncertainty.
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
        hat: .after("accento circonflesso"), tilde: .after("tilde"), bar: .after("barra sopra"), underbar: .after("con barra sotto"),
        dot: .after("punto"), doubleDot: .after("dieresi"), vector: .before("vettore"), check: .after("con caron"),
        breve: .after("breve"), overbrace: .after("parentesi graffa superiore"), underbrace: .after("parentesi graffa inferiore"))

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
    // phrases composed for MathMLLayout. See doc/speech-wording-audit.md.
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
    static func crossedOut(_ carry: String) -> String { phrase(carry, "con la cifra della colonna barrata") }
    static func longDivision(rows: Int) -> String {
        rows == 0 ? "divisione in colonna"
            : "divisione in colonna con \(rows) \(rows == 1 ? "riga" : "righe") di calcolo"
    }
    static func divisor(_ divisor: String) -> String { phrase("divisore:", divisor) }
    static func dividend(_ dividend: String) -> String { phrase("dividendo:", dividend) }
    static func result(_ result: String) -> String { phrase("risultato:", result) }
    static let endLongDivision = "fine della divisione"
    static let spatial = MathSpatialWords(
        digits: ["zero", "uno", "due", "tre", "quattro", "cinque", "sei", "sette", "otto", "nove"],
        point: "punto", comma: "virgola", space: "spazio", colon: "due punti", semicolon: "punto e virgola",
        column: "colonna", alignment: "allineamento", fullWidth: "su tutta la larghezza dell’operazione", carriesOrBorrows: "riporti o prestiti:",
        alignments: [
            .left: "a sinistra",
            .center: "al centro",
            .right: "a destra",
            .decimalPoint: "al separatore decimale",
        ],
        locations: [
            .w: "a sinistra",
            .nw: "in alto a sinistra",
            .n: "sopra",
            .ne: "in alto a destra",
            .e: "a destra",
            .se: "in basso a destra",
            .s: "sotto",
            .sw: "in basso a sinistra",
        ],
        strikes: [
            "updiagonalstrike": "barratura diagonale ascendente",
            "downdiagonalstrike": "barratura diagonale discendente",
            "verticalstrike": "barratura verticale",
            "horizontalstrike": "barratura orizzontale",
        ],
        frames: [
            .leftTop: "divisore a sinistra, risultato sopra",
            .stackedRightRight: "divisore e risultato a destra, linea verticale completa",
            .mediumStackedRightRight: "divisore e risultato a destra, linea verticale media",
            .shortStackedRightRight: "divisore e risultato a destra, linea verticale corta",
            .rightTop: "divisore a destra, risultato sopra",
            .leftSlashRight: "divisore a sinistra della barra, risultato a destra della barra inversa",
            .leftParenRight: "divisore a sinistra della parentesi chiusa, risultato a destra della parentesi aperta",
            .colonRightEqualsRight: "divisore a destra dei due punti, risultato a destra del segno uguale",
            .stackedLeftLeft: "divisore e risultato a sinistra",
            .stackedLeftLineTop: "divisore a sinistra, risultato sopra con linea verticale sinistra",
        ])

    // Bounded ordinal names adapted from pinned SRE number rules and MathCAT root rules.
    // See doc/speech-wording-audit.md; compound indices retain explicit labels.
    static let ordinalRoots = ["1": "prima", "4": "quarta", "5": "quinta", "6": "sesta", "7": "settima", "8": "ottava", "9": "nona", "10": "decima", "n": "n-esima"]
    static func ordinalRoot(_ radicand: String, ordinal: String) -> String {
        phrase("radice", ordinal, "di", radicand, "fine radice")
    }

}
