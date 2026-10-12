import CoreGraphics
import CoreText
import CryptoKit
import Foundation
@testable import MathMLLayout
import XCTest

/// Numeric assertions from pinned WPT tests. Expectations come from upstream JS and
/// purpose-built fonts, never from this library's font decoder or a regenerated baseline.
final class ExternalValidationTests: XCTestCase {
    struct Manifest: Decodable {
        let schemaVersion: Int
        let revision: String
        let cases: [Case]
        let fonts: [Font]
    }
    struct Case: Decodable {
        let id: String
        let feature: String
        let source: String
        let sourceSHA256: String
        let markup: String
        let sha256: String
        let font: String
        let fontSize: CGFloat
        let firstMetric: String
        let secondMetric: String
        let expected: CGFloat
        let tolerance: CGFloat
        let classification: String
        let issue: String?
        let observed: CGFloat?
    }
    struct Font: Decodable {
        let path: String
        let postScriptName: String
        let sha256: String
        let mathSHA256: String
    }

    private func fixtures() throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "ExternalFixtures", withExtension: nil))
    }

    private func manifest() throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: fixtures().appendingPathComponent("manifest.json")))
    }

    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func register(_ font: Font, at root: URL) throws {
        let url = root.appendingPathComponent(font.path)
        XCTAssertEqual(hash(try Data(contentsOf: url)), font.sha256, font.path)
        var error: Unmanaged<CFError>?
        // Register once for the process. On subsequent runs CoreText reports already registered.
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            let code = error.map { CFErrorGetCode($0.takeRetainedValue()) }
            XCTAssertEqual(code, CTFontManagerError.alreadyRegistered.rawValue, font.path)
        }
        let loaded = CTFontCreateWithName(font.postScriptName as CFString, 10, nil)
        XCTAssertEqual(CTFontCopyPostScriptName(loaded) as String, font.postScriptName,
                       "A substituted font invalidates this assertion")
        let math = try XCTUnwrap(CTFontCopyTable(loaded, CTFontTableTag(kCTFontTableMATH), [])) as Data
        XCTAssertEqual(hash(math), font.mathSHA256, "CoreText must use the original WPT MATH bytes")
    }

    /// Match WPT's DOM coordinates (y down), while retaining the formula baseline as origin.
    private func metric(_ name: String, of rect: CGRect) throws -> CGFloat {
        switch name {
        case "left": return rect.minX
        case "right": return rect.maxX
        case "top": return -rect.maxY
        case "bottom": return -rect.minY
        case "width": return rect.width
        case "height": return rect.height
        default: throw NSError(domain: "ExternalValidation", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Unknown metric: \(name)"])
        }
    }

    func testPinnedWPTMeasurements() throws {
        let root = try fixtures(), manifest = try manifest()
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertGreaterThanOrEqual(manifest.cases.count, 50)
        XCTAssertLessThanOrEqual(manifest.cases.count, 100)
        XCTAssertEqual(Set(manifest.cases.map(\.id)).count, manifest.cases.count)
        for font in manifest.fonts { try register(font, at: root) }
        let fonts = Dictionary(uniqueKeysWithValues: manifest.fonts.map { ($0.path, $0.postScriptName) })
        var report: [[String: Any]] = []
        for sample in manifest.cases {
            XCTAssertEqual(hash(Data(sample.markup.utf8)), sample.sha256, sample.id)
            let sourceName = try XCTUnwrap(URL(string: sample.source)?.lastPathComponent)
            XCTAssertEqual(hash(try Data(contentsOf: root.appendingPathComponent("upstream").appendingPathComponent(sourceName))),
                           sample.sourceSHA256, sample.id)
            let label = "\(sample.id): \(sample.source)"
            let node = try MathMLNode.parse(xml: Data(sample.markup.utf8))
            let font = try XCTUnwrap(fonts[sample.font], label)
            let result = try MathLayout(node, style: MathStyle(fontSize: sample.fontSize, color: black, fontName: font))
            let rendering = Rendering(result, scale: 4)
            // Glyphs and radical rules can completely obscure a measured background. Draw
            // them transparently for rectangle measurements, retaining the same layout.
            let geometry = try MathLayout(node, style: MathStyle(fontSize: sample.fontSize,
                color: CGColor(gray: 0, alpha: 0), fontName: font))
            XCTAssertEqual([result.width, result.ascent, result.descent], [geometry.width, geometry.ascent, geometry.descent], label)
            let rectangles = Rendering(geometry, scale: 4)
            let first = try XCTUnwrap(rectangles.bounds(.red), label)
            let second = try XCTUnwrap(rectangles.bounds(.blue), label)
            let actual = try metric(sample.firstMetric, of: first) - metric(sample.secondMetric, of: second)
            let passes = abs(actual - sample.expected) <= sample.tolerance
            report.append(["id": sample.id, "feature": sample.feature, "actual": actual,
                           "expected": sample.expected, "tolerance": sample.tolerance,
                           "classification": passes ? "pass" : (sample.classification == "pass" ? "unreviewed" : sample.classification),
                           "meetsAssertion": passes, "issue": sample.issue as Any? ?? NSNull()])
            if sample.classification == "pass" {
                XCTAssertEqual(actual, sample.expected, accuracy: sample.tolerance, label)
            } else {
                // Known discrepancies remain executable and must be tied to an issue. A fix
                // requires review of the classification, instead of silently counting a pass.
                XCTAssertNotNil(sample.issue, "Untracked discrepancy: \(label)")
                let observed = try XCTUnwrap(sample.observed, "A known discrepancy needs a reviewed measurement: \(label)")
                XCTAssertEqual(actual, observed, accuracy: sample.tolerance, "Known discrepancy changed: \(label)")
                if passes { XCTFail("Known discrepancy now passes; review \(label)") }
                if ProcessInfo.processInfo.environment["MATHML_STRICT_EXTERNAL"] == "1" {
                    XCTAssertEqual(actual, sample.expected, accuracy: sample.tolerance, label)
                }
            }
            assertBoxCoversInk(result, label, rendering: rendering)
        }
        if let path = ProcessInfo.processInfo.environment["MATHML_EXTERNAL_REPORT"] {
            let data = try JSONSerialization.data(withJSONObject: ["revision": manifest.revision,
                "os": ProcessInfo.processInfo.operatingSystemVersionString, "cases": report], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path))
        }
    }
}
