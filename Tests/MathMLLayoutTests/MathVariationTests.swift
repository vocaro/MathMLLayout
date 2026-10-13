import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

final class MathVariationTests: XCTestCase {
    private struct Bytes {
        var data: [UInt8] = []
        mutating func u16(_ value: Int) {
            data.append(UInt8(truncatingIfNeeded: value >> 8))
            data.append(UInt8(truncatingIfNeeded: value))
        }
        mutating func u32(_ value: Int) { u16(value >> 16); u16(value) }
        mutating func fixed(_ value: Int) { u32(value * 65_536) }
    }

    /// One data subtable: first columns use int16; the remainder use int8.
    private func gdef(regions: [[(Int, Int, Int)]], rows: [[Int]], wordCount: Int,
                      indices: [Int]? = nil) -> [UInt8] {
        let columns = indices ?? Array(regions.indices)
        var regionData = Bytes()
        regionData.u16(regions.first?.count ?? 1)
        regionData.u16(regions.count)
        for region in regions {
            for (start, peak, end) in region {
                regionData.u16(start); regionData.u16(peak); regionData.u16(end)
            }
        }
        var itemData = Bytes()
        itemData.u16(rows.count); itemData.u16(wordCount); itemData.u16(columns.count)
        for index in columns { itemData.u16(index) }
        for row in rows {
            for (column, delta) in row.enumerated() {
                if column < wordCount { itemData.u16(delta) }
                else { itemData.data.append(UInt8(truncatingIfNeeded: delta)) }
            }
        }
        var data = Bytes()
        data.u16(1); data.u16(3)
        for _ in 0..<5 { data.u16(0) }
        data.u32(18)
        data.u16(1); data.u32(12); data.u16(1); data.u32(12 + regionData.data.count)
        data.data += regionData.data + itemData.data
        return data.data
    }

    private func overwrite(_ bytes: [UInt8], at offset: Int, value: Int) -> [UInt8] {
        var result = bytes
        result[offset] = UInt8(truncatingIfNeeded: value >> 8)
        result[offset + 1] = UInt8(truncatingIfNeeded: value)
        return result
    }

    func testSignedDeltasMultipleRegionsAndRows() throws {
        let data = gdef(regions: [[(0, 16_384, 16_384)], [(-16_384, -16_384, 0)], [(0, 0, 0)]],
                        rows: [[300, -120, -8], [-240, 110, 12]], wordCount: 1)
        let positive = try XCTUnwrap(MathVariationStore(gdef: data, normalizedCoordinates: [0.5]))
        XCTAssertEqual(try XCTUnwrap(positive.delta(outer: 0, inner: 0)), 142, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(positive.delta(outer: 0, inner: 1)), -108, accuracy: 0.000_001)
        let negative = try XCTUnwrap(MathVariationStore(gdef: data, normalizedCoordinates: [-0.5]))
        XCTAssertEqual(try XCTUnwrap(negative.delta(outer: 0, inner: 0)), -68, accuracy: 0.000_001)
        let defaultInstance = try XCTUnwrap(MathVariationStore(gdef: data, normalizedCoordinates: [0]))
        XCTAssertEqual(defaultInstance.delta(outer: 0, inner: 0), -8)
        XCTAssertEqual(positive.delta(outer: 0xFFFF, inner: 0xFFFF), 0)
        for (outer, inner) in [(-1, 0), (1, 0), (0, -1), (0, 2), (Int.max, Int.max)] {
            XCTAssertNil(positive.delta(outer: outer, inner: inner))
        }
    }

    func testIntermediateRegionMultipliesAxisScalarsAndHonorsColumnIndices() throws {
        let data = gdef(regions: [[(0, 8192, 16_384), (-16_384, -8192, 0)],
                                  [(0, 0, 0), (0, 0, 0)]],
                        rows: [[-10, 400]], wordCount: 2, indices: [1, 0])
        for coordinates: [CGFloat] in [[0.25, -0.25], [0.75, -0.75]] {
            let store = try XCTUnwrap(MathVariationStore(gdef: data, normalizedCoordinates: coordinates))
            XCTAssertEqual(try XCTUnwrap(store.delta(outer: 0, inner: 0)), 90, accuracy: 0.000_001)
        }
        let outside = try XCTUnwrap(MathVariationStore(gdef: data, normalizedCoordinates: [0.5, 0.5]))
        XCTAssertEqual(outside.delta(outer: 0, inner: 0), -10)
    }

    func testInvalidAxisRegionsAreIgnoredAsSpecified() throws {
        for region in [[(8192, 4096, 16_384)], [(-16_384, 8192, 16_384)], [(-16_384, 0, 16_384)]] {
            let data = gdef(regions: [region], rows: [[123]], wordCount: 1)
            let store = try XCTUnwrap(MathVariationStore(gdef: data, normalizedCoordinates: [-0.5]))
            XCTAssertEqual(store.delta(outer: 0, inner: 0), 123)
        }
    }

    func testMalformedStoresAndEveryTruncationAreSafe() {
        let data = gdef(regions: [[(0, 16_384, 16_384)]], rows: [[200]], wordCount: 1)
        for length in 0..<data.count {
            XCTAssertNil(MathVariationStore(gdef: Array(data.prefix(length)), normalizedCoordinates: [0.5]), "Length \(length)")
        }
        for coordinates: [CGFloat] in [[], [0, 0], [.nan], [.infinity], [1.1], Array(repeating: 0, count: 65)] {
            XCTAssertNil(MathVariationStore(gdef: data, normalizedCoordinates: coordinates))
        }
        // GDEF version, variation format, region count/coordinates, word count and region index.
        for (offset, value) in [(2, 2), (18, 2), (32, 4097), (36, 16_385),
                                (42, 0x8001), (42, 2), (46, 1)] {
            XCTAssertNil(MathVariationStore(gdef: overwrite(data, at: offset, value: value), normalizedCoordinates: [0.5]))
        }
        var noData = data
        for index in 26..<30 { noData[index] = 0 }
        let store = MathVariationStore(gdef: noData, normalizedCoordinates: [0.5])
        XCTAssertNotNil(store)
        XCTAssertNil(store?.delta(outer: 0, inner: 0))
    }

    private let weight: UInt32 = 0x77676874
    private let width: UInt32 = 0x77647468

    private func fvar() -> [UInt8] {
        var data = Bytes()
        for value in [1, 0, 16, 2, 2, 20, 0, 12] { data.u16(value) }
        for (tag, minimum, defaultValue, maximum) in [(width, 50, 100, 200), (weight, 100, 400, 900)] {
            data.u32(Int(tag)); data.fixed(minimum); data.fixed(defaultValue); data.fixed(maximum)
            data.u16(0); data.u16(256)
        }
        return data.data
    }

    private func avar() -> [UInt8] {
        var data = Bytes()
        for value in [1, 0, 0, 2] { data.u16(value) }
        for pairs in [[(-16_384, -16_384), (0, 0), (8192, 12_288), (16_384, 16_384)],
                      [(-16_384, -16_384), (0, 0), (16_384, 16_384)]] {
            data.u16(pairs.count)
            for (from, to) in pairs { data.u16(from); data.u16(to) }
        }
        return data.data
    }

    func testCoordinatesUseFvarOrderAndSelectedInstanceAndClamp() throws {
        let parsed = try XCTUnwrap(MathVariationCoordinates.normalized(fvar: fvar(), avar: nil,
                                                                       coordinates: [weight: 650, width: 75]))
        XCTAssertEqual(parsed, [-0.5, 0.5])
        XCTAssertEqual(MathVariationCoordinates.normalized(fvar: fvar(), avar: nil, coordinates: [:]), [0, 0])
        XCTAssertEqual(MathVariationCoordinates.normalized(fvar: fvar(), avar: nil,
                                                           coordinates: [weight: 10_000, width: -100]), [-1, 1])
        XCTAssertNil(MathVariationCoordinates.normalized(fvar: fvar(), avar: nil, coordinates: [weight: .nan]))
    }

    func testAvarPiecewiseInterpolationAndMissingAnchors() throws {
        let mapped = try XCTUnwrap(MathVariationCoordinates.normalized(fvar: fvar(), avar: avar(),
                                                                       coordinates: [width: 125, weight: 650]))
        XCTAssertEqual(mapped, [0.375, 0.5])
        let missingAnchor = overwrite(avar(), at: 22, value: 15_000)
        XCTAssertNil(MathVariationCoordinates.normalized(fvar: fvar(), avar: missingAnchor,
                                                         coordinates: [width: 125]))
    }

    func testMalformedCoordinateTablesAndEveryTruncationAreSafe() {
        let axes = fvar()
        for length in 0..<axes.count {
            XCTAssertNil(MathVariationCoordinates.normalized(fvar: Array(axes.prefix(length)), avar: nil, coordinates: [:]))
        }
        let mapping = avar()
        for length in 0..<mapping.count {
            XCTAssertNil(MathVariationCoordinates.normalized(fvar: axes, avar: Array(mapping.prefix(length)), coordinates: [:]))
        }
        XCTAssertNil(MathVariationCoordinates.normalized(fvar: axes, avar: overwrite(mapping, at: 0, value: 2), coordinates: [:]))
        XCTAssertNil(MathVariationCoordinates.normalized(fvar: axes, avar: overwrite(mapping, at: 6, value: 1), coordinates: [:]))
        XCTAssertNil(MathVariationCoordinates.normalized(fvar: overwrite(axes, at: 8, value: 65), avar: nil, coordinates: [:]))
    }

    func testActualCoreTextFontSelectionAppliesAvarAndMathVariation() throws {
        let root = try XCTUnwrap(Bundle.module.url(forResource: "ExternalFixtures", withExtension: nil))
        let url = root.appendingPathComponent("fonts/MathMLVariationTest.ttf")
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            XCTAssertEqual(error.map { CFErrorGetCode($0.takeRetainedValue()) }, CTFontManagerError.alreadyRegistered.rawValue)
        }
        let name = "MathMLVariationTest-Regular"
        let defaultFont = MathFont.named(name)
        let selectedFont = MathFont.named(name, variations: [weight: 650])
        XCTAssertEqual(CTFontCopyPostScriptName(defaultFont.base) as String, name)
        // CoreText appends an instance suffix to a non-default variable PostScript name.
        XCTAssertEqual(CTFontCopyFamilyName(selectedFont.base) as String, "MathML Variation Test")
        XCTAssertEqual(try XCTUnwrap(MathVariationCoordinates.normalized(font: defaultFont.base)).first, 0)
        XCTAssertEqual(try XCTUnwrap(MathVariationCoordinates.normalized(font: selectedFont.base)).first, 0.75)
        XCTAssertEqual(defaultFont.constants.axisHeight, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(selectedFont.constants.axisHeight, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(MathFont.named(name).constants.axisHeight, 0.2, accuracy: 0.000_001)
        XCTAssertTrue(MathFont.named(name, variations: [weight: 650]) === selectedFont)

        let node = try MathMLNode.parse(xml: Data("<math><mi mathvariant=\"normal\">x</mi></math>".utf8))
        let color = CGColor(gray: 0, alpha: 1)
        let defaultLayout = try MathLayout(node, style: MathStyle(fontSize: 20, color: color, fontName: name))
        let selectedLayout = try MathLayout(node, style: MathStyle(fontSize: 20, color: color, fontName: name,
                                                                   fontVariations: [weight: 650]))
        XCTAssertEqual(defaultLayout.axisHeight, 4, accuracy: 0.000_001)
        XCTAssertEqual(selectedLayout.axisHeight, 10, accuracy: 0.000_001)
        XCTAssertEqual(selectedLayout.width, defaultLayout.width, accuracy: 0.000_001)
    }
}
