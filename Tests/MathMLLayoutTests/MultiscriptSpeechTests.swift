// Selected script names and the tensor fixture adapted from pinned MathCAT (MIT) and
// Speech Rule Engine (Apache-2.0). Modified for MathMLLayout's source order, explicit
// sides and compound closing phrases; see doc/licenses/THIRD_PARTY_NOTICES.md and
// doc/speech-wording-audit.md for exact sources and remaining uncertainty.
import Foundation
@testable import MathMLLayout
import XCTest

final class MultiscriptSpeechTests: MathTestCase {
    // Right sub/super, then left sub/super. These expected words are independent of
    // the vocabulary functions so that the parsed-formula checks catch dispatch errors.
    private let labels: [(language: String, corners: [String], ends: [String], plus: String)] = [
        ("en", ["right subscript", "right superscript", "left subscript", "left superscript"],
         ["end subscript", "end superscript", "end subscript", "end superscript"], "plus"),
        ("fr", ["indice droite", "exposant droite", "indice gauche", "exposant gauche"],
         ["fin d'indice", "fin d'exposant", "fin d'indice", "fin d'exposant"], "plus"),
        ("de", ["rechter unterer Index", "rechter oberer Index", "linker unterer Index", "linker oberer Index"],
         ["Ende Index", "Ende Index", "Ende Index", "Ende Index"], "plus"),
        ("es", ["subíndice derecho", "superíndice derecho", "subíndice izquierdo", "superíndice izquierdo"],
         ["fin de subíndice", "fin de superíndice", "fin de subíndice", "fin de superíndice"], "más"),
        ("it", ["pedice destro", "apice destro", "pedice sinistro", "apice sinistro"],
         ["fine pedice", "fine apice", "fine pedice", "fine apice"], "più"),
    ]

    func testAllFourCornersAndEveryCombinationOfMissingPartners() throws {
        for mask in 0..<16 {
            let scripts = (0..<4).map { mask & (1 << $0) == 0 ? "<none/>" : "<mn>\($0 + 1)</mn>" }
            let formula = try node("<mmultiscripts><mi>T</mi>\(scripts[0])\(scripts[1])<mprescripts/>\(scripts[2])\(scripts[3])</mmultiscripts>")
            for (language, corners, _, _) in labels {
                let parts = (0..<4).filter { mask & (1 << $0) != 0 }.map { "\(corners[$0]) \($0 + 1)" }
                let expected = (["T"] + parts).joined(separator: " ")
                XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: language)),
                               MathReading(text: expected, language: language), "mask \(mask), \(language)")
                if language == "en" { XCTAssertEqual(formula.accessibilityDescription, expected) }
            }
        }
    }

    func testMultiplePairsOnBothSidesAreReadInSourceOrder() throws {
        // Five pairs exceed the pinned MathCAT rule's positional special cases.
        let right = (1...10).map { "<mn>\($0)</mn>" }.joined()
        let left = (11...20).map { "<mn>\($0)</mn>" }.joined()
        let formula = try node("<mmultiscripts><mi>T</mi>\(right)<mprescripts/>\(left)</mmultiscripts>")
        for (language, corners, _, _) in labels {
            let parts = (1...20).map { "\(corners[($0 > 10 ? 2 : 0) + ($0 - 1) % 2]) \($0)" }
            XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: language)).text,
                           (["T"] + parts).joined(separator: " "), language)
        }
    }

    func testTensorFixtureKeepsSlotsAcrossEmptyPairs() throws {
        // MathCAT shared.rs::tensor_mmultiscripts. Its es fixture requests English,
        // so it supplies structure, not evidence for Spanish wording.
        let formula = try node("<mmultiscripts><mi>R</mi><mi>i</mi><none/><none/><mi>j</mi><none/><none/><mi>k</mi><none/><mi>l</mi><none/></mmultiscripts>")
        for (language, corners, _, _) in labels {
            XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: language)).text,
                           "R \(corners[0]) i \(corners[1]) j \(corners[0]) k \(corners[0]) l", language)
        }
    }

    func testPrescriptsWithoutPostscriptsAndIncompletePairs() throws {
        // Hand-authored incomplete pairs are tolerated by speech. Every marker
        // starts a left subscript slot, including repeated markers in invalid input.
        let cases = [
            ("<mprescripts/><none/><mi>n</mi>", 3),
            ("<mi>k</mi>", 0),
            ("<mprescripts/><mi>k</mi>", 2),
        ]
        for (scripts, corner) in cases {
            let formula = try node("<mmultiscripts><mi>T</mi>\(scripts)</mmultiscripts>")
            for (language, corners, _, _) in labels {
                XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: language)).text,
                               "T \(corners[corner]) \(corner == 3 ? "n" : "k")", language)
            }
        }
        let formula = try node("<mmultiscripts><mi>T</mi><mi>k</mi><mprescripts/><mprescripts/><mi>n</mi><none/></mmultiscripts>")
        XCTAssertEqual(formula.accessibilityDescription, "T right subscript k left subscript n")
    }

    func testCompoundScriptsAtEveryCornerMarkTheirEnd() throws {
        for corner in 0..<4 {
            var scripts = Array(repeating: "<none/>", count: 4)
            scripts[corner] = "<mrow><mi>n</mi><mo>+</mo><mn>1</mn></mrow>"
            let formula = try node("<mmultiscripts><mi>T</mi>\(scripts[0])\(scripts[1])<mprescripts/>\(scripts[2])\(scripts[3])</mmultiscripts><mi>z</mi>")
            for (language, corners, ends, plus) in labels {
                XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: language)).text,
                               "T \(corners[corner]) n \(plus) 1 \(ends[corner]) z", language)
            }
        }
    }

    func testNestedMultiscriptsCloseBeforeTheNextOuterScript() throws {
        let nested = "<mmultiscripts><mi>U</mi><none/><mn>2</mn><mprescripts/><mi>i</mi><none/></mmultiscripts>"
        let formula = try node("<mmultiscripts><mi>T</mi>\(nested)<mi>j</mi></mmultiscripts><mi>z</mi>")
        for (language, corners, ends, _) in labels {
            XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: language)).text,
                           "T \(corners[0]) U \(corners[1]) 2 \(corners[2]) i \(ends[0]) \(corners[1]) j z", language)
        }
    }

    func testSimpleSelectedScriptDoesNotNeedAClosingPhrase() throws {
        for wrapper in ["<mrow><mstyle><mi>i</mi></mstyle></mrow>",
                        "<semantics><annotation>hidden</annotation><mi>i</mi></semantics>",
                        "<maction selection=\"2\"><mi>hidden</mi><mi>i</mi></maction>"] {
            let formula = try node("<mmultiscripts><mi>T</mi>\(wrapper)<none/></mmultiscripts>")
            for (language, corners, _, _) in labels {
                XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: language)).text,
                               "T \(corners[0]) i", language)
            }
        }
    }

    func testSilentExpressionsOccupySlotsWithoutDanglingLabels() throws {
        let formula = try node("<mmultiscripts><mi>T</mi><mphantom><mi>hidden</mi></mphantom><mi>j</mi><mrow/><mi>l</mi><mprescripts/><mspace/><mi>n</mi></mmultiscripts>")
        for (language, corners, _, _) in labels {
            XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: language)).text,
                           "T \(corners[1]) j \(corners[1]) l \(corners[3]) n", language)
        }
    }

    func testRegionalAndScriptLanguageTagsAndWholeLanguageFallback() throws {
        let formula = try node("<mmultiscripts><mi>T</mi><mi>i</mi><mi>j</mi><mprescripts/><mi>k</mi><mi>l</mi></mmultiscripts>")
        for (tag, language) in [("en-GB", "en"), ("fr-CA", "fr"), ("de-CH", "de"),
                                ("es-MX", "es"), ("it-CH", "it"), ("fr-Latn-CA", "fr"),
                                ("ja-JP", "en"), ("ar-Arab-EG", "en")] {
            let corners = labels.first { $0.language == language }!.corners
            let expected = "T \(corners[0]) i \(corners[1]) j \(corners[2]) k \(corners[3]) l"
            XCTAssertEqual(formula.accessibilityDescription(locale: Locale(identifier: tag)),
                           MathReading(text: expected, language: language), tag)
        }
    }
}
