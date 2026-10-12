import CoreGraphics
import CoreText
import CryptoKit
import Foundation
@testable import MathMLLayout
import XCTest

/// Numeric assertions from pinned WPT tests. Expectations come from upstream JS and
/// purpose-built fonts, never from this library's font decoder or a regenerated baseline.
final class ExternalValidationTests: XCTestCase {
    private struct Supplement: Decodable {
        struct Sample: Decodable {
            let id: String
            let source: String
            let sourceSHA256: String
            let markup: String
            let sha256: String
            let kind: String
            let fontSize: CGFloat
            let tolerance: CGFloat
            let expectedOuterGap: CGFloat?
            let expectedInnerGap: CGFloat?
            let referenceMarkup: String?
            let referenceSHA256: String?
        }
        struct Font: Decodable { let path: String; let postScriptName: String; let sha256: String }
        let cases: [Sample]
        let fonts: [Font]
    }

    /// WPT checks of grouping operators and implicit mrow layout in table cells.
    /// Ahem's square ink matches the DOM glyph boxes used by the upstream spacing test.
    func testSupplementalWPTOperatorsAndTableCells() throws {
        let root = try fixtures()
        let supplement = try JSONDecoder().decode(Supplement.self,
            from: Data(contentsOf: root.appendingPathComponent("supplemental.json")))
        XCTAssertEqual(supplement.cases.count, 8)
        let font = try XCTUnwrap(supplement.fonts.first)
        let url = root.appendingPathComponent(font.path)
        XCTAssertEqual(hash(try Data(contentsOf: url)), font.sha256)
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            XCTAssertEqual(error.map { CFErrorGetCode($0.takeRetainedValue()) },
                           CTFontManagerError.alreadyRegistered.rawValue)
        }
        XCTAssertEqual(CTFontCopyPostScriptName(CTFontCreateWithName(font.postScriptName as CFString, 25, nil)) as String,
                       font.postScriptName)
        XCTAssertEqual(Set(supplement.cases.map(\.id)).count, supplement.cases.count)
        var report: [[String: Any]] = []
        for sample in supplement.cases {
            let label = "\(sample.id): \(sample.source)"
            XCTAssertEqual(hash(Data(sample.markup.utf8)), sample.sha256, label)
            let sourceName = try XCTUnwrap(URL(string: sample.source)?.lastPathComponent)
            XCTAssertEqual(hash(try Data(contentsOf: root.appendingPathComponent("upstream").appendingPathComponent(sourceName))),
                           sample.sourceSHA256, label)
            let node = try MathMLNode.parse(xml: Data(sample.markup.utf8))
            let layout = try MathLayout(node, style: MathStyle(fontSize: sample.fontSize, color: black,
                fontName: sample.kind == "operator" ? font.postScriptName : "STIXTwoMath-Regular"))
            let rendering = Rendering(layout)
            if sample.kind == "operator" {
                // Ahem's solid square glyphs completely obscure the backgrounds. As in
                // the numeric subset, expose backgrounds with a separate transparent draw.
                let measuringMarkup = sample.markup.replacingOccurrences(of: " mathcolor=\"red\"", with: "")
                    .replacingOccurrences(of: " mathcolor=\"lime\"", with: "")
                let measuring = try MathLayout(MathMLNode.parse(xml: Data(measuringMarkup.utf8)),
                    style: MathStyle(fontSize: sample.fontSize, color: CGColor(gray: 0, alpha: 0), fontName: font.postScriptName))
                XCTAssertEqual([layout.width, layout.ascent, layout.descent], [measuring.width, measuring.ascent, measuring.descent], label)
                let backgrounds = Rendering(measuring)
                let before = try XCTUnwrap(backgrounds.bounds(.red), label)
                let wrapper = try XCTUnwrap(backgrounds.bounds(.blue), label)
                let core = try XCTUnwrap(rendering.bounds(.green), label)
                XCTAssertEqual(wrapper.minX - before.maxX, try XCTUnwrap(sample.expectedOuterGap), accuracy: sample.tolerance, label)
                XCTAssertEqual(core.minX - wrapper.minX, try XCTUnwrap(sample.expectedInnerGap), accuracy: sample.tolerance, label)
                let outer = wrapper.minX - before.maxX, inner = core.minX - wrapper.minX
                report.append(["id": sample.id, "source": sample.source, "outerGap": outer, "innerGap": inner,
                    "expectedOuterGap": sample.expectedOuterGap!, "expectedInnerGap": sample.expectedInnerGap!,
                    "meetsAssertion": abs(outer - sample.expectedOuterGap!) <= sample.tolerance &&
                        abs(inner - sample.expectedInnerGap!) <= sample.tolerance])
            } else {
                let markup = try XCTUnwrap(sample.referenceMarkup)
                XCTAssertEqual(hash(Data(markup.utf8)), sample.referenceSHA256, label)
                let reference = try MathLayout(MathMLNode.parse(xml: Data(markup.utf8)),
                    style: MathStyle(fontSize: sample.fontSize, color: black, fontName: "STIXTwoMath-Regular"))
                let expected = Rendering(reference)
                // Cell geometry is translated by the table's math-axis alignment. Compare
                // every child's rectangle relative to the first child, not root baselines.
                let origin = try XCTUnwrap(rendering.bounds(.red), label).origin
                let referenceOrigin = try XCTUnwrap(expected.bounds(.red), label).origin
                var maximumDifference: CGFloat = 0
                for color in [Rendering.Ink.red, .green, .blue] {
                    let actual = try XCTUnwrap(rendering.bounds(color), label)
                    let target = try XCTUnwrap(expected.bounds(color), label)
                    for (a, b) in [(actual.minX - origin.x, target.minX - referenceOrigin.x),
                                   (actual.minY - origin.y, target.minY - referenceOrigin.y),
                                   (actual.width, target.width), (actual.height, target.height)] {
                        XCTAssertEqual(a, b, accuracy: sample.tolerance, label)
                        maximumDifference = max(maximumDifference, abs(a - b))
                    }
                }
                XCTAssertEqual(try XCTUnwrap(rendering.bounds()).width, 30, accuracy: sample.tolerance, label)
                XCTAssertEqual(try XCTUnwrap(rendering.bounds()).height, 60, accuracy: sample.tolerance, label)
                let ink = try XCTUnwrap(rendering.bounds())
                report.append(["id": sample.id, "source": sample.source, "maximumChildGeometryDifference": maximumDifference,
                    "inkWidth": ink.width, "inkHeight": ink.height, "expectedInkWidth": 30, "expectedInkHeight": 60,
                    "meetsAssertion": maximumDifference <= sample.tolerance && abs(ink.width - 30) <= sample.tolerance &&
                        abs(ink.height - 60) <= sample.tolerance])
            }
            assertBoxCoversInk(layout, label, rendering: rendering)
        }
        if let path = ProcessInfo.processInfo.environment["MATHML_EXTERNAL_SUPPLEMENT_REPORT"] {
            try JSONSerialization.data(withJSONObject: ["cases": report], options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: path))
        }
    }

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
    struct ReviewedOutcome: Decodable {
        let classification: String
        let issue: String
        let observed: CGFloat
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

    /// WPT's summation glyph is a 1em square above its baseline, with AxisHeight=0.
    /// Unlike STIX's nearly centered natural glyphs, it exposes an unwanted 0.5em shift.
    func testInlineLargeOperatorRetainsItsBaselineThroughEmbellishments() throws {
        let root = try fixtures()
        let font = try XCTUnwrap(try manifest().fonts.first {
            $0.postScriptName == "limits-lowerlimitbaselinedropmin3000"
        })
        try register(font, at: root)
        let op = "<mo movablelimits=\"false\">∑</mo>"
        let script = "<mspace width=\"1em\" height=\"1em\" depth=\"1em\"/>"
        let bodies = [op, "<mrow>\(op)</mrow>", "<mstyle>\(op)</mstyle>",
            "<msub>\(op)\(script)</msub>", "<msup>\(op)\(script)</msup>",
            "<msubsup>\(op)\(script)\(script)</msubsup>",
            "<munder>\(op)\(script)</munder>", "<mover>\(op)\(script)</mover>",
            "<munderover>\(op)\(script)\(script)</munderover>"]
        for body in bodies {
            let layout = try typeset(body, size: 10, font: font.postScriptName)
            let ink = try XCTUnwrap(Rendering(layout).bounds(), body)
            XCTAssertEqual(ink.minY, 0, accuracy: 0.25, body)
            XCTAssertEqual(ink.maxY, 10, accuracy: 0.25, body)
            assertBoxCoversInk(layout, body)
        }
    }

    func testLargeOperatorCenteringFollowsEffectiveDisplayStyle() throws {
        let root = try fixtures()
        let font = try XCTUnwrap(try manifest().fonts.first {
            $0.postScriptName == "limits-lowerlimitbaselinedropmin3000"
        })
        try register(font, at: root)
        let cases: [(String, Bool, CGFloat, CGFloat)] = [
            ("<mo>∑</mo>", false, 0, 10),
            ("<mo>∑</mo>", true, -5, 5),
            ("<mo largeop=\"false\">∑</mo>", true, 0, 10),
            ("<mstyle displaystyle=\"false\"><mo>∑</mo></mstyle>", true, 0, 10),
            ("<mstyle displaystyle=\"true\"><mo>∑</mo></mstyle>", false, -5, 5),
        ]
        for (body, display, bottom, top) in cases {
            let layout = try typeset(body, size: 10, display: display, font: font.postScriptName)
            let ink = try XCTUnwrap(Rendering(layout).bounds(), body)
            XCTAssertEqual(ink.minY, bottom, accuracy: 0.25, body)
            XCTAssertEqual(ink.maxY, top, accuracy: 0.25, body)
            assertBoxCoversInk(layout, body)
        }
    }

    func testPinnedWPTMeasurements() throws {
        let root = try fixtures(), manifest = try manifest()
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertGreaterThanOrEqual(manifest.cases.count, 50)
        XCTAssertLessThanOrEqual(manifest.cases.count, 100)
        XCTAssertEqual(Set(manifest.cases.map(\.id)).count, manifest.cases.count)
        let reviewed = try JSONDecoder().decode([String: ReviewedOutcome].self,
            from: Data(contentsOf: root.appendingPathComponent("reviewed-outcomes.json")))
        XCTAssertEqual(Set(reviewed.keys), Set(manifest.cases.filter { $0.classification != "pass" }.map(\.id)))
        guard Set(manifest.fonts.map(\.path)).count == manifest.fonts.count else {
            XCTFail("Duplicate font paths"); return
        }
        for font in manifest.fonts { try register(font, at: root) }
        let fonts = Dictionary(uniqueKeysWithValues: manifest.fonts.map { ($0.path, $0.postScriptName) })
        var report: [[String: Any]] = []
        for sample in manifest.cases {
            guard sample.fontSize.isFinite, sample.fontSize > 0, sample.expected.isFinite,
                  sample.tolerance.isFinite, sample.tolerance >= 0 else {
                XCTFail("Invalid numeric fixture: \(sample.id)"); continue
            }
            if sample.classification != "pass" {
                let outcome = try XCTUnwrap(reviewed[sample.id], sample.id)
                XCTAssertEqual(sample.classification, "bug", sample.id)
                XCTAssertEqual(sample.classification, outcome.classification, sample.id)
                XCTAssertEqual(sample.issue, outcome.issue, sample.id)
                XCTAssertEqual(sample.observed, outcome.observed, sample.id)
            }
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
