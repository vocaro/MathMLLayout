import CoreGraphics
import Foundation

// MathMLLayout lays out presentation MathML with CoreText and an OpenType MATH font. It uses
// no UI framework, web view or script engine: lay out anywhere, draw into any CGContext.

/// A presentation-MathML element, independent of any XML parser. Token elements (`mi`, `mn`,
/// `mo`, `mtext`, `ms`) carry their character data in `text` and their element children, with
/// their attributes, in `children`; other elements carry their content in `children`.
///
/// An `mglyph` in a token marks its place in `text` with one U+FFFC OBJECT REPLACEMENT
/// CHARACTER, in document order: `<mi>a<mglyph src="s" alt="t"/>b</mi>` is the text "a\u{FFFC}b"
/// with one `mglyph` child. An embedded `malignmark` records its UTF-16 position in
/// `tokenTextOffset`. A host that builds nodes from its own DOM should do the same. Where it does not, `mglyph` children beyond
/// the markers go after the text, in order, and a marker with no `mglyph` left for it is ignored.
public struct MathMLNode: Equatable, Sendable {
    /// Local name in the MathML namespace, e.g. `mfrac`.
    public var name: String
    /// Attributes by local name.
    public var attributes: [String: String]
    public var children: [MathMLNode]
    public var text: String
    /// An embedded `malignmark`'s position in its parent token's raw UTF-16 text.
    /// nil places a programmatically constructed marker at the end of the token.
    public var tokenTextOffset: Int?
    public init(name: String, attributes: [String: String] = [:], children: [MathMLNode] = [], text: String = "", tokenTextOffset: Int? = nil) {
        self.name = name; self.attributes = attributes; self.children = children; self.text = text; self.tokenTextOffset = tokenTextOffset
    }
}

/// Resolves an `mglyph`'s `src` to its image.
///
/// Layout calls it on the thread that lays out, at most once for each distinct `src` in a
/// formula, and passes `src` as written: resolving it against the document's base URL is left
/// to the host, and so is refusing what the document may not read, since `src` is as untrusted
/// as the markup. An image is one pixel to the point unless the `mglyph` gives a `width` or
/// `height`. Returning nil draws the `mglyph`'s `alt` text instead.
///
/// A closure has no value to compare, so two providers are equal only when one is a copy of the
/// other: keep one and reuse it, so that equal styles stay equal.
public struct MathImageProvider: Sendable, Equatable {
    /// Boxed, so that copies share an identity.
    private final class Storage: Sendable {
        let image: @Sendable (String) -> CGImage?
        init(_ image: @escaping @Sendable (String) -> CGImage?) { self.image = image }
    }
    private let storage: Storage

    public init(_ image: @escaping @Sendable (_ source: String) -> CGImage?) { storage = Storage(image) }

    func image(_ source: String) -> CGImage? { storage.image(source) }

    public static func == (lhs: MathImageProvider, rhs: MathImageProvider) -> Bool { lhs.storage === rhs.storage }
}

public struct MathStyle: Equatable, Sendable {
    /// The surrounding text's font size, in points.
    public var fontSize: CGFloat
    public var color: CGColor
    /// `display="block"` (or `displaystyle="true"` at the root).
    public var isDisplay: Bool
    /// PostScript name of an OpenType MATH font. nil, or a font that is not installed, uses
    /// the platform's STIX Two Math.
    public var fontName: String?
    /// The images of `mglyph` elements. nil draws each one's `alt` text.
    public var imageProvider: MathImageProvider?
    public init(fontSize: CGFloat, color: CGColor, isDisplay: Bool = false, fontName: String? = nil,
                imageProvider: MathImageProvider? = nil) {
        self.fontSize = fontSize; self.color = color; self.isDisplay = isDisplay; self.fontName = fontName
        self.imageProvider = imageProvider
    }
}

public enum MathLayoutError: Error, Equatable, Sendable {
    /// An element the engine does not lay out; callers show `alttext` instead.
    case unsupported(String)
    /// Deeper, larger or longer than the engine's bounds on untrusted input.
    case limitExceeded
    /// Markup that is not MathML the engine can read: an element with the wrong number of
    /// children, or XML that does not parse.
    case invalidMarkup(String)
}

/// A laid-out formula. Immutable and thread-safe: lay out off the main thread, draw anywhere.
///
/// It is one row unless the markup forces a line break or a host width or `math maxwidth` requires one. Its box
/// covers everything it draws, and each row's box everything that row draws, as laid out. A
/// bitmap context moves each glyph onto its pixel grid and on macOS thickens it, so a host that
/// clips to a box allows two device pixels around it (see doc/line-breaking.md, "Clipping").
public final class MathLayout: @unchecked Sendable {
    // Unchecked: the box trees are never mutated after init, and the CoreText fonts and
    // CoreGraphics paths and images they hold are immutable and thread-safe.

    /// Width, and height above (`ascent`) and below (`descent`) the baseline, in points. The
    /// baseline is the first row's: `descent` reaches down through the last row.
    public let width: CGFloat
    public let ascent: CGFloat
    public let descent: CGFloat
    /// The lines of the formula, top to bottom. One, unless the markup forces a break or
    /// a host width or `math maxwidth` requires one.
    public let rows: [Row]
    /// How far the math axis is above the baseline, at the style's font size (the MATH table's
    /// AxisHeight).
    public let axisHeight: CGFloat
    /// The width of the widest unit that cannot break: the narrowest `maximumWidth` at which no row
    /// overflows. When it is more than the `maximumWidth` given, a row is wider than that, and a
    /// host scales the formula. Tables, fractions, radicals and enclosures count as they were laid
    /// out: wrapped as far as the width given asked, and where a row overflows all the same, as far
    /// as they go, so that a formula laid out again at this width fits it. A smaller authored
    /// `maxwidth` must also be removed or enlarged for that retry; this report does not override it.
    public let widestUnbreakableWidth: CGFloat

    /// One line of a formula.
    public struct Row: @unchecked Sendable {
        /// The left end of this row's baseline relative to the layout's baseline origin, y up.
        public let origin: CGPoint
        /// The row's own box: `width` wide, `ascent` above and `descent` below its baseline.
        public let width: CGFloat
        public let ascent: CGFloat
        public let descent: CGFloat
        fileprivate let box: MathBox

        /// Draws this row alone: what a host does to put an inline formula's rows on consecutive
        /// text lines. The row's baseline starts at `baselineOrigin`, in a context whose y axis
        /// points up.
        public func draw(in context: CGContext, baselineOrigin: CGPoint) {
            // The text matrix is no part of the graphics state that is saved, so the host's is
            // put back by hand.
            let textMatrix = context.textMatrix
            context.saveGState()
            defer { context.restoreGState(); context.textMatrix = textMatrix }
            context.textMatrix = .identity
            box.draw(in: context, at: baselineOrigin)
        }
    }

    /// Lays out `root`, usually a `math` element (whose `display="block"` also selects display
    /// style). Throws `unsupported` for elements outside presentation MathML's common subset.
    ///
    /// Rows are no wider than `maximumWidth`, and the first no wider than `firstRowMaximumWidth`:
    /// the space left on the text line where an inline formula starts. Lines break where the
    /// markup forces them (`linebreak="newline"`, whatever the width) and otherwise at operators,
    /// at relations sooner than sums and at sums sooner than products (MathML 3, 3.1.7). Only a
    /// unit that cannot break makes a row wider: see `widestUnbreakableWidth`.
    /// A top-level `math`'s valid `maxwidth` can further narrow either host width, never enlarge
    /// it. Percentages and unitless multiples use the finite host `maximumWidth` as reference;
    /// absolute and font-relative lengths also work with an unbounded host. See `doc/line-breaking.md`.
    public init(_ root: MathMLNode, style: MathStyle, maximumWidth: CGFloat = .infinity,
                firstRowMaximumWidth: CGFloat? = nil) throws {
        let lines = try LayoutEngine.lines(root, style: style, maximumWidth: maximumWidth,
                                           firstRowMaximumWidth: firstRowMaximumWidth)
        rows = lines.rows.map {
            Row(origin: $0.origin, width: $0.box.width, ascent: $0.box.ascent, descent: $0.box.descent, box: $0.box)
        }
        width = lines.width; ascent = lines.ascent; descent = lines.descent
        axisHeight = lines.axisHeight; widestUnbreakableWidth = lines.widestUnbreakable
    }

    /// Draws every row at its origin from `baselineOrigin`, the left end of the first row's
    /// baseline unless that row is indented, in a context whose y axis points up.
    public func draw(in context: CGContext, baselineOrigin: CGPoint) {
        for row in rows {
            row.draw(in: context, baselineOrigin: CGPoint(x: baselineOrigin.x + row.origin.x,
                                                          y: baselineOrigin.y + row.origin.y))
        }
    }
}
