import CoreGraphics
import CryptoKit
import Foundation
import MathMLLayout
import XCTest

/// Bundled textbook and regression corpora run offline by default. An external manifest
/// adds optional cases. Rendering success is robustness evidence, never a standards pass.
final class ExternalCorpusTests: XCTestCase {
    private struct Manifest: Decodable {
        struct Sample: Decodable {
            let id: String
            let markup: String
            let sha256: String
            let fontSize: CGFloat
            let expectedInvalidMarkup: String?
        }
        let cases: [Sample]
    }

    func testSampledCorpusInvariants() throws {
        var inputs: [(url: URL, required: Bool)] = try ["openstax-precalculus", "sre-mathspeak"].map { dataset in
            (try XCTUnwrap(Bundle.module.url(forResource: "manifest", withExtension: "json",
                                            subdirectory: "ExternalFixtures/Corpus/" + dataset)), true)
        }
        if let path = ProcessInfo.processInfo.environment["MATHML_CORPUS_MANIFEST"] {
            inputs.append((URL(fileURLWithPath: path), false))
        }
        var report: [[String: Any]] = []
        for input in inputs {
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: input.url))
            XCTAssertFalse(manifest.cases.isEmpty)
            XCTAssertEqual(Set(manifest.cases.map(\.id)).count, manifest.cases.count)
            var rendered = 0, rejected = 0
            for sample in manifest.cases {
                do {
                    let hash = SHA256.hash(data: Data(sample.markup.utf8)).map { String(format: "%02x", $0) }.joined()
                    guard hash == sample.sha256 else {
                        XCTFail("Corpus markup changed: \(sample.id)")
                        report.append(["id": sample.id, "classification": "invalid/out-of-bounds input", "error": "Markup hash mismatch"])
                        continue
                    }
                    guard sample.fontSize.isFinite, sample.fontSize > 0 else {
                        XCTFail("Invalid corpus font size: \(sample.id)")
                        report.append(["id": sample.id, "classification": "invalid/out-of-bounds input", "error": "Invalid font size"])
                        continue
                    }
                    let node = try MathMLNode.parse(xml: Data(sample.markup.utf8))
                    let style = MathStyle(fontSize: sample.fontSize, color: black, fontName: "STIXTwoMath-Regular")
                    let layout = try MathLayout(node, style: style)
                    let repeated = try MathLayout(node, style: style)
                    let dimensions = [layout.width, layout.ascent, layout.descent]
                    let valid = dimensions.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 50_000 }
                    let deterministic = dimensions == [repeated.width, repeated.ascent, repeated.descent]
                    XCTAssertTrue(valid, sample.id)
                    XCTAssertTrue(deterministic, sample.id)
                    let pixelWidth = ceil((layout.width + 32) * 2)
                    let pixelHeight = ceil((layout.ascent + layout.descent + 32) * 2)
                    let rasterFits = valid && pixelWidth <= 16_384 && pixelHeight <= 16_384 && pixelWidth * pixelHeight < 4_000_000
                    if input.required { XCTAssertTrue(rasterFits, "Bundled case must be raster checked: \(sample.id)") }
                    var coversInk = true
                    // The public drawing contract allows two device pixels for bitmap
                    // quantization/smoothing (doc/line-breaking.md). At 2x that is one point.
                    let tolerance: CGFloat = 1 + 1e-9
                    if rasterFits, let ink = Rendering(layout, scale: 2).bounds() {
                        coversInk = CGRect(x: 0, y: -layout.descent, width: layout.width,
                                           height: layout.ascent + layout.descent).insetBy(dx: -tolerance, dy: -tolerance).contains(ink)
                        XCTAssertTrue(coversInk, "Ink \(ink) outside width \(layout.width), ascent \(layout.ascent), descent \(layout.descent): \(sample.id)")
                    }
                    if let expected = sample.expectedInvalidMarkup {
                        XCTFail("Expected invalidMarkup(\(expected)), but case rendered: \(sample.id)")
                    }
                    rendered += 1
                    func jsonNumber(_ value: CGFloat) -> Any { value.isFinite ? value as Any : NSNull() }
                    report.append(["id": sample.id, "classification": "unreviewed",
                                   "invariants": valid && deterministic && coversInk && (!input.required || rasterFits) ? "pass" : "fail",
                                   "raster": rasterFits ? "checked" : "excluded: raster budget", "width": jsonNumber(layout.width),
                                   "ascent": jsonNumber(layout.ascent), "descent": jsonNumber(layout.descent)])
                } catch MathLayoutError.invalidMarkup(let element) where sample.expectedInvalidMarkup == element {
                    rejected += 1
                    report.append(["id": sample.id, "classification": "expected invalid input",
                                   "invariants": "pass", "error": "invalidMarkup(\(element))"])
                } catch MathLayoutError.limitExceeded {
                    if input.required { XCTFail("Bundled case exceeded layout bounds: \(sample.id)") }
                    report.append(["id": sample.id, "classification": "invalid/out-of-bounds input",
                                   "error": "limitExceeded (including available stack)"])
                } catch {
                    report.append(["id": sample.id, "classification": "unreviewed", "error": String(describing: error)])
                    XCTFail("\(sample.id): \(error)")
                }
            }
            if input.required { XCTAssertEqual(rendered + rejected, manifest.cases.count, "Every bundled case must render or match its explicit rejection") }
            print("CORPUS \(input.url.deletingLastPathComponent().lastPathComponent): \(rendered) rendered, \(rejected) expected rejections, \(manifest.cases.count) total")
        }
        if let path = ProcessInfo.processInfo.environment["MATHML_CORPUS_REPORT"] {
            try JSONSerialization.data(withJSONObject: ["cases": report], options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: path))
        }
    }
}
