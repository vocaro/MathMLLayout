// Selected wording adapted from MathCAT (MIT) and Speech Rule Engine (Apache-2.0).
// Modified for MathMLLayout's phrase templates; see THIRD_PARTY_NOTICES.md and
// Documentation/SpeechWordingAudit.md for sources, decisions and remaining uncertainty.
/// French formula readings. A label's colon takes a space before it.
enum FrenchVocabulary: MathVocabulary {
    static let language = "fr"

    static let symbols = MathSymbols(
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

    static let accents = MathAccents(
        hat: .after("accent circonflexe"), tilde: .after("tilde"), bar: .after("barre"), underbar: .after("souligné"),
        dot: .after("point"), doubleDot: .after("tréma"), vector: .before("vecteur"), check: .after("caron"),
        breve: .after("brève"), overbrace: .after("avec accolade au-dessus"),
        underbrace: .after("avec accolade en dessous"))

    static func fraction(_ numerator: String, _ denominator: String, simple: Bool) -> String {
        simple ? phrase(numerator, "sur", denominator)
            : phrase("début de fraction", numerator, "sur", denominator, "fin de fraction")
    }
    static func squared(_ base: String) -> String { phrase(base, "au carré") }
    static func cubed(_ base: String) -> String { phrase(base, "au cube") }
    static func primed(_ base: String) -> String { phrase(base, "prime") }
    static func power(_ base: String, _ exponent: String, simple: Bool) -> String {
        phrase(base, "puissance", exponent, simple ? "" : "fin d'exposant")
    }
    static func subscripted(_ base: String, _ script: String) -> String { phrase(base, "indice", script) }
    static func squareRoot(_ radicand: String, closed: Bool) -> String {
        phrase("racine carrée de", radicand, closed ? "fin de racine" : "")
    }
    static func cubeRoot(_ radicand: String) -> String { phrase("racine cubique de", radicand, "fin de racine") }
    static func root(_ radicand: String, index: String) -> String {
        phrase("racine d'indice", index, "de", radicand, "fin de racine")
    }
    static func under(_ base: String, _ script: String) -> String { phrase(base, "avec en dessous", script) }
    static func over(_ base: String, _ script: String) -> String { phrase(base, "avec au-dessus", script) }
    static func limits(_ base: String, from lower: String, to upper: String) -> String {
        phrase(base, "de", lower, "à", upper)
    }
    static func script(_ script: String) -> String { phrase("indice", script) }
    /// French counts none and one in the singular.
    static func table(rows: Int) -> String { "tableau de \(rows) \(rows < 2 ? "ligne" : "lignes")" }
    static func row(_ number: Int) -> String { "ligne \(number) :" }

    static func stack(rows: Int) -> String { "opération posée de \(rows) \(rows < 2 ? "ligne" : "lignes")" }
    static let endStack = "fin de l'opération"
    static let line = "trait"
    static func carries(_ carries: String) -> String { phrase("retenues :", carries) }
    static let blank = "vide"
    static func crossedOut(_ carry: String) -> String { phrase(carry, "avec le chiffre en dessous barré") }
    static func longDivision(rows: Int) -> String {
        rows == 0 ? "division posée" : "division posée avec \(rows) \(rows < 2 ? "ligne" : "lignes") de calcul"
    }
    static func divisor(_ divisor: String) -> String { phrase("diviseur :", divisor) }
    static func dividend(_ dividend: String) -> String { phrase("dividende :", dividend) }
    static func result(_ result: String) -> String { phrase("résultat :", result) }
    static let endLongDivision = "fin de la division"
}
