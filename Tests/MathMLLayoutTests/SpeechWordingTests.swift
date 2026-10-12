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

    /// The check names supported by MathCAT's fr/de tests and es unicode map.
    /// Italian caron remains unverified and is deliberately not an audited expectation.
    func testSupportedCheckAccentNames() throws {
        for (language, expected) in [("fr", "x caron"), ("de", "x Caron"), ("es", "x carón")] {
            try assertReading("<mover><mi>x</mi><mo>ˇ</mo></mover>", language: language, expected: expected)
        }
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
