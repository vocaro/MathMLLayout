import CoreGraphics
import CryptoKit
import Foundation
import MathMLLayout
import XCTest

/// On-demand external corpus invariants. Rendering success is robustness evidence, never
/// a standards pass. Inputs are sampled by tools/externalvalidation/sample_corpus.py.
final class ExternalCorpusTests: XCTestCase {
    private struct Manifest: Decodable {
        struct Sample: Decodable { let id: String; let markup: String; let sha256: String; let fontSize: CGFloat }
        let cases: [Sample]
    }

    func testSampledCorpusInvariants() throws {
        guard let path = ProcessInfo.processInfo.environment["MATHML_CORPUS_MANIFEST"] else {
            throw XCTSkip("Set MATHML_CORPUS_MANIFEST to a licensed, locally sampled corpus manifest")
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertFalse(manifest.cases.isEmpty)
        XCTAssertEqual(Set(manifest.cases.map(\.id)).count, manifest.cases.count)
        var report: [[String: Any]] = []
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
                var coversInk = true
                // The public drawing contract allows two device pixels for bitmap
                // quantization/smoothing (doc/line-breaking.md). At 2x that is one point.
                let tolerance: CGFloat = 1 + 1e-9
                if rasterFits, let ink = Rendering(layout, scale: 2).bounds() {
                    coversInk = CGRect(x: 0, y: -layout.descent, width: layout.width,
                                       height: layout.ascent + layout.descent).insetBy(dx: -tolerance, dy: -tolerance).contains(ink)
                    XCTAssertTrue(coversInk, "Ink \(ink) outside width \(layout.width), ascent \(layout.ascent), descent \(layout.descent): \(sample.id)")
                }
                func jsonNumber(_ value: CGFloat) -> Any { value.isFinite ? value as Any : NSNull() }
                report.append(["id": sample.id, "classification": "unreviewed",
                               "invariants": valid && deterministic && coversInk ? "pass" : "fail",
                               "raster": rasterFits ? "checked" : "excluded: raster budget", "width": jsonNumber(layout.width),
                               "ascent": jsonNumber(layout.ascent), "descent": jsonNumber(layout.descent)])
            } catch MathLayoutError.limitExceeded {
                report.append(["id": sample.id, "classification": "invalid/out-of-bounds input",
                               "error": "limitExceeded (including available stack)"])
            } catch {
                report.append(["id": sample.id, "classification": "unreviewed", "error": String(describing: error)])
                XCTFail("\(sample.id): \(error)")
            }
        }
        if let path = ProcessInfo.processInfo.environment["MATHML_CORPUS_REPORT"] {
            try JSONSerialization.data(withJSONObject: ["cases": report], options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: path))
        }
    }
}
