import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

/// The OpenType MATH table reader: a table built here byte by byte from the specification
/// (https://learn.microsoft.com/typography/opentype/spec/math) must read back as written, and
/// no truncated or corrupted table may crash it.
final class MathTableTests: XCTestCase {
    /// Big-endian bytes.
    private struct Bytes {
        var data: [UInt8] = []
        var count: Int { data.count }
        mutating func u16(_ values: Int...) { for value in values { data.append(UInt8((value >> 8) & 0xFF)); data.append(UInt8(value & 0xFF)) } }
        mutating func append(_ other: Bytes) { data.append(contentsOf: other.data) }
    }

    /// The 51 MathValueRecords of MathConstants, in the specification's order.
    nonisolated(unsafe) private static let records: [(name: String, field: KeyPath<MathConstants, CGFloat>)] = [
        ("mathLeading", \.mathLeading), ("axisHeight", \.axisHeight), ("accentBaseHeight", \.accentBaseHeight),
        ("flattenedAccentBaseHeight", \.flattenedAccentBaseHeight), ("subscriptShiftDown", \.subscriptShiftDown), ("subscriptTopMax", \.subscriptTopMax),
        ("subscriptBaselineDropMin", \.subscriptBaselineDropMin), ("superscriptShiftUp", \.superscriptShiftUp),
        ("superscriptShiftUpCramped", \.superscriptShiftUpCramped), ("superscriptBottomMin", \.superscriptBottomMin),
        ("superscriptBaselineDropMax", \.superscriptBaselineDropMax), ("subSuperscriptGapMin", \.subSuperscriptGapMin),
        ("superscriptBottomMaxWithSubscript", \.superscriptBottomMaxWithSubscript), ("spaceAfterScript", \.spaceAfterScript),
        ("upperLimitGapMin", \.upperLimitGapMin), ("upperLimitBaselineRiseMin", \.upperLimitBaselineRiseMin), ("lowerLimitGapMin", \.lowerLimitGapMin),
        ("lowerLimitBaselineDropMin", \.lowerLimitBaselineDropMin), ("stackTopShiftUp", \.stackTopShiftUp),
        ("stackTopDisplayStyleShiftUp", \.stackTopDisplayStyleShiftUp), ("stackBottomShiftDown", \.stackBottomShiftDown),
        ("stackBottomDisplayStyleShiftDown", \.stackBottomDisplayStyleShiftDown), ("stackGapMin", \.stackGapMin), ("stackDisplayStyleGapMin", \.stackDisplayStyleGapMin),
        ("stretchStackTopShiftUp", \.stretchStackTopShiftUp), ("stretchStackBottomShiftDown", \.stretchStackBottomShiftDown),
        ("stretchStackGapAboveMin", \.stretchStackGapAboveMin), ("stretchStackGapBelowMin", \.stretchStackGapBelowMin),
        ("fractionNumeratorShiftUp", \.fractionNumeratorShiftUp), ("fractionNumeratorDisplayStyleShiftUp", \.fractionNumeratorDisplayStyleShiftUp),
        ("fractionDenominatorShiftDown", \.fractionDenominatorShiftDown), ("fractionDenominatorDisplayStyleShiftDown", \.fractionDenominatorDisplayStyleShiftDown),
        ("fractionNumeratorGapMin", \.fractionNumeratorGapMin), ("fractionNumDisplayStyleGapMin", \.fractionNumDisplayStyleGapMin),
        ("fractionRuleThickness", \.fractionRuleThickness), ("fractionDenominatorGapMin", \.fractionDenominatorGapMin),
        ("fractionDenomDisplayStyleGapMin", \.fractionDenomDisplayStyleGapMin), ("skewedFractionHorizontalGap", \.skewedFractionHorizontalGap),
        ("skewedFractionVerticalGap", \.skewedFractionVerticalGap), ("overbarVerticalGap", \.overbarVerticalGap), ("overbarRuleThickness", \.overbarRuleThickness),
        ("overbarExtraAscender", \.overbarExtraAscender), ("underbarVerticalGap", \.underbarVerticalGap), ("underbarRuleThickness", \.underbarRuleThickness),
        ("underbarExtraDescender", \.underbarExtraDescender), ("radicalVerticalGap", \.radicalVerticalGap),
        ("radicalDisplayStyleVerticalGap", \.radicalDisplayStyleVerticalGap), ("radicalRuleThickness", \.radicalRuleThickness),
        ("radicalExtraAscender", \.radicalExtraAscender), ("radicalKernBeforeDegree", \.radicalKernBeforeDegree), ("radicalKernAfterDegree", \.radicalKernAfterDegree),
    ]

    /// A whole MATH table. Record `i` of the constants holds `10 * (i + 1)` design units, the
    /// last one negative; glyph data is as the tests below read it back.
    private func table(scriptPercent: Int = 80, scriptScriptPercent: Int = 60, version: Int = 1) -> [UInt8] {
        var constants = Bytes()
        constants.u16(scriptPercent & 0xFFFF, scriptScriptPercent & 0xFFFF, 1500, 2500)
        for index in Self.records.indices { constants.u16(index == Self.records.count - 1 ? (-556 & 0xFFFF) : 10 * (index + 1), 0) }
        constants.u16(65)

        // Italics corrections for glyphs 5, 9 and 20, under a format 1 coverage.
        var italics = Bytes()
        italics.u16(4 + 3 * 4, 3, 50, 0, -30 & 0xFFFF, 0, 120, 0)
        italics.u16(1, 3, 5, 9, 20)
        // Top accent attachments for glyphs 10–12 and 30, under a format 2 (range) coverage.
        var accents = Bytes()
        accents.u16(4 + 4 * 4, 4, 100, 0, 200, 0, 300, 0, 400, 0)
        accents.u16(2, 2, 10, 12, 0, 30, 30, 3)
        var glyphInfo = Bytes()
        glyphInfo.u16(8, 8 + italics.count, 0, 0)
        glyphInfo.append(italics); glyphInfo.append(accents)

        // Vertical constructions for glyphs 7 (two variants and a three-part assembly) and 8 (one
        // variant); a horizontal one for glyph 40 (an assembly only).
        var verticalCoverage = Bytes(); verticalCoverage.u16(1, 2, 7, 8)
        var horizontalCoverage = Bytes(); horizontalCoverage.u16(1, 1, 40)
        var seven = Bytes()
        seven.u16(4 + 2 * 4, 2, 70, 1200, 71, 1800)
        seven.u16(25, 0, 3, 80, 0, 100, 500, 0, 81, 100, 100, 400, 1, 82, 100, 0, 500, 0)
        var eight = Bytes(); eight.u16(0, 1, 72, 900)
        var forty = Bytes()
        forty.u16(4, 0)
        forty.u16(0, 0, 2, 90, 0, 50, 300, 0, 91, 50, 0, 300, 1)
        let header = 10 + 3 * 2
        var variants = Bytes()
        variants.u16(40, header, header + verticalCoverage.count, 2, 1)
        let first = header + verticalCoverage.count + horizontalCoverage.count
        variants.u16(first, first + seven.count, first + seven.count + eight.count)
        variants.append(verticalCoverage); variants.append(horizontalCoverage); variants.append(seven); variants.append(eight); variants.append(forty)

        var whole = Bytes()
        whole.u16(version, 0, 10, 10 + constants.count, 10 + constants.count + glyphInfo.count)
        whole.append(constants); whole.append(glyphInfo); whole.append(variants)
        return whole.data
    }

    // MARK: Reading a well-formed table

    func testConstantsAreReadInSpecificationOrder() throws {
        let parsed = try XCTUnwrap(MathTable(data: table(), unitsPerEm: 1000))
        let constants = parsed.constants
        XCTAssertEqual(constants.scriptPercentScaleDown, 80); XCTAssertEqual(constants.scriptScriptPercentScaleDown, 60)
        XCTAssertEqual(constants.delimitedSubFormulaMinHeight, 1.5, accuracy: 1e-9); XCTAssertEqual(constants.displayOperatorMinHeight, 2.5, accuracy: 1e-9)
        XCTAssertEqual(Self.records.count, 51)
        for (index, record) in Self.records.enumerated() {
            let expected: CGFloat = index == Self.records.count - 1 ? -0.556 : CGFloat(index + 1) / 100
            XCTAssertEqual(constants[keyPath: record.field], expected, accuracy: 1e-9, record.name)
        }
        XCTAssertEqual(constants.radicalDegreeBottomRaisePercent, 65)
        // Design units scale by the font's units per em.
        let fine = try XCTUnwrap(MathTable(data: table(), unitsPerEm: 2048))
        XCTAssertEqual(fine.constants.axisHeight, 20.0 / 2048, accuracy: 1e-9); XCTAssertEqual(fine.unitsPerEm, 2048)
        XCTAssertEqual(try XCTUnwrap(MathTable(data: table(), unitsPerEm: 0)).unitsPerEm, 1000, "a font without units per em is read as 1000")
    }

    func testImplausibleScriptPercentagesFallBack() throws {
        for (given, expected) in [(0, 70), (-20, 70), (101, 70), (32767, 70), (100, 100), (1, 1)] {
            XCTAssertEqual(try XCTUnwrap(MathTable(data: table(scriptPercent: given), unitsPerEm: 1000)).constants.scriptPercentScaleDown, CGFloat(expected), "\(given)")
        }
        for (given, expected) in [(0, 50), (-1, 50), (500, 50), (55, 55)] {
            XCTAssertEqual(try XCTUnwrap(MathTable(data: table(scriptScriptPercent: given), unitsPerEm: 1000)).constants.scriptScriptPercentScaleDown, CGFloat(expected), "\(given)")
        }
    }

    func testGlyphValuesAreFoundThroughBothCoverageFormats() throws {
        let parsed = try XCTUnwrap(MathTable(data: table(), unitsPerEm: 1000))
        XCTAssertEqual(parsed.italicsCorrection(5), 50); XCTAssertEqual(parsed.italicsCorrection(9), -30); XCTAssertEqual(parsed.italicsCorrection(20), 120)
        for glyph in [CGGlyph(0), 4, 6, 8, 10, 19, 21, 100, 65535] { XCTAssertNil(parsed.italicsCorrection(glyph), "glyph \(glyph)") }
        XCTAssertEqual(parsed.topAccentAttachment(10), 100); XCTAssertEqual(parsed.topAccentAttachment(11), 200); XCTAssertEqual(parsed.topAccentAttachment(12), 300)
        XCTAssertEqual(parsed.topAccentAttachment(30), 400)
        for glyph in [CGGlyph(0), 9, 13, 29, 31, 65535] { XCTAssertNil(parsed.topAccentAttachment(glyph), "glyph \(glyph)") }
    }

    func testConstructionsAreReadForEachAxis() throws {
        let parsed = try XCTUnwrap(MathTable(data: table(), unitsPerEm: 1000))
        XCTAssertEqual(parsed.minConnectorOverlap, 40)
        let seven = try XCTUnwrap(parsed.construction(7, vertical: true))
        XCTAssertEqual(seven.variants.map(\.glyph), [70, 71]); XCTAssertEqual(seven.variants.map(\.advance), [1200, 1800])
        XCTAssertEqual(seven.assemblyItalicsCorrection, 25)
        XCTAssertEqual(seven.parts.map(\.glyph), [80, 81, 82]); XCTAssertEqual(seven.parts.map(\.isExtender), [false, true, false])
        XCTAssertEqual(seven.parts.map(\.startConnector), [0, 100, 100]); XCTAssertEqual(seven.parts.map(\.endConnector), [100, 100, 0])
        XCTAssertEqual(seven.parts.map(\.fullAdvance), [500, 400, 500])
        let eight = try XCTUnwrap(parsed.construction(8, vertical: true))
        XCTAssertEqual(eight.variants.map(\.glyph), [72]); XCTAssertTrue(eight.parts.isEmpty)
        let forty = try XCTUnwrap(parsed.construction(40, vertical: false))
        XCTAssertTrue(forty.variants.isEmpty); XCTAssertEqual(forty.parts.map(\.glyph), [90, 91]); XCTAssertEqual(forty.parts.map(\.isExtender), [false, true])
        // Each axis has its own coverage.
        XCTAssertNil(parsed.construction(7, vertical: false)); XCTAssertNil(parsed.construction(8, vertical: false)); XCTAssertNil(parsed.construction(40, vertical: true))
        for glyph in [CGGlyph(0), 6, 9, 39, 41, 65535] { XCTAssertNil(parsed.construction(glyph, vertical: true)); XCTAssertNil(parsed.construction(glyph, vertical: false)) }
    }

    func testOnlyVersionOneIsRead() {
        XCTAssertNotNil(MathTable(data: table(), unitsPerEm: 1000))
        XCTAssertNil(MathTable(data: table(version: 0), unitsPerEm: 1000)); XCTAssertNil(MathTable(data: table(version: 2), unitsPerEm: 1000))
        XCTAssertNil(MathTable(data: [], unitsPerEm: 1000)); XCTAssertNil(MathTable(data: [0, 1, 0, 0], unitsPerEm: 1000))
        XCTAssertNil(MathTable(data: Array(table().prefix(100)), unitsPerEm: 1000), "constants cut short")
    }

    // MARK: Malformed tables

    /// Every query the engine makes of a table, for a spread of glyphs.
    private func exercise(_ data: [UInt8], glyphs: [CGGlyph]) {
        guard let table = MathTable(data: data, unitsPerEm: 1000) else { return }
        XCTAssertTrue(table.constants.axisHeight.isFinite)
        _ = table.minConnectorOverlap
        for glyph in glyphs {
            _ = table.italicsCorrection(glyph); _ = table.topAccentAttachment(glyph)
            for vertical in [true, false] {
                guard let construction = table.construction(glyph, vertical: vertical) else { continue }
                XCTAssertLessThanOrEqual(construction.variants.count, 64); XCTAssertLessThanOrEqual(construction.parts.count, 32)
            }
        }
    }

    func testTruncatedTablesAreReadWithoutCrashing() {
        let whole = table(), glyphs = (0...100).map { CGGlyph($0) } + [65535]
        for length in 0...whole.count { exercise(Array(whole.prefix(length)), glyphs: glyphs) }
        // Missing glyph data is missing, not wrong: with only the constants, nothing else is found.
        let constantsOnly = MathTable(data: Array(whole.prefix(10 + 8 + 51 * 4 + 2)), unitsPerEm: 1000)
        XCTAssertEqual(constantsOnly?.constants.axisHeight, 0.02); XCTAssertNil(constantsOnly?.italicsCorrection(5)); XCTAssertNil(constantsOnly?.construction(7, vertical: true))
    }

    func testCorruptedTablesAreReadWithoutCrashing() {
        let whole = table(), glyphs = (0...100).map { CGGlyph($0) } + [65535]
        // Each byte in turn set to each extreme: every offset and count pointing somewhere wrong.
        for position in whole.indices {
            for value in [UInt8(0x00), 0x7F, 0x80, 0xFF] where whole[position] != value {
                var corrupt = whole
                corrupt[position] = value
                exercise(corrupt, glyphs: glyphs)
            }
        }
    }

    func testTheSystemFontsTableSurvivesCorruption() throws {
        let font = MathFont.named(nil)
        let data = try XCTUnwrap(CTFontCopyTable(font.base, CTFontTableTag(kCTFontTableMATH), [])) as Data
        let whole = [UInt8](data)
        XCTAssertNotNil(MathTable(data: whole, unitsPerEm: font.unitsPerEm))
        let named = "(){}[]|√∑∫xfA^~→⏞".unicodeScalars.compactMap { font.glyph(for: $0) }
        let glyphs = named + stride(from: 0, to: 6000, by: 97).map { CGGlyph($0) }
        var state: UInt64 = 0x1234_5678_9ABC_DEF0
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        for _ in 0..<150 { exercise(Array(whole.prefix(next(whole.count))), glyphs: glyphs) }
        for _ in 0..<300 {
            var corrupt = whole
            // Mostly near the start, where the offsets to everything else are.
            for _ in 0...next(4) { corrupt[next(2) == 0 ? next(600) : next(corrupt.count)] = UInt8(next(256)) }
            exercise(corrupt, glyphs: glyphs)
        }
    }

    // MARK: The platform's font

    func testThePlatformFontsConstantsArePlausible() throws {
        let font = MathFont.named(nil), constants = font.constants
        XCTAssertNotNil(font.table)
        XCTAssertEqual(font.unitsPerEm, 1000)
        // Every length is a sensible fraction of an em.
        for record in Self.records where record.name != "radicalKernAfterDegree" {
            let value = constants[keyPath: record.field]
            XCTAssertGreaterThan(value, 0, record.name); XCTAssertLessThan(value, 1.5, record.name)
        }
        XCTAssertLessThan(constants.radicalKernAfterDegree, 0); XCTAssertGreaterThan(constants.radicalKernAfterDegree, -1)
        XCTAssertGreaterThan(constants.radicalDegreeBottomRaisePercent, 30); XCTAssertLessThan(constants.radicalDegreeBottomRaisePercent, 90)
        XCTAssertGreaterThan(constants.scriptPercentScaleDown, constants.scriptScriptPercentScaleDown)
        XCTAssertGreaterThan(constants.displayOperatorMinHeight, 1); XCTAssertLessThan(constants.displayOperatorMinHeight, 3)
        // The axis is where the minus sign is, and the x-height is where accents sit.
        let minus = try XCTUnwrap(Rendering(try typeset("<mo>−</mo>")).bounds())
        XCTAssertEqual(minus.midY, constants.axisHeight * em, accuracy: 0.6)
        let x = try XCTUnwrap(Rendering(try typeset("<mi mathvariant=\"normal\">x</mi>")).bounds())
        XCTAssertEqual(x.maxY, constants.accentBaseHeight * em, accuracy: 0.6)
        // Display style is roomier than text style, and cramped superscripts sit lower.
        XCTAssertGreaterThanOrEqual(constants.fractionNumeratorDisplayStyleShiftUp, constants.fractionNumeratorShiftUp)
        XCTAssertGreaterThanOrEqual(constants.fractionDenominatorDisplayStyleShiftDown, constants.fractionDenominatorShiftDown)
        XCTAssertGreaterThanOrEqual(constants.fractionNumDisplayStyleGapMin, constants.fractionNumeratorGapMin)
        XCTAssertGreaterThanOrEqual(constants.stackDisplayStyleGapMin, constants.stackGapMin)
        XCTAssertGreaterThanOrEqual(constants.radicalDisplayStyleVerticalGap, constants.radicalVerticalGap)
        XCTAssertGreaterThan(constants.superscriptShiftUp, constants.superscriptShiftUpCramped)
        // Rules are all one weight in STIX Two Math, as in most math fonts.
        XCTAssertEqual(constants.fractionRuleThickness, constants.radicalRuleThickness); XCTAssertEqual(constants.overbarRuleThickness, constants.underbarRuleThickness)
    }

    func testThePlatformFontsGlyphDataIsUsable() throws {
        let font = MathFont.named(nil), table = try XCTUnwrap(font.table)
        XCTAssertGreaterThan(table.minConnectorOverlap, 0)
        // Fences: variants in increasing size, then an assembly with an extender.
        for fence in "([{)]}".unicodeScalars {
            let construction = try XCTUnwrap(table.construction(try XCTUnwrap(font.glyph(for: fence)), vertical: true), "\(fence)")
            XCTAssertGreaterThan(construction.variants.count, 3, "\(fence)")
            XCTAssertEqual(construction.variants.map(\.advance), construction.variants.map(\.advance).sorted(), "\(fence) variants grow")
            XCTAssertTrue(construction.parts.contains(where: \.isExtender), "\(fence) has an extender")
            XCTAssertTrue(construction.parts.contains { !$0.isExtender }, "\(fence) has end pieces")
            for part in construction.parts { XCTAssertGreaterThan(part.fullAdvance, 0, "\(fence)") }
            XCTAssertNil(table.construction(try XCTUnwrap(font.glyph(for: fence)), vertical: false), "\(fence) does not stretch sideways")
        }
        for horizontal in "→←⏞⏟".unicodeScalars {
            let glyph = try XCTUnwrap(font.glyph(for: horizontal))
            XCTAssertNotNil(table.construction(glyph, vertical: false), "\(horizontal)"); XCTAssertNil(table.construction(glyph, vertical: true), "\(horizontal)")
        }
        // Large operators have a display size; letters have none.
        for op in "∑∏∫∮⋃".unicodeScalars { XCTAssertGreaterThanOrEqual(try XCTUnwrap(table.construction(try XCTUnwrap(font.glyph(for: op)), vertical: true)).variants.count, 2, "\(op)") }
        XCTAssertNil(table.construction(try XCTUnwrap(font.glyph(for: "x")), vertical: true))
        // Slanted letters lean; upright ones do not need a correction.
        for letter in "𝑓𝑇𝑉𝑊".unicodeScalars { XCTAssertGreaterThan(try XCTUnwrap(table.italicsCorrection(try XCTUnwrap(font.glyph(for: letter))), "\(letter)"), 0, "\(letter)") }
        // Accents attach within the letter's advance.
        for letter in "A𝐴𝑥f".unicodeScalars {
            var glyph = try XCTUnwrap(font.glyph(for: letter)), advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font.font(size: 1000), .horizontal, &glyph, &advance, 1)
            let attachment = try XCTUnwrap(table.topAccentAttachment(glyph), "\(letter)")
            XCTAssertGreaterThan(attachment, 0, "\(letter)"); XCTAssertLessThan(attachment, advance.width * 1.2, "\(letter)")
        }
        XCTAssertNil(font.glyph(for: "数"), "a character the font lacks has no glyph")
    }

    func testFontSelection() {
        let standard = MathFont.named(nil)
        XCTAssertTrue(MathFont.named(nil) === standard, "fonts are shared")
        XCTAssertEqual(CTFontCopyPostScriptName(MathFont.named("NoSuchFont-Regular").base) as String, CTFontCopyPostScriptName(standard.base) as String)
        XCTAssertEqual(CTFontCopyPostScriptName(MathFont.named("").base) as String, CTFontCopyPostScriptName(standard.base) as String)
        let text = MathFont.named("Helvetica")
        XCTAssertEqual(CTFontCopyPostScriptName(text.base) as String, "Helvetica")
        XCTAssertNil(text.table, "a text font has no MATH table")
        XCTAssertEqual(text.constants.axisHeight, MathConstants.fallback.axisHeight)
        // Sized fonts are cached per size and script level; script levels turn on the font's script forms.
        XCTAssertEqual(CTFontGetSize(standard.font(size: 17)), 17); XCTAssertTrue(standard.font(size: 17) === standard.font(size: 17))
        XCTAssertEqual(CTFontGetSize(standard.font(size: 11.9, scriptLevel: 1)), 11.9, accuracy: 0.001)
        XCTAssertFalse(standard.font(size: 12, scriptLevel: 1) === standard.font(size: 12))
        XCTAssertTrue(standard.font(size: 12, scriptLevel: 7) === standard.font(size: 12, scriptLevel: 2), "levels past 2 share the script-script form")
        XCTAssertTrue(standard.font(size: 12, scriptLevel: -3) === standard.font(size: 12))
        XCTAssertEqual(standard.points(500, size: 20), 10)
    }
}
