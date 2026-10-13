// Selected localized expectations adapted from MathCAT (MIT) and Speech Rule Engine
// (Apache-2.0), modified for MathMLLayout; see THIRD_PARTY_NOTICES.md and
// doc/speech-wording-audit.md for attribution and pinned sources.
import Foundation
@testable import MathMLLayout
import XCTest

final class SpeechTests: MathTestCase {
    private func reading(_ body: String, _ language: String) throws -> String {
        let reading = try node(body).accessibilityDescription(locale: Locale(identifier: language))
        XCTAssertEqual(reading.language, language, body)
        return reading.text
    }

    private func english(_ node: MathMLNode) -> String { node.accessibilityDescription }

    // MARK: Languages

    /// One formula for each kind of phrase, and its reading in every language, in the order of
    /// `MathReading.languages`: English, French, German, Spanish, Italian.
    private static let readings: [(body: String, readings: [String])] = [
        ("<msup><mi>x</mi><mn>2</mn></msup><mo>+</mo><mn>1</mn>",
         ["x squared plus 1", "x au carré plus 1", "x Quadrat plus 1", "x al cuadrado más 1", "x al quadrato più 1"]),
        ("<msup><mi>x</mi><mn>3</mn></msup>", ["x cubed", "x au cube", "x hoch 3", "x al cubo", "x al cubo"]),
        ("<msup><mi>f</mi><mo>′</mo></msup>", ["f prime", "f prime", "f Strich", "f prima", "f primo"]),
        ("<msup><mi>x</mi><mi>n</mi></msup>",
         ["x to the power of n", "x puissance n", "x hoch n", "x elevado a n", "x elevato a n"]),
        ("<msup><mi>x</mi><mrow><mi>n</mi><mo>+</mo><mn>1</mn></mrow></msup>",
         ["x to the power of n plus 1 end power", "x puissance n plus 1 fin d'exposant", "x hoch n plus 1 Ende Exponent",
          "x elevado a n más 1 fin de exponente", "x elevato a n più 1 fine esponente"]),
        ("<msub><mi>x</mi><mn>1</mn></msub>", ["x sub 1", "x indice 1", "x Index 1", "x sub 1", "x pedice 1"]),
        ("<msubsup><mi>x</mi><mi>i</mi><mn>2</mn></msubsup>",
         ["x sub i to the power of 2", "x indice i puissance 2", "x Index i hoch 2", "x sub i elevado a 2",
          "x pedice i elevato a 2"]),
        ("<mfrac><mi>a</mi><mi>b</mi></mfrac>", ["a over b", "a sur b", "a durch b", "a sobre b", "a fratto b"]),
        ("<mfrac><mrow><mi>a</mi><mo>+</mo><mi>b</mi></mrow><mi>c</mi></mfrac>",
         ["start fraction a plus b over c end fraction", "début de fraction a plus b sur c fin de fraction",
          "Anfang Bruch a plus b durch c Ende Bruch", "inicio de fracción a más b sobre c fin de fracción",
          "inizio frazione a più b fratto c fine frazione"]),
        ("<msqrt><mi>x</mi></msqrt>",
         ["the square root of x", "racine carrée de x", "Quadratwurzel aus x", "raíz cuadrada de x", "radice quadrata di x"]),
        ("<msqrt><mi>x</mi><mo>+</mo><mn>1</mn></msqrt>",
         ["the square root of x plus 1 end root", "racine carrée de x plus 1 fin de racine",
          "Quadratwurzel aus x plus 1 Ende Wurzel", "raíz cuadrada de x más 1 fin de raíz",
          "radice quadrata di x più 1 fine radice"]),
        ("<mroot><mi>x</mi><mn>3</mn></mroot>",
         ["the cube root of x end root", "racine cubique de x fin de racine", "Kubikwurzel aus x Ende Wurzel",
          "raíz cúbica de x fin de raíz", "radice cubica di x fine radice"]),
        ("<mroot><mi>x</mi><mi>n</mi></mroot>",
         ["the n-th root of x end root", "racine n-ième de x fin de racine",
          "n-te Wurzel aus x Ende Wurzel", "raíz de índice n de x fin de raíz",
          "radice n-esima di x fine radice"]),
        ("<munderover><mo>∑</mo><mrow><mi>i</mi><mo>=</mo><mn>1</mn></mrow><mi>n</mi></munderover><msup><mi>i</mi><mn>2</mn></msup>",
         ["the sum from i equals 1 to n i squared", "la somme d'i égale 1 à n i au carré",
          "die Summe von i gleich 1 bis n i Quadrat", "la suma desde i igual a 1 hasta n i al cuadrado",
          "la sommatoria da i uguale a 1 fino a n i al quadrato"]),
        ("<munder><mi>lim</mi><mrow><mi>n</mi><mo>→</mo><mo>∞</mo></mrow></munder>",
         ["lim under n goes to infinity", "lim avec en dessous n tend vers l'infini", "lim darunter n gegen unendlich",
          "lim y debajo n tiende a infinito", "lim con sotto n tende a infinito"]),
        ("<mover><mi>a</mi><mi>b</mi></mover>",
         ["a over b", "a avec au-dessus b", "a darüber b", "a y encima b", "a con sopra b"]),
        ("<mover><mi>x</mi><mo>^</mo></mover><mo>=</mo><mover><mi>y</mi><mo>¯</mo></mover>",
         ["x hat equals y bar", "x accent circonflexe égale y barre", "x Zirkumflex gleich y Überstrich", "x circunflejo igual a y barra",
          "x accento circonflesso uguale a y barra sopra"]),
        // Most languages name a vector before its letter.
        ("<mover><mi>v</mi><mo>→</mo></mover>", ["v vector", "vecteur v", "Vektor v", "vector v", "vettore v"]),
        ("<mmultiscripts><mi>C</mi><mi>k</mi><none/><mprescripts/><mi>n</mi><none/></mmultiscripts>",
         ["C right subscript k left subscript n", "C indice droite k indice gauche n",
          "C rechter unterer Index k linker unterer Index n", "C subíndice derecho k subíndice izquierdo n",
          "C pedice destro k pedice sinistro n"]),
        ("<mtable><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr><mtr><mtd><mi>c</mi></mtd><mtd><mi>d</mi></mtd></mtr></mtable>",
         ["table with 2 rows row 1: a , b row 2: c , d", "tableau de 2 lignes ligne 1 : a , b ligne 2 : c , d",
          "Tabelle mit 2 Zeilen Zeile 1: a , b Zeile 2: c , d", "tabla de 2 filas fila 1: a , b fila 2: c , d",
          "tabella di 2 righe riga 1: a , b riga 2: c , d"]),
        ("<mtable><mtr><mtd><mn>0</mn></mtd></mtr></mtable>",
         ["table with 1 row row 1: 0", "tableau de 1 ligne ligne 1 : 0", "Tabelle mit 1 Zeile Zeile 1: 0",
          "tabla de 1 fila fila 1: 0", "tabella di 1 riga riga 1: 0"]),
        ("<mfenced open=\"[\" close=\"]\"><mi>a</mi><mi>b</mi></mfenced>",
         ["open bracket a , b close bracket", "crochet ouvrant a , b crochet fermant",
          "eckige Klammer auf a , b eckige Klammer zu", "abre corchete a , b cierra corchete",
          "aperta parentesi quadra a , b chiusa parentesi quadra"]),
        ("<mi>f</mi><mo>(</mo><mi>a</mi><mo>+</mo><mi>b</mi><mo>)</mo>",
         ["f open paren a plus b close paren", "f parenthèse ouvrante a plus b parenthèse fermante",
          "f Klammer auf a plus b Klammer zu", "f abre paréntesis a más b cierra paréntesis",
          "f aperta parentesi a più b chiusa parentesi"]),
        ("<mi>a</mi><mo>≤</mo><mi>b</mi><mo>×</mo><mi>c</mi><mo>≠</mo><mo>−</mo><mn>3</mn>",
         ["a is less than or equal to b times c is not equal to minus 3",
          "a est inférieur ou égal à b fois c est différent de moins 3", "a kleiner oder gleich b mal c ungleich minus 3",
          "a es menor o igual que b por c es distinto de menos 3", "a è minore o uguale a b per c è diverso da meno 3"]),
        ("<mi>x</mi><mo>∈</mo><mi>A</mi><mo>∪</mo><mi>B</mi><mo>⇒</mo><mi>x</mi><mo>&lt;</mo><mn>5</mn><mo>!</mo>",
         ["x is in A union B implies x is less than 5 factorial",
          "x appartient à A union B implique x est inférieur à 5 factorielle",
          "x Element von A vereinigt mit B impliziert x kleiner als 5 Fakultät",
          "x pertenece a A unión B implica x es menor que 5 factorial",
          "x appartiene a A unione B implica x è minore di 5 fattoriale"]),
        ("<mstack><mscarries><mn>1</mn><mn>1</mn><none/></mscarries><mn>456</mn><msrow><mo>+</mo><mn>278</mn></msrow><msline/><mn>734</mn></mstack>",
         ["stack with 3 rows alignment decimal point carries or borrows: column minus 3: above one column minus 2: above one column minus 1: blank row 1: column minus 3: four column minus 2: five column minus 1: six row 2: column minus 4: plus column minus 3: two column minus 2: seven column minus 1: eight line across the whole stack row 3: column minus 3: seven column minus 2: three column minus 1: four end stack",
          "opération posée de 3 lignes alignement sur le séparateur décimal retenues ou emprunts : colonne moins 3: au-dessus un colonne moins 2: au-dessus un colonne moins 1: vide ligne 1 : colonne moins 3: quatre colonne moins 2: cinq colonne moins 1: six ligne 2 : colonne moins 4: plus colonne moins 3: deux colonne moins 2: sept colonne moins 1: huit trait sur toute la largeur de l’opération ligne 3 : colonne moins 3: sept colonne moins 2: trois colonne moins 1: quatre fin de l'opération",
          "schriftliche Rechnung mit 3 Zeilen Ausrichtung am Dezimaltrennzeichen Überträge oder Entlehnungen: Spalte minus 3: oben eins Spalte minus 2: oben eins Spalte minus 1: leer Zeile 1: Spalte minus 3: vier Spalte minus 2: fünf Spalte minus 1: sechs Zeile 2: Spalte minus 4: plus Spalte minus 3: zwei Spalte minus 2: sieben Spalte minus 1: acht Strich über die gesamte Rechnung Zeile 3: Spalte minus 3: sieben Spalte minus 2: drei Spalte minus 1: vier Ende der Rechnung",
          "operación en columna de 3 filas alineación en el separador decimal acarreos o préstamos: columna menos 3: arriba uno columna menos 2: arriba uno columna menos 1: vacío fila 1: columna menos 3: cuatro columna menos 2: cinco columna menos 1: seis fila 2: columna menos 4: más columna menos 3: dos columna menos 2: siete columna menos 1: ocho línea en todo el ancho de la operación fila 3: columna menos 3: siete columna menos 2: tres columna menos 1: cuatro fin de la operación",
          "operazione in colonna di 3 righe allineamento al separatore decimale riporti o prestiti: colonna meno 3: sopra uno colonna meno 2: sopra uno colonna meno 1: vuoto riga 1: colonna meno 3: quattro colonna meno 2: cinque colonna meno 1: sei riga 2: colonna meno 4: più colonna meno 3: due colonna meno 2: sette colonna meno 1: otto linea su tutta la larghezza dell’operazione riga 3: colonna meno 3: sette colonna meno 2: tre colonna meno 1: quattro fine dell'operazione"]),
        ("<mstack><mscarries crossout=\"updiagonalstrike\"><mn>4</mn><none/></mscarries><mn>52</mn><msrow><mo>−</mo><mn>7</mn></msrow><msline/><mn>45</mn></mstack>",
         ["stack with 3 rows alignment decimal point carries or borrows: column minus 2: above four with the column's digit crossed out upward diagonal strike column minus 1: blank row 1: column minus 2: five column minus 1: two row 2: column minus 2: minus column minus 1: seven line across the whole stack row 3: column minus 2: four column minus 1: five end stack",
          "opération posée de 3 lignes alignement sur le séparateur décimal retenues ou emprunts : colonne moins 2: au-dessus quatre avec le chiffre de la colonne barré trait diagonal montant colonne moins 1: vide ligne 1 : colonne moins 2: cinq colonne moins 1: deux ligne 2 : colonne moins 2: moins colonne moins 1: sept trait sur toute la largeur de l’opération ligne 3 : colonne moins 2: quatre colonne moins 1: cinq fin de l'opération",
          "schriftliche Rechnung mit 3 Zeilen Ausrichtung am Dezimaltrennzeichen Überträge oder Entlehnungen: Spalte minus 2: oben vier mit durchgestrichener Ziffer in dieser Spalte aufsteigender diagonaler Strich Spalte minus 1: leer Zeile 1: Spalte minus 2: fünf Spalte minus 1: zwei Zeile 2: Spalte minus 2: minus Spalte minus 1: sieben Strich über die gesamte Rechnung Zeile 3: Spalte minus 2: vier Spalte minus 1: fünf Ende der Rechnung",
          "operación en columna de 3 filas alineación en el separador decimal acarreos o préstamos: columna menos 2: arriba cuatro con la cifra de la columna tachada tachado diagonal ascendente columna menos 1: vacío fila 1: columna menos 2: cinco columna menos 1: dos fila 2: columna menos 2: menos columna menos 1: siete línea en todo el ancho de la operación fila 3: columna menos 2: cuatro columna menos 1: cinco fin de la operación",
          "operazione in colonna di 3 righe allineamento al separatore decimale riporti o prestiti: colonna meno 2: sopra quattro con la cifra della colonna barrata barratura diagonale ascendente colonna meno 1: vuoto riga 1: colonna meno 2: cinque colonna meno 1: due riga 2: colonna meno 2: meno colonna meno 1: sette linea su tutta la larghezza dell’operazione riga 3: colonna meno 2: quattro colonna meno 1: cinque fine dell'operazione"]),
        ("<mlongdiv><mn>3</mn><mn>41</mn><mn>123</mn><mn>12</mn><msline/><mn>3</mn><mn>3</mn><msline/><mn>0</mn></mlongdiv>",
         ["long division with 4 working rows divisor left, result above alignment decimal point divisor: three dividend: column minus 3: one column minus 2: two column minus 1: three result: column minus 2: four column minus 1: one row 1: column minus 2: one column minus 1: two line across the whole stack row 2: column minus 1: three row 3: column minus 1: three line across the whole stack row 4: column minus 1: zero end long division",
          "division posée avec 4 lignes de calcul diviseur à gauche, résultat au-dessus alignement sur le séparateur décimal diviseur : trois dividende : colonne moins 3: un colonne moins 2: deux colonne moins 1: trois résultat : colonne moins 2: quatre colonne moins 1: un ligne 1 : colonne moins 2: un colonne moins 1: deux trait sur toute la largeur de l’opération ligne 2 : colonne moins 1: trois ligne 3 : colonne moins 1: trois trait sur toute la largeur de l’opération ligne 4 : colonne moins 1: zéro fin de la division",
          "schriftliche Division mit 4 Rechenzeilen Divisor links, Ergebnis oben Ausrichtung am Dezimaltrennzeichen Divisor: drei Dividend: Spalte minus 3: eins Spalte minus 2: zwei Spalte minus 1: drei Ergebnis: Spalte minus 2: vier Spalte minus 1: eins Zeile 1: Spalte minus 2: eins Spalte minus 1: zwei Strich über die gesamte Rechnung Zeile 2: Spalte minus 1: drei Zeile 3: Spalte minus 1: drei Strich über die gesamte Rechnung Zeile 4: Spalte minus 1: null Ende der Division",
          "división larga con 4 filas de cálculo divisor a la izquierda, resultado arriba alineación en el separador decimal divisor: tres dividendo: columna menos 3: uno columna menos 2: dos columna menos 1: tres resultado: columna menos 2: cuatro columna menos 1: uno fila 1: columna menos 2: uno columna menos 1: dos línea en todo el ancho de la operación fila 2: columna menos 1: tres fila 3: columna menos 1: tres línea en todo el ancho de la operación fila 4: columna menos 1: cero fin de la división",
          "divisione in colonna con 4 righe di calcolo divisore a sinistra, risultato sopra allineamento al separatore decimale divisore: tre dividendo: colonna meno 3: uno colonna meno 2: due colonna meno 1: tre risultato: colonna meno 2: quattro colonna meno 1: uno riga 1: colonna meno 2: uno colonna meno 1: due linea su tutta la larghezza dell’operazione riga 2: colonna meno 1: tre riga 3: colonna meno 1: tre linea su tutta la larghezza dell’operazione riga 4: colonna meno 1: zero fine della divisione"]),
        ("<mlongdiv><mn>3</mn><none/><mn>6</mn><mn>6</mn></mlongdiv>",
         ["long division with 1 working row divisor left, result above alignment decimal point divisor: three dividend: column minus 1: six row 1: column minus 1: six end long division",
          "division posée avec 1 ligne de calcul diviseur à gauche, résultat au-dessus alignement sur le séparateur décimal diviseur : trois dividende : colonne moins 1: six ligne 1 : colonne moins 1: six fin de la division",
          "schriftliche Division mit 1 Rechenzeile Divisor links, Ergebnis oben Ausrichtung am Dezimaltrennzeichen Divisor: drei Dividend: Spalte minus 1: sechs Zeile 1: Spalte minus 1: sechs Ende der Division",
          "división larga con 1 fila de cálculo divisor a la izquierda, resultado arriba alineación en el separador decimal divisor: tres dividendo: columna menos 1: seis fila 1: columna menos 1: seis fin de la división",
          "divisione in colonna con 1 riga di calcolo divisore a sinistra, risultato sopra allineamento al separatore decimale divisore: tre dividendo: colonna meno 1: sei riga 1: colonna meno 1: sei fine della divisione"]),
    ]

    func testReadsEveryKindOfPhraseInEachLanguage() throws {
        XCTAssertEqual(MathReading.languages, ["en", "fr", "de", "es", "it"])
        for (body, readings) in Self.readings {
            XCTAssertEqual(readings.count, MathReading.languages.count, body)
            for (language, expected) in zip(MathReading.languages, readings) {
                XCTAssertEqual(try reading(body, language), expected, "\(language): \(body)")
            }
        }
    }

    func testEnglishPropertyIsTheEnglishReading() throws {
        for (body, readings) in Self.readings {
            let node = try node(body)
            XCTAssertEqual(node.accessibilityDescription, readings[0], body)
            XCTAssertEqual(node.accessibilityDescription(locale: Locale(identifier: "en")),
                           MathReading(text: node.accessibilityDescription, language: "en"), body)
        }
    }

    /// The names 0.1.0 gave operators and accents, which hosts quote. Every language reaches its
    /// own names through the same characters, so this also pins what each character means.
    func testEnglishNamesAreUnchanged() {
        let operators = [
            "+": "plus", "\u{2212}": "minus", "-": "minus", "±": "plus or minus", "∓": "minus or plus",
            "×": "times", "·": "times", "⋅": "times", "∗": "times", "*": "times", "÷": "divided by", "/": "over",
            "=": "equals", "≠": "is not equal to", "<": "is less than", ">": "is greater than",
            "≤": "is less than or equal to", "≥": "is greater than or equal to", "≈": "is approximately equal to",
            "≡": "is equivalent to", "∼": "is similar to", "∝": "is proportional to", "→": "goes to", "←": "left arrow",
            "⇒": "implies", "⇔": "if and only if", "∈": "is in", "∉": "is not in", "⊂": "is a subset of",
            "⊆": "is a subset of or equal to", "∪": "union", "∩": "intersection", "∑": "the sum", "∏": "the product",
            "∫": "the integral", "∮": "the contour integral", "∂": "partial", "∇": "nabla", "√": "square root",
            "′": "prime", "″": "double prime", "!": "factorial", "%": "percent", "°": "degrees", "∞": "infinity",
            "(": "open paren", ")": "close paren", "[": "open bracket", "]": "close bracket",
            "{": "open brace", "}": "close brace", "|": "vertical bar", "‖": "double vertical bar",
            "⟨": "open angle bracket", "⟩": "close angle bracket", "…": "dot dot dot", "⋯": "dot dot dot",
            "∀": "for all", "∃": "there exists", "¬": "not", "∧": "and", "∨": "or",
        ]
        let accents = [
            "^": "hat", "ˆ": "hat", "\u{0302}": "hat", "~": "tilde", "˜": "tilde", "\u{0303}": "tilde",
            "¯": "bar", "‾": "bar", "\u{0305}": "bar", "_": "underbar", "˙": "dot", "\u{0307}": "dot",
            "¨": "double dot", "\u{0308}": "double dot", "→": "vector", "\u{20D7}": "vector", "ˇ": "check",
            "˘": "breve", "⏞": "top brace", "⏟": "bottom brace",
        ]
        for (text, name) in operators {
            XCTAssertEqual(english(MathMLNode(name: "mo", text: text)), name, text)
        }
        for (text, name) in accents {
            let accented = MathMLNode(name: "mover", children: [MathMLNode(name: "mi", text: "x"), MathMLNode(name: "mo", text: text)])
            XCTAssertEqual(english(accented), "x \(name)", text)
        }
    }

    /// Pretty-printed markup pads its tokens. The padding is not part of a word, and must not
    /// hide an operator or a power from its name.
    func testPaddedTokensAreReadAsTheirText() throws {
        let body = "<mi>a</mi><mo> + </mo><mi>\n  b\n</mi><mo>\t=</mo><msup><mi> x</mi><mn> 2 </mn></msup><mtext> if  it  fits </mtext>"
        XCTAssertEqual(try reading(body, "en"), "a plus b equals x squared if it fits")
        XCTAssertEqual(try reading(body, "fr"), "a plus b égale x au carré if it fits")
        XCTAssertEqual(try node(body).accessibilityDescription, "a plus b equals x squared if it fits")
    }

    func testLocalesMatchOnLanguageAndFallBackToEnglish() throws {
        let node = try node("<mfrac><mrow><mi>a</mi><mo>+</mo><mn>1</mn></mrow><msqrt><mi>b</mi></msqrt></mfrac>")
        let regions = ["fr": ["fr", "fr-CA", "fr_CH", "fr-Latn-BE", "fra"], "de": ["de_AT", "de-CH", "de-Latn-DE", "deu"],
                       "es": ["es-419", "es_MX", "es-ES", "spa"], "it": ["it-CH", "it_IT"], "en": ["en_AU", "en-US-POSIX"]]
        for (language, identifiers) in regions {
            let expected = node.accessibilityDescription(locale: Locale(identifier: language))
            XCTAssertEqual(expected.language, language)
            for identifier in identifiers {
                XCTAssertEqual(node.accessibilityDescription(locale: Locale(identifier: identifier)), expected, identifier)
            }
        }
        XCTAssertEqual(node.accessibilityDescription(locale: Locale(identifier: "fr")).text,
                       "début de fraction a plus 1 sur racine carrée de b fin de fraction")
        // A supported region returns its actual voice tag even where the words match its base.
        XCTAssertEqual(node.accessibilityDescription(locale: Locale(identifier: "en-GB")),
                       MathReading(text: node.accessibilityDescription, language: "en-GB"))
        // No vocabulary: the whole reading is English, and says so, so a host can pick a matching voice.
        for identifier in ["ja", "pt-BR", "nl_NL", "zh-Hant-TW", "und", "", "x-private"] {
            XCTAssertEqual(node.accessibilityDescription(locale: Locale(identifier: identifier)),
                           MathReading(text: "start fraction a plus 1 over the square root of b end fraction", language: "en"),
                           identifier)
        }
    }

    // MARK: Completeness

    private static let vocabularies = MathReading.vocabularies
    /// Every operator text and accent text that has a name.
    private static let symbols = MathSymbols.names.keys.sorted(), accents = MathAccents.names.keys.sorted()

    func testEveryVocabularyNamesEverySymbolAndAccent() {
        XCTAssertGreaterThan(Self.symbols.count, 55)
        for words in Self.vocabularies {
            for text in Self.symbols {
                XCTAssertFalse((words.symbols[text] ?? "").isEmpty, "\(words.language): \(text)")
            }
            for text in Self.accents {
                let reading = words.accents[text]?.reading(on: "x") ?? ""
                XCTAssertTrue(reading.hasPrefix("x ") || reading.hasSuffix(" x"), "\(words.language): \(text)")
                XCTAssertGreaterThan(reading.count, 3, "\(words.language): \(text)")
            }
        }
    }

    /// Every template says each operand it is given once, with words of its own around them.
    func testEveryPhraseKeepsItsOperands() {
        for words in Self.vocabularies {
            let phrases: [(String, [String])] = [
                (words.fraction("Q1", "Q2", simple: true), ["Q1", "Q2"]), (words.fraction("Q1", "Q2", simple: false), ["Q1", "Q2"]),
                (words.squared("Q1"), ["Q1"]), (words.cubed("Q1"), ["Q1"]), (words.primed("Q1"), ["Q1"]),
                (words.power("Q1", "Q2", simple: true), ["Q1", "Q2"]), (words.power("Q1", "Q2", simple: false), ["Q1", "Q2"]),
                (words.subscripted("Q1", "Q2"), ["Q1", "Q2"]), (words.squareRoot("Q1", closed: false), ["Q1"]),
                (words.squareRoot("Q1", closed: true), ["Q1"]), (words.cubeRoot("Q1"), ["Q1"]),
                (words.root("Q1", index: "Q2"), ["Q1", "Q2"]), (words.under("Q1", "Q2"), ["Q1", "Q2"]),
                (words.over("Q1", "Q2"), ["Q1", "Q2"]), (words.limits("Q1", from: "Q2", to: "Q3"), ["Q1", "Q2", "Q3"]),
                (words.table(rows: 1), ["1"]), (words.table(rows: 12), ["12"]),
                (words.row(12), []), (words.stack(rows: 1), ["1"]), (words.stack(rows: 12), ["12"]), (words.endStack, []),
                (words.line, []), (words.carries("Q1"), ["Q1"]), (words.blank, []), (words.crossedOut("Q1"), ["Q1"]),
                (words.longDivision(rows: 0), []), (words.longDivision(rows: 1), ["1"]), (words.longDivision(rows: 12), ["12"]),
                (words.divisor("Q1"), ["Q1"]), (words.dividend("Q1"), ["Q1"]), (words.result("Q1"), ["Q1"]),
                (words.endLongDivision, []),
            ]
            let scripts = MathScriptPosition.allCases.flatMap { position in
                [true, false].map { (words.script("Q1", position: position, simple: $0), ["Q1"]) }
            }
            for (phrase, operands) in phrases + scripts {
                let said = phrase.split(separator: " ").map(String.init)
                for operand in operands { XCTAssertEqual(said.filter { $0 == operand }.count, 1, "\(words.language): \(phrase)") }
                XCTAssertGreaterThan(said.count, operands.count, "\(words.language): \(phrase)")
                XCTAssertEqual(phrase, said.joined(separator: " "), "\(words.language): single spaces, none at the ends")
            }
            XCTAssertTrue(words.row(12).contains("12"), words.language)
            // Singular and plural differ.
            XCTAssertNotEqual(words.table(rows: 1).replacingOccurrences(of: "1", with: "2"), words.table(rows: 2), words.language)
            XCTAssertNotEqual(words.stack(rows: 1).replacingOccurrences(of: "1", with: "2"), words.stack(rows: 2), words.language)
            XCTAssertNotEqual(words.longDivision(rows: 1).replacingOccurrences(of: "1", with: "2"), words.longDivision(rows: 2),
                              words.language)
        }
    }

    /// A formula with every symbol, accent and construct the speaker has words for.
    private func everything() -> MathMLNode {
        func token(_ name: String, _ text: String) -> MathMLNode { MathMLNode(name: name, text: text) }
        func element(_ name: String, _ children: [MathMLNode], _ attributes: [String: String] = [:]) -> MathMLNode {
            MathMLNode(name: name, attributes: attributes, children: children)
        }
        let x = token("mi", "ξ"), two = token("mn", "2"), three = token("mn", "3"), sum = element("mrow", [x, token("mo", "+"), x])
        let symbols = Self.symbols.map { token("mo", $0) }
        let accents = Self.accents.map { element("mover", [x, token("mo", $0)]) }
        let row = element("mtr", [element("mtd", [x]), element("mtd", [x])])
        let carries = element("mscarries", [x, element("none", []), element("mscarry", [x], ["crossout": "none"])],
                              ["crossout": "updiagonalstrike"])
        let rows = [carries, element("msrow", [token("mo", "+"), x]), element("msline", []), element("msrow", []), x]
        let constructs = [
            element("mfrac", [x, x]), element("mfrac", [sum, x]), element("msup", [x, two]), element("msup", [x, three]),
            element("msup", [x, token("mo", "′")]), element("msup", [x, x]), element("msup", [x, sum]), element("msub", [x, x]),
            element("msubsup", [x, x, x]), element("msqrt", [x]), element("msqrt", [sum]), element("mroot", [x, two]),
            element("mroot", [x, three]), element("mroot", [x, x]), element("munder", [x, x]), element("mover", [x, x]),
            element("munderover", [x, x, x]), element("mmultiscripts", [x, x, x]), element("mtable", [row]),
            element("mtable", [row, row]), element("mfenced", [x, x]), element("mstack", [x]), element("mstack", rows),
            element("mlongdiv", [x, x, x]), element("mlongdiv", [x, x, x, x]), element("mlongdiv", [x, x] + rows + rows),
        ]
        return element("math", symbols + accents + constructs)
    }

    /// A reading is in one language throughout. No symbol is left as written, and the only words
    /// a language shares with the English reading are ones that are also its own.
    func testNoVocabularyBorrowsFromEnglish() {
        let node = everything()
        func words(_ language: String) -> Set<String> {
            let reading = node.accessibilityDescription(locale: Locale(identifier: language))
            XCTAssertEqual(reading.language, language)
            // The hyphen is the one symbol that also spells words ("au-dessus").
            for symbol in (Self.symbols + Self.accents).joined().unicodeScalars where symbol != "-" {
                XCTAssertFalse(reading.text.unicodeScalars.contains(symbol), "\(language) leaves \(symbol) unnamed")
            }
            return Set(reading.text.split(separator: " ").map(String.init).filter { $0 != "ξ" && $0.contains(where: \.isLetter) })
        }
        let english = words("en")
        XCTAssertGreaterThan(english.count, 90)
        let shared = ["fr": ["contour", "cube", "diagonal", "division", "double", "fraction", "nabla", "plus", "point", "prime", "tilde", "union"],
                      "de": ["in", "minus", "plus", "proportional"], "it": ["a", "breve", "in", "nabla", "tilde"],
                      "es": ["a", "breve", "decimal", "diagonal", "divisor", "divisor:", "factorial", "integral", "nabla", "sub", "tilde", "vector", "vertical"]]
        for (language, cognates) in shared {
            let own = words(language)
            XCTAssertGreaterThan(own.count, 90, language)
            XCTAssertEqual(own.intersection(english).sorted(), cognates.sorted(), language)
        }
        XCTAssertEqual(Set(shared.keys).union(["en"]), Set(MathReading.languages))
    }

    // MARK: maction and semantics

    /// An `maction` and a `semantics` are read as the child that is drawn, in every language, and
    /// nothing is said of their other children, which would each read as a fraction.
    func testAnActionAndSemanticsAreReadAsTheChildThatIsDrawnInEachLanguage() throws {
        let hidden = "<mfrac><mi>p</mi><mi>q</mi></mfrac>"
        let annotations = "<annotation encoding=\"application/x-tex\">p/q</annotation>"
            + "<annotation-xml encoding=\"MathML-Presentation\">\(hidden)</annotation-xml>"
        for (body, readings) in Self.readings {
            let wrapped = [
                "<maction actiontype=\"toggle\" selection=\"2\">\(hidden)<mrow>\(body)</mrow>\(hidden)</maction>",
                "<semantics>\(annotations)<mrow>\(body)</mrow>\(hidden)\(annotations)</semantics>",
                "<semantics>\(annotations)<maction selection=\"3\">\(hidden)\(hidden)<mrow>\(body)</mrow></maction></semantics>",
            ]
            for (language, expected) in zip(MathReading.languages, readings) {
                for markup in wrapped { XCTAssertEqual(try reading(markup, language), expected, "\(language): \(markup)") }
            }
        }
    }

    /// Which child that is, for every `selection` and wherever the annotations stand: the one
    /// layout draws. The three children say different things and are of different widths, so the
    /// reading and the width each name one of them, and it has to be the same one.
    func testTheChildThatIsReadIsTheOneLayoutDraws() throws {
        let parts = ["<mn>1</mn>", "<mn>22</mn>", "<mn>333</mn>"], said = ["1", "22", "333"], all = parts.joined()
        let note = "<annotation encoding=\"TeX\">4444</annotation>"
        let xml = "<annotation-xml encoding=\"MathML-Presentation\"><mn>55555</mn></annotation-xml>"
        var cases: [(markup: String, shown: Int?)] = [("<maction>\(all)</maction>", 0), ("<maction selection=\"2\"/>", nil), ("<semantics/>", nil)]
        // A `selection` that is no number, or that names no child, shows the first.
        for (selection, shown) in [("1", 0), ("2", 1), ("3", 2), (" 2 ", 1), ("0", 0), ("4", 0), ("-1", 0), ("bogus", 0), ("", 0), ("99999999999999999999", 0),
                                   ("9223372036854775807", 0), ("-9223372036854775808", 0)] {
            cases.append(("<maction actiontype=\"toggle\" selection=\"\(selection)\">\(all)</maction>", shown))
        }
        cases += [
            ("<semantics>\(all)</semantics>", 0), ("<semantics>\(parts[1])\(note)\(xml)</semantics>", 1), ("<semantics>\(note)\(xml)\(parts[2])</semantics>", 2),
            ("<semantics>\(xml)\(parts[1])\(note)\(parts[2])</semantics>", 1),
            // Only annotations: nothing is drawn, and nothing is said.
            ("<semantics>\(note)</semantics>", nil), ("<semantics>\(note)\(xml)\(note)</semantics>", nil),
            // One inside the other, each choosing its own child.
            ("<maction selection=\"2\">\(parts[0])<semantics>\(note)<maction selection=\"3\">\(all)</maction>\(parts[1])</semantics></maction>", 2),
            ("<semantics>\(xml)<maction selection=\"2\">\(parts[0])<semantics>\(note)\(parts[1])</semantics>\(parts[2])</maction>\(note)</semantics>", 1),
            ("<semantics>\(note)<maction selection=\"9\"><semantics>\(xml)\(parts[2])</semantics>\(parts[0])</maction></semantics>", 2),
            ("<maction selection=\"2\">\(parts[0])<semantics>\(note)\(xml)</semantics>\(parts[2])</maction>", nil),
            // The first child that is no annotation stands for a `semantics` even when it shows nothing.
            ("<semantics>\(note)<maction/>\(parts[0])</semantics>", nil),
        ]
        for (markup, shown) in cases {
            XCTAssertEqual(try reading(markup, "en"), shown.map { said[$0] } ?? "", markup)
            XCTAssertEqual(try layout(markup).width, try shown.map { try layout(parts[$0]).width } ?? 0, accuracy: 0.01, "drawn: \(markup)")
        }
        // A host's tree may keep the text of an annotation, which the parser drops. It is not read either.
        let annotation = MathMLNode(name: "annotation", text: "x squared")
        XCTAssertEqual(english(MathMLNode(name: "semantics", children: [annotation, token("mi", "y")])), "y")
        XCTAssertEqual(english(MathMLNode(name: "semantics", children: [annotation])), "")
    }

    /// What encloses an `maction` or a `semantics` asks whether the child that is drawn is one
    /// word, not whether the first child is: a fraction, a power and a root say where they end
    /// only when it is not. Each formula reads as the one beside it, which is written without them.
    func testAnActionOrSemanticsIsOneWordWhenTheChildThatIsDrawnIs() throws {
        let sum = "<mrow><mi>a</mi><mo>+</mo><mi>b</mi></mrow>", note = "<annotation encoding=\"TeX\">a+b</annotation>"
        /// A sum and a letter, of which `selection` shows one.
        func action(_ selection: Int) -> String { "<maction selection=\"\(selection)\">\(sum)<mi>c</mi></maction>" }
        let pairs = [
            ("<mfrac>\(action(2))<semantics>\(note)<mi>b</mi></semantics></mfrac>", "<mfrac><mi>c</mi><mi>b</mi></mfrac>"),
            ("<mfrac>\(action(1))<mi>c</mi></mfrac>", "<mfrac>\(sum)<mi>c</mi></mfrac>"),
            ("<mfrac><mi>c</mi><semantics>\(note)\(sum)<mi>c</mi></semantics></mfrac>", "<mfrac><mi>c</mi>\(sum)</mfrac>"),
            ("<msup><mi>x</mi>\(action(2))</msup>", "<msup><mi>x</mi><mi>c</mi></msup>"),
            ("<msup><mi>x</mi>\(action(1))</msup>", "<msup><mi>x</mi>\(sum)</msup>"),
            ("<msqrt>\(action(2))</msqrt>", "<msqrt><mi>c</mi></msqrt>"), ("<msqrt>\(action(1))</msqrt>", "<msqrt>\(sum)</msqrt>"),
            // Through any number of them, and the rows and styles that hold one child.
            ("<msqrt><mstyle><semantics>\(note)<mrow>\(action(2))</mrow></semantics></mstyle></msqrt>", "<msqrt><mi>c</mi></msqrt>"),
            ("<msqrt><semantics>\(note)\(action(1))<mi>c</mi></semantics></msqrt>", "<msqrt>\(sum)</msqrt>"),
        ]
        for (wrapped, plain) in pairs {
            for language in MathReading.languages {
                XCTAssertEqual(try reading(wrapped, language), try reading(plain, language), "\(language): \(wrapped)")
            }
        }
        XCTAssertEqual(try pairs.map { try reading($0.0, "en") }, [
            "c over b", "start fraction a plus b over c end fraction", "start fraction c over a plus b end fraction", "x to the power of c",
            "x to the power of a plus b end power", "the square root of c", "the square root of a plus b end root", "the square root of c",
            "the square root of a plus b end root",
        ])
    }

    /// Finding the child that is drawn goes no deeper than a reading does, in a tree a host built
    /// deeper than the parser allows: every level here shows its second child.
    func testNestedActionsAndSemanticsAreReadWithinTheDepthBound() {
        let x = token("mi", "x"), other = token("mi", "y"), note = MathMLNode(name: "annotation", text: "note")
        func nested(_ levels: Int) -> MathMLNode {
            (0..<levels).reduce(x) { inner, level in
                level.isMultiple(of: 2) ? MathMLNode(name: "maction", attributes: ["selection": "2"], children: [other, inner])
                    : MathMLNode(name: "semantics", children: [note, inner, other])
            }
        }
        let shallow = nested(MathLimits.depth - 4), deep = nested(10_000), nothing = MathMLNode(name: "mrow")
        XCTAssertEqual(english(shallow), "x")
        XCTAssertEqual(english(MathMLNode(name: "msqrt", children: [shallow])), "the square root of x")
        XCTAssertEqual(english(MathMLNode(name: "mfrac", children: [shallow, shallow])), "x over x")
        // Past the bound nothing is said, and what encloses it reads as it does around nothing.
        XCTAssertEqual(english(deep), "")
        for name in ["msqrt", "mfrac", "msup"] {
            XCTAssertEqual(english(MathMLNode(name: name, children: [x, deep])), english(MathMLNode(name: name, children: [x, nothing])), name)
            XCTAssertEqual(english(MathMLNode(name: name, children: [deep, x])), english(MathMLNode(name: name, children: [nothing, x])), name)
        }
    }

    // MARK: mglyph

    private func glyph(_ alt: String?) -> MathMLNode {
        MathMLNode(name: "mglyph", attributes: alt.map { ["alt": $0, "src": "glyph.png"] } ?? ["src": "glyph.png"])
    }

    private func token(_ name: String, _ text: String, _ children: [MathMLNode] = []) -> MathMLNode {
        MathMLNode(name: name, children: children, text: text)
    }

    func testGlyphInATokenIsReadAsItsAlt() {
        // Each marker is the glyph at its position.
        XCTAssertEqual(english(token("mi", "\u{FFFC}", [glyph("smiley")])), "smiley")
        XCTAssertEqual(english(token("mtext", "a \u{FFFC} b", [glyph("right hook")])), "a right hook b")
        XCTAssertEqual(english(token("mtext", "x\u{FFFC}y\u{FFFC}", [glyph("cat"), glyph("dog")])), "x cat y dog")
        // Glyphs past the last marker follow the text, in order: hosts may build tokens without markers.
        XCTAssertEqual(english(token("mtext", "see", [glyph("A"), glyph("B")])), "see A B")
        XCTAssertEqual(english(token("mtext", "\u{FFFC} then", [glyph("A"), glyph("B")])), "A then B")
        XCTAssertEqual(english(token("mi", "", [glyph("smiley")])), "smiley")
        // A marker without a glyph, and a glyph without alt, say nothing.
        XCTAssertEqual(english(token("mtext", "a\u{FFFC}b")), "a b")
        XCTAssertEqual(english(token("mtext", "a\u{FFFC}b\u{FFFC}", [glyph("g")])), "a g b")
        XCTAssertEqual(english(token("mi", "\u{FFFC}", [glyph(nil)])), "")
        XCTAssertEqual(english(token("mtext", "a\u{FFFC}b\u{FFFC}c", [glyph(nil), glyph("g")])), "a b g c")
        // Only mglyph children stand behind markers, and alt is normalized like token text.
        XCTAssertEqual(english(token("mtext", "a\u{FFFC}", [MathMLNode(name: "malignmark"), glyph("  two\n words ")])), "a two words")
        // A glyph that is an operator is named like one, in the reading's language.
        let sum = MathMLNode(name: "mrow", children: [token("mi", "a"), token("mo", "\u{FFFC}", [glyph("+")]), token("mi", "b")])
        XCTAssertEqual(english(sum), "a plus b")
        XCTAssertEqual(sum.accessibilityDescription(locale: Locale(identifier: "es")).text, "a más b")
        XCTAssertEqual(english(MathMLNode(name: "msup", children: [token("mi", "x"), token("mn", "\u{FFFC}", [glyph("2")])])), "x squared")
    }

    func testRowLevelGlyphIsReadAsItsAlt() {
        XCTAssertEqual(english(glyph(" a  star ")), "a star")
        XCTAssertEqual(english(glyph(nil)), "")
        let row = MathMLNode(name: "math", children: [token("mi", "x"), token("mo", "="), glyph("star"), glyph(nil)])
        XCTAssertEqual(english(row), "x equals star")
        XCTAssertEqual(row.accessibilityDescription(locale: Locale(identifier: "de")), MathReading(text: "x gleich star", language: "de"))
        // Like a token, it is one word to what encloses it.
        XCTAssertEqual(english(MathMLNode(name: "mfrac", children: [glyph("half moon"), token("mn", "2")])), "half moon over 2")
        XCTAssertEqual(english(MathMLNode(name: "msqrt", children: [glyph("star")])), "the square root of star")
    }

    // MARK: Elementary math

    func testStackIsReadRowByRow() throws {
        // MathML 3 §3.6's subtraction: a borrow above each digit it crosses out, and the last column spared.
        let borrows = """
        <mstack>
          <mscarries crossout='updiagonalstrike'>
            <mn>2</mn> <mn>12</mn> <mscarry crossout='none'> <none/> </mscarry>
          </mscarries>
          <mn>2,327</mn>
          <msrow> <mo>-</mo> <mn> 1,156</mn> </msrow>
          <msline/>
          <mn>1,171</mn>
        </mstack>
        """
        XCTAssertEqual(try reading(borrows, "en"), "stack with 3 rows alignment decimal point carries or borrows: column minus 3: above two with the column's digit crossed out upward diagonal strike column minus 2: above one two with the column's digit crossed out upward diagonal strike column minus 1: above blank row 1: column minus 5: two column minus 4: comma column minus 3: three column minus 2: two column minus 1: seven row 2: column minus 6: minus column minus 5: one column minus 4: comma column minus 3: one column minus 2: five column minus 1: six line across the whole stack row 3: column minus 5: one column minus 4: comma column minus 3: one column minus 2: seven column minus 1: one end stack")
        // A carry may cross out without replacing, or override the row's crossout.
        let crossouts = """
        <mstack><mscarries><mscarry crossout="updiagonalstrike"><none/></mscarry><mscarry crossout="none verticalstrike"><mn>10</mn></mscarry><mn>1</mn></mscarries><mn>523</mn></mstack>
        """
        XCTAssertEqual(try reading(crossouts, "en"), "stack with 1 row alignment decimal point carries or borrows: column minus 3: above blank with the column's digit crossed out upward diagonal strike column minus 2: above one zero with the column's digit crossed out vertical strike column minus 1: above one row 1: column minus 3: five column minus 2: two column minus 1: three end stack")
        // Its multiplication: groups shift their rows, whose logical columns retain those positions.
        let product = """
        <mstack>
          <msgroup><mn>123</mn><msrow><mo>×</mo><mn>321</mn></msrow></msgroup>
          <msline/>
          <msgroup shift="1"><mn>123</mn><mn>246</mn><mn>369</mn></msgroup>
          <msline/>
          <mn>39483</mn>
        </mstack>
        """
        XCTAssertEqual(try reading(product, "en"),
                       "stack with 6 rows alignment decimal point row 1: column minus 3: one column minus 2: two column minus 1: three row 2: column minus 4: times column minus 3: three column minus 2: two column minus 1: one line across the whole stack row 3: column minus 3: one column minus 2: two column minus 1: three row 4: column minus 4: two column minus 3: four column minus 2: six row 5: column minus 5: three column minus 4: six column minus 3: nine line across the whole stack row 6: column minus 5: three column minus 4: nine column minus 3: four column minus 2: eight column minus 1: three end stack")
        XCTAssertEqual(try reading(product, "fr"), "opération posée de 6 lignes alignement sur le séparateur décimal ligne 1 : colonne moins 3: un colonne moins 2: deux colonne moins 1: trois ligne 2 : colonne moins 4: fois colonne moins 3: trois colonne moins 2: deux colonne moins 1: un trait sur toute la largeur de l’opération ligne 3 : colonne moins 3: un colonne moins 2: deux colonne moins 1: trois ligne 4 : colonne moins 4: deux colonne moins 3: quatre colonne moins 2: six ligne 5 : colonne moins 5: trois colonne moins 4: six colonne moins 3: neuf trait sur toute la largeur de l’opération ligne 6 : colonne moins 5: trois colonne moins 4: neuf colonne moins 3: quatre colonne moins 2: huit colonne moins 1: trois fin de l'opération")
        // Empty columns are explicit; an empty row is blank.
        XCTAssertEqual(try reading("<mstack><msrow><mo>+</mo><none/><mn>33</mn></msrow><msrow/><none/><msrow><none/></msrow></mstack>", "en"),
                       "stack with 4 rows alignment decimal point row 1: column minus 4: plus column minus 3: blank column minus 2: three column minus 1: three row 2: blank row 3: column minus 1: blank row 4: column minus 1: blank end stack")
        XCTAssertEqual(try reading("<mstack/>", "en"), "stack with 0 rows alignment decimal point end stack")
        XCTAssertEqual(try reading("<mstack><msline length=\"1\"/><mn>0.3333</mn></mstack>", "en"),
                       "stack with 1 row alignment decimal point line column minus 1: column minus 1: row 1: column minus 1: zero column 0: point column 1: three column 2: three column 3: three column 4: three end stack")
        // A stack is one operand of what holds it.
        XCTAssertEqual(try reading("<mstack><mn>1</mn><mn>2</mn></mstack><mo>=</mo><mn>3</mn>", "en"),
                       "stack with 2 rows alignment decimal point row 1: column minus 1: one row 2: column minus 1: two end stack equals 3")
    }

    func testLongDivisionNamesItsParts() throws {
        // MathML 3 §3.6's long division: 1306 ÷ 3.
        let division = """
        <mlongdiv longdivstyle="lefttop">
          <mn> 3 </mn>
          <mn> 435.3</mn>
          <mn> 1306</mn>
          <msgroup position="2" shift="-1">
            <msgroup> <mn> 12</mn> <msline length="2"/> </msgroup>
            <msgroup> <mn> 10</mn> <mn> 9</mn> <msline length="2"/> </msgroup>
            <msgroup> <mn> 16</mn> <mn> 15</mn> <msline length="2"/> <mn> 1.0</mn> </msgroup>
            <msgroup position='-1'> <mn> 9</mn> <msline length="3"/> <mn> 1</mn> </msgroup>
          </msgroup>
        </mlongdiv>
        """
        XCTAssertEqual(try reading(division, "en"), "long division with 8 working rows divisor left, result above alignment decimal point divisor: three dividend: column minus 4: one column minus 3: three column minus 2: zero column minus 1: six result: column minus 3: four column minus 2: three column minus 1: five column 0: point column 1: three row 1: column minus 4: one column minus 3: two line column minus 4: column minus 3: row 2: column minus 3: one column minus 2: zero row 3: column minus 2: nine line column minus 3: column minus 2: row 4: column minus 2: one column minus 1: six row 5: column minus 2: one column minus 1: five line column minus 2: column minus 1: row 6: column minus 1: one column 0: point column 1: zero row 7: column 1: nine line column minus 1: column 1: row 8: column 1: one end long division")
        XCTAssertEqual(try reading(division, "de"), "schriftliche Division mit 8 Rechenzeilen Divisor links, Ergebnis oben Ausrichtung am Dezimaltrennzeichen Divisor: drei Dividend: Spalte minus 4: eins Spalte minus 3: drei Spalte minus 2: null Spalte minus 1: sechs Ergebnis: Spalte minus 3: vier Spalte minus 2: drei Spalte minus 1: fünf Spalte 0: Punkt Spalte 1: drei Zeile 1: Spalte minus 4: eins Spalte minus 3: zwei Strich Spalte minus 4: Spalte minus 3: Zeile 2: Spalte minus 3: eins Spalte minus 2: null Zeile 3: Spalte minus 2: neun Strich Spalte minus 3: Spalte minus 2: Zeile 4: Spalte minus 2: eins Spalte minus 1: sechs Zeile 5: Spalte minus 2: eins Spalte minus 1: fünf Strich Spalte minus 2: Spalte minus 1: Zeile 6: Spalte minus 1: eins Spalte 0: Punkt Spalte 1: null Zeile 7: Spalte 1: neun Strich Spalte minus 1: Spalte 1: Zeile 8: Spalte 1: eins Ende der Division")
        // No working, and parts the markup leaves out, are not announced.
        XCTAssertEqual(try reading("<mlongdiv><mn>3</mn><mn>41</mn><mn>123</mn></mlongdiv>", "en"),
                       "long division divisor left, result above alignment decimal point divisor: three dividend: column minus 3: one column minus 2: two column minus 1: three result: column minus 2: four column minus 1: one end long division")
        XCTAssertEqual(try reading("<mlongdiv><none/><none/><mn>123</mn></mlongdiv>", "en"), "long division divisor left, result above alignment decimal point dividend: column minus 3: one column minus 2: two column minus 1: three end long division")
        XCTAssertEqual(try reading("<mlongdiv><mn>3</mn></mlongdiv>", "en"), "long division divisor left, result above alignment decimal point divisor: three end long division")
        XCTAssertEqual(try reading("<mlongdiv/>", "en"), "long division divisor left, result above alignment decimal point end long division")
        // Borrows marked above the dividend are read before it; the dividend is the first row of digits.
        XCTAssertEqual(try reading("<mlongdiv><mn>7</mn><mn>14</mn><mscarries><mn>1</mn><none/></mscarries><mn>98</mn><mn>7</mn></mlongdiv>", "en"),
                       "long division with 1 working row divisor left, result above alignment decimal point divisor: seven carries or borrows: column minus 2: above one column minus 1: blank dividend: column minus 2: nine column minus 1: eight result: column minus 2: one column minus 1: four row 1: column minus 1: seven end long division")
        // Compound operands retain their mathematical structure.
        XCTAssertEqual(try reading("<mlongdiv><msup><mi>x</mi><mn>2</mn></msup><mi>q</mi><msrow><mi>x</mi><mo>+</mo><mn>1</mn></msrow></mlongdiv>", "it"),
                       "divisione in colonna divisore a sinistra, risultato sopra allineamento al separatore decimale divisore: x al quadrato dividendo: colonna meno 3: x colonna meno 2: più colonna meno 1: uno risultato: q fine della divisione")
    }

    // MARK: Bounds

    func testSpeechOfUntrustedInputIsBounded() {
        let x = MathMLNode(name: "mi", text: "x"), one = MathMLNode(name: "mn", text: "1")
        func words(_ node: MathMLNode, _ language: String = "fr") -> Int {
            node.accessibilityDescription(locale: Locale(identifier: language)).text.split(separator: " ").count
        }
        // Deep: nothing past the depth bound is visited, whichever element asks about its children.
        let deep = (0..<10_000).reduce(x) { inner, _ in MathMLNode(name: "mrow", children: [inner]) }
        XCTAssertEqual(deep.accessibilityDescription, "")
        for name in ["mfrac", "msup", "msqrt", "mroot", "mstack", "mlongdiv", "mtable", "munderover"] {
            XCTAssertLessThan(words(MathMLNode(name: name, children: [deep, deep, deep])), 20, name)
        }
        let groups = (0..<10_000).reduce(one) { inner, _ in MathMLNode(name: "msgroup", children: [inner, inner]) }
        XCTAssertLessThan(words(MathMLNode(name: "mstack", children: [groups])), 20)
        // Large: reading stops at the node bound.
        let limit = MathLimits.nodes
        XCTAssertEqual(words(MathMLNode(name: "math", children: Array(repeating: x, count: 300_000))), limit - 1)
        let rows = Array(repeating: one, count: 300_000)
        XCTAssertLessThanOrEqual(words(MathMLNode(name: "mstack", children: rows)), 12 * limit)
        XCTAssertLessThanOrEqual(words(MathMLNode(name: "mlongdiv", children: rows)), 12 * limit)
        let carries = MathMLNode(name: "mscarries", attributes: ["crossout": "updiagonalstrike"], children: rows)
        XCTAssertLessThanOrEqual(words(MathMLNode(name: "mstack", children: [carries, one])), 20 * limit)
        let glyphs = Array(repeating: MathMLNode(name: "mglyph", attributes: ["alt": "g"]), count: 300_000)
        XCTAssertLessThanOrEqual(words(MathMLNode(name: "mtext", children: glyphs, text: String(repeating: "\u{FFFC}", count: 1_000))), limit)
        // Shared subtrees make a tree larger than its memory: 400 million rows here.
        let shared = MathMLNode(name: "msgroup", children: Array(repeating: MathMLNode(name: "msgroup", children: rows), count: 20_000))
        let large = MathMLNode(name: "mstack", children: Array(repeating: shared, count: 20_000))
        let smallerShared = MathMLNode(name: "msgroup", children: Array(repeating: MathMLNode(name: "msgroup", children: rows), count: 1_000))
        let small = MathMLNode(name: "mstack", children: Array(repeating: smallerShared, count: 1_000))
        // Both fill the same row budget in their first branch. The 400-fold increase in
        // implied group occurrences must not multiply the amount of reading work.
        assertCPUScaling(factor: 5, "shared groups past the row budget", baseline: {
            XCTAssertLessThanOrEqual(words(small), 12 * limit)
        }, larger: {
            XCTAssertLessThanOrEqual(words(large), 12 * limit)
        })
    }
}
