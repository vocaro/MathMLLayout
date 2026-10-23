import CoreGraphics
import CoreText
import Foundation

/// Shared by all text sources in one layout pass. Cached glyphs and repeated shaping are bounded
/// independently of input length; exhaustion becomes the public limitExceeded error.
final class TextShapingWork {
    static let limit = 2_000_000
    private(set) var spent = 0
    private(set) var exhausted = false
    /// CoreText line requests, independently of cache hits and the UTF-16/assembly work budget.
    private(set) var lineRequests = 0
    private(set) var rowAssemblies = 0
    /// Kept from pass to pass: what a glyph's ink is does not change with the width tried.
    let glyphInk: GlyphInk

    init(glyphInk: GlyphInk = GlyphInk()) { self.glyphInk = glyphInk }

    func requestedLine() { lineRequests += 1 }
    func assembledRow() { rowAssemblies += 1 }

    func consume(_ count: Int) -> Bool {
        guard !exhausted, count <= Self.limit - spent else { exhausted = true; return false }
        spent += count
        return true
    }
}

/// The ink of each glyph one layout has measured, in each font it measured it in.
///
/// CoreText takes a glyph's ink from its outline, and FontParser keeps outlines in one cache per
/// font file behind one lock, which every size of the font and every thread share. Line breaking
/// shapes the same words again for each row and each width it tries, and asked for the ink of
/// every glyph each time: a release build laying formulas out on 18 threads spent most of its CPU
/// time in the kernel, waiting for that lock. A layout runs on one thread, so what it keeps here
/// needs no lock of its own.
final class GlyphInk {
    /// Holding the font keeps its address, the key, from passing to another font.
    private final class Measured {
        let font: CTFont
        var rects: [CGGlyph: CGRect] = [:]
        init(_ font: CTFont) { self.font = font }
    }
    private var fonts: [ObjectIdentifier: Measured] = [:]
    private var count = 0
    /// Glyphs whose ink was asked of CoreText.
    private(set) var requests = 0

    /// What `CTFontGetBoundingRectsForGlyphs` gives for each of `glyphs` in `font`.
    func rects(_ glyphs: [CGGlyph], in font: CTFont) -> [CGRect] {
        // Bounded like a layout's other caches: a full one starts again.
        if count >= 16_384 || fonts.count >= 64 { fonts.removeAll(); count = 0 }
        let measured = fonts[ObjectIdentifier(font)] ?? Measured(font)
        fonts[ObjectIdentifier(font)] = measured
        let missing = Array(Set(glyphs.lazy.filter { measured.rects[$0] == nil }))
        if !missing.isEmpty {
            var rects = [CGRect](repeating: .zero, count: missing.count)
            CTFontGetBoundingRectsForGlyphs(font, .horizontal, missing, &rects, missing.count)
            for (glyph, rect) in zip(missing, rects) { measured.rects[glyph] = rect }
            count += missing.count
            requests += missing.count
        }
        return glyphs.map { measured.rects[$0]! }
    }

    func rect(_ glyph: CGGlyph, in font: CTFont) -> CGRect { rects([glyph], in: font)[0] }
}

struct LogicalTextSlice {
    let source: LogicalTextSource
    let range: Range<Int>
}

/// CoreText owns the delegate, which owns this box until its attributed paragraph is released.
final class LogicalTextAttachment {
    let box: MathBox
    init(_ box: MathBox) { self.box = box }

    static func delegate(_ box: MathBox) -> CTRunDelegate {
        var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1,
            dealloc: { Unmanaged<LogicalTextAttachment>.fromOpaque($0).release() },
            getAscent: { Unmanaged<LogicalTextAttachment>.fromOpaque($0).takeUnretainedValue().box.ascent },
            getDescent: { Unmanaged<LogicalTextAttachment>.fromOpaque($0).takeUnretainedValue().box.descent },
            getWidth: { Unmanaged<LogicalTextAttachment>.fromOpaque($0).takeUnretainedValue().box.width })
        let reference = Unmanaged.passRetained(LogicalTextAttachment(box)).toOpaque()
        return CTRunDelegateCreate(&callbacks, reference)!
    }
}

final class LogicalTextDecoration {
    static let key = "MathMLLogicalTextBackground"
    let color: CGColor
    let ascent: CGFloat
    let descent: CGFloat
    init(color: CGColor, ascent: CGFloat, descent: CGFloat) {
        self.color = color; self.ascent = ascent; self.descent = descent
    }
}

/// One normalized token, in logical UTF-16 order. A single typesetter resolves paragraph bidi
/// levels, including controls that begin before a selected line. CoreText creates each line's
/// visual runs and contextual glyphs from that paragraph's logical range (UAX #9 L1–L4).
final class LogicalTextSource {
    let attributedString: CFAttributedString
    let string: String
    let hasAttachments: Bool
    /// A decorated fallback can be expanded back into its surrounding logical paragraph.
    let decoration: LogicalTextDecoration?
    private let inputOffsets: [Int]?
    let typesetter: CTTypesetter
    let color: CGColor
    let work: TextShapingWork
    let words: [Range<Int>]
    let spaceWidth: CGFloat
    private let trackAlignment: Bool
    private var alignmentMark: (offset: Int, word: Range<Int>, event: AlignmentEvent)?
    private var boxes: [Range<Int>: MathBox] = [:]
    private var itemCounts: [Range<Int>: Int] = [:]

    init(_ text: CFAttributedString, color: CGColor, work: TextShapingWork, trackAlignment: Bool = false,
         hasAttachments: Bool = false, inputOffsets: [Int]? = nil, decoration: LogicalTextDecoration? = nil) {
        attributedString = text
        string = CFAttributedStringGetString(text) as String
        self.hasAttachments = hasAttachments
        self.inputOffsets = inputOffsets
        self.decoration = decoration
        typesetter = CTTypesetterCreateWithAttributedString(text)
        self.color = color
        self.work = work
        self.trackAlignment = trackAlignment
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
            work.requestedLine()
            spaceWidth = CGFloat(CTLineGetTypographicBounds(
                CTTypesetterCreateLine(typesetter, CFRange(location: space, length: 1)), nil, nil, nil))
        } else { spaceWidth = 0 }
    }

    func logicalOffset(_ offset: Int) -> Int {
        guard let inputOffsets else { return min(max(0, offset), string.utf16.count) }
        return inputOffsets[min(max(0, offset), inputOffsets.count - 1)]
    }

    func caret(_ offset: Int) -> CGFloat {
        work.requestedLine()
        let line = CTTypesetterCreateLine(typesetter, CFRange(location: 0, length: string.utf16.count))
        return caret(line, offset: logicalOffset(offset))
    }

    /// At a bidi boundary CoreText's primary caret can follow the neighboring text run.
    /// An attachment mark instead follows its exact logical edge in the drawn object run.
    private func caret(_ line: CTLine, offset: Int) -> CGFloat {
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard attributes[kCTRunDelegateAttributeName] != nil else { continue }
            let range = CTRunGetStringRange(run)
            guard offset == range.location || offset == range.location + range.length else { continue }
            var position = CGPoint.zero
            CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
            let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(), nil, nil, nil))
            let before = offset == range.location
            return position.x + ((before == CTRunGetStatus(run).contains(.rightToLeft)) ? width : 0)
        }
        return CTLineGetOffsetForStringIndex(line, offset, nil)
    }

    /// Added wrapper drawing invalidates reshaping; source attachment drawing is eligible.
    func matchesItemCount(_ count: Int, range: Range<Int>) -> Bool {
        itemCounts[range] == count
    }

    /// A mark in a separator follows its requested neighboring word when the separator
    /// is trimmed at a soft break. Choose that word once, rather than scanning on every shape.
    func setAlignmentMark(_ offset: Int, event: AlignmentEvent) {
        guard let first = words.first, let last = words.last else { return }
        let word = event.tokenEdgeRight
            ? (words.last { $0.lowerBound < offset } ?? first)
            : (words.first { $0.upperBound > offset } ?? last)
        alignmentMark = (offset, word, event)
        boxes.removeAll()
    }

    func box(_ range: Range<Int>) -> MathBox {
        guard !range.isEmpty else { return .empty() }
        // Count cache hits too: repeatedly assembling arbitrarily long rows must also stay bounded.
        guard work.consume(range.count) else { return .empty(width: MathLimits.extent + 1) }
        if let cached = boxes[range] { return cached }
        work.requestedLine()
        let line = CTTypesetterCreateLine(typesetter, CFRange(location: range.lowerBound, length: range.count))
        var box = LayoutEngine.shapedTextBox(line, color: color, ink: work.glyphInk)
        if trackAlignment {
            let ink = box.spacingInkBounds
            let left = min(0, ink?.minX ?? 0), right = max(box.width, ink?.maxX ?? box.width)
            box.alignment.append(AlignmentEvent(kind: .extent(right - left), x: left))
        }
        if let mark = alignmentMark, range.lowerBound <= mark.word.lowerBound, range.upperBound >= mark.word.upperBound {
            var event = mark.event
            event.x = caret(line, offset: min(max(mark.offset, range.lowerBound), range.upperBound))
            box.alignment.append(event)
        }
        boxes[range] = box
        itemCounts[range] = box.items.count
        return box
    }
}
