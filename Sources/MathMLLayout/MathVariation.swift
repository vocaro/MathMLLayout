import CoreGraphics
import CoreText
import Foundation

/// GDEF 1.3 variation deltas in design units, evaluated for one immutable font instance.
/// See OpenType otvarcommonformats and otvaroverview. Limits bound work on untrusted fonts;
/// Resolved rows are cached so every MathValueRecord correction takes constant time.
struct MathVariationStore: Sendable {
    private let items: [[CGFloat]?]

    init?(gdef: [UInt8], normalizedCoordinates: [CGFloat]) {
        let bytes = VariationBytes(data: gdef)
        guard bytes.contains(0, 18), bytes.u16(0) == 1, bytes.u16(2) == 3,
              !normalizedCoordinates.isEmpty, normalizedCoordinates.count <= 64,
              normalizedCoordinates.allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else { return nil }
        let store = bytes.u32(14)
        guard store >= 18, bytes.contains(store, 8), bytes.u16(store) == 1 else { return nil }
        let itemCount = bytes.u16(store + 6)
        guard itemCount <= 4096, bytes.contains(store + 8, itemCount * 4) else { return nil }
        let headerSize = 8 + itemCount * 4
        let regionOffset = bytes.u32(store + 2)
        let regions = store + regionOffset
        guard regionOffset >= headerSize, bytes.contains(regions, 4) else { return nil }
        let axisCount = bytes.u16(regions)
        let regionCount = bytes.u16(regions + 2)
        guard axisCount == normalizedCoordinates.count, regionCount <= 4096,
              bytes.contains(regions + 4, axisCount * regionCount * 6) else { return nil }
        var scalars: [CGFloat] = []
        scalars.reserveCapacity(regionCount)
        for region in 0..<regionCount {
            var scalar: CGFloat = 1
            for axis in 0..<axisCount {
                let offset = regions + 4 + (region * axisCount + axis) * 6
                let start = bytes.f2dot14(offset)
                let peak = bytes.f2dot14(offset + 2)
                let end = bytes.f2dot14(offset + 4)
                guard (-1...1).contains(start), (-1...1).contains(peak), (-1...1).contains(end) else { return nil }
                // The specification ignores invalid axis regions and zero peaks.
                if start > peak || peak > end || (start < 0 && end > 0 && peak != 0) || peak == 0 { continue }
                let coordinate = normalizedCoordinates[axis]
                if coordinate < start || coordinate > end { scalar = 0 }
                else if coordinate < peak { scalar *= (coordinate - start) / (peak - start) }
                else if coordinate > peak { scalar *= (end - coordinate) / (end - peak) }
            }
            scalars.append(scalar)
        }

        var items: [[CGFloat]?] = []
        items.reserveCapacity(itemCount)
        var totalIndices = 0
        var totalCells = 0
        var totalRows = 0
        for item in 0..<itemCount {
            let relativeOffset = bytes.u32(store + 8 + item * 4)
            if relativeOffset == 0 { items.append(nil); continue }
            let offset = store + relativeOffset
            guard relativeOffset >= headerSize, bytes.contains(offset, 6) else { return nil }
            let count = bytes.u16(offset)
            let wordCount = bytes.u16(offset + 2)
            let indexCount = bytes.u16(offset + 4)
            // LONG_WORDS applies to variable 32-bit values in COLR, not GDEF.
            guard wordCount & 0x8000 == 0, wordCount <= indexCount, indexCount <= regionCount else { return nil }
            totalIndices += indexCount
            totalCells += count * indexCount
            totalRows += count
            guard totalIndices <= 65_536, totalCells <= 1_000_000, totalRows <= 1_000_000,
                  bytes.contains(offset + 6, indexCount * 2 + count * (wordCount + indexCount)) else { return nil }
            var indices: [Int] = []
            indices.reserveCapacity(indexCount)
            for index in 0..<indexCount {
                let region = bytes.u16(offset + 6 + index * 2)
                guard region < regionCount else { return nil }
                indices.append(region)
            }
            var rows: [CGFloat] = []
            rows.reserveCapacity(count)
            var position = offset + 6 + indexCount * 2
            for _ in 0..<count {
                var result: CGFloat = 0
                for (column, region) in indices.enumerated() {
                    let delta: CGFloat
                    if column < wordCount {
                        delta = CGFloat(bytes.i16(position))
                        position += 2
                    } else {
                        delta = CGFloat(Int8(bitPattern: bytes.data[position]))
                        position += 1
                    }
                    result += delta * scalars[region]
                }
                rows.append(result)
            }
            items.append(rows)
        }
        self.items = items
    }

    func delta(outer: Int, inner: Int) -> CGFloat? {
        if outer == 0xFFFF && inner == 0xFFFF { return 0 }
        guard items.indices.contains(outer), let rows = items[outer], rows.indices.contains(inner) else { return nil }
        return rows[inner]
    }
}

enum MathVariationCoordinates {
    /// Reads the selected CTFont instance, preserving the axis order used by GDEF.
    static func normalized(font: CTFont) -> [CGFloat]? {
        guard let fvar = CTFontCopyTable(font, CTFontTableTag(0x66766172), []) else { return nil }
        let avar = CTFontCopyTable(font, CTFontTableTag(0x61766172), [])
        let selected = CTFontCopyVariation(font) as? [NSNumber: NSNumber] ?? [:]
        var coordinates: [UInt32: CGFloat] = [:]
        for (tag, value) in selected { coordinates[tag.uint32Value] = CGFloat(value.doubleValue) }
        return normalized(fvar: Array(fvar as Data), avar: avar.map { Array($0 as Data) }, coordinates: coordinates)
    }

    /// Kept separate from CoreText so malformed and synthetic tables can be checked directly.
    static func normalized(fvar: [UInt8], avar: [UInt8]?, coordinates: [UInt32: CGFloat]) -> [CGFloat]? {
        let axes = VariationBytes(data: fvar)
        guard axes.contains(0, 16), axes.u16(0) == 1, axes.u16(2) == 0 else { return nil }
        let offset = axes.u16(4)
        let count = axes.u16(8)
        let size = axes.u16(10)
        guard offset >= 16, count > 0, count <= 64, size >= 20,
              axes.contains(offset, count * size) else { return nil }
        var seen: Set<UInt32> = []
        var normalized: [CGFloat] = []
        for axis in 0..<count {
            let position = offset + axis * size
            let tag = UInt32(axes.u32(position))
            guard seen.insert(tag).inserted else { return nil }
            let minimum = axes.fixed(position + 4)
            let defaultValue = axes.fixed(position + 8)
            let maximum = axes.fixed(position + 12)
            guard minimum <= defaultValue, defaultValue <= maximum else { return nil }
            let requested = coordinates[tag] ?? defaultValue
            guard requested.isFinite else { return nil }
            let selected = min(max(requested, minimum), maximum)
            let value: CGFloat
            if selected < defaultValue { value = (selected - defaultValue) / (defaultValue - minimum) }
            else if selected > defaultValue { value = (selected - defaultValue) / (maximum - defaultValue) }
            else { value = 0 }
            normalized.append(value)
        }
        guard let avar else { return normalized }
        let maps = VariationBytes(data: avar)
        // avar 2 requires an additional variation store; do not silently use v1 normalization.
        guard maps.contains(0, 8), maps.u16(0) == 1, maps.u16(2) == 0, maps.u16(6) == count else { return nil }
        var position = 8
        var totalPairs = 0
        for axis in 0..<count {
            guard maps.contains(position, 2) else { return nil }
            let pairCount = maps.u16(position)
            position += 2
            totalPairs += pairCount
            guard totalPairs <= 65_536, maps.contains(position, pairCount * 4) else { return nil }
            var pairs: [(from: CGFloat, to: CGFloat)] = []
            for _ in 0..<pairCount {
                let from = maps.f2dot14(position)
                let to = maps.f2dot14(position + 2)
                position += 4
                guard (-1...1).contains(from), (-1...1).contains(to) else { return nil }
                if let last = pairs.last, from <= last.from || to < last.to { return nil }
                pairs.append((from, to))
            }
            if pairs.isEmpty { continue }
            // Reject malformed maps so consumers retain unadjusted MATH metrics.
            guard pairs.contains(where: { $0.from == -1 && $0.to == -1 }),
                  pairs.contains(where: { $0.from == 0 && $0.to == 0 }),
                  pairs.contains(where: { $0.from == 1 && $0.to == 1 }) else { return nil }
            let value = normalized[axis]
            for index in 1..<pairs.count where value <= pairs[index].from {
                let lower = pairs[index - 1]
                let upper = pairs[index]
                normalized[axis] = lower.to + (value - lower.from) * (upper.to - lower.to) / (upper.from - lower.from)
                break
            }
        }
        return normalized
    }
}

/// All callers validate byte ranges before using the fixed-width readers.
private struct VariationBytes: Sendable {
    let data: [UInt8]
    func contains(_ offset: Int, _ length: Int) -> Bool {
        offset >= 0 && length >= 0 && offset <= data.count && length <= data.count - offset
    }
    func u16(_ offset: Int) -> Int { Int(data[offset]) << 8 | Int(data[offset + 1]) }
    func i16(_ offset: Int) -> Int16 { Int16(bitPattern: UInt16(u16(offset))) }
    func u32(_ offset: Int) -> Int { u16(offset) << 16 | u16(offset + 2) }
    func fixed(_ offset: Int) -> CGFloat { CGFloat(Int32(bitPattern: UInt32(u32(offset)))) / 65_536 }
    func f2dot14(_ offset: Int) -> CGFloat { CGFloat(i16(offset)) / 16_384 }
}
