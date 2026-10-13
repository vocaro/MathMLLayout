import CoreGraphics
import CoreText

/// A laid-out box: an advance `width` and its extents above (`ascent`) and below (`descent`)
/// the baseline, with what it draws relative to its baseline origin, y up. Extents follow the
/// ink of glyphs, so either may be negative (an accent floats above the baseline).
struct MathBox {
    var width: CGFloat = 0
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    /// How far an italic glyph's top leans past the advance; superscripts start after it.
    var italicCorrection: CGFloat = 0
    /// Where an accent over this box centres, from its left edge; nil is the middle.
    var topAccentAttachment: CGFloat?
    /// Set when the box is an embellished operator: the core `mo`'s resolved properties.
    var op: OperatorProperties?
    /// Set when the box is a row a line may break inside: its children, kept apart.
    var row: BreakableRow?
    /// The source of a vertically stretched fence, for a pair that later stays on one output row.
    var fenceLayout: FenceLayout?
    var items: [MathItem] = []

    var height: CGFloat { ascent + descent }

    static func empty(width: CGFloat = 0, ascent: CGFloat = 0, descent: CGFloat = 0) -> MathBox {
        MathBox(width: width, ascent: ascent, descent: descent)
    }

    /// Adds `box` with its baseline origin at `point`. Its extents are not merged: callers set
    /// their own metrics.
    mutating func add(_ box: MathBox, at point: CGPoint) {
        guard !box.items.isEmpty else { return }
        if point == .zero, box.fenceLayout == nil, box.items.count == 1, case .box = box.items[0] {
            items.append(box.items[0]); return
        }
        // What is drawn keeps no row structure: that is for whoever may still break the row.
        var box = box
        box.row = nil
        items.append(.box(box, at: point))
    }

    /// One cursor per nested drawing box. Only the active ancestry is retained, so wide
    /// formulas do not put all their drawing items on a pending work stack.
    private struct ItemCursor {
        var items: [MathItem]
        var index = 0
        var origin: CGPoint
        var ink: CGRect?
    }

    /// The union of everything drawn, relative to the baseline origin; nil when nothing is.
    var inkBounds: CGRect? {
        var cursors = [ItemCursor(items: items, origin: .zero)]
        while !cursors.isEmpty {
            let last = cursors.count - 1
            if cursors[last].index == cursors[last].items.count {
                let completed = cursors.removeLast()
                guard !cursors.isEmpty else { return completed.ink }
                if let ink = completed.ink {
                    let translated = ink.offsetBy(dx: completed.origin.x, dy: completed.origin.y)
                    let parent = cursors.count - 1
                    cursors[parent].ink = cursors[parent].ink.map { $0.union(translated) } ?? translated
                }
                continue
            }
            let item = cursors[last].items[cursors[last].index]
            cursors[last].index += 1
            let rect: CGRect
            switch item {
            case .glyphs(let run):
                if run.ink.isNull { continue }
                rect = run.ink
            case .rect(let bounds, _), .image(_, let bounds, _): rect = bounds
            case .path(let path, let width, _, _), .dashes(let path, let width, _, _):
                rect = path.boundingBoxOfPath.insetBy(dx: -width / 2, dy: -width / 2)
            case .box(let box, let point):
                cursors.append(ItemCursor(items: box.items, origin: point))
                continue
            }
            cursors[last].ink = cursors[last].ink.map { $0.union(rect) } ?? rect
        }
        return nil
    }

    var itemCount: Int {
        var count = 0
        var cursors = [ItemCursor(items: items, origin: .zero)]
        while !cursors.isEmpty {
            let last = cursors.count - 1
            if cursors[last].index == cursors[last].items.count {
                cursors.removeLast()
                continue
            }
            let item = cursors[last].items[cursors[last].index]
            cursors[last].index += 1
            count += 1
            if case .box(let box, _) = item {
                cursors.append(ItemCursor(items: box.items, origin: .zero))
            }
        }
        return count
    }

    func draw(in context: CGContext, at origin: CGPoint) {
        var cursors = [ItemCursor(items: items, origin: origin)]
        while !cursors.isEmpty {
            let last = cursors.count - 1
            if cursors[last].index == cursors[last].items.count {
                cursors.removeLast()
                continue
            }
            let item = cursors[last].items[cursors[last].index]
            let origin = cursors[last].origin
            cursors[last].index += 1
            switch item {
            case .glyphs(let run):
                context.setFillColor(run.color)
                let positions = run.positions.map { CGPoint(x: $0.x + origin.x, y: $0.y + origin.y) }
                CTFontDrawGlyphs(run.font, run.glyphs, positions, run.glyphs.count, context)
            case .rect(let rect, let color):
                context.setFillColor(color)
                context.fill(rect.offsetBy(dx: origin.x, dy: origin.y))
            case .path(let path, let lineWidth, let color, let fill):
                context.saveGState()
                context.translateBy(x: origin.x, y: origin.y)
                context.addPath(path)
                if fill {
                    context.setFillColor(color)
                    context.fillPath()
                } else {
                    context.setStrokeColor(color)
                    context.setLineWidth(lineWidth)
                    context.setLineCap(.round)
                    context.setLineJoin(.round)
                    context.strokePath()
                }
                context.restoreGState()
            case .dashes(let path, let lineWidth, let color, let lengths):
                context.saveGState()
                context.translateBy(x: origin.x, y: origin.y)
                context.addPath(path)
                context.setStrokeColor(color)
                context.setLineWidth(lineWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                // A pattern CoreGraphics would refuse (a rule of no thickness has dashes of no length) is no pattern.
                if lengths.allSatisfy({ $0.isFinite && $0 > 0 }) { context.setLineDash(phase: 0, lengths: lengths) }
                context.strokePath()
                context.restoreGState()
            case .image(let image, let rect, let color):
                // An image mask is filled with the context's fill colour, which is otherwise that of
                // whatever was drawn last. An image with colours of its own takes no notice of it.
                context.setFillColor(color)
                // Upright as it is: CoreGraphics puts an image's top row at the rect's greater y.
                context.draw(image, in: rect.offsetBy(dx: origin.x, dy: origin.y))
            case .box(let box, let point):
                cursors.append(ItemCursor(items: box.items,
                                          origin: CGPoint(x: origin.x + point.x, y: origin.y + point.y)))
            }
        }
    }
}

/// Glyphs of one font, positioned relative to a box's baseline origin.
struct GlyphRun {
    var font: CTFont
    var glyphs: [CGGlyph]
    var positions: [CGPoint]
    var color: CGColor
    /// Ink bounds relative to the same origin.
    var ink: CGRect
}

enum MathItem {
    case glyphs(GlyphRun)
    case rect(CGRect, CGColor)
    /// Stroked with `lineWidth`, or filled when the flag is set.
    case path(CGPath, lineWidth: CGFloat, color: CGColor, fill: Bool)
    /// Stroked with `lineWidth` in dashes of `lengths`, drawn and skipped in turn. The path is whole
    /// and the context dashes it as it draws: a path dashed when it is laid out has as many pieces as
    /// its length holds dashes, and markup sets the two apart (a table's rule is as thick as its own
    /// font is large, and as long as its content is wide), so that was millions of dashes nobody drew.
    case dashes(CGPath, lineWidth: CGFloat, color: CGColor, lengths: [CGFloat])
    /// An `mglyph`'s image, scaled to fill the rect. The colour is for an image mask, which is a
    /// shape with none of its own: its token's, as for the text beside it.
    case image(CGImage, CGRect, CGColor)
    case box(MathBox, at: CGPoint)
}
