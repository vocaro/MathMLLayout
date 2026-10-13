import CoreGraphics
import Foundation

/// The layout constants of an OpenType MATH table, in ems of the font size.
///
/// Field names follow the MathConstants table of the OpenType specification
/// (https://learn.microsoft.com/typography/opentype/spec/math). Fonts without a MATH table get
/// `fallback`, values close to Latin Modern Math's, so layout still works with any font.
struct MathConstants: Sendable {
    var scriptPercentScaleDown: CGFloat = 70
    var scriptScriptPercentScaleDown: CGFloat = 50
    var delimitedSubFormulaMinHeight: CGFloat = 1.3
    var displayOperatorMinHeight: CGFloat = 1.3
    var mathLeading: CGFloat = 0.154
    var axisHeight: CGFloat = 0.25
    var accentBaseHeight: CGFloat = 0.45
    var flattenedAccentBaseHeight: CGFloat = 0.664
    var subscriptShiftDown: CGFloat = 0.247
    var subscriptTopMax: CGFloat = 0.344
    var subscriptBaselineDropMin: CGFloat = 0.2
    var superscriptShiftUp: CGFloat = 0.363
    var superscriptShiftUpCramped: CGFloat = 0.289
    var superscriptBottomMin: CGFloat = 0.108
    var superscriptBaselineDropMax: CGFloat = 0.25
    var subSuperscriptGapMin: CGFloat = 0.16
    var superscriptBottomMaxWithSubscript: CGFloat = 0.344
    var spaceAfterScript: CGFloat = 0.056
    var upperLimitGapMin: CGFloat = 0.2
    var upperLimitBaselineRiseMin: CGFloat = 0.111
    var lowerLimitGapMin: CGFloat = 0.167
    var lowerLimitBaselineDropMin: CGFloat = 0.6
    var stackTopShiftUp: CGFloat = 0.444
    var stackTopDisplayStyleShiftUp: CGFloat = 0.677
    var stackBottomShiftDown: CGFloat = 0.345
    var stackBottomDisplayStyleShiftDown: CGFloat = 0.686
    var stackGapMin: CGFloat = 0.12
    var stackDisplayStyleGapMin: CGFloat = 0.28
    var stretchStackTopShiftUp: CGFloat = 0.111
    var stretchStackBottomShiftDown: CGFloat = 0.6
    var stretchStackGapAboveMin: CGFloat = 0.2
    var stretchStackGapBelowMin: CGFloat = 0.167
    var fractionNumeratorShiftUp: CGFloat = 0.394
    var fractionNumeratorDisplayStyleShiftUp: CGFloat = 0.677
    var fractionDenominatorShiftDown: CGFloat = 0.345
    var fractionDenominatorDisplayStyleShiftDown: CGFloat = 0.686
    var fractionNumeratorGapMin: CGFloat = 0.04
    var fractionNumDisplayStyleGapMin: CGFloat = 0.12
    var fractionRuleThickness: CGFloat = 0.04
    var fractionDenominatorGapMin: CGFloat = 0.04
    var fractionDenomDisplayStyleGapMin: CGFloat = 0.12
    var skewedFractionHorizontalGap: CGFloat = 0.35
    var skewedFractionVerticalGap: CGFloat = 0.096
    var overbarVerticalGap: CGFloat = 0.12
    var overbarRuleThickness: CGFloat = 0.04
    var overbarExtraAscender: CGFloat = 0.04
    var underbarVerticalGap: CGFloat = 0.12
    var underbarRuleThickness: CGFloat = 0.04
    var underbarExtraDescender: CGFloat = 0.04
    var radicalVerticalGap: CGFloat = 0.05
    var radicalDisplayStyleVerticalGap: CGFloat = 0.148
    var radicalRuleThickness: CGFloat = 0.04
    var radicalExtraAscender: CGFloat = 0.04
    var radicalKernBeforeDegree: CGFloat = 0.278
    var radicalKernAfterDegree: CGFloat = -0.556
    var radicalDegreeBottomRaisePercent: CGFloat = 60

    static let fallback = MathConstants()

    /// The MathValueRecords in table order, after the four leading integer fields.
    nonisolated(unsafe) private static let recordFields: [WritableKeyPath<MathConstants, CGFloat>] = [
        \.mathLeading, \.axisHeight, \.accentBaseHeight, \.flattenedAccentBaseHeight,
        \.subscriptShiftDown, \.subscriptTopMax, \.subscriptBaselineDropMin, \.superscriptShiftUp,
        \.superscriptShiftUpCramped, \.superscriptBottomMin, \.superscriptBaselineDropMax,
        \.subSuperscriptGapMin, \.superscriptBottomMaxWithSubscript, \.spaceAfterScript,
        \.upperLimitGapMin, \.upperLimitBaselineRiseMin, \.lowerLimitGapMin, \.lowerLimitBaselineDropMin,
        \.stackTopShiftUp, \.stackTopDisplayStyleShiftUp, \.stackBottomShiftDown,
        \.stackBottomDisplayStyleShiftDown, \.stackGapMin, \.stackDisplayStyleGapMin,
        \.stretchStackTopShiftUp, \.stretchStackBottomShiftDown, \.stretchStackGapAboveMin,
        \.stretchStackGapBelowMin, \.fractionNumeratorShiftUp, \.fractionNumeratorDisplayStyleShiftUp,
        \.fractionDenominatorShiftDown, \.fractionDenominatorDisplayStyleShiftDown,
        \.fractionNumeratorGapMin, \.fractionNumDisplayStyleGapMin, \.fractionRuleThickness,
        \.fractionDenominatorGapMin, \.fractionDenomDisplayStyleGapMin, \.skewedFractionHorizontalGap,
        \.skewedFractionVerticalGap, \.overbarVerticalGap, \.overbarRuleThickness, \.overbarExtraAscender,
        \.underbarVerticalGap, \.underbarRuleThickness, \.underbarExtraDescender, \.radicalVerticalGap,
        \.radicalDisplayStyleVerticalGap, \.radicalRuleThickness, \.radicalExtraAscender,
        \.radicalKernBeforeDegree, \.radicalKernAfterDegree,
    ]

    /// Reads the MathConstants subtable at `offset`; nil when it is truncated.
    init?(table: MathTable, offset: Int, unitsPerEm: CGFloat, size: CGFloat? = nil) {
        guard table.contains(offset, length: 8 + 4 * Self.recordFields.count + 2) else { return nil }
        scriptPercentScaleDown = CGFloat(table.int16(offset))
        scriptScriptPercentScaleDown = CGFloat(table.int16(offset + 2))
        delimitedSubFormulaMinHeight = CGFloat(table.uint16(offset + 4)) / unitsPerEm
        displayOperatorMinHeight = CGFloat(table.uint16(offset + 6)) / unitsPerEm
        var position = offset + 8
        for field in Self.recordFields {
            self[keyPath: field] = table.valueRecord(position, relativeTo: offset, size: size) / unitsPerEm
            position += 4 // value and device-table offset
        }
        radicalDegreeBottomRaisePercent = CGFloat(table.int16(position))
        if scriptPercentScaleDown <= 0 || scriptPercentScaleDown > 100 { scriptPercentScaleDown = 70 }
        if scriptScriptPercentScaleDown <= 0 || scriptScriptPercentScaleDown > 100 { scriptScriptPercentScaleDown = 50 }
    }

    init() {}
}

/// How a glyph stretches along one axis: pre-made size variants, and an assembly of parts for
/// sizes beyond the largest variant. Measurements are in font design units.
struct GlyphConstruction: Sendable {
    struct Part: Sendable {
        var glyph: CGGlyph
        var startConnector: CGFloat
        var endConnector: CGFloat
        var fullAdvance: CGFloat
        var isExtender: Bool
    }
    struct Variant: Sendable {
        var glyph: CGGlyph
        /// The variant's size along the stretch axis.
        var advance: CGFloat
    }
    /// Smallest first.
    var variants: [Variant]
    /// Bottom to top (vertical) or left to right (horizontal); empty when there is no assembly.
    var parts: [Part]
    var assemblyItalicsCorrection: CGFloat
}

/// An OpenType MATH table read from a font's bytes. Constants are read once; per-glyph data is
/// looked up by binary search in the coverage tables. Every read is bounds-checked, so a
/// malformed table yields missing data rather than a crash.
struct MathTable: Sendable {
    private let bytes: [UInt8]
    let unitsPerEm: CGFloat
    private(set) var constants = MathConstants.fallback
    private var italicsCorrection = 0
    private var topAccentAttachment = 0
    private var variants = 0
    private var kerns: [CGGlyph: [MathKern?]] = [:]
    private let variationStore: MathVariationStore?
    /// Fixed when the font is selected; drawing never changes recorded geometry.
    let deviceScale: CGFloat?

    init?(data: [UInt8], unitsPerEm: CGFloat, variationStore: MathVariationStore? = nil, deviceScale: CGFloat? = nil) {
        bytes = data
        self.unitsPerEm = unitsPerEm.isFinite && unitsPerEm > 0 ? unitsPerEm : 1000
        self.variationStore = variationStore
        self.deviceScale = deviceScale.flatMap { $0.isFinite && (1.0 / 64...64).contains($0) ? $0 : nil }
        guard contains(0, length: 10), uint16(0) == 1 else { return nil }
        guard let constants = MathConstants(table: self, offset: Int(uint16(4)), unitsPerEm: self.unitsPerEm) else { return nil }
        self.constants = constants
        let glyphInfo = Int(uint16(6))
        if glyphInfo > 0, contains(glyphInfo, length: 8) {
            italicsCorrection = subtable(glyphInfo, uint16(glyphInfo))
            topAccentAttachment = subtable(glyphInfo, uint16(glyphInfo + 2))
            kerns = readKerns(at: subtable(glyphInfo, uint16(glyphInfo + 6)))
        }
        variants = Int(uint16(8))
        if variants > 0, !contains(variants, length: 10) { variants = 0 }
    }

    private func subtable(_ base: Int, _ offset: UInt16) -> Int { offset == 0 ? 0 : base + Int(offset) }

    func contains(_ offset: Int, length: Int) -> Bool { offset >= 0 && length >= 0 && offset <= bytes.count && length <= bytes.count - offset }
    func uint16(_ offset: Int) -> UInt16 {
        guard contains(offset, length: 2) else { return 0 }
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }
    func int16(_ offset: Int) -> Int16 { Int16(bitPattern: uint16(offset)) }

    /// A MathValueRecord in design units. Device deltas are pixels, converted back to
    /// design units at the actual inherited/script size before the existing point conversion.
    func valueRecord(_ record: Int, relativeTo parent: Int, size: CGFloat? = nil) -> CGFloat {
        let base = CGFloat(int16(record))
        guard contains(record, length: 4) else { return base }
        let relative = Int(uint16(record + 2))
        guard relative > 0, parent >= 0, parent <= bytes.count,
              relative <= bytes.count - parent else { return base }
        let adjustment = parent + relative
        guard contains(adjustment, length: 6) else { return base }
        let format = uint16(adjustment + 4)
        if format == 0x8000 {
            return base + (variationStore?.delta(outer: Int(uint16(adjustment)), inner: Int(uint16(adjustment + 2))) ?? 0)
        }
        guard (1...3).contains(format), let scale = deviceScale, let size,
              size.isFinite, size > 0 else { return base }
        let ppemValue = (size * scale).rounded()
        guard ppemValue >= 1, ppemValue <= 65535 else { return base }
        let start = Int(uint16(adjustment)), end = Int(uint16(adjustment + 2))
        guard start <= end else { return base }
        let bits = 1 << Int(format), perWord = 16 / bits
        let wordCount = (end - start + perWord) / perWord
        guard contains(adjustment + 6, length: wordCount * 2) else { return base }
        let ppem = Int(ppemValue)
        guard ppem >= start, ppem <= end else { return base }
        let index = ppem - start, shift = 16 - bits * (index % perWord + 1)
        let mask = (1 << bits) - 1
        let packed = (Int(uint16(adjustment + 6 + index / perWord * 2)) >> shift) & mask
        let signed = packed & (1 << (bits - 1)) == 0 ? packed : packed - (1 << bits)
        let adjusted = base + CGFloat(signed) * unitsPerEm / (size * scale)
        return adjusted.isFinite ? adjusted : base
    }

    func constants(size: CGFloat) -> MathConstants {
        MathConstants(table: self, offset: Int(uint16(4)), unitsPerEm: unitsPerEm, size: size) ?? constants
    }

    /// The coverage index of `glyph` in the Coverage table at `offset`, if covered.
    private func coverageIndex(_ glyph: CGGlyph, coverage offset: Int) -> Int? {
        guard offset > 0, contains(offset, length: 4) else { return nil }
        let count = Int(uint16(offset + 2))
        var low = 0, high = count
        switch uint16(offset) {
        case 1:
            while low < high {
                let mid = (low + high) / 2
                let value = uint16(offset + 4 + mid * 2)
                if value == glyph { return mid }
                if value < glyph { low = mid + 1 } else { high = mid }
            }
        case 2:
            while low < high {
                let mid = (low + high) / 2
                let record = offset + 4 + mid * 6
                let start = uint16(record), end = uint16(record + 2)
                if glyph < start { high = mid } else if glyph > end { low = mid + 1 } else {
                    return Int(uint16(record + 4)) + Int(glyph - start)
                }
            }
        default: break
        }
        return nil
    }

    /// A coverage-keyed list of MathValueRecords: italics corrections or top accent attachments.
    private func glyphValue(_ glyph: CGGlyph, table offset: Int, size: CGFloat?) -> CGFloat? {
        guard offset > 0, contains(offset, length: 4) else { return nil }
        let coverage = offset + Int(uint16(offset))
        guard let index = coverageIndex(glyph, coverage: coverage), index < Int(uint16(offset + 2)) else { return nil }
        let record = offset + 4 + index * 4
        guard contains(record, length: 2) else { return nil }
        return valueRecord(record, relativeTo: offset, size: size)
    }

    func italicsCorrection(_ glyph: CGGlyph, size: CGFloat? = nil) -> CGFloat? { glyphValue(glyph, table: italicsCorrection, size: size) }
    func topAccentAttachment(_ glyph: CGGlyph, size: CGFloat? = nil) -> CGFloat? { glyphValue(glyph, table: topAccentAttachment, size: size) }

    /// Height-dependent corner correction, in design units. Missing or malformed data is zero.
    func kern(_ glyph: CGGlyph, corner: MathKernCorner, height: CGFloat, size: CGFloat? = nil) -> CGFloat {
        guard height.isFinite, let tables = kerns[glyph], let table = tables[corner.rawValue] else { return 0 }
        guard let size, size.isFinite, size > 0, deviceScale != nil else { return table.value(at: height) }
        return table.adjustedValue(at: height, size: size) { valueRecord($0, relativeTo: table.offset, size: size) }
    }

    private func readKerns(at offset: Int) -> [CGGlyph: [MathKern?]] {
        guard offset > 0, contains(offset, length: 4) else { return [:] }
        let count = Int(uint16(offset + 2)), recordsEnd = offset + 4 + count * 8
        guard contains(offset + 4, length: count * 8) else { return [:] }
        let coverage = subtable(offset, uint16(offset))
        guard coverage >= recordsEnd, contains(coverage, length: 4) else { return [:] }
        let coverageCount = Int(uint16(coverage + 2))
        var glyphs: [CGGlyph] = []
        var coverageEnd = coverage + 4
        switch uint16(coverage) {
        case 1:
            guard coverageCount == count, contains(coverage + 4, length: count * 2) else { return [:] }
            coverageEnd += count * 2
            for index in 0..<count {
                let glyph = uint16(coverage + 4 + index * 2)
                guard glyphs.last.map({ $0 < glyph }) ?? true else { return [:] }
                glyphs.append(glyph)
            }
        case 2:
            guard contains(coverage + 4, length: coverageCount * 6) else { return [:] }
            coverageEnd += coverageCount * 6
            for index in 0..<coverageCount {
                let record = coverage + 4 + index * 6
                let start = uint16(record), end = uint16(record + 2)
                guard start <= end, Int(uint16(record + 4)) == glyphs.count,
                      glyphs.last.map({ $0 < start }) ?? true,
                      glyphs.count + Int(end) - Int(start) + 1 <= count else { return [:] }
                glyphs.append(contentsOf: start...end)
            }
            guard glyphs.count == count else { return [:] }
        default: return [:]
        }
        let records = (0..<count).map { index in
            (0..<4).map { subtable(offset, uint16(offset + 4 + index * 8 + $0 * 2)) }
        }
        // Shared corner tables are parsed once. Distinct tables must not overlap each other or
        // coverage; this also bounds total allocation and work for malicious overlapping offsets.
        let offsets = Set(records.flatMap { $0 }.filter { $0 >= recordsEnd }).sorted()
        var tables: [Int: MathKern] = [:]
        for (index, table) in offsets.enumerated() {
            guard contains(table, length: 2) else { continue }
            let heightCount = Int(uint16(table))
            let end = table + 2 + (heightCount * 2 + 1) * 4
            guard contains(table + 2, length: (heightCount * 2 + 1) * 4),
                  end <= (index + 1 < offsets.count ? offsets[index + 1] : bytes.count),
                  end <= coverage || table >= coverageEnd else { continue }
            let heightRecords = (0..<heightCount).map { table + 2 + $0 * 4 }
            let rawHeights = heightRecords.map { CGFloat(int16($0)) }
            guard zip(rawHeights, rawHeights.dropFirst()).allSatisfy({ $0 < $1 }) else { continue }
            let adjustedHeights = heightRecords.map { valueRecord($0, relativeTo: table) }
            let heights = zip(adjustedHeights, adjustedHeights.dropFirst()).allSatisfy({ $0 < $1 }) ? adjustedHeights : rawHeights
            let valueRecords = (0...heightCount).map { table + 2 + heightCount * 4 + $0 * 4 }
            let values = valueRecords.map { valueRecord($0, relativeTo: table) }
            tables[table] = MathKern(offset: table, heightRecords: heightRecords, valueRecords: valueRecords, heights: heights, values: values)
        }
        var result: [CGGlyph: [MathKern?]] = [:]
        for (index, glyph) in glyphs.enumerated() { result[glyph] = records[index].map { tables[$0] } }
        return result
    }

    var minConnectorOverlap: CGFloat { variants > 0 ? CGFloat(uint16(variants)) : 0 }

    /// The vertical or horizontal construction of `glyph`, if the font has one.
    func construction(_ glyph: CGGlyph, vertical: Bool, size: CGFloat? = nil) -> GlyphConstruction? {
        guard variants > 0 else { return nil }
        let coverageOffset = Int(uint16(variants + (vertical ? 2 : 4)))
        guard coverageOffset > 0, let index = coverageIndex(glyph, coverage: variants + coverageOffset) else { return nil }
        let verticalCount = Int(uint16(variants + 6)), horizontalCount = Int(uint16(variants + 8))
        guard index < (vertical ? verticalCount : horizontalCount) else { return nil }
        let offset = Int(uint16(variants + 10 + 2 * (vertical ? index : verticalCount + index)))
        guard offset > 0 else { return nil }
        let construction = variants + offset
        guard contains(construction, length: 4) else { return nil }
        var result = GlyphConstruction(variants: [], parts: [], assemblyItalicsCorrection: 0)
        for item in 0..<min(Int(uint16(construction + 2)), 64) {
            let record = construction + 4 + item * 4
            guard contains(record, length: 4) else { break }
            result.variants.append(.init(glyph: uint16(record), advance: CGFloat(uint16(record + 2))))
        }
        let assemblyOffset = Int(uint16(construction))
        if assemblyOffset > 0, contains(construction + assemblyOffset, length: 6) {
            let assembly = construction + assemblyOffset
            result.assemblyItalicsCorrection = valueRecord(assembly, relativeTo: assembly, size: size)
            for item in 0..<min(Int(uint16(assembly + 4)), 32) {
                let record = assembly + 6 + item * 10
                guard contains(record, length: 10) else { result.parts = []; break }
                result.parts.append(.init(glyph: uint16(record), startConnector: CGFloat(uint16(record + 2)),
                                          endConnector: CGFloat(uint16(record + 4)),
                                          fullAdvance: CGFloat(uint16(record + 6)),
                                          isExtender: uint16(record + 8) & 1 != 0))
            }
        }
        return result.variants.isEmpty && result.parts.isEmpty ? nil : result
    }
}

/// Offset order in a MathKernInfoRecord.
enum MathKernCorner: Int, CaseIterable {
    case topRight, topLeft, bottomRight, bottomLeft
}

private final class MathKern: @unchecked Sendable {
    // Raw data is immutable. Per-size device decoding is bounded and protected by the lock.
    private let lock = NSLock()
    private var adjusted: [CGFloat: (heights: [CGFloat], values: [CGFloat])] = [:]
    let offset: Int
    let heightRecords: [Int]
    let valueRecords: [Int]
    let heights: [CGFloat]
    let values: [CGFloat]

    init(offset: Int, heightRecords: [Int], valueRecords: [Int], heights: [CGFloat], values: [CGFloat]) {
        self.offset = offset; self.heightRecords = heightRecords; self.valueRecords = valueRecords
        self.heights = heights; self.values = values
    }

    func adjustedValue(at height: CGFloat, size: CGFloat, resolve: (Int) -> CGFloat) -> CGFloat {
        // Bound repeated decoding under many distinct authored sizes. Large tables retain
        // their selected-instance variation corrections and omit only Device adjustments.
        guard heightRecords.count <= 1024 else { return value(at: height) }
        lock.lock(); defer { lock.unlock() }
        if let cached = adjusted[size] { return Self.value(at: height, heights: cached.heights, values: cached.values) }
        let corrected = heightRecords.map(resolve)
        let ordered = zip(corrected, corrected.dropFirst()).allSatisfy { $0 < $1 }
        let result = (heights: ordered ? corrected : heights, values: valueRecords.map(resolve))
        // At most four independent size evaluations per shared corner table are retained.
        if adjusted.count >= 4 { adjusted.removeAll() }
        adjusted[size] = result
        return Self.value(at: height, heights: result.heights, values: result.values)
    }

    func value(at height: CGFloat) -> CGFloat { Self.value(at: height, heights: heights, values: values) }

    private static func value(at height: CGFloat, heights: [CGFloat], values: [CGFloat]) -> CGFloat {
        var low = 0, high = heights.count
        while low < high {
            let middle = (low + high) / 2
            if height < heights[middle] { high = middle } else { low = middle + 1 }
        }
        return values[low]
    }
}
