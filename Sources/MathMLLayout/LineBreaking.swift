import CoreGraphics
import CoreText
import Foundation

// Line breaking (MathML 3, 3.1.7). A formula is first laid out unbroken, so every operator has its
// form, spacing and stretched size. Each row keeps its children apart on its box (`BreakableRow`),
// `Paragraph` flattens rows nested in rows into one sequence of units that never part, and the
// rows of the result are built from those boxes. A bracket pair split across rows keeps one size;
// one that stays on a row can shrink to that row after the breaks have been chosen. Operator
// spacing and the chosen breaks stay fixed.

// MARK: Attributes

/// `linebreak` on an `mo` (MathML 3, 3.2.5.2.2) or an `mspace` (3.2.7.2).
enum Linebreak: String, Sendable { case auto, newline, nobreak, goodbreak, badbreak }

/// `linebreakstyle`: where the operator goes that a line breaks at. The operator dictionary sets
/// it, to `after` for its three separators (the comma, the semicolon and the invisible separator)
/// and to `before` for everything else (MathML 3, 3.2.5.2.2 and appendix C).
enum LinebreakStyle: String, Sendable { case before, after, duplicate }

/// `indentalign` (MathML 3, 3.2.5.2.3).
enum IndentAlign: String, Sendable { case auto, left, center, right, id }

/// A length that may be a share of something known only once lines break: `indentshift="10%"` is
/// of the line's width, `lineleading="150%"` of the font's leading.
struct LineLength: Sendable, Equatable {
    var points: CGFloat = 0
    var fraction: CGFloat = 0
    func resolve(_ whole: CGFloat) -> CGFloat { points + (whole.isFinite ? fraction * whole : 0) }
}

/// The line-breaking and indentation attributes in effect at an element. They are read at the
/// `mo` or `mspace` a line breaks at (MathML 3, 3.2.5.2.2 and 3.2.5.2.3), and those that say
/// where the operator goes, how far apart the lines are and how they are indented may be
/// "inherited from mstyle or math elements" (3.1.7.1).
///
/// `linebreak` is inherited here too, and of that the specification says two things. It "can
/// only be set on mo and mspace elements" (3.1.7.1). But an `mstyle` takes every attribute that
/// has a default, the schema lists `linebreak` among those it takes (appendix A), and a value
/// there changes the default "for all elements within its scope" (3.3.4.1). The second is
/// followed: `linebreak="nobreak"` on an `mstyle` keeps what it holds on one line.
struct LineStyle: Sendable {
    var linebreak = Linebreak.auto
    /// nil is the default: before an operator, after a separator.
    var style: LinebreakStyle?
    /// `infixlinebreakstyle`, for operators that set no style of their own.
    var infixStyle: LinebreakStyle?
    /// `linebreakmultchar` when it is visible: what an invisible times becomes where a line breaks at it.
    var multiplication: String?
    /// `lineleading`: the gap under a broken line, by default the font's whole `mathLeading`.
    var leading = LineLength(fraction: 1)
    var align = IndentAlign.auto
    /// nil is `indentalign`, their default.
    var alignFirst: IndentAlign?
    var alignLast: IndentAlign?
    /// nil is unset: no shift, and under `indentalign="auto"` the engine's own indentation.
    var shift: LineLength?
    /// nil is `indentshift`, their default.
    var shiftFirst: LineLength?
    var shiftLast: LineLength?
    var target: String?

    static let elements: Set<String> = ["math", "mstyle", "mo", "mspace"]
    static let attributes: Set<String> = [
        "linebreak", "linebreakstyle", "infixlinebreakstyle", "linebreakmultchar", "lineleading", "indentalign",
        "indentalignfirst", "indentalignlast", "indentshift", "indentshiftfirst", "indentshiftlast", "indenttarget",
    ]

    /// Applies an element's attributes. Lengths resolve against its `em` and `ex`, except shares of
    /// the line's width, which wait for it. A value that does not parse changes nothing.
    mutating func apply(_ attributes: [String: String], em: CGFloat, ex: CGFloat) {
        func text(_ name: String) -> String? { attributes[name]?.trimmingCharacters(in: .whitespacesAndNewlines) }
        func keyword(_ name: String) -> String? { text(name)?.lowercased() }
        func length(_ name: String) -> LineLength? {
            guard let text = attributes[name], let length = MathLength(text) else { return nil }
            switch length.unit {
            case .percent, .multiple: return LineLength(fraction: length.value)
            default: return length.resolve(em: em, ex: ex).map { LineLength(points: $0) }
            }
        }
        if let value = keyword("linebreak") {
            // MathML 2's `indentingnewline` now means `newline` (MathML 3, 3.2.7.2).
            linebreak = value == "indentingnewline" ? .newline : Linebreak(rawValue: value) ?? linebreak
        }
        if let value = keyword("linebreakstyle") {
            style = value == "infixlinebreakstyle" ? nil : LinebreakStyle(rawValue: value) ?? style
        }
        if let value = keyword("infixlinebreakstyle") { infixStyle = LinebreakStyle(rawValue: value) ?? infixStyle }
        if let value = text("linebreakmultchar") { multiplication = value.isEmpty || value == "\u{2062}" ? nil : value }
        if let value = length("lineleading") { leading = value }
        if let value = keyword("indentalign") { align = IndentAlign(rawValue: value) ?? align }
        if let value = keyword("indentalignfirst") {
            alignFirst = value == "indentalign" ? nil : IndentAlign(rawValue: value) ?? alignFirst
        }
        if let value = keyword("indentalignlast") {
            alignLast = value == "indentalign" ? nil : IndentAlign(rawValue: value) ?? alignLast
        }
        if let value = length("indentshift") { shift = value }
        if let value = keyword("indentshiftfirst") {
            shiftFirst = value == "indentshift" ? nil : length("indentshiftfirst") ?? shiftFirst
        }
        if let value = keyword("indentshiftlast") {
            shiftLast = value == "indentshift" ? nil : length("indentshiftlast") ?? shiftLast
        }
        if let value = text("indenttarget") { target = value.isEmpty ? nil : value }
    }
}

/// What line breaking knows about one `mo`, `mspace` or space in an `mtext`. A class, so the box
/// of every operator carries a pointer rather than a copy of the style.
final class BreakPoint: Sendable {
    let kind: BreakClass
    let linebreak: Linebreak
    let position: LinebreakStyle
    let isInvisibleTimes: Bool
    /// An operator that holds what follows it (an opening fence, a sign, a large operator) or what
    /// precedes it (a closing fence, a factorial): no line breaks on that side of it.
    let opens: Bool
    let closes: Bool
    let style: LineStyle

    init(kind: BreakClass, linebreak: Linebreak, position: LinebreakStyle = .before, isInvisibleTimes: Bool = false,
         opens: Bool = false, closes: Bool = false, style: LineStyle) {
        self.kind = kind; self.linebreak = linebreak; self.position = position; self.isInvisibleTimes = isInvisibleTimes
        self.opens = opens; self.closes = closes; self.style = style
    }

    /// An `mo` drawn as `text`, where `style` is in effect. Its class is its dictionary entry's,
    /// and so is what it is: a "+" that is a sign has the prefix entry and no class, an "=" that
    /// is first after an `mtext`, formally a prefix, still has its only entry, a relation's, and a
    /// "(" in the middle of a row, formally infix, is still an opening fence. A line breaks
    /// before an operator, as "+ c" starts a line in print, but after a separator.
    convenience init(operator text: String, _ entry: OperatorDictionary.Entry, form: OperatorForm, flags: OperatorFlags,
                     _ style: LineStyle) {
        let isSeparator = flags.contains(.separator), isFence = flags.contains(.fence)
        let listed = OperatorDictionary.listedForm(text, form: form) ?? form
        self.init(kind: isSeparator && entry.breakClass == .none ? .separator : isFence ? .none : entry.breakClass,
                  linebreak: style.linebreak, position: style.style ?? (isSeparator ? .after : style.infixStyle ?? .before),
                  isInvisibleTimes: text == "\u{2062}", opens: listed == .prefix || isFence && form == .prefix,
                  closes: listed == .postfix || isFence && form == .postfix, style: style)
    }
}

/// What a row keeps on its box so that a line can break inside it: its children, apart, each
/// with its place in the row.
final class BreakableRow {
    struct Child {
        var box: MathBox
        /// The left edge in the row, after the space before it.
        var x: CGFloat
        var point: BreakPoint?
        /// A binary operator that is a sign here (TeX's rule 5): no line breaks before a sign.
        var isUnary = false
        /// Held to the child before it, as a script is to its base: no line breaks between them.
        var isAttached = false
        /// The element's `id`, which an `indenttarget` may name.
        var id: String?
    }
    let children: [Child]
    /// By child index, the visible form of an invisible times whose `linebreakmultchar` asks for one.
    let visible: [Int: MathBox]
    /// How many items the row's box drew when it was built. A box changed since (an `mphantom`
    /// emptied it, a `mathbackground` went under it) no longer matches its children, and is one unit.
    let itemCount: Int
    /// An embellished operator: breaking at it is no deeper than breaking at a bare `mo`.
    let isOperator: Bool
    /// Whether a `linebreak="newline"` is somewhere in the row: it then breaks whatever the width.
    let hasForced: Bool
    /// Whether the row is more than one thing, itself or the one row it wraps: only then may a line
    /// break in it.
    let isSeveral: Bool
    let fontSize: CGFloat
    let display: Bool
    let style: LineStyle

    init(children: [Child], visible: [Int: MathBox] = [:], itemCount: Int, isOperator: Bool = false,
         _ context: LayoutContext) {
        self.children = children; self.visible = visible; self.itemCount = itemCount; self.isOperator = isOperator
        hasForced = children.contains { $0.point?.linebreak == .newline || $0.box.row?.hasForced == true }
        isSeveral = children.count > 1 || children.first?.box.row?.isSeveral == true
        fontSize = context.fontSize; display = context.display; style = context.lines
    }
}

// MARK: Layout

extension LayoutEngine {
    /// Limits on retries of complete layouts. Part retries compare completed ancestors; the
    /// boundary search only runs when the first measurement fails to reproduce its own width.
    static let wrappingPartTrials = 12
    static let wrappingBoundaryRefinements = 40
    // At most 53 finite fits of 21 passes, plus one natural-layout pass.
    static let maximumWrappingPasses = 1_114
    /// The line-breaking attributes of `node` join the context its content inherits, on the elements
    /// that may carry them: `mo` and `mspace`, and `mstyle` and `math` for the operators inside
    /// (`LineStyle` has what MathML 3 says of each).
    func inheritLineStyle(_ node: MathMLNode, _ context: inout LayoutContext) {
        guard LineStyle.elements.contains(node.name),
              node.attributes.keys.contains(where: LineStyle.attributes.contains) else { return }
        context.lines.apply(node.attributes, em: context.fontSize, ex: xHeight(context))
    }

    /// The structure `row` leaves on its box: each child with its place, what a line may do at it,
    /// and for an `mtext` its words.
    func breakableRow(_ children: [MathMLNode], _ boxes: [MathBox], at offsets: [CGFloat], unary: Set<Int>, _ box: MathBox,
                      _ context: LayoutContext, depth: Int) throws -> BreakableRow {
        var result: [BreakableRow.Child] = []
        result.reserveCapacity(children.count)
        var visible: [Int: MathBox] = [:]
        for (index, child) in children.enumerated() {
            var item = BreakableRow.Child(box: boxes[index], x: offsets[index], point: boxes[index].op?.breakPoint,
                                          isUnary: unary.contains(index), id: child.attributes["id"])
            switch child.name {
            case "mspace":
                item.point = spaceBreak(child, context)
            case "mtext":
                // Right-to-left text is drawn in visual order: its words would wrap last first.
                if !child.text.unicodeScalars.contains(where: Self.isRightToLeft) {
                    item.box.row = words(item.box, inherit(child, context))
                }
            case "mo":
                if let point = item.point, point.isInvisibleTimes, let text = point.style.multiplication {
                    visible[index] = try layout(MathMLNode(name: "mo", text: text), context, Embellishment(form: .infix),
                                                depth: depth + 1)
                }
            default: break
            }
            result.append(item)
        }
        return BreakableRow(children: result, visible: visible, itemCount: box.items.count, isOperator: box.op != nil,
                            context)
    }

    /// Hebrew, Arabic and the other right-to-left scripts, by block.
    private static func isRightToLeft(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF: true
        default: false
        }
    }

    /// An `mspace` is a place to break when its `linebreak` says so and it has no size: the
    /// attribute "should be ignored if any dimensional attribute is set" (MathML 3, 3.2.7.2).
    private func spaceBreak(_ node: MathMLNode, _ context: LayoutContext) -> BreakPoint? {
        guard !["width", "height", "depth"].contains(where: { node.attributes[$0] != nil }) else { return nil }
        let style = inherit(node, context).lines
        guard style.linebreak != .auto, style.linebreak != .nobreak else { return nil }
        return BreakPoint(kind: .none, linebreak: style.linebreak, style: style)
    }

    /// An `mtext`'s box as a row of its words, so that a line can break at its spaces; nil when it
    /// has fewer than two words or is not plain left-to-right text. The words are the box's own
    /// glyphs, cut at the space glyphs, so together they measure what the text does. A no-break
    /// space is no space glyph and keeps its words together.
    private func words(_ box: MathBox, _ context: LayoutContext) -> BreakableRow? {
        guard context.lines.linebreak != .nobreak else { return nil }
        var runs: [(run: GlyphRun, space: CGGlyph)] = []
        var hasSpace = false
        for item in box.items {
            guard case .glyphs(let run) = item else { return nil }
            var character: UniChar = 0x20
            var space: CGGlyph = 0
            if !CTFontGetGlyphsForCharacters(run.font, &character, &space, 1) { space = 0 }
            hasSpace = hasSpace || space != 0 && run.glyphs.contains(space)
            runs.append((run, space))
        }
        guard hasSpace else { return nil }
        let point = BreakPoint(kind: .space, linebreak: .auto, style: context.lines)
        var children: [BreakableRow.Child] = []
        var word = MathBox(), ink: CGRect?
        var start: CGFloat?, edge = -CGFloat.infinity
        var spaced = false
        func close(at end: CGFloat) {
            guard let x = start else { return }
            word.width = end - x
            word.ascent = ink?.maxY ?? 0
            word.descent = ink.map { -$0.minY } ?? 0
            children.append(BreakableRow.Child(box: word, x: x, point: spaced && !children.isEmpty ? point : nil))
            word = MathBox(); ink = nil; start = nil; spaced = false
        }
        for (run, space) in runs {
            var index = 0
            while index < run.glyphs.count {
                // Glyphs that do not advance left to right are not words in a row: leave the text whole.
                guard run.positions[index].x >= edge - 0.01 else { return nil }
                edge = run.positions[index].x
                if space != 0, run.glyphs[index] == space {
                    close(at: edge)
                    spaced = true
                    index += 1
                    continue
                }
                var end = index + 1
                while end < run.glyphs.count, space == 0 || run.glyphs[end] != space {
                    guard run.positions[end].x >= edge - 0.01 else { return nil }
                    edge = run.positions[end].x
                    end += 1
                }
                let x = start ?? run.positions[index].x
                start = x
                let glyphs = Array(run.glyphs[index..<end])
                let positions = run.positions[index..<end].map { CGPoint(x: $0.x - x, y: $0.y) }
                var rects = [CGRect](repeating: .zero, count: glyphs.count)
                CTFontGetBoundingRectsForGlyphs(run.font, .horizontal, glyphs, &rects, glyphs.count)
                var runInk: CGRect?
                for (rect, position) in zip(rects, positions) where !rect.isEmpty {
                    let placed = rect.offsetBy(dx: position.x, dy: position.y)
                    runInk = runInk.map { $0.union(placed) } ?? placed
                }
                if let runInk { ink = ink.map { $0.union(runInk) } ?? runInk }
                word.items.append(.glyphs(GlyphRun(font: run.font, glyphs: glyphs, positions: positions, color: run.color,
                                                   ink: runInk ?? .null)))
                index = end
            }
        }
        close(at: box.width)
        guard children.count > 1 else { return nil }
        return BreakableRow(children: children, itemCount: box.items.count, context)
    }

    // MARK: Lines

    /// Fits a formula with shared budgets first, then independent budgets for wrapping neighbours.
    /// Kept apart from `lines` so the reporter's search does not enlarge the layout frame.
    private static func fittedParagraph(_ root: MathMLNode, style: MathStyle, limit: CGFloat,
                                        first: CGFloat, engine: LayoutEngine, layoutPasses: inout Int) throws -> Paragraph {
        let size = fontSize(style)
        engine.wrapOverrides = [:]
        engine.mayNarrow = false
        engine.lineWidth = limit; engine.wrapWidth = limit
        /// The formula laid out again, what wraps in it wrapping to `wrap`.
        func pass(_ wrap: CGFloat) throws -> Paragraph {
            layoutPasses += 1
            engine.restart()
            engine.wrapWidth = wrap
            return Paragraph(try engine.layoutRoot(root, style: style), fontSize: size)
        }
        /// The wrap width that made the pass just made what it is: `wrap`, or the width of the widest
        /// thing in it that wraps when that is less, since any wrap width beyond that leaves it whole.
        func reach(_ wrap: CGFloat) -> CGFloat { engine.loosest > 0 ? min(wrap, engine.loosest) : wrap }
        var paragraph = try pass(limit)
        // The wrap width of the layout that is kept and its widest stretch, and those of the layout
        // wrapped least far beyond it in which a row overflowed.
        var kept = (wrap: reach(limit), widest: paragraph.widest)
        var over: (wrap: CGFloat, widest: CGFloat)?
        // A table (or a fraction, radical or enclosure) wraps its content to fit the line, but takes
        // no account of what stands beside it. So it narrows further, as far as the stretch it cannot
        // break from needs. A table that is most of its row narrows to keep the row whole instead:
        // the brace of a list of cases stays beside it rather than on a row above. Fences may widen
        // as what they hold grows taller, so a third pass settles what the second left over.
        for _ in 0..<2 {
            guard limit.isFinite, let wrapping = engine.narrowable else { break }
            let whole = paragraph.entire.width
            let keepsOneRow = wrapping.isTable && whole - wrapping.width <= first / 2
                && wrapping.width - (whole - first) >= wrapping.minimum
            let excess = keepsOneRow ? whole - first : kept.widest - limit
            let narrowed = wrapping.width - excess
            guard excess > Paragraph.slop, narrowed > 0, narrowed < kept.wrap else { break }
            let narrower = try pass(narrowed)
            // No better: it was not what was too wide.
            guard keepsOneRow ? narrower.entire.width < whole : narrower.widest < kept.widest else { break }
            // A table narrowed to keep its row whole is as narrow as that takes, whatever room is left.
            over = keepsOneRow || kept.widest <= limit + Paragraph.slop ? nil : kept
            paragraph = narrower
            kept = (reach(narrowed), narrower.widest)
        }
        // Those passes narrow by one measure: that of the widest thing that wraps and is most of the
        // line. Two fractions side by side are one stretch, each half the line when it is theirs alone:
        // the excess is more than either can lose, so both stayed whole and the stretch overflowed; on a
        // line twice as wide both wrapped to that, and overflowed again. A host that scaled the formula
        // to `widestUnbreakable` and laid it out at that width found a row wider still.
        //
        // Try fully wrapping too, and keep any improvement. Height-dependent geometry can make
        // some neighbours wider, so the independent part retries below also try leaving them whole.
        if limit.isFinite, engine.mayNarrow, kept.wrap > 0, kept.widest > limit + Paragraph.slop {
            let narrowest = try pass(0)
            if narrowest.widest <= limit + Paragraph.slop || narrowest.widest < kept.widest {
                over = kept
                paragraph = narrowest
                kept = (0, narrowest.widest)
            }
        }
        // And a layout that fits where one wrapped less far overflowed may have wrapped much further
        // than the line asked: every term of those fractions on a line of its own. The wrap width is
        // raised again, twice, and whichever layout fits is kept: first to where a stretch that grows
        // evenly between the two would fill the line, and when that overflows, since a stretch grows a
        // term at a time, to half way. This initial shared-budget search takes at most six passes.
        if var over, limit.isFinite {
            var missed = false
            for _ in 0..<2 where kept.widest < limit * 7 / 8 && over.widest > kept.widest {
                let even = kept.wrap + (limit - kept.widest) * (over.wrap - kept.wrap) / (over.widest - kept.widest)
                let wrap = missed ? (kept.wrap + over.wrap) / 2 : even
                guard wrap > kept.wrap + 1, wrap < over.wrap else { break }
                let between = try pass(wrap)
                if between.widest <= limit + Paragraph.slop {
                    paragraph = between
                    kept = (reach(wrap), between.widest)
                } else {
                    over = (reach(wrap), between.widest)
                    missed = true
                }
            }
        }
        // A shared budget cannot choose which neighbour should wrap. In particular, a taller
        // radical can widen its sign or a surrounding fence, and padding may depend on height.
        // Try each part independently and compare the completed formula, including that ink.
        // A strict improvement is kept; the bounded search never oscillates between neighbours.
        if limit.isFinite, kept.widest > limit + Paragraph.slop, engine.mayNarrow {
            _ = try pass(kept.wrap)
            var budgets: [Int: CGFloat] = [:]
            var trials = 0
            for _ in 0..<2 {
                let parts = engine.wrapParts
                var changed = false
                for (index, part) in parts.enumerated() where part.natural > part.minimum + Paragraph.slop {
                    for budget in [CGFloat(0), part.natural] {
                        guard trials < Self.wrappingPartTrials else { break }
                        guard budget != (budgets[index] ?? kept.wrap) else { continue }
                        trials += 1
                        engine.wrapOverrides = budgets
                        engine.wrapOverrides[index] = budget
                        let candidate = try pass(kept.wrap)
                        if candidate.widest < paragraph.widest - Paragraph.slop {
                            paragraph = candidate
                            kept.widest = candidate.widest
                            budgets[index] = budget
                            changed = true
                        }
                    }
                }
                engine.wrapOverrides = budgets
                _ = try pass(kept.wrap)
                if !changed || trials >= Self.wrappingPartTrials { break }
            }
        }
        return paragraph
    }

    /// Lays out `root` and breaks it into rows no wider than `maximumWidth`, the first no wider than
    /// `firstRowMaximumWidth`. Each row's box covers its ink, so a host that clips to a row (an
    /// attachment image) never cuts an italic overhang or a glyph that leans past the left edge.
    ///
    /// `overflow` and `maxwidth` on `math` (MathML 3, 2.2.1) are not read: the width given decides.
    /// Breaking is what `overflow="linebreak"`, the default, asks for (3.1.7.1). The other values
    /// "suggest a processing method to the renderer" that is a host's to carry out (scrolling,
    /// eliding, truncating, scaling), and a host that means to gives no width.
    static func lines(_ root: MathMLNode, style: MathStyle, maximumWidth: CGFloat,
                      firstRowMaximumWidth: CGFloat?) throws -> MathLines {
        // Check before entering the fitting and element-layout frames. A tiny host thread may
        // have no room for those frames even before the first element can check its own stack.
        guard !MathLimits.isStackSpent(MathLimits.stackFloor()) else { throw MathLayoutError.limitExceeded }
        // A line wider than any formula may be is no limit: `.greatestFiniteMagnitude` is how a host
        // says so as often as `.infinity`. Taken as a width, a row centred in it, or indented by a
        // tenth of it, was placed past the bound on extent and the formula refused, and a share of
        // 1e308 points overflowed to infinity and from there to rows of no width.
        func bound(_ width: CGFloat) -> CGFloat { width.isNaN || width > MathLimits.extent ? .infinity : max(width, 0) }
        let limit = bound(maximumWidth)
        let first = firstRowMaximumWidth.map { $0.isNaN ? limit : bound($0) } ?? limit
        let size = fontSize(style)
        // One engine, so whatever it keeps for the formula is kept across a second pass.
        let engine = LayoutEngine(fontName: style.fontName)
        var layoutPasses = 0
        func fitted(_ limit: CGFloat, first: CGFloat) throws -> Paragraph {
            try fittedParagraph(root, style: style, limit: limit, first: first,
                                engine: engine, layoutPasses: &layoutPasses)
        }
        let paragraph = try fitted(limit, first: first)
        var needed = paragraph.widest
        // The width of a stretch in this layout need not reproduce the same layout: wrapping
        // changes height, ink and negative spacing. Find the feasible boundary by laying out at
        // the reported width itself, with the normal first-row limit. This search is separate
        // from the host's first-row budget and is bounded even for hostile input.
        // Equal widths do not prove equal height: even a part already at its minimum can gain
        // breaks on a shorter forced row, changing height-dependent padding or fence geometry.
        // Breaking an otherwise plain paragraph can change validity too: an enormous lineleading
        // may fit on one unbounded first row but exceed the height bound on several normal rows.
        if !engine.wrapParts.isEmpty || paragraph.stops.count > 2, needed > 0 {
            func excess(_ width: CGFloat) throws -> CGFloat {
                do {
                    let candidate = try fitted(width, first: width)
                    // Fitting includes the same geometry and item bounds as the returned public
                    // layout. A narrow width that makes a wrapping ancestor too tall is not a
                    // feasible bound, even when every row is narrow enough.
                    let measured = try engine.measuredLines(candidate, limit: width, first: width, size: size)
                    return max(0, measured.width - width)
                } catch MathLayoutError.limitExceeded {
                    return .infinity
                }
            }
            var low = needed, high = needed
            var over = try excess(high)
            if over > Paragraph.slop {
                // Advance to an actually measured overflow edge; once fitting, keep that layout's
                // width as the upper bound, and refine down to floating-point comparison slack.
                for _ in 0..<8 where over > Paragraph.slop && over.isFinite && high < MathLimits.extent {
                    high = min(MathLimits.extent, high + max(over, Paragraph.slop * 2))
                    over = try excess(high)
                }
                // A fitting input width is a useful upper bound even when height changes make
                // the measured overflow edge jump beyond it. Recheck with the normal first row,
                // since the host may have given its first row a different width.
                if limit.isFinite, needed < limit, limit < high || over > Paragraph.slop {
                    let inputExcess = try excess(limit)
                    if inputExcess <= Paragraph.slop { high = limit; over = inputExcess }
                }
                if over > Paragraph.slop {
                    // Forced rows and negative spacing can reach beyond the natural entire row.
                    // Use all of their measured edges, then verify the proposed bound too.
                    let natural = try fitted(.infinity, first: .infinity)
                    let naturalRows = natural.rows(limit: .infinity, first: .infinity, auto: (.left, 0))
                    high = min(MathLimits.extent, max(high, natural.entire.width, natural.widest,
                               naturalRows.reduce(0) { max($0, $1.x + $1.box.width) }))
                    over = try excess(high)
                }
                // No unverified measurement escapes as the promised width. The maximum permitted
                // extent is the last upper bound tried, and is itself laid out and measured.
                if over > Paragraph.slop, high < MathLimits.extent {
                    high = MathLimits.extent
                    over = try excess(high)
                }
                guard over <= Paragraph.slop else { throw MathLayoutError.limitExceeded }
                for _ in 0..<Self.wrappingBoundaryRefinements where high - low > Paragraph.slop {
                    let middle = (low + high) / 2
                    if try excess(middle) <= Paragraph.slop { high = middle } else { low = middle }
                }
                needed = high
            }
        }
        var lines = try engine.measuredLines(paragraph, limit: limit, first: first, size: size)
        lines.widestUnbreakable = needed
        lines.layoutPasses = layoutPasses
        return lines
    }

    /// The actual returned rows and their public geometry bounds, shared by width trials.
    private func measuredLines(_ paragraph: Paragraph, limit: CGFloat, first: CGFloat, size: CGFloat) throws -> MathLines {
        let rows = paragraph.rows(limit: limit, first: first, auto: (.left, paragraph.display ? paragraph.em : 0))
        var lines = MathLines(rows: stack(rows, em: paragraph.em), widestUnbreakable: paragraph.widest,
                              axisHeight: constants.axisHeight * size)
        var items = 0
        for row in lines.rows {
            lines.width = max(lines.width, row.origin.x + row.box.width)
            lines.ascent = max(lines.ascent, row.origin.y + row.box.ascent)
            lines.descent = max(lines.descent, row.box.descent - row.origin.y)
            items += row.box.itemCount
        }
        guard [lines.width, lines.ascent, lines.descent].allSatisfy({ $0.isFinite && $0 <= MathLimits.extent }),
              items <= MathLimits.items else { throw MathLayoutError.limitExceeded }
        return lines
    }

    /// Rows one under another like lines of text. Each counts as at least a strut of the font's
    /// ascent and descent, so rows of plain symbols keep one baseline distance, and a taller row
    /// pushes its neighbours away. Between them goes the MATH table's `mathLeading`, scaled by
    /// `lineleading` (MathML 3 leaves its default to the renderer). Origins have y up.
    func stack(_ rows: [Paragraph.Row], em: CGFloat) -> [(box: MathBox, origin: CGPoint)] {
        let ascent = CTFontGetAscent(font.base) * em, descent = CTFontGetDescent(font.base) * em
        var y: CGFloat = 0
        var result: [(box: MathBox, origin: CGPoint)] = []
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let above = rows[index - 1]
                y += max(0, max(above.box.descent, descent) + above.leading.resolve(constants.mathLeading * em)
                    + max(row.box.ascent, ascent))
            }
            result.append((row.box, CGPoint(x: row.x, y: 0 - y)))
        }
        return result
    }

    /// A row broken to `width` and stacked into one box on its first line's baseline; nil when it
    /// stays one line.
    private func wrapped(_ paragraph: Paragraph, width: CGFloat, align: IndentAlign) -> MathBox? {
        let rows = paragraph.rows(limit: width, first: width, auto: (align, 0), tight: true)
        guard rows.count > 1 else { return nil }
        var box = MathBox(ascent: rows[0].box.ascent)
        for line in stack(rows, em: paragraph.em) {
            box.add(line.box, at: line.origin)
            box.width = max(box.width, line.origin.x + line.box.width)
            box.descent = max(box.descent, line.box.descent - line.origin.y)
        }
        return box
    }

    /// Counts something that wraps and is `width` wide, which is more than the least it can be.
    private func loose(_ width: CGFloat) {
        mayNarrow = true
        loosest = max(loosest, width)
    }

    /// Counts something wrapped as what `lines` may narrow further: the widest that is most of the line.
    private func note(width: CGFloat, minimum: CGFloat, isTable: Bool = false) {
        guard lineWidth.isFinite, width > lineWidth / 2, width > minimum + Paragraph.slop,
              width > narrowable?.width ?? 0 else { return }
        narrowable = (width, minimum, isTable)
    }

    /// The part of a fraction, a radicand or an enclosure's content, wrapped into stacked lines when
    /// with the `fixed` width its parent adds it is wider than the line; nil when it stays as it
    /// is. MathML 3 (3.1.7.1) requires no breaks inside these and allows them, forced ones too.
    func wrapped(_ box: MathBox, beside fixed: CGFloat, align: IndentAlign = .center) -> MathBox? {
        let part = wrapParts.count, budget = nextWrapWidth
        wrapParts.append((box.width + fixed, box.width + fixed, box.width + fixed))
        let isForced = box.row?.hasForced == true
        guard isForced || lineWidth.isFinite && box.width + fixed > min(budget, lineWidth / 2) else {
            // Left whole and unmeasured: a row of more than one thing might wrap in a narrower line.
            if box.row?.isSeveral == true {
                loose(box.width + fixed)
                wrapParts[part].minimum = min(Paragraph(box).widest, box.width) + fixed
            }
            return nil
        }
        let paragraph = Paragraph(box)
        let least = min(paragraph.widest, box.width)
        var result = wrapped(paragraph, width: max(least, budget - fixed), align: align)
        // Negative spacing may make a broken row wider than the whole row. Automatic wrapping
        // must keep the narrower alternative; a forced break still takes precedence.
        if !isForced, let stacked = result, stacked.width >= box.width { result = nil }
        result?.op = box.op
        wrapParts[part].width = (result ?? box).width + fixed
        wrapParts[part].minimum = least + fixed
        if (result ?? box).width > least + Paragraph.slop { loose((result ?? box).width + fixed) }
        note(width: (result ?? box).width + fixed, minimum: least + fixed)
        return result
    }

    /// Narrows the columns of a table wider than the line, and wraps the cells that no longer fit
    /// theirs into stacked lines: a column's width "should be used as the line wrapping width for
    /// linebreaking, and each entry in an mtable is linewrapped as needed" (MathML 3, 3.1.7.1).
    /// That width is an attribute's or the content's there; narrowing it to the line is this
    /// engine's. Columns narrower than an equal share keep their width and the rest share what
    /// is left, none below its widest unbreakable unit. A cell with a forced break is stacked
    /// whatever the width. `fixed` is the width of everything but the columns.
    func wrapCells(_ cells: inout [[(box: MathBox, align: String?)]], columnAlign: [String], fixed: CGFloat) {
        let part = wrapParts.count, budget = nextWrapWidth
        wrapParts.append((0, 0, 0))
        func align(_ row: Int, _ column: Int) -> IndentAlign {
            let name = cells[row][column].align ?? columnAlign.last.map { _ in columnAlign[min(column, columnAlign.count - 1)] }
            return name == "left" ? .left : name == "right" ? .right : .center
        }
        var paragraphs: [[Paragraph?]] = cells.map { [Paragraph?](repeating: nil, count: $0.count) }
        // Asked before a forced break stacks a cell, which is then a box and no row.
        let isSeveral = cells.contains { $0.contains { $0.box.row?.isSeveral == true } }
        for row in cells.indices {
            for column in cells[row].indices where cells[row][column].box.row?.hasForced == true {
                let paragraph = Paragraph(cells[row][column].box)
                paragraphs[row][column] = paragraph
                guard let box = wrapped(paragraph, width: .infinity, align: align(row, column)) else { continue }
                cells[row][column].box = box
            }
        }
        var natural = [CGFloat](repeating: 0, count: cells.map(\.count).max() ?? 0), least = natural
        func total() -> CGFloat {
            for index in natural.indices { natural[index] = 0 }
            for row in cells {
                for (column, cell) in row.enumerated() { natural[column] = max(natural[column], cell.box.width) }
            }
            return natural.reduce(0, +) + fixed
        }
        var width = total()
        wrapParts[part] = (width, width, width)
        // Smaller tables are left alone, and unmeasured: a row breaks around them.
        guard lineWidth.isFinite, width > min(budget, lineWidth / 2) else {
            if isSeveral { loose(width) }
            return
        }
        for row in cells.indices {
            for column in cells[row].indices {
                let paragraph = paragraphs[row][column] ?? Paragraph(cells[row][column].box)
                paragraphs[row][column] = paragraph
                least[column] = max(least[column], min(paragraph.widest, cells[row][column].box.width))
            }
        }
        if width > budget + Paragraph.slop {
            let room = budget - fixed
            func filled(_ level: CGFloat) -> CGFloat { zip(natural, least).reduce(0) { $0 + min($1.0, max($1.1, level)) } }
            var low: CGFloat = 0, high = natural.max() ?? 0
            if filled(0) < room {
                for _ in 0..<48 {
                    let level = (low + high) / 2
                    if filled(level) <= room { low = level } else { high = level }
                }
            }
            for row in cells.indices {
                for column in cells[row].indices {
                    let share = max(least[column], low)
                    guard cells[row][column].box.width > share + Paragraph.slop, let paragraph = paragraphs[row][column],
                          let box = wrapped(paragraph, width: share, align: align(row, column)) else { continue }
                    cells[row][column].box = box
                }
            }
            width = total()
        }
        if width > least.reduce(0, +) + fixed + Paragraph.slop { loose(width) }
        wrapParts[part].width = width
        wrapParts[part].minimum = least.reduce(0, +) + fixed
        note(width: width, minimum: least.reduce(0, +) + fixed, isTable: true)
    }
}

/// The rows of a broken formula, each covering its ink, with its baseline's left end relative to
/// the first row's (y up), and what `MathLayout` reports of the whole.
struct MathLines {
    /// Complete-layout retries, exposed internally so adversarial tests can verify the work bound.
    var layoutPasses = 0
    var rows: [(box: MathBox, origin: CGPoint)]
    var width: CGFloat = 0
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var widestUnbreakable: CGFloat
    var axisHeight: CGFloat
}

// MARK: Breaking

/// A row flattened for breaking: the units that never part, in order, and the stops between
/// them where a row may end.
///
/// The spine is the row itself and every row laid out directly as its child: an `mrow`,
/// `mstyle` or `mfenced`, through `semantics` and `maction`, the words of an `mtext`, and the
/// base of `msub`, `msup`, `msubsup` and `mmultiscripts` when it is a row, with its scripts
/// held to it. Everything else (a fraction, a radical, a table, a limit) is one unit.
struct Paragraph {
    struct Unit {
        var box: MathBox
        /// The left edge in the unbroken row.
        var x: CGFloat
        var ink: CGRect?
        /// Held to the unit before it: no row starts here.
        var isAttached = false
    }

    /// A place a row may end. The row after it starts with unit `at`.
    struct Stop {
        var at: Int
        var penalty: CGFloat = 0
        var isForced = false
        /// The `mo`, `mspace` or space there: its attributes indent the row after it.
        var point: BreakPoint
        /// What the stop adds to the rows it parts, as an index into `inserts`: at the start of the
        /// row after it a head, `headAdvance` wide to the unit that follows and overhanging its left
        /// edge by `headLeft`; at the end of the row before it a tail, `tailOffset` after the last
        /// unit, ending `tailAdvance` after it and overhanging that by `tailRight`. The other edge
        /// of each one's ink, from its own origin, is `headInk` and `tailInk`: a head is on the
        /// right of its row, and a tail on the left, when what the row holds runs leftward.
        var insert: Int?
        var headAdvance: CGFloat = 0, headLeft: CGFloat = 0, headInk = -CGFloat.infinity
        var tailOffset: CGFloat = 0, tailAdvance: CGFloat = 0, tailRight: CGFloat = 0, tailInk = CGFloat.infinity
    }

    struct Row {
        /// Covers its ink.
        var box: MathBox
        var x: CGFloat
        /// The `lineleading` under it.
        var leading = LineLength(fraction: 1)
    }

    /// A unit a line may break at, as `flatten` finds it: what it is nested in, whether it is a
    /// sign, and its visible form when it is an invisible times with one.
    private typealias Break = (unit: Int, point: BreakPoint, depth: Int, isUnary: Bool, visible: MathBox?)

    /// Floating-point slack when a width is compared with a limit: a formula fits the width it measured.
    static let slop: CGFloat = 0.001
    /// How many stops back from the farthest a row can reach are tried as its end. Fuller rows cost
    /// less, so the best is among the nearest, and the search stays linear in the formula however
    /// wide the line. Also how many rows up an `indenttarget` is looked for.
    static let window = 48
    // Costs, in the units of a break's penalty. A row costs its break, how empty it is left (the
    // square of the unused share of the line, as TeX's badness grows) and a little for being a
    // row. So a relation is the place to break unless it leaves its row some 70% empty where a
    // sum would fill it, and likewise a sum before a product, and an outer level before an inner.
    static let emptiness: CGFloat = 60, rowCost: CGFloat = 10, nesting: CGFloat = 25, overflow: CGFloat = 1_000_000

    private(set) var units: [Unit] = []
    /// The start, every place a row may end, and the end.
    private(set) var stops: [Stop] = []
    /// A duplicated operator, or an invisible times made visible, for the stops that have one.
    private var inserts: [(head: MathBox?, tail: MathBox?)] = []
    /// The first unit of each element with an `id`.
    private var ids: [String: Int] = [:]
    /// Matching fence units, including pairs written flat among other children.
    private var pairs: [(open: Int, close: Int)] = []
    private var hasForced = false
    /// The attributes the formula starts with, those of the row its first unit is in: they place
    /// its first row.
    private var lead = BreakPoint(kind: .none, linebreak: .auto, style: LineStyle())
    /// By stop: where a row starting there begins and one ending there ends in the unbroken row.
    private var starts: [CGFloat] = [], ends: [CGFloat] = []
    /// By unit boundary: the leftmost ink from there on and the rightmost before it, in the unbroken row.
    private var inkFrom: [CGFloat] = [], inkTo: [CGFloat] = []
    /// Units run left to right, so the end of a row is the farthest it reaches, and the ink at its
    /// edges is the leftmost from its start on and the rightmost up to its end. A negative space
    /// undoes that: after `<mspace width="20em"/>`, an operator and `<mspace width="-20em"/>`, every
    /// row was measured as reaching where the first space did, none fitted, and each stretch of the
    /// rest of the formula was a row of its own. Where the ends of the stops, the right edges of the
    /// units' ink or its left edges (negated here) do not rise from one to the next, these find the
    /// greatest within a row instead; each is nil while the running extreme above is the row's own.
    private var farthest: Maxima?, rightmost: Maxima?, leftmost: Maxima?
    /// The unbroken row, covering its ink: the one row when nothing breaks.
    private let unbroken: MathBox
    /// Its width, and how far its ink overhangs its left edge.
    let entire: (width: CGFloat, left: CGFloat)
    /// The font size and style of the row that breaks; `em` is `fontSize` for a box that is no row.
    let em: CGFloat
    let display: Bool

    init(_ box: MathBox, fontSize: CGFloat = 0) {
        let covered = Self.covering(box, ink: box.inkBounds)
        unbroken = covered.box
        entire = (covered.box.width, covered.left)
        if let row = box.row, row.itemCount == box.items.count {
            em = row.fontSize; display = row.display
            var breaks: [Break] = []
            flatten(row, at: 0, depth: 0, isUnary: false, isAttached: false, level: 0, &breaks)
            if !units.isEmpty { addStops(breaks) }
        } else {
            em = fontSize; display = false
        }
        if units.isEmpty { units = [Unit(box: box, x: 0, ink: box.inkBounds)] }
        var opened: [Int] = []
        for index in units.indices {
            guard let op = units[index].box.op, op.has(.fence), let point = op.breakPoint else { continue }
            if point.closes, let start = opened.popLast() { pairs.append((start, index)) }
            if point.opens { opened.append(index) }
        }
        stops = [Stop(at: 0, point: lead)] + stops + [Stop(at: units.count, point: lead)]
        let lefts = units.map { unit in unit.ink.map { unit.x + $0.minX } ?? .infinity }
        let rights = units.map { unit in unit.ink.map { unit.x + $0.maxX } ?? -.infinity }
        inkFrom = [CGFloat](repeating: .infinity, count: units.count + 1)
        inkTo = [CGFloat](repeating: -.infinity, count: units.count + 1)
        for index in units.indices { inkTo[index + 1] = max(inkTo[index], rights[index]) }
        for index in units.indices.reversed() { inkFrom[index] = min(inkFrom[index + 1], lefts[index]) }
        // The formula's own edges stay where the unbroken row has them. A row made by a break starts
        // at its first unit and ends with its last, without the space the operator there had outside.
        starts = stops.map { $0.at == 0 ? 0 : units[min($0.at, units.count - 1)].x }
        ends = stops.map { stop in
            stop.at == units.count ? box.width : stop.at == 0 ? 0 : units[stop.at - 1].x + units[stop.at - 1].box.width
        }
        /// Whether no value is less than the one before it; a unit without ink has none.
        func rises(_ values: [CGFloat]) -> Bool {
            var last = -CGFloat.infinity
            for value in values where value.isFinite {
                if value < last { return false }
                last = value
            }
            return true
        }
        if !rises(ends) { farthest = Maxima(ends) }
        if !rises(rights) { rightmost = Maxima(rights) }
        if !rises(lefts) { leftmost = Maxima(lefts.map { -$0 }) }
    }

    /// The greatest of any stretch of a sequence, found in constant time: a table whose every level
    /// holds the greatest of each stretch twice as long as those of the level before.
    private struct Maxima {
        private var levels: [[CGFloat]]

        init(_ values: [CGFloat]) {
            levels = [values]
            var span = 1
            while span * 2 <= values.count {
                let below = levels[levels.count - 1]
                levels.append((0...values.count - span * 2).map { max(below[$0], below[$0 + span]) })
                span *= 2
            }
        }

        /// The greatest of the values in `range`; of none, minus infinity.
        func callAsFunction(_ range: Range<Int>) -> CGFloat {
            guard !range.isEmpty else { return -.infinity }
            let level = Int.bitWidth - 1 - range.count.leadingZeroBitCount
            return max(levels[level][range.lowerBound], levels[level][range.upperBound - (1 << level)])
        }
    }

    /// The fence a child of a row is, when it is one.
    private static func fence(_ child: BreakableRow.Child) -> BreakPoint? {
        child.box.op.flatMap { $0.has(.fence) ? $0.breakPoint : nil }
    }

    /// Whether `row` is a bracket pair and what it holds, as the row of an `mfenced` is: its first
    /// child opens a fence, and its last closes that one.
    private static func isPair(_ row: BreakableRow) -> Bool {
        guard row.children.count > 1, fence(row.children[0])?.opens == true,
              fence(row.children[row.children.count - 1])?.closes == true else { return false }
        var open = 1
        for child in row.children.dropFirst().dropLast() {
            guard let fence = fence(child) else { continue }
            if fence.closes { open -= 1 }
            // Closed before the end: two pairs side by side, or more.
            guard open > 0 else { return false }
            if fence.opens { open += 1 }
        }
        return open == 1
    }

    /// Rows nested in `row` become its units in turn. `depth` counts what a break there is nested
    /// in: rows, and bracket pairs. A pair is one level however it is written: its fences flat in
    /// a row among other things or in a row of their own, and what they hold in a row or not. It
    /// was counted as each of those it had, so that the sum in `<mfenced><mrow>` was three levels
    /// deep (the row of the fences, the pair, the row between them) where the same sum between
    /// fences written flat was one, and a line broke anywhere outside such a bracket, leaving a
    /// row all but empty, sooner than inside it.
    private mutating func flatten(_ row: BreakableRow, at x: CGFloat, depth: Int, isUnary: Bool, isAttached: Bool,
                                  level: Int, _ breaks: inout [Break]) {
        var fences = 0
        for (index, child) in row.children.enumerated() {
            // What holds a row to its neighbour holds the row's first unit.
            let isAttached = child.isAttached || index == 0 && isAttached
            let fence = Self.fence(child)
            if fence?.closes == true { fences = max(fences - 1, 0) }
            if let id = child.id, ids[id] == nil { ids[id] = units.count }
            if let inner = child.box.row, inner.itemCount == child.box.items.count, !inner.children.isEmpty,
               level < MathLimits.depth {
                // A row that only wraps another, or is one operator, is no deeper than what it holds.
                // Nor is one that is a bracket pair with what it holds, or all that a pair here holds:
                // the pair is the level.
                let isHeld = index > 0 && index + 1 < row.children.count && Self.fence(row.children[index - 1])?.opens == true
                    && Self.fence(row.children[index + 1])?.closes == true
                let deeper = inner.isOperator || row.children.count == 1 || isHeld || Self.isPair(inner) ? 0 : 1
                flatten(inner, at: x + child.x, depth: depth + fences + deeper, isUnary: isUnary || child.isUnary,
                        isAttached: isAttached, level: level + 1, &breaks)
            } else {
                if let point = child.point {
                    breaks.append((units.count, point, depth + fences, isUnary || child.isUnary, row.visible[index]))
                }
                if units.isEmpty { lead = BreakPoint(kind: .none, linebreak: .auto, style: row.style) }
                units.append(Unit(box: child.box, x: x + child.x, ink: child.box.inkBounds, isAttached: isAttached))
            }
            if fence?.opens == true { fences += 1 }
        }
    }

    /// The stops, from the units a line may break at. A forced break (`linebreak="newline"`) is
    /// always one. Any other must be allowed where it falls: at an operator the dictionary ranks
    /// (so not a prefix or postfix one) that is not a sign, not just after an opening fence or
    /// another prefix operator, not just before a closing fence or a postfix operator, and never
    /// beside a function application.
    private mutating func addStops(_ breaks: [Break]) {
        var unary = Set<Int>()
        for item in breaks where item.isUnary { unary.insert(item.unit) }
        for (index, point, depth, isUnary, visible) in breaks where point.linebreak != .nobreak {
            let isForced = point.linebreak == .newline
            let at = point.position == .before ? index : index + 1
            // A break that would leave an empty row, before the first unit or after the last, is none,
            // and nor is one between a base and its script.
            guard at > 0, at < units.count, !units[at].isAttached else { continue }
            if !isForced {
                guard point.linebreak == .goodbreak || (point.kind != .none && point.kind != .glue && !isUnary) else {
                    continue
                }
                if at - 1 != index, let before = units[at - 1].box.op?.breakPoint,
                   before.opens || unary.contains(at - 1) || before.kind == .glue { continue }
                if at != index, let after = units[at].box.op?.breakPoint, after.closes || after.kind == .glue { continue }
            }
            var stop = Stop(at: at, penalty: isForced ? 0 : Self.penalty(point, depth: depth), isForced: isForced,
                            point: point)
            // `linebreakstyle="duplicate"` repeats the operator at the start of the new row, and
            // `linebreakmultchar` shows an invisible times wherever the style puts the operator.
            var head = point.position == .after ? nil : visible ?? (point.position == .duplicate ? units[index].box : nil)
            let tail = point.position == .before ? nil : visible
            if let head {
                stop.headAdvance = visible.map { $0.width + ($0.op?.rspace ?? 0) } ?? units[at].x - units[index].x
                let ink = head.inkBounds
                stop.headLeft = max(0, -(ink?.minX ?? 0)); stop.headInk = ink?.maxX ?? -.infinity
            }
            if let tail {
                let ink = tail.inkBounds
                stop.tailOffset = tail.op?.lspace ?? 0
                stop.tailAdvance = stop.tailOffset + tail.width
                stop.tailRight = max(0, (ink?.maxX ?? 0) - tail.width); stop.tailInk = ink?.minX ?? .infinity
            }
            hasForced = hasForced || isForced
            guard let last = stops.last, last.at == at else {
                if head != nil || tail != nil {
                    stop.insert = inserts.count
                    inserts.append((head, tail))
                }
                stops.append(stop)
                continue
            }
            // An operator that breaks after it and the next that breaks before it share a stop: a line
            // that breaks there breaks at both. The better of the two says what the break costs and
            // how the row after it is placed, and each still adds to the rows what it adds wherever a
            // line breaks at it. `last` is the stop of the operator before the break, which may leave
            // a tail and its duplicate, and `stop` that of the one after, which has only its visible
            // form to show: that goes after the duplicate, next to the operator it stands for.
            var shared = !last.isForced && (isForced || stop.penalty < last.penalty) ? stop : last
            let first = last.insert.map { inserts[$0] }
            shared.tailOffset = last.tailOffset; shared.tailAdvance = last.tailAdvance
            shared.tailRight = last.tailRight; shared.tailInk = last.tailInk
            shared.headAdvance = last.headAdvance + stop.headAdvance
            if let repeated = first?.head, let shown = head {
                var both = MathBox(width: last.headAdvance + shown.width, ascent: max(repeated.ascent, shown.ascent),
                                   descent: max(repeated.descent, shown.descent))
                both.add(repeated, at: .zero)
                both.add(shown, at: CGPoint(x: last.headAdvance, y: 0))
                head = both
            } else {
                head = first?.head ?? head
            }
            let ink = head?.inkBounds
            shared.headLeft = max(0, -(ink?.minX ?? 0)); shared.headInk = ink?.maxX ?? -.infinity
            shared.insert = last.insert
            if let insert = last.insert {
                inserts[insert] = (head, first?.tail)
            } else if head != nil {
                shared.insert = inserts.count
                inserts.append((head, nil))
            }
            stops[stops.count - 1] = shared
        }
    }

    /// What breaking at `point` costs: relations before sums before products, a visible operator
    /// before an invisible one, and more for each level of nesting. Never negative, so that no
    /// break pays for itself and a formula that fits stays whole.
    private static func penalty(_ point: BreakPoint, depth: Int) -> CGFloat {
        var value: CGFloat = switch point.kind {
        case .relation: 0
        case .separator: 10
        case .space: 20
        case .additive: 30
        case .multiplicative: point.isInvisibleTimes ? 70 : 60
        case .none, .glue: 60
        }
        value += nesting * CGFloat(min(depth, 8))
        switch point.linebreak {
        case .goodbreak: value -= 40
        case .badbreak: value += 100
        default: break
        }
        return max(value, 0)
    }

    /// `content` in a box that covers its ink, as every row does so that a host may clip to it,
    /// and how far the ink overhung its left edge.
    private static func covering(_ content: MathBox, ink: CGRect?) -> (box: MathBox, left: CGFloat) {
        let ink = ink ?? .zero
        let left = max(0, -ink.minX)
        var box = MathBox(width: max(0, content.width + left, ink.maxX + left), ascent: max(0, content.ascent, ink.maxY),
                          descent: max(0, content.descent, -ink.minY))
        box.add(content, at: CGPoint(x: left, y: 0))
        return (box, left)
    }

    /// The width of the row between two stops, its box covering its ink, and how far that ink
    /// overhangs its left edge. Constant time, from the unbroken row's ink, and never less than
    /// the row that `row` builds measures: what fits by this fits.
    private func extent(_ i: Int, _ j: Int) -> (width: CGFloat, left: CGFloat) {
        if i == 0, j == stops.count - 1 { return entire }
        let content = stops[i].headAdvance + ends[j] - starts[i] + stops[j].tailAdvance
        // The running extremes take in what the stops add, a duplicate where the operator it repeats
        // was and a tail where the next unit is. Those of the row alone do not.
        let first = stops[i].at, end = stops[j].at
        let from = leftmost.map { min(-$0(first..<end), ends[j] + stops[j].tailOffset + stops[j].tailInk) } ?? inkFrom[first]
        let to = rightmost.map { max($0(first..<end), starts[i] - stops[i].headAdvance + stops[i].headInk) } ?? inkTo[end]
        let left = max(0, starts[i] - from - stops[i].headAdvance, stops[i].headLeft)
        let right = max(0, to - ends[j] - stops[j].tailAdvance, stops[j].tailRight)
        return (max(0, left + content + right), left)
    }

    /// The widest stretch between two stops: the narrowest line on which no row overflows.
    var widest: CGFloat { (0..<stops.count - 1).reduce(0) { max($0, extent($1, $1 + 1).width) } }

    /// The row between two stops: its units where the unbroken row had them, less what came before.
    private func row(_ i: Int, _ j: Int, fences: Set<Int> = []) -> (box: MathBox, left: CGFloat, shifts: [Int: CGFloat]) {
        if i == 0, j == stops.count - 1 { return (unbroken, entire.left, [:]) }
        let shift = stops[i].headAdvance - starts[i]
        var box = MathBox(width: stops[i].headAdvance + ends[j] - starts[i] + stops[j].tailAdvance)
        var ink: CGRect?
        var isFirst = true
        let first = stops[i].at, end = stops[j].at
        let head = stops[i].insert.flatMap { inserts[$0].head }
        let tail = stops[j].insert.flatMap { inserts[$0].tail }
        var ascent = -CGFloat.infinity, descent = -CGFloat.infinity
        // Like the inferred row's original stretch pass, fences do not set the target size.
        // In particular a stationary outer fence spanning lines must not keep a whole inner
        // pair on this line at the height of content that is now on another line.
        for index in first..<end where units[index].box.fenceLayout == nil {
            ascent = max(ascent, units[index].box.ascent)
            descent = max(descent, units[index].box.descent)
        }
        for insert in [head, tail].compactMap({ $0 }) {
            ascent = max(ascent, insert.ascent); descent = max(descent, insert.descent)
        }
        if ascent == -.infinity { ascent = 0 }
        if descent == -.infinity { descent = 0 }
        var delta: CGFloat = 0
        var shifts: [Int: CGFloat] = [:]
        func add(_ child: MathBox, _ childInk: CGRect?, at x: CGFloat) {
            box.add(child, at: CGPoint(x: x, y: 0))
            box.ascent = isFirst ? child.ascent : max(box.ascent, child.ascent)
            box.descent = isFirst ? child.descent : max(box.descent, child.descent)
            isFirst = false
            guard let placed = childInk?.offsetBy(dx: x, dy: 0) else { return }
            ink = ink.map { $0.union(placed) } ?? placed
        }
        if let head { add(head, head.inkBounds, at: 0) }
        for index in first..<end {
            let unit = units[index]
            shifts[index] = delta
            var child = unit.box
            var childInk = unit.ink
            if fences.contains(index), let resized = child.fenceLayout?.box(ascent: ascent, descent: descent),
               resized.width <= child.width, resized.height <= child.height,
               [resized.width, resized.ascent, resized.descent].allSatisfy({ $0.isFinite && abs($0) <= MathLimits.extent }) {
                child = resized
                childInk = resized.inkBounds
            }
            add(child, childInk, at: unit.x + shift + delta)
            delta += child.width - unit.box.width
        }
        if let tail { add(tail, tail.inkBounds, at: ends[j] + shift + delta + stops[j].tailOffset) }
        box.width += delta
        let covered = Self.covering(box, ink: ink)
        // Negative spacing or unusual variants may widen the ink despite smaller advances. The
        // chosen rows must still fit the widths used to choose them; keep the original in that case.
        if !fences.isEmpty, covered.box.width > extent(i, j).width + Self.slop {
            return row(i, j)
        }
        return (covered.box, covered.left, shifts)
    }

    /// Breaks the row into rows no wider than `limit`, the first no wider than `first`, and
    /// places each by the indentation attributes of the stop before it.
    ///
    /// The breaks are those of least total cost (see `emptiness`): every forced break, and
    /// between them the cheapest stops that leave no row too wide. A row is too wide only when it
    /// is a single stretch between two stops that is wider than the line; it then gives up its
    /// indentation and overflows. `auto` is what `indentalign="auto"` means here: the alignment,
    /// and the indentation of rows after the first. `tight` aligns centred and right-aligned
    /// rows within the widest row rather than the line, as an infinite line does.
    func rows(limit: CGFloat, first: CGFloat, auto: (align: IndentAlign, indent: CGFloat), tight: Bool = false) -> [Row] {
        let last = stops.count - 1
        var best = [CGFloat](repeating: .infinity, count: stops.count)
        var previous = [Int](repeating: 0, count: stops.count)
        // Of the row that ends at each stop on the best way there: its left edge and ink overhang.
        var origins = [CGFloat](repeating: 0, count: stops.count)
        var lefts = origins
        var targets = [CGFloat?](repeating: nil, count: stops.count)
        var unitShifts: [Int: CGFloat] = [:]

        /// Where the element an `indenttarget` names has its left edge, when it is on a row above
        /// the one that starts at stop `i`. The rows above are those of the best way to `i`, which
        /// is settled by the time rows from `i` are tried.
        func target(_ i: Int, _ id: String?) -> CGFloat? {
            guard let id, let unit = ids[id], unit < stops[i].at else { return nil }
            if let known = targets[i] { return known }
            var end = i
            var steps = 0
            while stops[previous[end]].at > unit {
                end = previous[end]
                // A row above that aligned with the same element has found it already.
                if stops[end].point.style.target == id, let known = targets[end] { targets[i] = known; return known }
                steps += 1
                guard steps < Self.window else { return nil }
            }
            let start = previous[end]
            let edge = origins[end] + lefts[end] + stops[start].headAdvance + units[unit].x - starts[start]
                + (unitShifts[unit] ?? 0)
            targets[i] = edge
            return edge
        }

        /// Where the row from stop `i` to `j` goes (MathML 3, 3.2.5.2.3): its left edge, how much of
        /// the line its indentation takes, and the alignment still to apply once the rows are known.
        func place(_ i: Int, _ j: Int, _ size: (width: CGFloat, left: CGFloat), room: CGFloat)
            -> (x: CGFloat, indent: CGFloat, align: IndentAlign) {
            // A row is placed by the attributes of the stop it starts at: those on an operator "control
            // linebreaking and indentation of the following line" (MathML 3, 3.1.7.1), so an `indentshift`
            // there is for the row after the break and no other. Whose attributes place the first row
            // the specification does not say, only that `indentalignfirst` and `indentshiftfirst` place
            // a formula of one line too: here it has those the formula starts with, unless the stop it
            // ends at gives the first row its own.
            let from = stops[i].point, to = stops[j].point
            var align = from.style.align, shift = from.style.shift
            if i == 0 {
                align = to.style.alignFirst ?? from.style.alignFirst ?? align
                shift = to.style.shiftFirst ?? from.style.shiftFirst ?? shift
            } else if j == last {
                align = from.style.alignLast ?? align; shift = from.style.shiftLast ?? shift
            }
            var x = shift?.resolve(room) ?? 0
            if align == .id {
                // An element that is not on a row above makes this `auto` (MathML 3, 3.2.5.2.3).
                if let edge = target(i, from.style.target) { x += edge - size.left; align = .left } else { align = .auto }
            }
            if align == .auto {
                if shift == nil, i > 0 { x = auto.indent }
                align = auto.align
            }
            guard align == .center || align == .right else { return (max(0, x), max(0, x), .left) }
            // What a shift takes from the line: all of it on the right, and as much again on the left
            // of a centred row.
            let indent = align == .center ? 2 * abs(x) : max(0, -x)
            guard room.isFinite, !tight else { return (x, indent, align) }
            x += align == .center ? (room - size.width) / 2 : room - size.width
            return (max(0, min(x, room - size.width)), indent, .left)
        }

        /// Tries the row from stop `i` to `j` as the way to `j`; false when it does not fit.
        func reach(_ j: Int, from i: Int) -> Bool {
            let room = i == 0 ? first : limit
            let size = extent(i, j)
            var (x, indent, _) = place(i, j, size, room: room)
            if indent + size.width > room + Self.slop {
                // Only a stretch that cannot break may be too wide. It gives up its indentation first:
                // a renderer may when the line is too narrow for it (MathML 3, 3.2.5.2.3).
                guard j == i + 1 else { return false }
                indent = max(0, min(indent, room - size.width)); x = max(0, min(x, room - size.width))
            }
            var cost = best[i] + Self.rowCost
            let over = indent + size.width - room
            if over > Self.slop {
                cost += Self.overflow + over
            } else if j != last, !stops[j].isForced {
                // The last row, and one the author ended, may be as short as it is.
                cost += stops[j].penalty
                if room.isFinite, room > 0 {
                    let unused = max(0, room - indent - size.width) / room
                    cost += Self.emptiness * unused * unused
                }
            }
            if cost < best[j] {
                best[j] = cost; previous[j] = i; origins[j] = x; lefts[j] = size.left
            }
            return true
        }

        best[0] = 0
        let whole = place(0, last, entire, room: first)
        if !hasForced, whole.indent + entire.width <= first + Self.slop {
            // Everything fits and nothing is forced: no search.
            origins[last] = whole.x
        } else {
            // The next forced break after each stop: no row runs past it.
            var forced = [Int](repeating: last, count: stops.count)
            for index in stride(from: last - 1, through: 0, by: -1) {
                forced[index] = stops[index + 1].isForced ? index + 1 : forced[index + 1]
            }
            // Stops in order: the best way to each is known before rows from it are tried.
            for i in 0..<last where best[i].isFinite {
                // The farthest stop the row from here can reach, its tail aside: the last before
                // its advance or ink has run past the line. Both extremes persist as the row grows,
                // wherever a negative space after that brings its end back to. Ignoring ink here
                // could put every candidate in the window beyond a leftward excursion, skipping
                // the rows that fit before it and falling back to single stretches.
                let room = i == 0 ? first : limit
                var low = i, high = forced[i]
                while low < high {
                    let middle = (low + high + 1) / 2
                    let end = farthest.map { $0(i + 1..<middle + 1) } ?? ends[middle]
                    let firstUnit = stops[i].at, endUnit = stops[middle].at
                    let from = leftmost.map { -$0(firstUnit..<endUnit) } ?? inkFrom[firstUnit]
                    let to = rightmost.map { $0(firstUnit..<endUnit) } ?? inkTo[endUnit]
                    let left = max(0, starts[i] - from - stops[i].headAdvance, stops[i].headLeft)
                    let right = max(end, to, starts[i] - stops[i].headAdvance + stops[i].headInk)
                    let fits = stops[i].headAdvance + right - starts[i] + left <= room + Self.slop
                    if fits { low = middle } else { high = middle - 1 }
                }
                var reached = false
                for j in stride(from: low, to: max(i, low - Self.window), by: -1) where reach(j, from: i) { reached = true }
                // Nothing fits: the row holds one stretch and overflows.
                if !reached { _ = reach(i + 1, from: i) }
            }
        }
        var ending = [last]
        while let end = ending.last, end != 0, ending.count <= stops.count { ending.append(previous[end]) }
        ending.reverse()
        // Once the breaks are settled, visit each pair once. A pair crossing a selected boundary
        // keeps both original fences, including its embellishments.
        var fences = Set<Int>()
        var output = [Int](repeating: 0, count: units.count)
        for (index, boundary) in zip(ending, ending.dropFirst()).enumerated() {
            for unit in stops[boundary.0].at..<stops[boundary.1].at { output[unit] = index }
        }
        for pair in pairs where output[pair.open] == output[pair.close] {
            if units[pair.open].box.fenceLayout != nil { fences.insert(pair.open) }
            if units[pair.close].box.fenceLayout != nil { fences.insert(pair.close) }
        }
        targets = [CGFloat?](repeating: nil, count: stops.count)
        var rows: [Row] = []
        var pending: [IndentAlign] = []
        for (i, j) in zip(ending, ending.dropFirst()) {
            let built = row(i, j, fences: fences)
            for (unit, delta) in built.shifts { unitShifts[unit] = delta }
            var placement = place(i, j, (built.box.width, built.left), room: i == 0 ? first : limit)
            let room = i == 0 ? first : limit
            if placement.indent + built.box.width > room + Self.slop {
                placement.x = max(0, min(placement.x, room - built.box.width))
            }
            origins[j] = placement.x; lefts[j] = built.left
            rows.append(Row(box: built.box, x: placement.x, leading: stops[j].point.style.leading))
            pending.append(placement.align)
        }
        // Centred and right-aligned rows with no line to align within: within the widest row.
        if pending.contains(where: { $0 != .left }) {
            let frame = zip(rows, pending).reduce(0) { max($0, ($1.1 == .left ? $1.0.x : 0) + $1.0.box.width) }
            for index in rows.indices where pending[index] != .left {
                let free = frame - rows[index].box.width
                rows[index].x = max(0, min(rows[index].x + (pending[index] == .center ? free / 2 : free), free))
            }
        }
        return rows
    }
}
