import CoreGraphics
import CoreText

/// Stretchy and large operators: MATH table size variants and glyph assemblies (MathML Core
/// 3.3.1, OpenType MathVariants), with drawn shapes for fonts that have neither.
extension LayoutEngine {
    /// Spacing accents whose wide forms the MATH table keys on the combining character.
    private static let combiningEquivalents: [Unicode.Scalar: Unicode.Scalar] = [
        "^": "\u{0302}", "ˆ": "\u{0302}", "~": "\u{0303}", "˜": "\u{0303}", "ˇ": "\u{030C}", "˘": "\u{0306}",
        "¯": "\u{0305}", "‾": "\u{0305}", "_": "\u{0332}",
    ]

    /// Long arrows, which a font may give no construction of their own, and the short arrow each
    /// is a longer form of. Stretched, the two are one arrow, so the long one takes the short
    /// one's assembly when the long glyph has no construction.
    private static let shortArrows: [Unicode.Scalar: Unicode.Scalar] = [
        "⟵": "←", "⟶": "→", "⟷": "↔", "⟸": "⇐", "⟹": "⇒", "⟺": "⇔", "⟻": "↤", "⟼": "↦",
    ]

    /// Vertical arrows as horizontal shapes turned a quarter turn counterclockwise. The upper
    /// shaft becomes the left shaft, and a downward barb becomes a rightward one.
    private static let horizontalEquivalents: [Unicode.Scalar: Unicode.Scalar] = [
        "↑": "→", "↓": "←", "↕": "↔", "⇑": "⇒", "⇓": "⇐", "⇕": "⇔",
        "↥": "↦", "↧": "↤", "⇅": "⇄", "⇈": "⇉", "⇊": "⇇",
        "↾": "⇁", "↿": "⇀", "⇂": "↽", "⇃": "↼",
    ]

    /// A large operator in display style: the first variant at least `DisplayOperatorMinHeight`
    /// tall (and √2 times the text size, as MathML Core asks), else the largest.
    func displayOperator(_ glyph: CGGlyph, _ context: LayoutContext) -> MathBox? {
        guard let construction = font.table?.construction(glyph, vertical: true, size: context.fontSize) else { return nil }
        let natural = glyphBox(glyph, context).height
        let minimum = max(value(\.displayOperatorMinHeight, context), natural * 2.squareRoot())
        let variant = construction.variants.first { font.points($0.advance, size: context.fontSize) >= minimum }
            ?? construction.variants.last
        return variant.map { glyphBox($0.glyph, context) }
    }

    /// An operator stretched to cover `ascent` and `descent`, centred on the math axis when
    /// symmetric. `minsize` and `maxsize` bound the size, relative to the natural size, and
    /// where the two disagree `minsize` is the one that holds. A row with nothing for the operator
    /// to cover passes zero for both extents: the operator keeps its natural size unless
    /// `minsize` is more, and then it is centred on the axis whether it is symmetric or not.
    func stretchVertically(_ node: MathMLNode, glyph: CGGlyph?, scalar: Unicode.Scalar?, natural: MathBox,
                           ascent: CGFloat, descent: CGFloat, symmetric: Bool, _ context: LayoutContext) -> MathBox? {
        let axis = value(\.axisHeight, context)
        var top = ascent, bottom = descent
        if symmetric {
            let half = max(ascent - axis, descent + axis)
            top = axis + half; bottom = half - axis
        }
        // TeX's \delimiterfactor and \delimitershortfall: a fence may fall a little short of
        // its content, so f(x) keeps ordinary parentheses.
        var target = max((top + bottom) * 0.901, top + bottom - context.fontSize / 2)
        // MathML Core 3.2.4.3: a negative `minsize` is zero, and a `maxsize` less than `minsize` is `minsize`.
        let minimum = max(length(node.attributes["minsize"], context, reference: natural.height) ?? 0, 0)
        target = max(target, minimum)
        if let maximum = node.attributes["maxsize"], maximum.trimmingCharacters(in: .whitespaces) != "infinity",
           let limit = length(maximum, context, reference: natural.height) {
            target = min(target, max(limit, minimum))
        }
        target = min(target, 200 * context.fontSize)
        guard target > natural.height else { return nil }
        // Nothing to cover is nothing to centre on. The size is then the `minsize`, and MathML
        // Core 3.2.4.3 puts half of it each side of the axis, symmetric or not.
        let center = top + bottom > 0 ? (top - bottom) / 2 : axis
        if let glyph, let box = stretchedGlyph(glyph, vertical: true, size: target, context) {
            return centered(box, on: center)
        }
        guard let scalar,
              let box = drawnVerticalArrow(scalar, height: target, natural: natural, context)
                ?? drawnDelimiter(directionalDelimiter(scalar, context), height: target, context) else { return nil }
        return centered(box, on: center)
    }

    /// An operator stretched to `width`: a variant or assembly of its own glyph, of the
    /// combining accent it stands for or of the short arrow it is a long form of, else a drawn
    /// bar, arrow or brace.
    func stretchHorizontally(glyph: CGGlyph?, scalar: Unicode.Scalar?, natural: MathBox, width: CGFloat,
                             _ context: LayoutContext) -> MathBox? {
        let target = min(width, MathLimits.extent)
        guard target > natural.width else { return nil }
        var candidates: [CGGlyph] = glyph.map { [$0] } ?? []
        let combining = scalar.flatMap { Self.combiningEquivalents[$0] }
        if let equivalent = combining ?? scalar.flatMap({ Self.shortArrows[$0] }), let alternate = font.glyph(for: equivalent) {
            candidates.append(alternate)
        }
        for candidate in candidates {
            guard font.table?.construction(candidate, vertical: false, size: context.fontSize) != nil else { continue }
            guard var box = stretchedGlyph(candidate, vertical: false, size: target, context) else { continue }
            // Keep the natural glyph's height: accents are designed to sit where they are. A short
            // arrow is where its long form is, on the axis, and stays there though its head is
            // larger: STIX Two Math assembles ⇔ with taller heads than either glyph has.
            if candidate != glyph, combining != nil, let ink = natural.inkBounds, let stretched = box.inkBounds {
                box = shifted(box, by: ink.minY - stretched.minY)
            }
            return box
        }
        guard let scalar else { return nil }
        return drawnHorizontal(scalar, width: target, natural: natural, context)
    }

    /// The smallest variant at least `size` long, else an assembly of exactly `size`, else
    /// the largest variant; nil when the font has no construction for the glyph.
    func stretchedGlyph(_ glyph: CGGlyph, vertical: Bool, size: CGFloat, _ context: LayoutContext) -> MathBox? {
        guard let table = font.table, let construction = table.construction(glyph, vertical: vertical, size: context.fontSize) else { return nil }
        if let variant = construction.variants.first(where: { font.points($0.advance, size: context.fontSize) >= size }) {
            return glyphBox(variant.glyph, context)
        }
        if let assembly = assemble(construction, vertical: vertical, size: size, context) { return assembly }
        return construction.variants.last.map { glyphBox($0.glyph, context) }
    }

    /// Parts laid end to end with extenders repeated as needed, overlapping uniformly between
    /// the font's minimum connector overlap and what the connectors allow.
    private func assemble(_ construction: GlyphConstruction, vertical: Bool, size: CGFloat,
                          _ context: LayoutContext) -> MathBox? {
        let parts = construction.parts
        guard !parts.isEmpty, let table = font.table else { return nil }
        let scale = context.fontSize / font.unitsPerEm
        let minimumOverlap = table.minConnectorOverlap * scale
        let fixed = parts.filter { !$0.isExtender }, extenders = parts.filter(\.isExtender)
        let fixedLength = fixed.reduce(0) { $0 + $1.fullAdvance } * scale
        let extenderLength = extenders.reduce(0) { $0 + $1.fullAdvance } * scale
        func longest(_ repeats: Int) -> CGFloat {
            let count = fixed.count + repeats * extenders.count
            return fixedLength + CGFloat(repeats) * extenderLength - CGFloat(max(count - 1, 0)) * minimumOverlap
        }
        var repeats = 0
        if !extenders.isEmpty, extenderLength - CGFloat(extenders.count) * minimumOverlap > 0 {
            while longest(repeats) < size, repeats < 200 { repeats += 1 }
        }
        var sequence: [GlyphConstruction.Part] = []
        for part in parts {
            sequence.append(contentsOf: repeatElement(part, count: part.isExtender ? repeats : 1))
        }
        guard !sequence.isEmpty else { return nil }
        let total = sequence.reduce(0) { $0 + $1.fullAdvance } * scale
        var overlap = minimumOverlap
        if sequence.count > 1 {
            var allowed = CGFloat.greatestFiniteMagnitude
            for index in 1..<sequence.count {
                allowed = min(allowed, min(sequence[index - 1].endConnector, sequence[index].startConnector) * scale)
            }
            overlap = min(max((total - size) / CGFloat(sequence.count - 1), minimumOverlap), max(allowed, minimumOverlap))
        }
        let ctFont = font.font(size: context.fontSize)
        var glyphs: [CGGlyph] = [], positions: [CGPoint] = []
        var ink: CGRect?
        var offset: CGFloat = 0, width: CGFloat = 0
        for (index, part) in sequence.enumerated() {
            if index > 0 { offset -= overlap }
            var glyph = part.glyph
            var rect = CGRect.zero, advance = CGSize.zero
            CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &glyph, &rect, 1)
            CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &advance, 1)
            // Vertical parts stack by their ink; horizontal parts by their origins.
            let position = vertical ? CGPoint(x: 0, y: offset - (rect.isEmpty ? 0 : rect.minY)) : CGPoint(x: offset, y: 0)
            glyphs.append(glyph); positions.append(position)
            if !rect.isEmpty {
                let placed = rect.offsetBy(dx: position.x, dy: position.y)
                ink = ink.map { $0.union(placed) } ?? placed
            }
            width = max(width, advance.width)
            offset += part.fullAdvance * scale
        }
        let bounds = ink ?? .zero
        var box = MathBox(width: vertical ? width : offset, ascent: bounds.maxY, descent: -bounds.minY)
        box.italicCorrection = max(0, construction.assemblyItalicsCorrection * scale)
        box.items = [.glyphs(GlyphRun(font: ctFont, glyphs: glyphs, positions: positions, color: context.color,
                                      ink: ink ?? .null))]
        return box
    }

    // MARK: Drawn shapes

    /// CoreText already chooses the mirrored font glyph. A drawn fallback must choose the
    /// same physical fence, rather than reverting to the unshaped source character.
    private func directionalDelimiter(_ scalar: Unicode.Scalar, _ context: LayoutContext) -> Unicode.Scalar {
        guard context.direction == .rightToLeft else { return scalar }
        switch scalar {
        case "(": return ")"
        case ")": return "("
        case "[": return "]"
        case "]": return "["
        case "{": return "}"
        case "}": return "{"
        case "⌈": return "⌉"
        case "⌉": return "⌈"
        case "⌊": return "⌋"
        case "⌋": return "⌊"
        case "⟨": return "⟩"
        case "⟩": return "⟨"
        case "〈": return "〉"
        case "〉": return "〈"
        default: return scalar
        }
    }

    func strokeWidth(_ context: LayoutContext) -> CGFloat {
        max(value(\.fractionRuleThickness, context) * 1.2, 0.5)
    }

    /// Arrow shafts have the font's rule weight, with the same small-size visibility floor.
    private func arrowStrokeWidth(_ context: LayoutContext) -> CGFloat {
        max(value(\.fractionRuleThickness, context), 0.5)
    }

    /// A fence, bar, angle bracket or radical sign drawn `height` tall, its ink from the
    /// baseline up; nil for other characters.
    func drawnDelimiter(_ scalar: Unicode.Scalar, height: CGFloat, _ context: LayoutContext) -> MathBox? {
        let em = context.fontSize, stroke = strokeWidth(context)
        let pad = em * 0.06
        var width = em * 0.33
        let top = height - stroke / 2, bottom = stroke / 2, middle = height / 2
        let path = CGMutablePath()
        func x(_ fraction: CGFloat, mirrored: Bool) -> CGFloat {
            pad + stroke / 2 + (mirrored ? 1 - fraction : fraction) * (width - stroke)
        }
        switch scalar {
        case "(", ")":
            let m = scalar == ")"
            path.move(to: CGPoint(x: x(1, mirrored: m), y: top))
            path.addQuadCurve(to: CGPoint(x: x(1, mirrored: m), y: bottom), control: CGPoint(x: x(-1, mirrored: m), y: middle))
        case "[", "]", "⌈", "⌉", "⌊", "⌋":
            let m = "]⌉⌋".unicodeScalars.contains(scalar)
            let hasTop = "[]⌈⌉".unicodeScalars.contains(scalar), hasBottom = "[]⌊⌋".unicodeScalars.contains(scalar)
            path.move(to: CGPoint(x: x(hasTop ? 1 : 0, mirrored: m), y: top))
            if hasTop { path.addLine(to: CGPoint(x: x(0, mirrored: m), y: top)) }
            path.addLine(to: CGPoint(x: x(0, mirrored: m), y: bottom))
            if hasBottom { path.addLine(to: CGPoint(x: x(1, mirrored: m), y: bottom)) }
        case "{", "}":
            let m = scalar == "}"
            let curl = min(height * 0.12, em * 0.3)
            path.move(to: CGPoint(x: x(1, mirrored: m), y: top))
            path.addQuadCurve(to: CGPoint(x: x(0.5, mirrored: m), y: top - curl), control: CGPoint(x: x(0.5, mirrored: m), y: top))
            path.addLine(to: CGPoint(x: x(0.5, mirrored: m), y: middle + curl))
            path.addQuadCurve(to: CGPoint(x: x(0, mirrored: m), y: middle), control: CGPoint(x: x(0.5, mirrored: m), y: middle))
            path.addQuadCurve(to: CGPoint(x: x(0.5, mirrored: m), y: middle - curl), control: CGPoint(x: x(0.5, mirrored: m), y: middle))
            path.addLine(to: CGPoint(x: x(0.5, mirrored: m), y: bottom + curl))
            path.addQuadCurve(to: CGPoint(x: x(1, mirrored: m), y: bottom), control: CGPoint(x: x(0.5, mirrored: m), y: bottom))
        case "⟨", "⟩", "〈", "〉":
            let m = scalar == "⟩" || scalar == "〉"
            path.move(to: CGPoint(x: x(1, mirrored: m), y: top))
            path.addLine(to: CGPoint(x: x(0, mirrored: m), y: middle))
            path.addLine(to: CGPoint(x: x(1, mirrored: m), y: bottom))
        case "|", "∣", "‖", "∥":
            let double = scalar == "‖" || scalar == "∥"
            width = double ? em * 0.25 : stroke
            for fraction in double ? [0.0, 1.0] : [0.0] {
                path.move(to: CGPoint(x: x(fraction, mirrored: false), y: top))
                path.addLine(to: CGPoint(x: x(fraction, mirrored: false), y: bottom))
            }
        case "√":
            width = em * 0.55 + min(height, em * 4) * 0.08
            path.move(to: CGPoint(x: pad, y: height * 0.45))
            path.addLine(to: CGPoint(x: pad + width * 0.2, y: height * 0.55))
            path.addLine(to: CGPoint(x: pad + width * 0.45, y: bottom))
            path.addLine(to: CGPoint(x: pad + width, y: top))
            var box = MathBox(width: pad + width, ascent: height, descent: 0)
            box.items = [.path(path, lineWidth: stroke, color: context.color, fill: false)]
            return box
        default:
            return nil
        }
        var box = MathBox(width: width + 2 * pad, ascent: height, descent: 0)
        box.items = [.path(path, lineWidth: stroke, color: context.color, fill: false)]
        return box
    }

    /// A vertical arrow whose stroked ink is exactly `height` tall. Keep its natural advance
    /// and ink's horizontal centre: a harpoon's shaft lies to one side of that centre.
    private func drawnVerticalArrow(_ scalar: Unicode.Scalar, height: CGFloat, natural: MathBox,
                                    _ context: LayoutContext) -> MathBox? {
        guard let equivalent = Self.horizontalEquivalents[scalar], let shape = Self.arrowShapes[equivalent] else { return nil }
        let nominalStroke = arrowStrokeWidth(context)
        // At sub-point sizes the visibility floor can be taller than the whole arrow. Leave
        // room for its shaft, then fit that shape and its stroke inside the requested height.
        let stroke = min(nominalStroke, height / 2)
        let width = stroke < nominalStroke ? 2 * nominalStroke + 2 * context.fontSize : height + nominalStroke
        let horizontal = drawnArrow(shape, width: width, middle: 0, context)
        guard case .path(let path, _, let color, let fill) = horizontal.items.first else { return nil }
        let bounds = path.boundingBoxOfPath
        guard bounds.width > 0 else { return nil }
        let scale = (height - stroke) / bounds.width
        let middle = natural.inkBounds?.midX ?? natural.width / 2
        // Fit the actual span, including any head that projects past a short shaft. A normal
        // arrow's span already fits and its proportions are unchanged by the quarter turn.
        var turn = CGAffineTransform(a: 0, b: scale, c: -1, d: 0,
                                     tx: middle + bounds.midY, ty: stroke / 2 - bounds.minX * scale)
        guard let rotated = path.copy(using: &turn) else { return nil }
        var box = MathBox(width: natural.width, ascent: height, descent: 0)
        box.items = [.path(rotated, lineWidth: stroke, color: color, fill: fill)]
        return box
    }

    /// A bar, arrow or brace drawn `width` long at the natural glyph's height.
    private func drawnHorizontal(_ scalar: Unicode.Scalar, width: CGFloat, natural: MathBox,
                                 _ context: LayoutContext) -> MathBox? {
        let em = context.fontSize, stroke = strokeWidth(context)
        let ink = natural.inkBounds ?? CGRect(x: 0, y: value(\.axisHeight, context), width: 0, height: 0)
        let middle = ink.midY
        if let shape = Self.arrowShapes[scalar] { return drawnArrow(shape, width: width, middle: middle, context) }
        let path = CGMutablePath()
        let ascent: CGFloat, descent: CGFloat
        switch scalar {
        case "‾", "¯", "_", "\u{0305}", "\u{0332}":
            var box = MathBox(width: width, ascent: middle + stroke / 2, descent: -middle + stroke / 2)
            box.items = [.rect(CGRect(x: 0, y: middle - stroke / 2, width: width, height: stroke), context.color)]
            return box
        case "⏞", "⏟":
            let up: CGFloat = scalar == "⏞" ? 1 : -1
            let depth = min(em * 0.3, width * 0.2) * up
            let base = scalar == "⏞" ? ink.minY : ink.maxY
            let curl = min(width * 0.1, em * 0.3)
            path.move(to: CGPoint(x: stroke, y: base))
            path.addQuadCurve(to: CGPoint(x: stroke + curl, y: base + depth / 2), control: CGPoint(x: stroke, y: base + depth / 2))
            path.addLine(to: CGPoint(x: width / 2 - curl, y: base + depth / 2))
            path.addQuadCurve(to: CGPoint(x: width / 2, y: base + depth), control: CGPoint(x: width / 2, y: base + depth / 2))
            path.addQuadCurve(to: CGPoint(x: width / 2 + curl, y: base + depth / 2), control: CGPoint(x: width / 2, y: base + depth / 2))
            path.addLine(to: CGPoint(x: width - stroke - curl, y: base + depth / 2))
            path.addQuadCurve(to: CGPoint(x: width - stroke, y: base), control: CGPoint(x: width - stroke, y: base + depth / 2))
            ascent = max(base, base + depth) + stroke; descent = -min(base, base + depth) + stroke
        default:
            return nil
        }
        var box = MathBox(width: width, ascent: ascent, descent: descent)
        box.items = [.path(path, lineWidth: stroke, color: context.color, fill: false)]
        return box
    }

    // MARK: Drawn arrows

    /// How a horizontal arrow is drawn: its shafts from the top down and what ends each, the
    /// lines a shaft is made of, and whether it waves or is struck through.
    private struct ArrowShape: Sendable {
        enum End: Sendable { case plain, head, twoHeads, tail, bar, hook, loop, barbUp, barbDown }
        typealias Shaft = (left: End, right: End)
        var shafts: [Shaft]
        var lines = 1
        var isWave = false
        var isNegated = false
    }

    /// Every horizontal arrow the operator dictionary calls stretchy, and the combining arrows:
    /// a font with no MATH table has a construction for none of them, and STIX Two Math for a third.
    private static let arrowShapes: [Unicode.Scalar: ArrowShape] = {
        var shapes: [Unicode.Scalar: ArrowShape] = [:]
        /// `left` and `right` point their ways with `tail` at the other end; `both` has a head at each.
        func add(left: String, right: String, both: String = "", head: ArrowShape.End = .head, tail: ArrowShape.End = .plain,
                 lines: Int = 1, isWave: Bool = false, isNegated: Bool = false) {
            for (arrows, shaft) in [(left, (head, tail)), (right, (tail, head)), (both, (head, head))] as [(String, ArrowShape.Shaft)] {
                for arrow in arrows.unicodeScalars {
                    shapes[arrow] = ArrowShape(shafts: [shaft], lines: lines, isWave: isWave, isNegated: isNegated)
                }
            }
        }
        add(left: "←⟵\u{20D6}", right: "→⟶\u{20D7}", both: "↔⟷\u{20E1}")
        add(left: "↚", right: "↛", both: "↮", isNegated: true)
        add(left: "↜", right: "↝", both: "↭", isWave: true)
        add(left: "↞", right: "↠", head: .twoHeads)
        add(left: "↢", right: "↣", tail: .tail)
        add(left: "↤⟻", right: "↦⟼", tail: .bar)
        add(left: "↩", right: "↪", tail: .hook)
        add(left: "↫", right: "↬", tail: .loop)
        add(left: "↼", right: "⇀", head: .barbUp)
        add(left: "↽", right: "⇁", head: .barbDown)
        add(left: "⇐⟸", right: "⇒⟹", both: "⇔⟺", lines: 2)
        add(left: "⇍", right: "⇏", both: "⇎", lines: 2, isNegated: true)
        add(left: "⟽", right: "⟾", tail: .bar, lines: 2)
        add(left: "⇚", right: "⇛", lines: 3)
        // One arrow or harpoon over another.
        let leftwards: ArrowShape.Shaft = (.head, .plain), rightwards: ArrowShape.Shaft = (.plain, .head)
        let pairs: [(Unicode.Scalar, [ArrowShape.Shaft])] = [
            ("⇄", [rightwards, leftwards]), ("⇆", [leftwards, rightwards]), ("⇇", [leftwards, leftwards]), ("⇉", [rightwards, rightwards]),
            ("⇋", [(.barbUp, .plain), (.plain, .barbDown)]), ("⇌", [(.plain, .barbUp), (.barbDown, .plain)]),
        ]
        for (arrow, shafts) in pairs { shapes[arrow] = ArrowShape(shafts: shafts) }
        return shapes
    }()

    /// An arrow drawn `width` long, its ink centred on `middle` as the natural glyph's is. The
    /// single arrow sets the proportions: a head's arms run back a quarter em and out 0.15 em,
    /// and those of a double or triple arrow at the same slope, as far past its outer lines.
    private func drawnArrow(_ shape: ArrowShape, width: CGFloat, middle: CGFloat, _ context: LayoutContext) -> MathBox {
        let em = context.fontSize, stroke = arrowStrokeWidth(context)
        // Between the lines of a double arrow, and the radius of a hook or a loop.
        let pitch = em * 0.2, curl = em * 0.13
        let outerLine = CGFloat(shape.lines - 1) * pitch / 2
        let head = em * 0.25 + outerLine / 0.6, spread = head * 0.6
        let left = stroke, right = width - stroke
        let path = CGMutablePath()
        /// The arms of a head whose tip is at (`x`, `y`) and points the way of `facing`: 1 right, -1 left.
        func arms(_ x: CGFloat, _ y: CGFloat, _ facing: CGFloat, up: Bool = true, down: Bool = true) {
            path.move(to: up ? CGPoint(x: x - facing * head, y: y + spread) : CGPoint(x: x, y: y))
            if up { path.addLine(to: CGPoint(x: x, y: y)) }
            if down { path.addLine(to: CGPoint(x: x - facing * head, y: y - spread)) }
        }
        /// What ends a shaft at `x`, the end of the arrow that `facing` points to.
        func draw(_ end: ArrowShape.End, _ x: CGFloat, _ y: CGFloat, _ facing: CGFloat) {
            switch end {
            case .plain: break
            case .head: arms(x, y, facing)
            case .twoHeads: arms(x, y, facing); arms(x - facing * head * 0.8, y, facing)
            case .barbUp: arms(x, y, facing, down: false)
            case .barbDown: arms(x, y, facing, up: false)
            case .tail: arms(x - facing * head, y, -facing)
            case .bar:
                path.move(to: CGPoint(x: x, y: y + spread))
                path.addLine(to: CGPoint(x: x, y: y - spread))
            case .hook, .loop:
                // From the shaft up and round, a hook half way and back along the shaft, a loop
                // three quarters and down across it.
                let loop = end == .loop
                path.move(to: CGPoint(x: x - facing * curl, y: y))
                path.addRelativeArc(center: CGPoint(x: x - facing * curl, y: y + curl), radius: curl, startAngle: -.pi / 2,
                                    delta: facing * .pi * (loop ? 1.5 : 1))
                path.addLine(to: loop ? CGPoint(x: x - facing * 2 * curl, y: y - 2 * curl) : CGPoint(x: x - facing * 1.5 * curl, y: y + 2 * curl))
            }
        }
        /// How far short of its end of the arrow a line `offset` from the middle of its shaft stops:
        /// where it meets the arm of a head, the point of a tail, or the foot of a hook or loop.
        func inset(_ end: ArrowShape.End, _ offset: CGFloat) -> CGFloat {
            switch end {
            case .head: head * abs(offset) / spread
            case .tail: head
            case .hook, .loop: curl
            default: 0
            }
        }
        // Harpoons turn their barbs outwards and lie close; whole heads need room for their inner arms.
        let hasHeads = shape.shafts.contains { $0.left == .head || $0.right == .head }
        let apart = hasHeads ? spread : pitch / 2
        for (index, shaft) in shape.shafts.enumerated() {
            let y = shape.shafts.count == 1 ? 0 : index == 0 ? apart : -apart
            for line in 0..<shape.lines {
                let offset = (CGFloat(line) - CGFloat(shape.lines - 1) / 2) * pitch
                let start = left + inset(shaft.left, offset), end = right - inset(shaft.right, offset)
                path.move(to: CGPoint(x: start, y: y + offset))
                if shape.isWave {
                    // A head sits on a straight end and the shaft waves between, in half-waves of the
                    // length nearest 0.18 em that fills it. At most 200, as an assembly repeats its
                    // extenders: markup can make a shaft any number of ems long.
                    let from = start + (shaft.left == .plain ? 0 : head), to = end - (shaft.right == .plain ? 0 : head)
                    let waves = (to - from) / (em * 0.18), count = (waves >= 2 ? min(waves, 200) : 2).rounded()
                    path.addLine(to: CGPoint(x: from, y: y + offset))
                    for wave in 0..<Int(count) {
                        path.addQuadCurve(to: CGPoint(x: from + (to - from) * CGFloat(wave + 1) / count, y: y + offset),
                                          control: CGPoint(x: from + (to - from) * (CGFloat(wave) + 0.5) / count,
                                                           y: y + offset + (wave % 2 == 0 ? 0.15 : -0.15) * em))
                    }
                }
                path.addLine(to: CGPoint(x: end, y: y + offset))
            }
            draw(shaft.right, right, y, 1)
            draw(shaft.left, left, y, -1)
        }
        if shape.isNegated {
            let reach = spread * 1.25
            path.move(to: CGPoint(x: width / 2 - reach / 2, y: -reach))
            path.addLine(to: CGPoint(x: width / 2 + reach / 2, y: reach))
        }
        // The path is about its own middle line, and its ink goes where the glyph's is: not as far
        // above the shaft as below, where a hook rises higher than a head falls. The box is a
        // stroke beyond the path each way, as the single arrow's always was.
        let bounds = path.boundingBoxOfPath
        var rise = CGAffineTransform(translationX: 0, y: middle - bounds.midY)
        var box = MathBox(width: width, ascent: rise.ty + bounds.maxY + stroke, descent: -(rise.ty + bounds.minY) + stroke)
        box.items = [.path(path.copy(using: &rise) ?? path, lineWidth: stroke, color: context.color, fill: false)]
        return box
    }
}
