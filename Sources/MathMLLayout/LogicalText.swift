import CoreGraphics
import CoreText
import Foundation

/// Shared by all text sources in one layout pass. Cached glyphs and repeated shaping are bounded
/// independently of input length; exhaustion becomes the public limitExceeded error.
final class TextShapingWork {
    static let limit = 2_000_000
    private(set) var spent = 0
    private(set) var exhausted = false

    func consume(_ count: Int) -> Bool {
        guard !exhausted, count <= Self.limit - spent else { exhausted = true; return false }
        spent += count
        return true
    }
}

struct LogicalTextSlice {
    let source: LogicalTextSource
    let range: Range<Int>
}

/// One normalized token, in logical UTF-16 order. A single typesetter resolves paragraph bidi
/// levels, including controls that begin before a selected line. CoreText creates each line's
/// visual runs and contextual glyphs from that paragraph's logical range (UAX #9 L1–L4).
final class LogicalTextSource {
    let typesetter: CTTypesetter
    let color: CGColor
    let work: TextShapingWork
    let words: [Range<Int>]
    let spaceWidth: CGFloat
    private var boxes: [Range<Int>: MathBox] = [:]

    init(_ text: CFAttributedString, color: CGColor, work: TextShapingWork) {
        typesetter = CTTypesetterCreateWithAttributedString(text)
        self.color = color
        self.work = work
        let string = CFAttributedStringGetString(text) as String
        let units = Array(string.utf16)
        var ranges: [Range<Int>] = []
        var start: Int?
        for (index, unit) in units.enumerated() {
            if unit == 0x20 {
                if let beginning = start { ranges.append(beginning..<index); start = nil }
            } else if start == nil { start = index }
        }
        if let start { ranges.append(start..<units.count) }
        // Author paragraph-edge spaces remain part of the edge words. Only the U+0020
        // separator at a soft break disappears; breaking elsewhere in the formula must not
        // trim a token that happened to keep all its words on that row.
        if !ranges.isEmpty {
            ranges[0] = 0..<ranges[0].upperBound
            let last = ranges.count - 1
            ranges[last] = ranges[last].lowerBound..<units.count
        }
        words = ranges
        if let space = units.firstIndex(of: 0x20) {
            spaceWidth = CGFloat(CTLineGetTypographicBounds(
                CTTypesetterCreateLine(typesetter, CFRange(location: space, length: 1)), nil, nil, nil))
        } else { spaceWidth = 0 }
    }

    func box(_ range: Range<Int>) -> MathBox {
        guard !range.isEmpty else { return .empty() }
        // Count cache hits too: repeatedly assembling arbitrarily long rows must also stay bounded.
        guard work.consume(range.count) else { return .empty(width: MathLimits.extent + 1) }
        if let cached = boxes[range] { return cached }
        let line = CTTypesetterCreateLine(typesetter, CFRange(location: range.lowerBound, length: range.count))
        let box = LayoutEngine.shapedTextBox(line, color: color)
        boxes[range] = box
        return box
    }
}
