import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

/// Records are built from the OpenType formats; point expectations below are arithmetic,
/// independent of CoreText's shaping or the engine's metric conversion helpers.
final class MathAdjustmentTests: MathTestCase {
    private struct Fixture {
        var bytes: [UInt8] = []
        var records: [String: (record: Int, parent: Int)] = [:]
        mutating func u16(_ values: Int...) {
            for value in values { bytes.append(UInt8((value >> 8) & 255)); bytes.append(UInt8(value & 255)) }
        }
        mutating func set(_ offset: Int, _ value: Int) {
            bytes[offset] = UInt8((value >> 8) & 255); bytes[offset + 1] = UInt8(value & 255)
        }
        mutating func record(_ name: String, _ value: Int, parent: Int) {
            records[name] = (bytes.count, parent); u16(value, 0)
        }
        mutating func device(_ name: String, start: Int = 10, values: [Int], format: Int = 3) {
            let record = records[name]!
            set(record.record + 2, bytes.count - record.parent)
            u16(start, start + values.count - 1, format)
            let bits = 1 << format, perWord = 16 / bits, mask = (1 << bits) - 1
            for first in stride(from: 0, to: values.count, by: perWord) {
                var word = 0
                for index in 0..<perWord where first + index < values.count {
                    word |= (values[first + index] & mask) << (16 - (index + 1) * bits)
                }
                u16(word)
            }
        }
    }

    private func fixture(units: CGFloat = 1000, glyphs: [CGGlyph] = [5, 9]) -> Fixture {
        var f = Fixture()
        f.u16(1, 0, 10, 224, 0)
        f.u16(70, 50, 1300, 1300)
        for index in 0..<51 {
            let value = [1: 250, 4: 200, 5: 1000, 7: 300, 8: 300, 10: 1000, 13: 50][index] ?? 0
            f.record("constant\(index)", Int((CGFloat(value) * units / 1000).rounded()), parent: 10)
        }
        f.u16(60)
        f.u16(8, 28, 0, 48) // MathGlyphInfo.
        for kind in ["italic", "accent"] {
            let parent = f.bytes.count
            f.u16(12, 2)
            f.record(kind + "5", 0, parent: parent); f.record(kind + "9", 0, parent: parent)
            f.u16(1, 2, Int(glyphs[0]), Int(glyphs[1]))
        }
        let kernInfo = f.bytes.count
        f.u16(20, 2)
        for index in 0..<8 { f.u16(28 + index * 14) }
        f.u16(1, 2, Int(glyphs[0]), Int(glyphs[1]))
        for index in 0..<8 {
            let parent = f.bytes.count
            f.u16(1)
            f.record("height\(index)", Int((300 * units / 1000).rounded()), parent: parent)
            f.record("kern\(index)a", 0, parent: parent); f.record("kern\(index)b", 0, parent: parent)
        }
        XCTAssertEqual(kernInfo, 272)
        let variants = f.bytes.count
        f.set(8, variants)
        f.u16(0, 12, 0, 1, 0, 18) // Variants header, one construction offset.
        f.u16(1, 1, Int(glyphs[0])) // Coverage.
        f.u16(4, 0) // Construction, assembly offset.
        let assembly = f.bytes.count
        f.record("assembly", 0, parent: assembly)
        f.u16(1, 5, 0, 0, 1000, 1)
        return f
    }

    func testPackedDeviceSignedValuesBoundariesAndOptIn() throws {
        for (format, values) in [(1, [-2, -1, 0, 1, -2, 1, 0, -1, 1]),
                                 (2, [-8, -1, 0, 7, -7]), (3, [-128, -1, 0, 127, -127])] {
            var f = fixture(); f.device("constant1", start: 11, values: values, format: format)
            let table = try XCTUnwrap(MathTable(data: f.bytes, unitsPerEm: 1000, deviceScale: 2))
            for (index, pixels) in values.enumerated() {
                let size = CGFloat(11 + index) / 2
                XCTAssertEqual(table.constants(size: size).axisHeight * size,
                               size / 4 + CGFloat(pixels) / 2, accuracy: 1e-10)
            }
            for size: CGFloat in [5, CGFloat(11 + values.count) / 2] {
                XCTAssertEqual(table.constants(size: size).axisHeight, 0.25, accuracy: 1e-10)
            }
            let ignored = try XCTUnwrap(MathTable(data: f.bytes, unitsPerEm: 1000))
            XCTAssertEqual(ignored.constants(size: 6).axisHeight, 0.25)
        }
        var f = fixture(); f.device("constant1", start: 20, values: [2])
        let table = try XCTUnwrap(MathTable(data: f.bytes, unitsPerEm: 1000, deviceScale: 1))
        XCTAssertEqual(table.constants(size: 19.49).axisHeight, 0.25)
        XCTAssertEqual(table.constants(size: 19.5).axisHeight * 19.5, 19.5 / 4 + 2, accuracy: 1e-10)
        XCTAssertEqual(table.constants(size: 20.49).axisHeight * 20.49, 20.49 / 4 + 2, accuracy: 1e-10)
        XCTAssertEqual(table.constants(size: 20.5).axisHeight, 0.25)
    }

    func testEveryRelevantRecordUsesItsOwnParentAndFontSize() throws {
        var f = fixture()
        for name in ["constant1", "italic5", "accent5", "height0", "kern0a", "kern0b", "assembly"] {
            f.device(name, start: 20, values: [-2])
        }
        let table = try XCTUnwrap(MathTable(data: f.bytes, unitsPerEm: 1000, deviceScale: 2))
        // 20 PPEM = 10 points at 2x; -2 pixels = -1 point = -100 design units.
        XCTAssertEqual(table.constants(size: 10).axisHeight, 0.15, accuracy: 1e-10)
        XCTAssertEqual(table.italicsCorrection(5, size: 10), -100)
        XCTAssertEqual(table.topAccentAttachment(5, size: 10), -100)
        XCTAssertEqual(table.kern(5, corner: .topRight, height: 199, size: 10), -100)
        XCTAssertEqual(table.kern(5, corner: .topRight, height: 200, size: 10), -100)
        XCTAssertEqual(table.construction(5, vertical: true, size: 10)?.assemblyItalicsCorrection, -100)
        XCTAssertEqual(table.italicsCorrection(5, size: 20), 0)
        XCTAssertNil(table.italicsCorrection(7, size: 10))
        XCTAssertEqual(table.kern(7, corner: .topRight, height: 0, size: 10), 0)
        // Distinct values prove the corrected boundary, independently of the two kern deltas.
        f.set(f.records["kern0b"]!.record, 100)
        let boundary = try XCTUnwrap(MathTable(data: f.bytes, unitsPerEm: 1000, deviceScale: 2))
        XCTAssertEqual(boundary.kern(5, corner: .topRight, height: 199.99, size: 10), -100)
        XCTAssertEqual(boundary.kern(5, corner: .topRight, height: 200, size: 10), 0)
    }

    func testVariationIndexAppliesToAllRecordsAtDefaultAndSelectedCoordinates() throws {
        // GDEF1.3 → format1 store → one positive region and two signed delta rows.
        var gdef = Fixture()
        gdef.u16(1, 3, 0, 0, 0, 0, 0, 0, 18)
        gdef.u16(1, 0, 12, 1, 0, 22)
        gdef.u16(1, 1, 0, 16384, 16384)
        gdef.u16(2, 1, 1, 0, 100, -50)
        for coordinate: CGFloat in [0, 0.5, 1] {
            let store = try XCTUnwrap(MathVariationStore(gdef: gdef.bytes, normalizedCoordinates: [coordinate]))
            var f = fixture()
            for name in ["constant1", "italic5", "accent5", "height0", "kern0a", "kern0b", "assembly"] {
                let record = f.records[name]!
                f.set(record.record + 2, f.bytes.count - record.parent)
                f.u16(0, name == "italic5" ? 1 : 0, 0x8000)
            }
            f.set(f.records["kern0b"]!.record, 100)
            let table = try XCTUnwrap(MathTable(data: f.bytes, unitsPerEm: 1000, variationStore: store, deviceScale: 2))
            let delta = coordinate * 100
            XCTAssertEqual(table.constants.axisHeight, (250 + delta) / 1000, accuracy: 1e-10)
            XCTAssertEqual(table.constants(size: 10).axisHeight, (250 + delta) / 1000, accuracy: 1e-10)
            XCTAssertEqual(table.italicsCorrection(5, size: 10), -coordinate * 50)
            XCTAssertEqual(table.topAccentAttachment(5, size: 10), delta)
            XCTAssertEqual(table.construction(5, vertical: true, size: 10)?.assemblyItalicsCorrection, delta)
            XCTAssertEqual(table.kern(5, corner: .topRight, height: 300 + delta - 0.01, size: 10), delta)
            XCTAssertEqual(table.kern(5, corner: .topRight, height: 300 + delta, size: 10), 100 + delta)
            var invalid = f
            let record = invalid.records["constant1"]!
            let adjustment = record.parent + Int(UInt16(invalid.bytes[record.record + 2]) << 8 | UInt16(invalid.bytes[record.record + 3]))
            invalid.set(adjustment + 2, 2) // Missing inner delta row.
            XCTAssertEqual(try XCTUnwrap(MathTable(data: invalid.bytes, unitsPerEm: 1000, variationStore: store)).constants.axisHeight, 0.25)
        }
    }

    func testInvalidCorrectedKernHeightOrderRetainsOrderedBoundaries() throws {
        var f = fixture()
        let parent = f.bytes.count
        f.set(272 + 4, parent - 272) // Base top-right table now has two heights.
        f.u16(2)
        f.record("newHeight0", 100, parent: parent); f.record("newHeight1", 200, parent: parent)
        f.u16(10, 0, 20, 0, 30, 0)
        f.device("newHeight0", start: 20, values: [8]) // +400 design units makes heights 500,200.
        let table = try XCTUnwrap(MathTable(data: f.bytes, unitsPerEm: 1000, deviceScale: 1))
        XCTAssertEqual(table.kern(5, corner: .topRight, height: 99, size: 20), 10)
        XCTAssertEqual(table.kern(5, corner: .topRight, height: 100, size: 20), 20)
        XCTAssertEqual(table.kern(5, corner: .topRight, height: 200, size: 20), 30)
    }

    func testLargeDeviceKernTableRetainsSelectedVariationWithoutUnboundedSizeDecoding() throws {
        var gdef = Fixture()
        gdef.u16(1, 3, 0, 0, 0, 0, 0, 0, 18)
        gdef.u16(1, 0, 12, 1, 0, 22)
        gdef.u16(1, 1, 0, 16384, 16384)
        gdef.u16(1, 1, 1, 0, 100)
        let store = try XCTUnwrap(MathVariationStore(gdef: gdef.bytes, normalizedCoordinates: [1]))
        var f = fixture()
        let parent = f.bytes.count
        f.set(272 + 4, parent - 272)
        f.u16(1025)
        for height in 0..<1025 { f.u16(height, 0) }
        f.record("largeDeviceValue", 20, parent: parent)
        f.record("largeVariationValue", 20, parent: parent)
        for _ in 2...1025 { f.u16(20, 0) }
        f.device("largeDeviceValue", start: 20, values: [-2])
        let varied = f.records["largeVariationValue"]!
        f.set(varied.record + 2, f.bytes.count - parent); f.u16(0, 0, 0x8000)
        let table = try XCTUnwrap(MathTable(data: f.bytes, unitsPerEm: 1000, variationStore: store, deviceScale: 1))
        // Oversized corner tables omit device -2px but retain variation +100 design units.
        for size: CGFloat in [20, 20.1, 20.2, 20.3, 20.4] {
            XCTAssertEqual(table.kern(5, corner: .topRight, height: -1, size: size), 20)
            XCTAssertEqual(table.kern(5, corner: .topRight, height: 0, size: size), 120)
        }
    }

    func testLimitGapsAndAccentAttachmentsUseAdjustedPointGeometry() throws {
        let ctFont = CTFontCreateWithName("Helvetica" as CFString, 1, nil)
        let units = CGFloat(CTFontGetUnitsPerEm(ctFont))
        let selected = MathFont(base: ctFont, table: nil)
        let glyphs = try [XCTUnwrap(selected.glyph(for: "x")), XCTUnwrap(selected.glyph(for: "y"))]
        var f = fixture(units: units, glyphs: glyphs)
        f.set(f.records["constant14"]!.record, Int((200 * units / 1000).rounded())) // UpperLimitGapMin=4pt.
        f.device("constant14", start: 20, values: [2]) // Gap becomes 6pt.
        f.set(f.records["accent5"]!.record, Int((150 * units / 1000).rounded()))
        f.set(f.records["accent9"]!.record, Int((300 * units / 1000).rounded()))
        f.device("accent5", start: 20, values: [2]); f.device("accent9", start: 20, values: [-1])
        let table = try XCTUnwrap(MathTable(data: f.bytes, unitsPerEm: units, deviceScale: 1))
        let engine = LayoutEngine(font: MathFont(base: ctFont, table: table))
        for body in ["<mover accent=\"true\"><mi mathvariant=\"normal\">x</mi><mo stretchy=\"false\">y</mo></mover>",
                     "<mover accent=\"false\"><mo largeop=\"true\" stretchy=\"false\" movablelimits=\"false\">x</mo><mi mathvariant=\"normal\">y</mi></mover>"] {
            let result = try engine.layoutRoot(node(body), style: MathStyle(fontSize: 20, color: black))
            guard case .box(let underOver, _) = result.items[0],
                  case .box(let base, let basePoint) = underOver.items[0],
                  case .box(let over, let overPoint) = underOver.items[1] else { return XCTFail("missing under/over boxes") }
            if body.contains("accent=\"true\"") {
                // Base attachment 3+2=5pt; accent attachment 6-1=5pt, so baselines share x.
                XCTAssertEqual(overPoint.x - basePoint.x, 0, accuracy: 0.01)
                XCTAssertEqual(try XCTUnwrap(base.topAccentAttachment), 5, accuracy: 0.01)
                XCTAssertEqual(try XCTUnwrap(over.topAccentAttachment), 5, accuracy: 0.01)
            } else {
                XCTAssertEqual(overPoint.y, base.ascent + 6 + over.descent, accuracy: 0.01)
            }
            let ink = try XCTUnwrap(result.inkBounds)
            XCTAssertTrue([result.width, result.ascent, result.descent].allSatisfy { $0.isFinite })
            XCTAssertLessThanOrEqual(ink.maxY, result.ascent + 0.01)
            XCTAssertGreaterThanOrEqual(ink.minY, -result.descent - 0.01)
        }
    }

    func testMalformedAdjustmentsRetainUnadjustedValues() throws {
        var f = fixture(); f.device("constant1", start: 20, values: [-2])
        let adjustment = f.bytes.count - 8
        for (offset, value) in [(adjustment, 21), (adjustment + 4, 4),
                                (f.records["constant1"]!.record + 2, 65535)] {
            var bad = f; bad.set(offset, value)
            XCTAssertEqual(try XCTUnwrap(MathTable(data: bad.bytes, unitsPerEm: 1000, deviceScale: 1)).constants(size: 20).axisHeight, 0.25)
        }
        for length in adjustment..<f.bytes.count {
            let table = try XCTUnwrap(MathTable(data: Array(f.bytes.prefix(length)), unitsPerEm: 1000, deviceScale: 1))
            XCTAssertEqual(table.constants(size: 20).axisHeight, 0.25)
        }
        for scale: CGFloat in [0, -1, .nan, .infinity, 1.0 / 128, 128] {
            let table = try XCTUnwrap(MathTable(data: f.bytes, unitsPerEm: 1000, deviceScale: scale))
            XCTAssertNil(table.deviceScale); XCTAssertEqual(table.constants(size: 20).axisHeight, 0.25)
        }
        XCTAssertEqual(try XCTUnwrap(MathTable(data: f.bytes, unitsPerEm: .infinity)).unitsPerEm, 1000)
    }

    func testScriptPlacementUsesPixelsAtEachSizeIncludingRTLCorners() throws {
        let ctFont = CTFontCreateWithName("Helvetica" as CFString, 1, nil)
        let units = CGFloat(CTFontGetUnitsPerEm(ctFont))
        var f = fixture(units: units)
        for name in ["constant4", "constant7", "constant8"] { f.device(name, start: 20, values: [1]) }
        for corner in 0..<8 {
            for suffix in ["a", "b"] { f.device("kern\(corner)\(suffix)", start: corner < 4 ? 20 : 10, values: [corner < 4 ? 1 : -2]) }
        }
        let table = try XCTUnwrap(MathTable(data: f.bytes, unitsPerEm: units, deviceScale: 1))
        let engine = LayoutEngine(font: MathFont(base: ctFont, table: table))
        func box(glyph: CGGlyph, size: CGFloat, width: CGFloat, ascent: CGFloat, descent: CGFloat) -> MathBox {
            MathBox(width: width, ascent: ascent, descent: descent,
                    items: [.glyphs(GlyphRun(font: engine.font.font(size: size), glyphs: [glyph], positions: [.zero], color: black,
                                             ink: CGRect(x: 0, y: -descent, width: width, height: ascent + descent)))])
        }
        var base = box(glyph: 5, size: 20, width: 20, ascent: 8, descent: 2); base.italicCorrection = 2
        let script = box(glyph: 9, size: 10, width: 5, ascent: 4, descent: 1)
        for rtl in [false, true] {
            var context = LayoutContext(fontSize: 20, unclampedSize: 20, minSize: 8, display: false, color: black)
            context.alignmentRTL = rtl
            let result = engine.attachScripts(base, post: [(script, script)], pre: [], context)
            guard case .box(_, let baseOrigin) = result.items[0], case .box(_, let sub) = result.items[1],
                  case .box(_, let sup) = result.items[2] else { return XCTFail("missing script boxes") }
            // Each corner pair contributes +1 pixel -2 pixels = -1 point, independent of size.
            // SubShift 4 +1 =5; SuperShift 6 +1 =7; after-script space=1.
            XCTAssertEqual(sub.y, -5, accuracy: 0.01); XCTAssertEqual(sup.y, 7, accuracy: 0.01)
            XCTAssertEqual(result.width, 25, accuracy: 0.01)
            XCTAssertEqual(baseOrigin.x, rtl ? 5 : 0, accuracy: 0.01)
            XCTAssertEqual(sub.x, rtl ? 1 : 17, accuracy: 0.01)
            XCTAssertEqual(sup.x, rtl ? 1 : 19, accuracy: 0.01)
            let ink = try XCTUnwrap(result.inkBounds)
            XCTAssertGreaterThanOrEqual(ink.minX, 0); XCTAssertLessThanOrEqual(ink.maxX, result.width)
            XCTAssertGreaterThanOrEqual(ink.minY, -result.descent); XCTAssertLessThanOrEqual(ink.maxY, result.ascent)
        }
    }

    func testInheritedSizeSelectsDevicePixelsForTokenAndConstantMetrics() throws {
        let ctFont = CTFontCreateWithName("Helvetica" as CFString, 1, nil)
        let units = CGFloat(CTFontGetUnitsPerEm(ctFont))
        let selected = MathFont(base: ctFont, table: nil)
        let glyphs = try [XCTUnwrap(selected.glyph(for: "x")), XCTUnwrap(selected.glyph(for: "y"))]
        var f = fixture(units: units, glyphs: glyphs)
        f.device("italic5", start: 10, values: [2])
        f.device("constant1", start: 10, values: [-1])
        let table = try XCTUnwrap(MathTable(data: f.bytes, unitsPerEm: units, deviceScale: 1))
        let engine = LayoutEngine(font: MathFont(base: ctFont, table: table))
        let root = try node("<mstyle mathsize=\"10px\"><mi mathvariant=\"normal\">x</mi></mstyle>")
        let context = engine.inherit(root.children[0], engine.rootContext(root, style: MathStyle(fontSize: 20, color: black)))
        XCTAssertEqual(context.fontSize, 10)
        let tokenContext = engine.inherit(root.children[0].children[0], context)
        let token = try engine.token(root.children[0].children[0], tokenContext)
        // Helvetica x has a 0.5em advance: 5pt +2px at1x =7pt.
        XCTAssertEqual(token.italicCorrection, 2, accuracy: 1e-10)
        XCTAssertEqual(token.width, 7, accuracy: 0.01)
        XCTAssertEqual(engine.value(\.axisHeight, context), 1.5, accuracy: 0.01)
        var larger = context; larger.fontSize = 20
        XCTAssertEqual(engine.value(\.axisHeight, larger), 5, accuracy: 0.01)
    }

    func testDeviceFontCacheKeepsSizesAcrossPPEMBoundaryDistinct() throws {
        var f = fixture(); f.device("constant1", start: 21, values: [1])
        let table = try XCTUnwrap(MathTable(data: f.bytes, unitsPerEm: 1000, deviceScale: 1))
        let font = MathFont(base: CTFontCreateWithName("Helvetica" as CFString, 1, nil), table: table)
        for level in 0...2 {
            XCTAssertEqual(CTFontGetSize(font.font(size: 20.499, scriptLevel: level)), 20.499)
            XCTAssertEqual(CTFontGetSize(font.font(size: 20.501, scriptLevel: level)), 20.501)
        }
        XCTAssertEqual(font.constants(size: 20.499).axisHeight * 20.499, 20.499 / 4, accuracy: 1e-10)
        XCTAssertEqual(font.constants(size: 20.501).axisHeight * 20.501, 20.501 / 4 + 1, accuracy: 1e-10)
    }

    func testConcurrentSizeCachesAndCornerQueriesStayDeterministic() throws {
        var f = fixture()
        f.device("constant1", start: 10, values: Array(repeating: 1, count: 11))
        f.device("kern0a", start: 10, values: Array(repeating: -1, count: 11))
        f.device("kern0b", start: 10, values: Array(repeating: -1, count: 11))
        let table = try XCTUnwrap(MathTable(data: f.bytes, unitsPerEm: 1000, deviceScale: 2))
        let font = MathFont(base: CTFontCreateWithName("Helvetica" as CFString, 1, nil), table: table)
        DispatchQueue.concurrentPerform(iterations: 256) { index in
            let size = CGFloat(10 + index % 11) / 2
            XCTAssertEqual(font.constants(size: size).axisHeight * size, size / 4 + 0.5, accuracy: 1e-10)
            XCTAssertEqual(table.kern(5, corner: .topRight, height: 200, size: size) * size / 1000, -0.5, accuracy: 1e-10)
        }
        XCTAssertEqual(MathFont.named(nil, deviceScale: 2).table?.deviceScale, 2)
        XCTAssertNil(MathFont.named(nil).table?.deviceScale)
    }

    func testFontsWithoutAdjustmentsKeepGeometryAcrossDevicePolicies() throws {
        for font in [nil, "Helvetica"] {
            for body in ["<msubsup><mi>f</mi><mi>j</mi><mi>f</mi></msubsup>",
                         "<mover accent=\"true\"><mi>x</mi><mo>^</mo></mover>",
                         "<munderover><mo>∑</mo><mi>i</mi><mi>n</mi></munderover>"] {
                let root = try node(body, display: true)
                let normal = try MathLayout(root, style: MathStyle(fontSize: 20, color: black, fontName: font))
                let scaled = try MathLayout(root, style: MathStyle(fontSize: 20, color: black, fontName: font, mathDeviceScale: 2))
                XCTAssertEqual(normal.width, scaled.width); XCTAssertEqual(normal.ascent, scaled.ascent); XCTAssertEqual(normal.descent, scaled.descent)
                XCTAssertEqual(normal.axisHeight, scaled.axisHeight)
                let before = [scaled.width, scaled.ascent, scaled.descent, scaled.axisHeight]
                _ = ink(scaled)
                XCTAssertEqual(before, [scaled.width, scaled.ascent, scaled.descent, scaled.axisHeight])
            }
        }
    }
}
