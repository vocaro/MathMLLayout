import CoreGraphics
import CoreText

extension LayoutEngine {
    /// Convert a component's progression offset to its physical left edge. Children retain
    /// their own direction, glyph orientation, alignment events and local coordinates.
    func schemaX(_ offset: CGFloat, _ width: CGFloat, _ total: CGFloat, _ context: LayoutContext) -> CGFloat {
        context.alignmentRTL ? total - offset - width : offset
    }

    /// Only a generated surd or bevelled fraction's slash is reflected. These decorations
    /// consist of flat font runs (including MATH assemblies) or drawn paths, never content.
    /// Runs preserve the selected size variant, hinting and connector positions without
    /// changing the font or adding another level to the formula's drawing/traversal tree.
    func reflectedDecoration(_ decoration: MathBox) -> MathBox {
        var box = MathBox(width: decoration.width, ascent: decoration.ascent, descent: decoration.descent)
        let reflection = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: decoration.width, ty: 0)
        box.items = decoration.items.map { item in
            switch item {
            case .glyphs(var run):
                run.reflectionWidth = decoration.width
                if !run.ink.isNull { run.ink = run.ink.applying(reflection) }
                return .glyphs(run)
            case .path(let path, let width, let color, let fill):
                var transform = reflection
                return .path(path.copy(using: &transform)!, lineWidth: width, color: color, fill: fill)
            default:
                preconditionFailure("Structural decoration must contain only font runs or paths")
            }
        }
        return box
    }
}
