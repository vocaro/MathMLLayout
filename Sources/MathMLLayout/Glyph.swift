import CoreGraphics
import CoreText
import Foundation

/// `mglyph`: an image that stands for a character no font has, among a token's text (MathML 3,
/// 3.2.1.2). Its image comes from the host's `MathImageProvider`; without one it is its `alt` text.
///
/// It is styled by where it stands, as a character is, and not by itself: on an `mglyph`
/// "mathcolor has no effect" (3.2.1.2.2), and the `mathvariant` and `mathsize` that MathML 2 let
/// it carry "have no effect in any case" (3.2.1.2.4). Only its `mathbackground` is its own.
extension LayoutEngine {
    /// U+FFFC OBJECT REPLACEMENT CHARACTER, which marks an `mglyph`'s place in its token's text.
    static let glyphMarker: Unicode.Scalar = "\u{FFFC}"
    /// U+25AF WHITE VERTICAL RECTANGLE, drawn for an `mglyph` with neither an image nor `alt`.
    private static let missingGlyph = "\u{25AF}"

    /// `text` without markers: what a token says apart from its `mglyph`s.
    static func unmarked(_ text: String) -> String {
        guard text.unicodeScalars.contains(glyphMarker) else { return text }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: text.unicodeScalars.lazy.filter { $0 != glyphMarker })
        return String(result)
    }

    static func hasGlyph(_ token: MathMLNode) -> Bool { token.children.contains { $0.name == "mglyph" } }

    /// A token's normalized text with its `mglyph` children resolved: a marker for each one that
    /// has an image, in step with `images`, and for each of the others its `alt`, which is so
    /// drawn as the token's own text is, or U+25AF when it has none. An `alt` with a
    /// `mathbackground` is a box among `images` too, and has a marker: see `altBox`.
    ///
    /// The nth marker is the nth `mglyph`. A tree that a host built may lack markers, so
    /// `mglyph`s beyond them follow the text; a marker beyond the `mglyph`s is dropped.
    func glyphContent(of token: MathMLNode, trimming: Bool = true,
                      _ context: LayoutContext) throws -> (text: String, images: [MathBox]) {
        let glyphs = token.children.filter { $0.name == "mglyph" }
        guard !glyphs.isEmpty || token.text.unicodeScalars.contains(Self.glyphMarker) else {
            return (Self.normalized(token.text, trimming: trimming), [])
        }
        // Each glyph adds a marker or its `alt` to the text, which the caller bounds once it is whole.
        guard glyphs.count <= MathLimits.nodes else { throw MathLayoutError.limitExceeded }
        // Markers and glyphs are paired before whitespace collapses, so it collapses around
        // what is drawn.
        var paired = String.UnicodeScalarView()
        var markers = 0
        for scalar in token.text.unicodeScalars {
            if scalar == Self.glyphMarker {
                guard markers < glyphs.count else { continue }
                markers += 1
            }
            paired.append(scalar)
        }
        paired.append(contentsOf: repeatElement(Self.glyphMarker, count: glyphs.count - markers))
        var text = String.UnicodeScalarView(), images: [MathBox] = []
        var remaining = glyphs[...]
        // A host's tree may give every glyph the same long `alt`, so those are bounded as they are
        // added: whole, they could be `MathLimits.nodes` times the longest.
        var altLength = 0
        for scalar in Self.normalized(String(paired), trimming: trimming).unicodeScalars {
            guard scalar == Self.glyphMarker, let glyph = remaining.popFirst() else { text.append(scalar); continue }
            if let image = image(of: glyph) {
                text.append(scalar)
                images.append(imageBox(glyph, image, context))
            } else {
                let alt = Self.normalized(Self.unmarked(glyph.attributes["alt"] ?? ""))
                altLength += alt.utf16.count
                guard altLength <= MathLimits.textLength else { throw MathLayoutError.limitExceeded }
                let shown = alt.isEmpty ? Self.missingGlyph : alt
                // "transparent" is the default, and no more a background than none: the `alt` stays in the text.
                if let background = glyph.attributes["mathbackground"].flatMap(MathColor.parse), background.alpha > 0 {
                    // It leaves the text the caller bounds, and is shaped here: so it is counted here.
                    try countText(shown)
                    text.append(scalar)
                    images.append(altBox(shown, on: background, context))
                } else {
                    text.append(contentsOf: shown.unicodeScalars)
                }
            }
        }
        return (String(text), images)
    }

    /// `glyphContent` of an `mo`, with its text as `operatorText` draws it: a hyphen-minus is the
    /// minus sign and an apostrophe the prime, beside an `mglyph` as alone. Either is all the text
    /// the `mo` has apart from markers and white space, so it is the only one of its kind there.
    /// An `alt` is left as written: it describes an image, and names no operator.
    func operatorGlyphContent(of node: MathMLNode, _ context: LayoutContext) throws -> (text: String, images: [MathBox]) {
        let typed = Self.normalized(Self.unmarked(node.text)), drawn = operatorText(node)
        guard typed != drawn else { return try glyphContent(of: node, context) }
        var shown = node
        shown.text = node.text.replacingOccurrences(of: typed, with: drawn, options: .literal)
        return try glyphContent(of: shown, context)
    }

    /// An `alt` on its `mglyph`'s `mathbackground`, which fills "the bounding box of the element"
    /// (3.1.10): the image's when there is one, and without one the box of what is drawn instead.
    /// So this `alt` is a box of its own among the token's text, where any other is part of that
    /// text. It is drawn as that text is, in the token's variant, size and colour.
    private func altBox(_ alt: String, on background: CGColor, _ context: LayoutContext) -> MathBox {
        var box = textBox(context.variant?.apply(to: alt) ?? alt, context, retainSegments: true)
        if let segments = box.textSegments {
            box.textSegments = segments.map { segment in
                var piece = segment
                piece.box.items.insert(.rect(CGRect(x: 0, y: -box.descent, width: piece.box.width, height: box.height), background), at: 0)
                piece.box.ascent = box.ascent; piece.box.descent = box.descent
                return piece
            }
        }
        box.items.insert(.rect(CGRect(x: 0, y: -box.descent, width: box.width, height: box.height), background), at: 0)
        return box
    }

    /// The provider's image for an `mglyph`, asked once for each `src` however often a formula
    /// repeats it. With no `src` there is none: MathML 2's `fontfamily` and `index`, a glyph of
    /// a named font, are deprecated (3.2.1.2.4) and ignored.
    private func image(of glyph: MathMLNode) -> CGImage? {
        guard let imageProvider, let source = glyph.attributes["src"], !source.isEmpty else { return nil }
        if let known = imageCache[source] { return known }
        let image = imageProvider.image(source)
        imageCache.updateValue(image, forKey: source)
        return image
    }

    /// An image's box (3.2.1.2.2): `width` and `height` where given, the image's proportions
    /// where one is missing, and its pixels as points where both are. `valign` raises the
    /// image's bottom edge above the baseline. A percentage or bare number is of the attribute's
    /// default (2.1.5.2): the image's own size, and for `valign` zero. `mathbackground` shows
    /// through a transparent image; `mathcolor` has no effect. An image mask, which is a shape and
    /// has no colour of its own, is filled with the token's as a character would be: that is "the
    /// foreground color to use when drawing ... the content for token elements" (3.1.10).
    ///
    /// No dimension exceeds `MathLimits.extent`, whatever the image or the lengths: a larger image
    /// is scaled down whole, and keeps the shape that its lengths or its pixels gave it. An image
    /// with a size that is not positive is empty.
    private func imageBox(_ glyph: MathMLNode, _ image: CGImage, _ context: LayoutContext) -> MathBox {
        let natural = CGSize(width: image.width, height: image.height)
        guard natural.width > 0, natural.height > 0 else { return .empty() }
        let given = (width: length(glyph.attributes["width"], context, reference: natural.width),
                     height: length(glyph.attributes["height"], context, reference: natural.height))
        var width = given.width ?? given.height.map { $0 * natural.width / natural.height } ?? natural.width
        var height = given.height ?? given.width.map { $0 * natural.height / natural.width } ?? natural.height
        guard width > 0, height > 0 else { return .empty() }
        // Past the bound it is scaled down whole: each side bounded by itself would change its shape.
        // The longer side is the bound itself, not what rounding makes of it.
        let longer = max(width, height)
        if longer > MathLimits.extent {
            width = width == longer ? MathLimits.extent : width / longer * MathLimits.extent
            height = height == longer ? MathLimits.extent : height / longer * MathLimits.extent
        }
        // A percentage or a multiple of `valign`'s default, 0ex, is zero. Resolved with nothing to be
        // a percentage of it is no length at all, which comes to the same.
        let raise = min(max(length(glyph.attributes["valign"], context) ?? 0, -MathLimits.extent),
                        MathLimits.extent - height)
        let rect = CGRect(x: 0, y: raise, width: width, height: height)
        var box = MathBox(width: width, ascent: height + raise, descent: -raise)
        if let background = glyph.attributes["mathbackground"].flatMap(MathColor.parse) {
            box.items.append(.rect(rect, background))
        }
        box.items.append(.image(image, rect, context.color))
        return box
    }

    /// Slice an already-shaped line at logical ordinary spaces. Glyph identity is not a word
    /// boundary: a font may use the same glyph for a no-break space. String indices also keep
    /// ligatures and combining marks with their source word, without reshaping its text.
    func textSegments(_ text: String, line: CTLine, box: MathBox) -> [TextSegment]? {
        let runs = (CTLineGetGlyphRuns(line) as? [CTRun] ?? []).filter { CTRunGetGlyphCount($0) > 0 }
        // Visual RTL runs need per-line shaping before they can wrap in source order.
        guard !runs.contains(where: { CTRunGetStatus($0).contains(.rightToLeft) }) else { return nil }
        let units = Array(text.utf16)
        guard !units.isEmpty else { return [] }
        var starts = [0], owners = [Int](repeating: 0, count: units.count)
        for index in 1..<units.count {
            if (units[index] == 0x20) != (units[index - 1] == 0x20) { starts.append(index) }
            owners[index] = starts.count - 1
        }
        // No opportunity inside the run: keep its original drawing, including shaping.
        if starts.count == 1 {
            return [TextSegment(box: box, x: 0, isSpace: units[0] == 0x20)]
        }
        // Asking CTLine for every boundary's offset scans the shaped line repeatedly. Derive
        // the source-order boundaries in one pass, using each piece's first visual glyph origin.
        var offsets = [CGFloat](repeating: .infinity, count: starts.count) + [box.width]
        var edge = -CGFloat.infinity, previousOwner = 0
        var indexedRuns: [(GlyphRun, [CFIndex])] = []
        for (run, item) in zip(runs, box.items) {
            guard case .glyphs(let drawing) = item else { return nil }
            var indices = [CFIndex](repeating: 0, count: CTRunGetGlyphCount(run))
            CTRunGetStringIndices(run, CFRange(), &indices)
            for index in indices.indices {
                guard indices[index] >= 0, indices[index] < owners.count else { return nil }
                let owner = owners[indices[index]]
                let x = drawing.positions[index].x
                // Keep the legacy conservative policy for visually reordered drawing origins.
                guard owner >= previousOwner, x >= edge - 0.01 else { return nil }
                previousOwner = owner; edge = x
                if !offsets[owner].isFinite { offsets[owner] = x }
            }
            indexedRuns.append((drawing, indices))
        }
        // A wholly invisible piece has no advance and shares the next boundary.
        for index in starts.indices.reversed() where !offsets[index].isFinite { offsets[index] = offsets[index + 1] }
        offsets[0] = 0
        guard zip(offsets, offsets.dropFirst()).allSatisfy({ $0 <= $1 }) else { return nil }
        var pieces = starts.indices.map {
            TextSegment(box: MathBox(width: offsets[$0 + 1] - offsets[$0]), x: offsets[$0], isSpace: units[starts[$0]] == 0x20)
        }
        for (drawing, indices) in indexedRuns {
            let count = indices.count
            var index = 0
            while index < count {
                guard indices[index] >= 0, indices[index] < owners.count else { return nil }
                let owner = owners[indices[index]]
                var end = index + 1
                while end < count, indices[end] >= 0, indices[end] < owners.count, owners[indices[end]] == owner { end += 1 }
                let glyphs = Array(drawing.glyphs[index..<end])
                let positions = drawing.positions[index..<end].map { CGPoint(x: $0.x - offsets[owner], y: $0.y) }
                var rects = [CGRect](repeating: .zero, count: glyphs.count)
                CTFontGetBoundingRectsForGlyphs(drawing.font, .horizontal, glyphs, &rects, glyphs.count)
                var ink: CGRect?
                for (rect, position) in zip(rects, positions) where !rect.isEmpty {
                    let placed = rect.offsetBy(dx: position.x, dy: position.y)
                    ink = ink.map { $0.union(placed) } ?? placed
                }
                pieces[owner].box.items.append(.glyphs(GlyphRun(font: drawing.font, glyphs: glyphs, positions: positions,
                                                               color: drawing.color, ink: ink ?? .null)))
                index = end
            }
        }
        for index in pieces.indices {
            let ink = pieces[index].box.inkBounds
            pieces[index].box.ascent = ink?.maxY ?? 0
            pieces[index].box.descent = ink.map { -$0.minY } ?? 0
        }
        return pieces
    }

    /// Text with an image, or an `alt` on its background, at each marker, side by side on the baseline.
    func textBox(_ text: String, images: [MathBox], _ context: LayoutContext, retainSegments: Bool = false) -> MathBox {
        var parts: [MathBox] = []
        var remaining = images[...]
        let runs = text.unicodeScalars.split(separator: Self.glyphMarker, omittingEmptySubsequences: false)
        for (index, run) in runs.enumerated() {
            if index > 0, let image = remaining.popFirst() { parts.append(image) }
            parts.append(textBox(String(run), context, retainSegments: retainSegments))
        }
        // An image of no size, or no text between two images, has no extents to count.
        parts.removeAll { $0.width == 0 && $0.items.isEmpty }
        var box = MathBox(ascent: parts.map(\.ascent).max() ?? 0, descent: parts.map(\.descent).max() ?? 0)
        var segments: [TextSegment] = []
        for part in parts {
            if retainSegments {
                if let pieces = part.textSegments {
                    segments += pieces.map { TextSegment(box: $0.box, x: box.width + $0.x, isSpace: $0.isSpace) }
                } else {
                    segments.append(TextSegment(box: part, x: box.width, isSpace: false))
                }
            }
            box.add(part, at: CGPoint(x: box.width, y: 0))
            box.width += part.width
        }
        // An unsegmentable textual part (currently RTL) keeps the whole token atomic.
        // Actual images have no text metadata and are still eligible atomic pieces.
        let hasUnsegmentableText = parts.contains { part in
            part.textSegments == nil && part.items.contains { if case .glyphs = $0 { return true }; return false }
        }
        if retainSegments, !hasUnsegmentableText { box.textSegments = segments }
        return box
    }
}
