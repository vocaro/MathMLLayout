import CoreGraphics
import Foundation

/// `mglyph`: an image that stands for a character no font has, among a token's text (MathML 3,
/// 3.2.1.2). Its image comes from the host's `MathImageProvider`; without one it is its `alt` text.
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
    /// drawn as the token's own text is, or U+25AF when it has none.
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
                text.append(contentsOf: (alt.isEmpty ? Self.missingGlyph : alt).unicodeScalars)
            }
        }
        return (String(text), images)
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
    /// through a transparent image; `mathcolor` has no effect.
    ///
    /// No dimension exceeds `MathLimits.extent`, whatever the image or the lengths, and an image
    /// with a size that is not positive is empty.
    private func imageBox(_ glyph: MathMLNode, _ image: CGImage, _ context: LayoutContext) -> MathBox {
        let natural = CGSize(width: image.width, height: image.height)
        guard natural.width > 0, natural.height > 0 else { return .empty() }
        let given = (width: length(glyph.attributes["width"], context, reference: natural.width),
                     height: length(glyph.attributes["height"], context, reference: natural.height))
        let width = min(given.width ?? given.height.map { $0 * natural.width / natural.height } ?? natural.width,
                        MathLimits.extent)
        let height = min(given.height ?? given.width.map { $0 * natural.height / natural.width } ?? natural.height,
                         MathLimits.extent)
        guard width > 0, height > 0 else { return .empty() }
        let raise = min(max(length(glyph.attributes["valign"], context) ?? 0, -MathLimits.extent),
                        MathLimits.extent - height)
        let rect = CGRect(x: 0, y: raise, width: width, height: height)
        var box = MathBox(width: width, ascent: height + raise, descent: -raise)
        if let background = glyph.attributes["mathbackground"].flatMap(MathColor.parse) {
            box.items.append(.rect(rect, background))
        }
        box.items.append(.image(image, rect))
        return box
    }

    /// Text with an image at each marker, side by side on the baseline.
    func textBox(_ text: String, images: [MathBox], _ context: LayoutContext) -> MathBox {
        var parts: [MathBox] = []
        var remaining = images[...]
        let runs = text.unicodeScalars.split(separator: Self.glyphMarker, omittingEmptySubsequences: false)
        for (index, run) in runs.enumerated() {
            if index > 0, let image = remaining.popFirst() { parts.append(image) }
            parts.append(textBox(String(run), context))
        }
        // An image of no size, or no text between two images, has no extents to count.
        parts.removeAll { $0.width == 0 && $0.items.isEmpty }
        var box = MathBox(ascent: parts.map(\.ascent).max() ?? 0, descent: parts.map(\.descent).max() ?? 0)
        for part in parts {
            box.add(part, at: CGPoint(x: box.width, y: 0))
            box.width += part.width
        }
        return box
    }
}
