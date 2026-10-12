import CoreGraphics
import CoreText
import CryptoKit
import Foundation
@testable import MathMLLayout
import XCTest

/// A real STIX Two Math table decoded by fontTools. Uncovered glyphs are checked too,
/// so a coverage-index error cannot hide among the positive samples.
final class IndependentFontTests: XCTestCase {
    private struct Oracle: Decodable {
        let schemaVersion: Int
        let postScriptName: String
        let mathSHA256: String
        let glyphCount: Int
        let unitsPerEm: CGFloat
        let constants: [String: CGFloat]
        let italics: [String: CGFloat]
        let accents: [String: CGFloat]
        let minConnectorOverlap: CGFloat
        let vertical: [String: Construction]
        let horizontal: [String: Construction]
    }
    private struct Construction: Decodable {
        struct Variant: Decodable { let glyph: CGGlyph; let advance: CGFloat }
        struct Part: Decodable {
            let glyph: CGGlyph
            let startConnector: CGFloat
            let endConnector: CGFloat
            let fullAdvance: CGFloat
            let isExtender: Bool
        }
        let variants: [Variant]
        let parts: [Part]
        let assemblyItalicsCorrection: CGFloat
    }

    func testRealFontAgainstFontTools() throws {
        let url: URL
        if let path = ProcessInfo.processInfo.environment["MATHML_FONT_ORACLE"] {
            url = URL(fileURLWithPath: path)
        } else {
            url = try XCTUnwrap(Bundle.module.url(forResource: "stix-fonttools", withExtension: "json", subdirectory: "ExternalFixtures"))
        }
        let oracle = try JSONDecoder().decode(Oracle.self, from: Data(contentsOf: url))
        XCTAssertEqual(oracle.schemaVersion, 1)
        let font = MathFont.named(oracle.postScriptName)
        XCTAssertEqual(CTFontCopyPostScriptName(font.base) as String, oracle.postScriptName)
        let data = try XCTUnwrap(CTFontCopyTable(font.base, CTFontTableTag(kCTFontTableMATH), [])) as Data
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == oracle.mathSHA256 else {
            let message = "Installed font differs from pinned fontTools oracle. Generate a new oracle with font_oracle.py and set MATHML_FONT_ORACLE; do not substitute metrics."
            if ProcessInfo.processInfo.environment["MATHML_REQUIRE_FONT_ORACLE"] == "1" { XCTFail(message); return }
            throw XCTSkip(message)
        }
        XCTAssertEqual(font.unitsPerEm, oracle.unitsPerEm)
        let glyphCount = CTFontGetGlyphCount(font.base)
        XCTAssertEqual(glyphCount, oracle.glyphCount, "The oracle must cover every installed glyph")
        let table = try XCTUnwrap(font.table)
        let constants = Dictionary(uniqueKeysWithValues: Mirror(reflecting: table.constants).children.compactMap { child -> (String, CGFloat)? in
            guard let name = child.label, let value = child.value as? CGFloat else { return nil }
            return (name, value)
        })
        XCTAssertEqual(Set(constants.keys), Set(oracle.constants.keys))
        for (name, value) in oracle.constants {
            XCTAssertEqual(try XCTUnwrap(constants[name]), value, accuracy: 1e-12, name)
        }
        XCTAssertEqual(table.minConnectorOverlap, oracle.minConnectorOverlap)
        for id in 0..<glyphCount {
            let glyph = CGGlyph(id), key = String(id)
            XCTAssertEqual(table.italicsCorrection(glyph), oracle.italics[key], "italics glyph \(id)")
            XCTAssertEqual(table.topAccentAttachment(glyph), oracle.accents[key], "accent glyph \(id)")
            for vertical in [false, true] {
                let expected = (vertical ? oracle.vertical : oracle.horizontal)[key]
                let actual = table.construction(glyph, vertical: vertical)
                let label = "glyph \(id), vertical \(vertical)"
                guard let expected else { XCTAssertNil(actual, label); continue }
                let value = try XCTUnwrap(actual, label)
                XCTAssertEqual(value.assemblyItalicsCorrection, expected.assemblyItalicsCorrection, label)
                XCTAssertEqual(value.variants.map(\.glyph), expected.variants.map(\.glyph), label)
                XCTAssertEqual(value.variants.map(\.advance), expected.variants.map(\.advance), label)
                XCTAssertEqual(value.parts.map(\.glyph), expected.parts.map(\.glyph), label)
                XCTAssertEqual(value.parts.map(\.startConnector), expected.parts.map(\.startConnector), label)
                XCTAssertEqual(value.parts.map(\.endConnector), expected.parts.map(\.endConnector), label)
                XCTAssertEqual(value.parts.map(\.fullAdvance), expected.parts.map(\.fullAdvance), label)
                XCTAssertEqual(value.parts.map(\.isExtender), expected.parts.map(\.isExtender), label)
            }
        }
    }
}
