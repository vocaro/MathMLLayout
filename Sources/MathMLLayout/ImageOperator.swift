import CoreGraphics
import CoreText

extension LayoutEngine {
    /// MathML 3 gives images author dimensions and permits renderer-specific stretching
    /// directions (3.2.1.2.2, 3.2.5.8). Explicit true attributes opt into our affine extension;
    /// dictionary defaults alone retain the authored token, including its baseline.
    func imageOperator(_ node: MathMLNode, natural: MathBox, properties: OperatorProperties,
                       _ context: LayoutContext, _ embellishment: Embellishment) -> MathBox {
        var box = natural
        if node.attributes.flag("largeop") == true, context.display, natural.height > 0 {
            let height = max(value(\.displayOperatorMinHeight, context), natural.height * 2.squareRoot())
            let factor = min(height / natural.height, MathLimits.extent / max(natural.width, natural.height))
            box = centered(scaledImageToken(natural, x: factor, y: factor), on: value(\.axisHeight, context))
        }
        guard node.attributes.flag("stretchy") == true, let stretch = embellishment.stretch else { return box }
        switch stretch {
        case .vertical(let ascent, let descent) where !properties.isHorizontal:
            guard natural.height > 0 else { return box }
            let axis = value(\.axisHeight, context)
            var top = ascent, bottom = descent
            if properties.has(.symmetric) {
                let half = max(ascent - axis, descent + axis)
                top = axis + half; bottom = half - axis
            }
            let target = imageOperatorSize(node, requested: max(top + bottom, box.height),
                                           reference: natural.height, context)
            box = scaledImageToken(box, x: 1, y: target / box.height)
            // Stretch positioning supersedes display centering and the authored valign.
            // With no siblings, use the axis, as for a font operator with only minsize.
            return centered(box, on: top + bottom > 0 ? (top - bottom) / 2 : axis)
        case .horizontal(let width) where properties.isHorizontal:
            guard natural.width > 0 else { return box }
            let target = imageOperatorSize(node, requested: max(width, box.width),
                                           reference: natural.width, context)
            return scaledImageToken(box, x: target / box.width, y: 1)
        default: return box
        }
    }

    /// Reference lengths are always the complete author-sized token, before display enlargement.
    /// Explicit maxima may shrink it; conflicting bounds follow MathML Core's minsize precedence.
    private func imageOperatorSize(_ node: MathMLNode, requested: CGFloat, reference: CGFloat,
                                   _ context: LayoutContext) -> CGFloat {
        let minimum = max(0, length(node.attributes["minsize"], context, reference: reference) ?? reference)
        var target = max(requested, minimum)
        if let maximum = node.attributes["maxsize"], maximum.trimmingCharacters(in: .whitespaces) != "infinity",
           let limit = length(maximum, context, reference: reference) {
            target = min(target, max(minimum, limit))
        }
        return min(target, MathLimits.extent)
    }

    /// Affine scaling of all drawing items, including text and backgrounds, never a font
    /// construction chosen from adjacent text. Images have no italic/accent attachment metrics.
    private func scaledImageToken(_ source: MathBox, x: CGFloat, y: CGFloat) -> MathBox {
        guard x > 0, y > 0 else { return .empty() }
        let transform = CGAffineTransform(scaleX: x, y: y)
        var box = MathBox(width: source.width * x, ascent: source.ascent * y, descent: source.descent * y)
        box.alignment = source.alignment.map { event in
            var scaled = event
            scaled.x *= x
            if case .extent(let width) = scaled.kind { scaled.kind = .extent(width * x) }
            return scaled
        }
        box.items = source.items.map { item in
            switch item {
            case .glyphs(var run):
                var matrix = CTFontGetMatrix(run.font).concatenating(transform)
                run.font = CTFontCreateCopyWithAttributes(run.font, 0, &matrix, nil)
                run.positions = run.positions.map { $0.applying(transform) }
                if !run.ink.isNull { run.ink = run.ink.applying(transform) }
                return .glyphs(run)
            case .image(let image, let rect, let color): return .image(image, rect.applying(transform), color)
            case .rect(let rect, let color): return .rect(rect.applying(transform), color)
            case .box(let inner, let point):
                return .box(scaledImageToken(inner, x: x, y: y), at: point.applying(transform))
            // Token shaping produces only glyphs, images, rectangles and nested boxes.
            case .path, .dashes: return item
            }
        }
        return box
    }
}
