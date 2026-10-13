// Selected expectations adapted from MathCAT (MIT) and Speech Rule Engine (Apache-2.0).
// Modified into isolated MathMLLayout regression cases; see THIRD_PARTY_NOTICES.md and
// Documentation/SpeechWordingAudit.md for pinned upstream files and rule/test identifiers.
import Foundation
@testable import MathMLLayout
import XCTest

final class SpeechWordingTests: MathTestCase {
    private func assertReading(_ markup: String, language: String, expected: String,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let formula = try node(markup)
        let locale = Locale(identifier: language)
        XCTAssertEqual(formula.accessibilityDescription(locale: locale),
                       MathReading(text: expected, language: language), file: file, line: line)
    }

    /// Spacing and combining forms must use the same name inside an actual mover.
    /// MathCAT's modified_vars tests cover fr/de; its es test runs in English, so the
    /// Spanish expectations come from its rules and SRE's symbol maps instead.
    func testAuditedAccentNamesAndAliases() throws {
        let cases: [(aliases: [String], readings: [String])] = [
            (["¨", "\u{0308}"], ["x double dot", "x tréma", "x diaeresis", "x diéresis", "x dieresi"]),
            (["^", "ˆ", "\u{0302}"],
             ["x hat", "x accent circonflexe", "x Zirkumflex", "x circunflejo", "x accento circonflesso"]),
            (["¯", "‾", "\u{0305}"],
             ["x bar", "x barre", "x Überstrich", "x barra", "x barra sopra"]),
        ]
        for (aliases, readings) in cases {
            for alias in aliases {
                for (language, expected) in zip(MathReading.languages, readings) {
                    try assertReading("<mover><mi>x</mi><mo>\(alias)</mo></mover>",
                                      language: language, expected: expected)
                }
            }
        }
    }

    /// MathCAT supplies fr/de/es names; SRE's Italian U+010D name supplies con caron.
    func testSupportedCheckAccentNames() throws {
        for (language, expected) in [("fr", "x caron"), ("de", "x Caron"), ("es", "x carón"), ("it", "x con caron")] {
            try assertReading("<mover><mi>x</mi><mo>ˇ</mo></mover>", language: language, expected: expected)
        }
    }

    /// Exact postfix underbar actions (or the French enclosure label) and U+23DF names.
    func testSourceBackedUnderbarAndUnderbraceNames() throws {
        let readings = [
            ("en", "x underbar", "x bottom brace"),
            ("fr", "x trait souscrit", "x accolade inférieure"),
            ("de", "x Unterstrich", "x Untere geschweifte Klammer"),
            ("es", "x subbarra", "x corchete rizado inferior"),
            ("it", "x con barra sotto", "x parentesi graffa inferiore"),
        ]
        for (language, bar, brace) in readings {
            try assertReading("<munder><mi>x</mi><mo>_</mo></munder>", language: language, expected: bar)
            try assertReading("<munder><mi>x</mi><mo>⏟</mo></munder>", language: language, expected: brace)
        }
    }

    /// SRE HighRoot012/015 and MathCAT ordinal_root/simple_mi_root supply these cores.
    /// MathMLLayout keeps its existing closure policy and MathCAT French root order.
    func testSourceBackedRootFixturesAndSpanishVariableFallback() throws {
        for (language, expected) in [
            ("fr", "racine quatrième de n fin de racine"),
            ("de", "vierte Wurzel aus n Ende Wurzel"),
            ("es", "cuarta raíz de n fin de raíz"),
            ("it", "radice quarta di n fine radice"),
        ] {
            try assertReading("<mroot><mi>n</mi><mn>4</mn></mroot>", language: language, expected: expected)
        }
        try assertReading("<mroot><mi>d</mi><mi>n</mi></mroot>", language: "it", expected: "radice n-esima di d fine radice")
        try assertReading("<mroot><mi>d</mi><mi>n</mi></mroot>", language: "es", expected: "raíz de índice n de d fin de raíz")
    }

    /// SRE's greekSmall alphabet entries and MathCAT's non-terse ∂ rules agree for
    /// fr/de. Spanish retains MathCAT's terse name rather than choosing between its
    /// "derivada parcial" and SRE's "diferencial parcial".
    func testPartialAndContourIntegralNamesInAFormula() throws {
        let readings = ["partial x plus the contour integral",
                        "dérivée partielle x plus l'intégrale de contour",
                        "partielle Ableitung x plus das Randintegral",
                        "parcial x más la integral de contorno",
                        "derivata parziale x più l'integrale di contorno"]
        for (language, expected) in zip(MathReading.languages, readings) {
            try assertReading("<mo>∂</mo><mi>x</mi><mo>+</mo><mo>∮</mo>", language: language, expected: expected)
        }
    }

    /// Removing "strictement" must not collapse < into ≤ (or > into ≥).
    func testFrenchStrictAndNonStrictRelationsRemainDistinct() throws {
        for (symbol, expected) in [("&lt;", "x est inférieur à y"), ("&gt;", "x est supérieur à y"),
                                   ("≤", "x est inférieur ou égal à y"), ("≥", "x est supérieur ou égal à y")] {
            try assertReading("<mi>x</mi><mo>\(symbol)</mo><mi>y</mi>", language: "fr", expected: expected)
        }
    }
}
