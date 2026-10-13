import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

/// Synthetic design-unit data, with expectations computed independently in points.
final class MathKernTests: XCTestCase {
    private let glyphInfo = 224
    private let kernInfo = 232
    private let coverage = 252
    private let firstKern = 260

    private func bytes(rangeCoverage: Bool = false) -> [UInt8] {
        var data: [UInt8] = []
        func u16(_ values: Int...) {
            for value in values { data.append(UInt8((value >> 8) & 255)); data.append(UInt8(value & 255)) }
        }
        u16(1, 0, 10, glyphInfo, 0)
        u16(70, 50, 1300, 1300)
        for index in 0..<51 {
            // SubShift=4, SuperShift=6, SpaceAfterScript=1 at size 20.
            let value = [4: 200, 5: 1000, 7: 300, 8: 300, 10: 1000, 13: 50][index] ?? 0
            u16(value, 0)
        }
        u16(60)
        u16(0, 0, 0, 8) // GlyphInfo, kern offset from GlyphInfo.
        let coverageSize = rangeCoverage ? 16 : 8
        let start = 20 + coverageSize
        // Two records: base 5, script 9. All offsets relative to KernInfo.
        u16(20, 2, start, start + 14, start + 20, start + 34,
            start + 40, start + 46, start + 60, start + 66)
        if rangeCoverage { u16(2, 2, 5, 5, 0, 9, 9, 1) } else { u16(1, 2, 5, 9) }
        // Each MathValueRecord has a value and a device offset. No device corrections applied.
        u16(1, 300, 0, 50, 0, 150, 0) // base TR
        u16(0, -100, 0) // base TL
        u16(1, -50, 0, -100, 0, 200, 0) // base BR
        u16(0, 250, 0) // base BL
        u16(0, -200, 0) // script TR
        u16(1, 300, 0, 300, 0, -100, 0) // script TL
        u16(0, 50, 0) // script BR
        u16(1, 0, 0, -200, 0, 100, 0) // script BL
        return data
    }

    private func set(_ data: inout [UInt8], _ offset: Int, _ value: Int) {
        data[offset] = UInt8((value >> 8) & 255); data[offset + 1] = UInt8(value & 255)
    }

    func testCornerOffsetsCoverageFormatsAndBoundaryHeights() throws {
        for ranges in [false, true] {
            let table = try XCTUnwrap(MathTable(data: bytes(rangeCoverage: ranges), unitsPerEm: 1000))
            XCTAssertEqual(table.kern(5, corner: .topRight, height: 299.99), 50)
            XCTAssertEqual(table.kern(5, corner: .topRight, height: 300), 150)
            XCTAssertEqual(table.kern(5, corner: .topRight, height: 100000), 150)
            XCTAssertEqual(table.kern(5, corner: .topLeft, height: -100000), -100)
            XCTAssertEqual(table.kern(5, corner: .bottomRight, height: -51), -100)
            XCTAssertEqual(table.kern(5, corner: .bottomRight, height: -50), 200)
            XCTAssertEqual(table.kern(5, corner: .bottomLeft, height: 0), 250)
            XCTAssertEqual(table.kern(9, corner: .bottomLeft, height: -0.01), -200)
            XCTAssertEqual(table.kern(9, corner: .bottomLeft, height: 0), 100)
            for glyph in [CGGlyph(0), 4, 6, 8, 10, 65535] {
                for corner in MathKernCorner.allCases { XCTAssertEqual(table.kern(glyph, corner: corner, height: 0), 0) }
            }
            XCTAssertEqual(table.kern(5, corner: .topRight, height: .nan), 0)
        }
    }

    func testMissingMalformedAndTruncatedDataFallsBackToZero() throws {
        // Coverage/count mismatch, unsupported format, unordered glyphs, invalid offsets,
        // truncated height/value arrays and unordered correction heights.
        for (offset, value) in [(glyphInfo + 6, 0), (glyphInfo + 6, 65535),
                                (kernInfo, 0), (kernInfo, 65535), (kernInfo + 2, 65535),
                                (coverage, 3), (coverage + 2, 3), (coverage + 6, 4),
                                (kernInfo + 4, 0), (kernInfo + 4, 65535), (firstKern, 65535)] {
            var data = bytes(); set(&data, offset, value)
            let table = try XCTUnwrap(MathTable(data: data, unitsPerEm: 1000))
            XCTAssertEqual(table.kern(5, corner: .topRight, height: 300), 0, "offset \(offset), value \(value)")
        }
        var unordered = bytes()
        // Make TR a two-height table with equal transition heights.
        set(&unordered, firstKern, 2); set(&unordered, firstKern + 6, 300)
        XCTAssertEqual(try XCTUnwrap(MathTable(data: unordered, unitsPerEm: 1000)).kern(5, corner: .topRight, height: 300), 0)
        for length in 0..<firstKern + 14 {
            let table = MathTable(data: Array(bytes().prefix(length)), unitsPerEm: 1000)
            XCTAssertEqual(table?.kern(5, corner: .topRight, height: 300) ?? 0, 0, "length \(length)")
        }
        for (offset, value) in [(coverage + 8, 4), (coverage + 14, 0), (coverage + 10, 4)] {
            var data = bytes(rangeCoverage: true); set(&data, offset, value)
            XCTAssertEqual(try XCTUnwrap(MathTable(data: data, unitsPerEm: 1000)).kern(5, corner: .topRight, height: 300), 0)
        }
    }

    func testSharedTablesAndMultipleHeightIntervals() throws {
        var data = bytes()
        // Two corners may share a table without reparsing or discarding it.
        set(&data, kernInfo + 6, firstKern - kernInfo)
        let shared = try XCTUnwrap(MathTable(data: data, unitsPerEm: 1000))
        XCTAssertEqual(shared.kern(5, corner: .topLeft, height: 300), 150)
        XCTAssertFalse(shared.contains(Int.max, length: 1))
        XCTAssertFalse(shared.contains(0, length: Int.max))
        // Append a distinct table with negative and positive transition heights.
        let tableOffset = data.count - kernInfo
        set(&data, kernInfo + 4, tableOffset)
        for value in [2, -100, 0, 200, 0, -40, 0, 20, 0, 70, 0] {
            data.append(UInt8((value >> 8) & 255)); data.append(UInt8(value & 255))
        }
        let table = try XCTUnwrap(MathTable(data: data, unitsPerEm: 1000))
        for (height, expected) in [(-101, -40), (-100, 20), (0, 20), (199, 20), (200, 70), (201, 70)] {
            XCTAssertEqual(table.kern(5, corner: .topRight, height: CGFloat(height)), CGFloat(expected))
        }
    }

    private func fixture() throws -> (LayoutEngine, MathBox, MathBox, LayoutContext) {
        let baseFont = CTFontCreateWithName("Helvetica" as CFString, 1, nil)
        let units = CGFloat(CTFontGetUnitsPerEm(baseFont))
        // Match synthetic design units to the actual font to test conversion without dependence
        // on any installed font's MathKernInfo or script variants.
        var data = bytes()
        for offset in stride(from: 18, to: 222, by: 4) {
            let value = CGFloat(Int16(bitPattern: UInt16(data[offset]) << 8 | UInt16(data[offset + 1])))
            set(&data, offset, Int((value * units / 1000).rounded()))
        }
        for offset in [262, 266, 270, 276, 282, 286, 290, 296, 302, 308, 312, 316, 322, 328, 332, 336] {
            let value = CGFloat(Int16(bitPattern: UInt16(data[offset]) << 8 | UInt16(data[offset + 1])))
            set(&data, offset, Int((value * units / 1000).rounded()))
        }
        let table = try XCTUnwrap(MathTable(data: data, unitsPerEm: units))
        let engine = LayoutEngine(font: MathFont(base: baseFont, table: table))
        func box(_ glyph: CGGlyph, size: CGFloat, width: CGFloat, ascent: CGFloat, descent: CGFloat) -> MathBox {
            let rect = CGRect(x: 0, y: -descent, width: width, height: ascent + descent)
            return MathBox(width: width, ascent: ascent, descent: descent,
                           items: [.glyphs(GlyphRun(font: engine.font.font(size: size), glyphs: [glyph], positions: [.zero], color: black, ink: rect))])
        }
        var base = box(5, size: 20, width: 20, ascent: 8, descent: 2)
        base.italicCorrection = 2
        return (engine, base, box(9, size: 10, width: 5, ascent: 4, descent: 1),
                LayoutContext(fontSize: 20, unclampedSize: 20, minSize: 8, display: false, color: black))
    }

    func testPostscriptPlacementUsesMinimumOfTwoSumsAndEachFontsSize() throws {
        let (engine, base, script, context) = try fixture()
        // TR + BL: min(1 - 2, 3 + 1) = -1 points. BR + TL: min(4 - 1, -2 + 3) = 1.
        let result = engine.attachScripts(base, post: [(script, script)], pre: [], context)
        guard case .box(_, let sub) = result.items[1], case .box(_, let sup) = result.items[2] else { return XCTFail("missing scripts") }
        XCTAssertEqual(sub.x, 19, accuracy: 0.04); XCTAssertEqual(sub.y, -4, accuracy: 0.04)
        XCTAssertEqual(sup.x, 19, accuracy: 0.04); XCTAssertEqual(sup.y, 6, accuracy: 0.04)
        XCTAssertEqual(result.width, 25, accuracy: 0.05)
        XCTAssertEqual(engine.scriptKern(base, script, shift: 7, upper: true, before: false), 1, accuracy: 0.04,
                       "base height exactly 300 chooses the next interval")
    }

    func testPrescriptsMirrorCornersAndExpandTheAdvance() throws {
        let (engine, base, script, context) = try fixture()
        // TL + BR = -2 + 0.5 = -1.5; BL + TR = 5 - 2 = 3.
        let result = engine.attachScripts(base, post: [], pre: [(script, script)], context)
        guard case .box(_, let sub) = result.items[0], case .box(_, let sup) = result.items[1],
              case .box(_, let origin) = result.items[2] else { return XCTFail("missing prescripts") }
        XCTAssertEqual(sub.x, 0, accuracy: 0.04); XCTAssertEqual(sup.x, 4.5, accuracy: 0.04)
        XCTAssertEqual(origin.x, 9, accuracy: 0.04); XCTAssertEqual(result.width, 29, accuracy: 0.05)
    }

    func testCompoundPositionedFallbackAndMissingTablesUseZero() throws {
        let (engine, base, script, _) = try fixture()
        var compound = script; compound.items += script.items
        XCTAssertEqual(engine.scriptKern(base, compound, shift: 6, upper: true, before: false), 0)
        var positioned = script
        guard case .glyphs(var run) = positioned.items[0] else { return XCTFail() }
        run.positions = [CGPoint(x: 0, y: 1)]; positioned.items = [.glyphs(run)]
        XCTAssertEqual(engine.scriptKern(base, positioned, shift: 6, upper: true, before: false), 0)
        run.font = CTFontCreateWithName("TimesNewRomanPSMT" as CFString, 10, nil); run.positions = [.zero]
        positioned.items = [.glyphs(run)]
        XCTAssertEqual(engine.scriptKern(base, positioned, shift: 6, upper: true, before: false), 0)
        let textEngine = LayoutEngine(fontName: "Helvetica")
        XCTAssertEqual(textEngine.scriptKern(base, script, shift: 6, upper: true, before: false), 0)
    }

    func testRealFormulaInkIsContainedForAllScriptKinds() throws {
        for font in [nil, "Helvetica"] {
            for body in ["<msup><mi>ω</mi><mi>f</mi></msup>", "<msub><mi>V</mi><mi>A</mi></msub>",
                         "<msubsup><mi>f</mi><mi>j</mi><mi>f</mi></msubsup>",
                         "<mmultiscripts><mi>V</mi><mi>A</mi><mi>f</mi><mprescripts/><mi>j</mi><mi>f</mi></mmultiscripts>"] {
                let layout = try typeset(body, font: font)
                let ink = try XCTUnwrap(Rendering(layout).bounds(), body)
                XCTAssertGreaterThanOrEqual(ink.minX, -0.6, body); XCTAssertLessThanOrEqual(ink.maxX, layout.width + 0.6, body)
                XCTAssertGreaterThanOrEqual(ink.minY, -layout.descent - 0.6, body)
                XCTAssertLessThanOrEqual(ink.maxY, layout.ascent + 0.6, body)
            }
        }
    }
}
