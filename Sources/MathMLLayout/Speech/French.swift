// Selected wording adapted from MathCAT (MIT) and Speech Rule Engine (Apache-2.0).
// Modified for MathMLLayout's phrase templates; see THIRD_PARTY_NOTICES.md and
// doc/speech-wording-audit.md for sources, decisions and remaining uncertainty.
/// French formula readings. A label's colon takes a space before it.
public enum FrenchVocabulary: MathVocabulary {
    public static let language = "fr"

    public static let symbols = MathSymbols(
        plus: "plus", minus: "moins", plusOrMinus: "plus ou moins", minusOrPlus: "moins ou plus", times: "fois",
        dividedBy: "divisé par", slash: "sur", equals: "égale", notEqual: "est différent de",
        less: "est inférieur à", greater: "est supérieur à",
        lessOrEqual: "est inférieur ou égal à", greaterOrEqual: "est supérieur ou égal à",
        approximately: "est approximativement égal à", equivalent: "est équivalent à",
        similar: "est semblable à", proportional: "est proportionnel à",
        rightArrow: "tend vers", leftArrow: "flèche vers la gauche", implies: "implique",
        ifAndOnlyIf: "si et seulement si", element: "appartient à", notElement: "n'appartient pas à",
        subset: "est inclus dans", subsetOrEqual: "est inclus dans ou égal à", union: "union",
        intersection: "inter", sum: "la somme", product: "le produit", integral: "l'intégrale",
        contourIntegral: "l'intégrale de contour", partial: "dérivée partielle", nabla: "nabla", squareRoot: "racine carrée",
        prime: "prime", doublePrime: "seconde", factorial: "factorielle", percent: "pour cent", degrees: "degrés",
        infinity: "l'infini", openParen: "parenthèse ouvrante", closeParen: "parenthèse fermante",
        openBracket: "crochet ouvrant", closeBracket: "crochet fermant", openBrace: "accolade ouvrante",
        closeBrace: "accolade fermante", verticalBar: "barre verticale", doubleVerticalBar: "double barre verticale",
        openAngle: "chevron ouvrant", closeAngle: "chevron fermant", ellipsis: "points de suspension",
        forAll: "pour tout", exists: "il existe", not: "non", and: "et", or: "ou")

    public static let accents = MathAccents(
        hat: .after("accent circonflexe"), tilde: .after("tilde"), bar: .after("barre"), underbar: .after("trait souscrit"),
        dot: .after("point"), doubleDot: .after("tréma"), vector: .before("vecteur"), check: .after("caron"),
        breve: .after("brève"), overbrace: .after("accolade supérieure"),
        underbrace: .after("accolade inférieure"))

    public static func fraction(_ numerator: String, _ denominator: String, simple: Bool) -> String {
        simple ? phrase(numerator, "sur", denominator)
            : phrase("début de fraction", numerator, "sur", denominator, "fin de fraction")
    }
    public static func squared(_ base: String) -> String { phrase(base, "au carré") }
    public static func cubed(_ base: String) -> String { phrase(base, "au cube") }
    public static func primed(_ base: String, count: Int) -> String {
        phrase([base] + Array(repeating: symbols.prime, count: max(0, count)))
    }
    public static func power(_ base: String, _ exponent: String, simple: Bool) -> String {
        phrase(base, "puissance", exponent, simple ? "" : "fin d'exposant")
    }
    public static func subscripted(_ base: String, _ script: String) -> String { phrase(base, "indice", script) }
    public static func squareRoot(_ radicand: String, closed: Bool) -> String {
        phrase("racine carrée", de(radicand), closed ? "fin de racine" : "")
    }
    public static func cubeRoot(_ radicand: String) -> String { phrase("racine cubique", de(radicand), "fin de racine") }
    public static func root(_ radicand: String, index: String) -> String {
        phrase("racine d'indice", index, de(radicand), "fin de racine")
    }
    public static func under(_ base: String, _ script: String) -> String { phrase(base, "avec en dessous", script) }
    public static func over(_ base: String, _ script: String) -> String { phrase(base, "avec au-dessus", script) }
    public static func limits(_ base: String, from lower: String, to upper: String) -> String {
        phrase(base, de(lower), "à", upper)
    }
    // Positional script names adapted from pinned MathCAT/SRE; compound closing
    // phrases composed for MathMLLayout. See doc/speech-wording-audit.md.
    public static func script(_ script: String, position: MathScriptPosition, simple: Bool) -> String {
        let label: String, end: String
        switch position {
        case .rightSubscript: label = "indice droite"; end = "fin d'indice"
        case .rightSuperscript: label = "exposant droite"; end = "fin d'exposant"
        case .leftSubscript: label = "indice gauche"; end = "fin d'indice"
        case .leftSuperscript: label = "exposant gauche"; end = "fin d'exposant"
        }
        return phrase(label, script, simple ? "" : end)
    }
    /// French counts none and one in the singular.
    public static func table(rows: Int) -> String { "tableau de \(rows) \(rows < 2 ? "ligne" : "lignes")" }
    public static func row(_ number: Int) -> String { "ligne \(number) :" }

    public static func stack(rows: Int) -> String { "opération posée de \(rows) \(rows < 2 ? "ligne" : "lignes")" }
    public static let endStack = "fin de l'opération"
    public static let line = "trait"
    public static func carries(_ carries: String) -> String { phrase(spatial.carriesOrBorrows, carries) }
    public static let blank = "vide"
    public static func crossedOut(_ carry: String) -> String { phrase(carry, "avec le chiffre de la colonne barré") }
    public static func longDivision(rows: Int) -> String {
        rows == 0 ? "division posée" : "division posée avec \(rows) \(rows < 2 ? "ligne" : "lignes") de calcul"
    }
    public static func divisor(_ divisor: String) -> String { phrase("diviseur :", divisor) }
    public static func dividend(_ dividend: String) -> String { phrase("dividende :", dividend) }
    public static func result(_ result: String) -> String { phrase("résultat :", result) }
    public static let endLongDivision = "fin de la division"
    public static let spatial = MathSpatialWords(
        digits: ["zéro", "un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf"],
        point: "point", comma: "virgule", space: "espace", colon: "deux-points", semicolon: "point-virgule",
        column: "colonne", alignment: "alignement", fullWidth: "sur toute la largeur de l’opération", carriesOrBorrows: "retenues ou emprunts :",
        alignments: [
            .left: "à gauche",
            .center: "au centre",
            .right: "à droite",
            .decimalPoint: "sur le séparateur décimal",
        ],
        locations: [
            .w: "à gauche",
            .nw: "en haut à gauche",
            .n: "au-dessus",
            .ne: "en haut à droite",
            .e: "à droite",
            .se: "en bas à droite",
            .s: "en dessous",
            .sw: "en bas à gauche",
        ],
        strikes: [
            "updiagonalstrike": "trait diagonal montant",
            "downdiagonalstrike": "trait diagonal descendant",
            "verticalstrike": "trait vertical",
            "horizontalstrike": "trait horizontal",
        ],
        frames: [
            .leftTop: "diviseur à gauche, résultat au-dessus",
            .stackedRightRight: "diviseur et résultat à droite, trait vertical complet",
            .mediumStackedRightRight: "diviseur et résultat à droite, trait vertical moyen",
            .shortStackedRightRight: "diviseur et résultat à droite, trait vertical court",
            .rightTop: "diviseur à droite, résultat au-dessus",
            .leftSlashRight: "diviseur à gauche d’une barre oblique, résultat à droite d’une barre oblique inverse",
            .leftParenRight: "diviseur à gauche d’une parenthèse fermante, résultat à droite d’une parenthèse ouvrante",
            .colonRightEqualsRight: "diviseur à droite des deux-points, résultat à droite du signe égal",
            .stackedLeftLeft: "diviseur et résultat à gauche",
            .stackedLeftLineTop: "diviseur à gauche, résultat au-dessus avec trait vertical à gauche",
        ])

    // Bounded ordinal names adapted from pinned SRE number rules and MathCAT root rules.
    // See doc/speech-wording-audit.md; compound indices retain explicit labels.
    public static let ordinalRoots = ["1": "première", "4": "quatrième", "5": "cinquième", "6": "sixième", "7": "septième", "8": "huitième", "9": "neuvième", "10": "dixième", "n": "n-ième"]
    public static func ordinalRoot(_ radicand: String, ordinal: String) -> String {
        phrase("racine", ordinal, de(radicand), "fin de racine")
    }

    /// Elide before an explicit vowel. Silent/aspirated h and letter names that
    /// differ from their written token require author-supplied alttext.
    private static func de(_ operand: String) -> String {
        guard let first = operand.first else { return "" }
        let opening = operand.split(separator: " ", maxSplits: 1).first?.lowercased() ?? ""
        // Preserve the disjunctive words identified by the Canadian elision guide.
        if ["oui", "onze", "onzième"].contains(opening) { return phrase("de", operand) }
        return "aàâäeéèêëiîïoôöuùûü".contains(first.lowercased())
            ? "d'" + operand : phrase("de", operand)
    }

}
