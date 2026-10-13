import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

final class EmbeddedGlyphSpeechTests: MathTestCase {
    private func read(_ body: String, language: String = "en") throws -> String {
        try node(body).accessibilityDescription(locale: Locale(identifier: language)).text
    }

    func testMultipleGlyphsKeepSourceOrderAndOneNumericColumn() throws {
        let text = try read("<mstack stackalign='left'><mn>1<mglyph src='a' alt='first glyph'/>2<mglyph fontfamily='missing' index='1' alt='second glyph'/>3</mn></mstack>")
        XCTAssertEqual(text, "stack with 1 row alignment left row 1: column 0: one column 1: first glyph column 2: two column 3: second glyph column 4: three end stack")
    }

    func testGlyphAltIsNotADecimalSeparatorAndEmptyAltReservesAColumn() throws {
        for alt in [".", ",", "", "  "] {
            let text = try read("<mstack><msrow><mn>1<mglyph alt='\(alt)'/>2</mn><mo>.</mo><mn>3</mn></msrow></mstack>")
            let entry = alt.trimmingCharacters(in: .whitespaces).isEmpty ? "" : " column minus 2: \(alt)"
            XCTAssertEqual(text, "stack with 1 row alignment decimal point row 1: column minus 3: one\(entry) column minus 1: two column 0: . column 1: three end stack")
        }
        XCTAssertEqual(try read("<mstack><mn>1<mglyph/>2</mn><mi>x</mi></mstack>"),
                       "stack with 2 rows alignment decimal point row 1: column minus 3: one column minus 1: two row 2: column minus 1: x end stack")
    }

    func testAuthoredDecimalTextBesideAGlyphStillSelectsTheAlignmentColumn() throws {
        XCTAssertEqual(try read("<mstack><msrow><mi>x</mi><mo>.<mglyph alt='marker'/></mo><mn>23</mn></msrow></mstack>"),
                       "stack with 1 row alignment decimal point row 1: column minus 1: x column 0: . marker column 1: two column 2: three end stack")
    }

    func testHostBuiltMarkerMismatchesMatchDrawingColumnConvention() {
        let first = MathMLNode(name: "mglyph", attributes: ["alt": "first"])
        let second = MathMLNode(name: "mglyph", attributes: ["alt": "second"])
        for source in ["1\u{FFFC}2", "12", "1\u{FFFC}2\u{FFFC}\u{FFFC}"] {
            let number = MathMLNode(name: "mn", children: [MathMLNode(name: "malignmark"), first, second], text: source)
            let stack = MathMLNode(name: "mstack", attributes: ["stackalign": "left"], children: [number])
            let expected = source == "12"
                ? "column 0: one column 1: two column 2: first column 3: second"
                : "column 0: one column 1: first column 2: two column 3: second"
            XCTAssertEqual(stack.accessibilityDescription, "stack with 1 row alignment left row 1: \(expected) end stack")
        }
        let orphan = MathMLNode(name: "mn", text: "1 \u{FFFC} 2")
        let stack = MathMLNode(name: "mstack", attributes: ["stackalign": "left"], children: [orphan])
        XCTAssertEqual(stack.accessibilityDescription, "stack with 1 row alignment left row 1: column 0: one column 1: space column 2: two end stack")
    }

    func testPositionsAndShiftsIncludeAtomicGlyphColumns() throws {
        XCTAssertEqual(try read("<mstack><msgroup position='2' shift='1'><mn>1<mglyph alt='23'/></mn><msrow position='-1'><mstyle><mn><mglyph alt='.'/>4</mn></mstyle><none/></msrow></msgroup></mstack>"),
                       "stack with 2 rows alignment decimal point row 1: column minus 4: one column minus 3: 23 row 2: column minus 4: . column minus 3: four column minus 2: blank end stack")
        for (align, start) in [("left", 0), ("right", -3), ("center", -1), ("decimalpoint", -3)] {
            let text = try read("<mstack stackalign='\(align)'><mn>1<mglyph alt='23'/>4</mn></mstack>")
            let words = EnglishVocabulary.self
            XCTAssertTrue(text.contains(words.phrase(words.column(start), "one", words.column(start + 1), "23", words.column(start + 2), "four")))
        }
    }

    func testCarriesAndDivisionOperandsKeepAltWhole() throws {
        XCTAssertEqual(try read("<mstack stackalign='left'><mscarries><mscarry><mn>1<mglyph alt='23'/></mn></mscarry><mn><mglyph alt='.'/></mn><none/></mscarries><mn>456</mn></mstack>"),
                       "stack with 1 row alignment left carries or borrows: column 0: above one 23 column 1: above . column 2: blank row 1: column 0: four column 1: five column 2: six end stack")
        let body = "<mlongdiv stackalign='left'><mn><mglyph alt='divisor glyph'/></mn><mn>1<mglyph alt='result glyph'/></mn><mn>2<mglyph alt='dividend glyph'/>3</mn><msrow position='1'><mn>4<mglyph alt='working glyph'/>5</mn></msrow></mlongdiv>"
        XCTAssertEqual(try read(body), "long division with 1 working row divisor left, result above alignment left divisor: divisor glyph dividend: column 0: two column 1: dividend glyph column 2: three result: column 0: one column 1: result glyph row 1: column minus 1: four column 0: working glyph column 1: five end long division")
        XCTAssertTrue(try read(body.replacingOccurrences(of: "stackalign='left'", with: "stackalign='left' longdivstyle='stackedrightright'")).contains("result: one result glyph"))
    }

    func testAltRemainsLiteralInEveryVocabularyAndTokenKind() throws {
        for language in MathReading.supportedLocales {
            for name in ["mi", "mo", "mn", "mtext", "ms"] {
                XCTAssertEqual(try read("<\(name)><mglyph alt='+'/><mglyph alt='∞'/></\(name)>", language: language), "+ ∞")
            }
            let words = MathVocabularyCatalog.standard.vocabulary(for: Locale(identifier: language)).words
            XCTAssertEqual(try read("<mo>+<mglyph alt='∞'/></mo>", language: language), "\(words.symbols["+"]!) ∞")
            let spatial = try read("<mstack stackalign='left'><mn><mglyph alt='23'/><mglyph alt='.'/></mn></mstack>", language: language)
            XCTAssertTrue(spatial.contains(words.phrase(words.column(0), "23", words.column(1), ".")))
        }
    }

    func testSpeechUsesSameAltForResolvedImageFontAndFallback() throws {
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = try XCTUnwrap(context.makeImage())
        let font = CTFontCreateWithName("TimesNewRomanPSMT" as CFString, 20, nil)
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, "TimesNewRomanPSMT")
        var character: UniChar = 65, index: CGGlyph = 0
        XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &character, &index, 1))
        let body = "<mstack stackalign='left'><mn><mglyph src='image' alt='image alt'/><mglyph fontfamily='TimesNewRomanPSMT' index='\(index)' alt='font alt'/><mglyph src='missing' alt='fallback alt'/></mn></mstack>"
        let parsed = try node(body)
        for provider in [MathImageProvider { $0 == "image" ? image : nil }, MathImageProvider { _ in nil }] {
            _ = try MathLayout(parsed, style: MathStyle(fontSize: 20, color: black, imageProvider: provider))
            XCTAssertEqual(parsed.accessibilityDescription, "stack with 1 row alignment left row 1: column 0: image alt column 1: font alt column 2: fallback alt end stack")
        }
    }

    func testNumericGlyphSourceBudgetsRemainBounded() {
        let glyph = MathMLNode(name: "mglyph", attributes: ["alt": "last"])
        let number = MathMLNode(name: "mn", children: [glyph, MathMLNode(name: "mglyph", attributes: ["alt": "past"])])
        let stack = MathMLNode(name: "mstack", attributes: ["stackalign": "left"], children: [number])
        let root = MathMLNode(name: "math", children: Array(repeating: MathMLNode(name: "none"), count: MathLimits.nodes - 4) + [stack])
        XCTAssertTrue(root.accessibilityDescription.contains("column 0: last"))
        XCTAssertFalse(root.accessibilityDescription.contains("past"))

        let maximumAlt = String(repeating: "𝑥", count: (MathLimits.textLength - 2) / 2)
        let full = MathMLNode(name: "mn", children: [MathMLNode(name: "mglyph", attributes: ["alt": maximumAlt])], text: "1\u{FFFC}")
        let bounded = MathMLNode(name: "mstack", attributes: ["stackalign": "left"], children: [full, MathMLNode(name: "mi", text: "past")])
        let text = bounded.accessibilityDescription
        XCTAssertTrue(text.contains("column 1: \(maximumAlt)"))
        XCTAssertFalse(text.contains("past"))

        let huge = MathMLNode(name: "mglyph", attributes: ["alt": String(repeating: "x", count: MathLimits.textLength + 1)])
        let shared = MathMLNode(name: "mn", children: Array(repeating: huge, count: 100_000))
        XCTAssertLessThan(MathMLNode(name: "mstack", children: [shared]).accessibilityDescription.count, 100)
    }

    func testEmbeddedGlyphDepthBoundDoesNotRecoverAlt() {
        let number = MathMLNode(name: "mn", children: [MathMLNode(name: "mglyph", attributes: ["alt": "hidden"])], text: "1\u{FFFC}")
        for wrappers in [MathLimits.depth - 3, MathLimits.depth - 2] {
            let nested = (0..<wrappers).reduce(number) { inner, _ in MathMLNode(name: "mrow", children: [inner]) }
            let stack = MathMLNode(name: "mstack", children: [nested])
            XCTAssertEqual(stack.accessibilityDescription.contains("hidden"), wrappers == MathLimits.depth - 3)
        }
    }
}
