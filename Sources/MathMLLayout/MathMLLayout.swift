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
/// with one `mglyph` child. Other element children (`malignmark`) leave no mark. A host that
/// builds nodes from its own DOM should do the same. Where it does not, `mglyph` children beyond
/// the markers go after the text, in order, and a marker with no `mglyph` left for it is ignored.
public struct MathMLNode: Equatable, Sendable {
    /// Local name in the MathML namespace, e.g. `mfrac`.
    public var name: String
    /// Attributes by local name.
    public var attributes: [String: String]
    public var children: [MathMLNode]
    public var text: String
    public init(name: String, attributes: [String: String] = [:], children: [MathMLNode] = [], text: String = "") {
        self.name = name; self.attributes = attributes; self.children = children; self.text = text
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
/// Its box covers everything it draws, so a host may clip to it.
public final class MathLayout: @unchecked Sendable {
    // Unchecked: the box tree is never mutated after init, and the CoreText fonts and
    // CoreGraphics paths it holds are immutable and thread-safe.

    /// Width, and height above (`ascent`) and below (`descent`) the baseline, in points.
    public let width: CGFloat
    public let ascent: CGFloat
    public let descent: CGFloat
    private let box: MathBox

    /// Lays out `root`, usually a `math` element (whose `display="block"` also selects display
    /// style). Throws `unsupported` for elements outside presentation MathML's common subset.
    public init(_ root: MathMLNode, style: MathStyle) throws {
        box = try LayoutEngine(fontName: style.fontName).layoutRoot(root, style: style)
        width = box.width; ascent = box.ascent; descent = box.descent
    }

    /// Draws with the baseline's left end at `baselineOrigin`, in a context whose y axis points up.
    public func draw(in context: CGContext, baselineOrigin: CGPoint) {
        context.saveGState()
        defer { context.restoreGState() }
        context.textMatrix = .identity
        box.draw(in: context, at: baselineOrigin)
    }
}
