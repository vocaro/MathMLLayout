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
        hat: .after("circunflejo"), tilde: .after("tilde"), bar: .after("barra"), underbar: .after("subbarra"),
        dot: .after("punto"), doubleDot: .after("diéresis"), vector: .before("vector"), check: .after("carón"),
        breve: .after("breve"), overbrace: .after("corchete rizado superior"), underbrace: .after("corchete rizado inferior"))

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
    // Positional script names adapted from pinned MathCAT/SRE; compound closing
    // phrases composed for MathMLLayout. See Documentation/SpeechWordingAudit.md.
    static func script(_ script: String, position: MathScriptPosition, simple: Bool) -> String {
        let label: String, end: String
        switch position {
        case .rightSubscript: label = "subíndice derecho"; end = "fin de subíndice"
        case .rightSuperscript: label = "superíndice derecho"; end = "fin de superíndice"
        case .leftSubscript: label = "subíndice izquierdo"; end = "fin de subíndice"
        case .leftSuperscript: label = "superíndice izquierdo"; end = "fin de superíndice"
        }
        return phrase(label, script, simple ? "" : end)
    }
    static func table(rows: Int) -> String { "tabla de \(rows) \(rows == 1 ? "fila" : "filas")" }
    static func row(_ number: Int) -> String { "fila \(number):" }

    static func stack(rows: Int) -> String { "operación en columna de \(rows) \(rows == 1 ? "fila" : "filas")" }
    static let endStack = "fin de la operación"
    static let line = "línea"
    static func carries(_ carries: String) -> String { phrase("acarreos:", carries) }
    static let blank = "vacío"
    static func crossedOut(_ carry: String) -> String { phrase(carry, "con la cifra de la columna tachada") }
    static func longDivision(rows: Int) -> String {
        rows == 0 ? "división larga" : "división larga con \(rows) \(rows == 1 ? "fila" : "filas") de cálculo"
    }
    static func divisor(_ divisor: String) -> String { phrase("divisor:", divisor) }
    static func dividend(_ dividend: String) -> String { phrase("dividendo:", dividend) }
    static func result(_ result: String) -> String { phrase("resultado:", result) }
    static let endLongDivision = "fin de la división"
    static let spatial = MathSpatialWords(
        digits: ["cero", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve"],
        point: "punto", comma: "coma", space: "espacio", colon: "dos puntos", semicolon: "punto y coma",
        column: "columna", alignment: "alineación", fullWidth: "en todo el ancho de la operación", carriesOrBorrows: "acarreos o préstamos:",
        alignments: [
            .left: "a la izquierda",
            .center: "en el centro",
            .right: "a la derecha",
            .decimalPoint: "en el separador decimal",
        ],
        locations: [
            .w: "a la izquierda",
            .nw: "arriba a la izquierda",
            .n: "arriba",
            .ne: "arriba a la derecha",
            .e: "a la derecha",
            .se: "abajo a la derecha",
            .s: "abajo",
            .sw: "abajo a la izquierda",
        ],
        strikes: [
            "updiagonalstrike": "tachado diagonal ascendente",
            "downdiagonalstrike": "tachado diagonal descendente",
            "verticalstrike": "tachado vertical",
            "horizontalstrike": "tachado horizontal",
        ],
        frames: [
            .leftTop: "divisor a la izquierda, resultado arriba",
            .stackedRightRight: "divisor y resultado a la derecha, línea vertical completa",
            .mediumStackedRightRight: "divisor y resultado a la derecha, línea vertical media",
            .shortStackedRightRight: "divisor y resultado a la derecha, línea vertical corta",
            .rightTop: "divisor a la derecha, resultado arriba",
            .leftSlashRight: "divisor a la izquierda de la barra, resultado a la derecha de la barra inversa",
            .leftParenRight: "divisor a la izquierda del paréntesis de cierre, resultado a la derecha del paréntesis de apertura",
            .colonRightEqualsRight: "divisor a la derecha de los dos puntos, resultado a la derecha del signo igual",
            .stackedLeftLeft: "divisor y resultado a la izquierda",
            .stackedLeftLineTop: "divisor a la izquierda, resultado arriba con línea vertical izquierda",
        ])

    // Bounded ordinal names adapted from pinned SRE number rules and MathCAT root rules.
    // See Documentation/SpeechWordingAudit.md; compound indices retain explicit labels.
    // No matching Spanish variable-root ordinal was found; n keeps the index template.
    static let ordinalRoots = ["1": "primera", "4": "cuarta", "5": "quinta", "6": "sexta", "7": "séptima", "8": "octava", "9": "novena", "10": "décima"]
    static func ordinalRoot(_ radicand: String, ordinal: String) -> String {
        phrase(ordinal, "raíz de", radicand, "fin de raíz")
    }

}
