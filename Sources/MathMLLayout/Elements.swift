import CoreGraphics
import CoreText
import Foundation

/// Layout of the structural elements: fractions, radicals, scripts, limits, padding,
/// enclosures, tables and errors. Rules follow MathML Core 3.3–3.6 with OpenType MATH constants.
extension LayoutEngine {
    // MARK: Fractions

    func fraction(_ node: MathMLNode, _ context: LayoutContext, _ embellishment: Embellishment,
                  depth: Int) throws -> MathBox {
        try arity(node, 2)
        let inner = scriptContext(context, levels: context.display ? 0 : 1)
        let numerator = try layout(node.children[0], inner, embellishment, depth: depth + 1)
        let denominator = try layout(node.children[1], inner.with(cramped: true), depth: depth + 1)
        return assembleFraction(node, context, numerator: numerator, denominator: denominator)
    }

    @inline(never)
    private func assembleFraction(_ node: MathMLNode, _ context: LayoutContext,
                                  numerator: MathBox, denominator: MathBox) -> MathBox {
        var numerator = numerator, denominator = denominator
        let standard = value(\.fractionRuleThickness, context)
        let thickness: CGFloat = switch node.attributes["linethickness"]?.trimmingCharacters(in: .whitespaces).lowercased() {
        case nil: standard
        case "thin": standard / 2
        case "medium": standard
        case "thick": standard * 2
        case let attribute?: min(max(length(attribute, context, reference: standard) ?? standard, 0), context.fontSize)
        }
        if node.attributes.flag("bevelled") == true {
            return bevelled(numerator, denominator, context)
        }
        // A little room each side, like TeX's null delimiters, so adjacent bars stay apart.
        let pad = context.fontSize * 0.08
        // A fraction too wide for the line stacks each part in lines.
        numerator = wrapped(numerator, beside: 2 * pad) ?? numerator
        denominator = wrapped(denominator, beside: 2 * pad) ?? denominator
        let display = context.display
        let axis = value(\.axisHeight, context)
        var numeratorShift: CGFloat, denominatorShift: CGFloat
        if thickness > 0 {
            let numeratorGap = display ? value(\.fractionNumDisplayStyleGapMin, context) : value(\.fractionNumeratorGapMin, context)
            let denominatorGap = display ? value(\.fractionDenomDisplayStyleGapMin, context) : value(\.fractionDenominatorGapMin, context)
            numeratorShift = max(display ? value(\.fractionNumeratorDisplayStyleShiftUp, context) : value(\.fractionNumeratorShiftUp, context),
                                 axis + thickness / 2 + numeratorGap + numerator.descent)
            denominatorShift = max(display ? value(\.fractionDenominatorDisplayStyleShiftDown, context)
                                       : value(\.fractionDenominatorShiftDown, context),
                                   denominator.ascent + denominatorGap - axis + thickness / 2)
        } else {
            numeratorShift = display ? value(\.stackTopDisplayStyleShiftUp, context) : value(\.stackTopShiftUp, context)
            denominatorShift = display ? value(\.stackBottomDisplayStyleShiftDown, context) : value(\.stackBottomShiftDown, context)
            let minimum = display ? value(\.stackDisplayStyleGapMin, context) : value(\.stackGapMin, context)
            let gap = (numeratorShift - numerator.descent) - (denominator.ascent - denominatorShift)
            if gap < minimum {
                numeratorShift += (minimum - gap) / 2
                denominatorShift += (minimum - gap) / 2
            }
        }
        let width = max(numerator.width, denominator.width)
        func offset(_ part: MathBox, _ attribute: String) -> CGFloat {
            switch node.attributes[attribute]?.trimmingCharacters(in: .whitespaces).lowercased() {
            case "left": 0
            case "right": width - part.width
            default: (width - part.width) / 2
            }
        }
        var box = MathBox(width: width + 2 * pad)
        if thickness > 0 {
            box.items.append(.rect(CGRect(x: pad, y: axis - thickness / 2, width: width, height: thickness), context.color))
        }
        box.add(numerator, at: CGPoint(x: pad + offset(numerator, "numalign"), y: numeratorShift))
        box.add(denominator, at: CGPoint(x: pad + offset(denominator, "denomalign"), y: -denominatorShift))
        box.ascent = max(numeratorShift + numerator.ascent, thickness > 0 ? axis + thickness / 2 : 0)
        box.descent = max(denominatorShift + denominator.descent, thickness > 0 ? thickness / 2 - axis : 0)
        box.op = numerator.op
        return box
    }

    /// `bevelled="true"`: numerator raised, denominator lowered, either side of a slash.
    private func bevelled(_ numerator: MathBox, _ denominator: MathBox, _ context: LayoutContext) -> MathBox {
        let axis = value(\.axisHeight, context)
        let horizontalGap = value(\.skewedFractionHorizontalGap, context)
        let verticalGap = value(\.skewedFractionVerticalGap, context)
        let numeratorShift = axis + verticalGap / 2 + max(numerator.descent, 0)
        let denominatorShift = max(denominator.ascent, 0) - axis + verticalGap / 2
        var slash = textBox("/", context)
        let height = numeratorShift + numerator.ascent + denominatorShift + denominator.descent
        if let glyph = singleGlyph(slash), let stretched = stretchedGlyph(glyph, vertical: true, size: height, context) {
            slash = stretched
        }
        slash = centered(slash, on: (numeratorShift + numerator.ascent - denominatorShift - denominator.descent) / 2)
        var box = MathBox()
        box.add(numerator, at: CGPoint(x: 0, y: numeratorShift))
        let slashX = numerator.width + horizontalGap / 2 - slash.width / 2
        box.add(slash, at: CGPoint(x: slashX, y: 0))
        let denominatorX = max(numerator.width + horizontalGap, slashX + slash.width)
        box.add(denominator, at: CGPoint(x: denominatorX, y: -denominatorShift))
        box.width = denominatorX + denominator.width
        box.ascent = max(numeratorShift + numerator.ascent, slash.ascent)
        box.descent = max(denominatorShift + denominator.descent, slash.descent)
        return box
    }

    // MARK: Radicals

    /// `msqrt` and `mroot`: the radical sign stretched to cover the base and the gap above it,
    /// with the overbar joining its top (MathML Core 3.3.3).
    func radical(base: MathBox, index: MathBox?, _ context: LayoutContext, wraps: Bool = true) -> MathBox {
        let thickness = value(\.radicalRuleThickness, context)
        let gap = context.display ? value(\.radicalDisplayStyleVerticalGap, context) : value(\.radicalVerticalGap, context)
        let target = base.ascent + base.descent + gap + thickness
        var sign: MathBox
        let natural = textBox("√", context)
        if let glyph = singleGlyph(natural), font.table != nil {
            sign = stretchedGlyph(glyph, vertical: true, size: target, context) ?? glyphBox(glyph, context)
        } else {
            sign = drawnDelimiter("√", height: target, context) ?? natural
        }
        // Extra height in the sign is shared between the gap and the depth below the base.
        let clearance = gap + max(0, sign.height - target) / 2
        let top = base.ascent + clearance + thickness
        let signShift = top - sign.ascent
        var x: CGFloat = 0
        var box = MathBox()
        var ascent = top + value(\.radicalExtraAscender, context)
        var descent = max(base.descent, sign.descent - signShift)
        if let index {
            let before = value(\.radicalKernBeforeDegree, context), after = value(\.radicalKernAfterDegree, context)
            let raise = constants.radicalDegreeBottomRaisePercent / 100
            let indexShift = signShift - sign.descent + raise * sign.height + index.descent
            x = max(before + index.width + after, 0)
            box.add(index, at: CGPoint(x: max(x - after - index.width, 0), y: indexShift))
            ascent = max(ascent, indexShift + index.ascent)
            descent = max(descent, index.descent - indexShift)
        }
        box.add(sign, at: CGPoint(x: x, y: signShift))
        x += sign.width
        box.items.append(.rect(CGRect(x: x, y: top - thickness, width: base.width, height: thickness), context.color))
        box.add(base, at: CGPoint(x: x, y: 0))
        box.width = x + base.width
        box.ascent = ascent
        box.descent = descent
        // A radicand too wide for the line stacks in lines under the one bar, beside the sign as wide
        // as it was: taller, it may be wider.
        if wraps, let stacked = wrapped(base, beside: x, align: .left) {
            return radical(base: stacked, index: index, context, wraps: false)
        }
        return box
    }

    // MARK: Scripts

    /// `msub`, `msup`, `msubsup` and `mmultiscripts`.
    func scripts(_ node: MathMLNode, _ context: LayoutContext, _ embellishment: Embellishment,
                 depth: Int) throws -> MathBox {
        let children = node.children
        switch node.name {
        case "msub", "msup": try arity(node, 2)
        case "msubsup": try arity(node, 3)
        default: guard !children.isEmpty else { throw MathLayoutError.invalidMarkup(node.name) }
        }
        // Script placement remains LTR in the staged RTL implementation. Keep the
        // base's inherited row progression consistent with that schema, while retaining
        // its token bidi direction. Explicit row direction overrides still apply.
        var baseContext = context
        baseContext.alignmentRTL = false
        let base = try layout(children[0], baseContext, embellishment, depth: depth + 1)
        let pairs = try scriptPairs(node, context, depth: depth)
        return attachScripts(base, post: pairs.post, pre: pairs.pre, context)
    }

    @inline(never)
    private func scriptPairs(_ node: MathMLNode, _ context: LayoutContext, depth: Int) throws
        -> (post: [(MathBox?, MathBox?)], pre: [(MathBox?, MathBox?)]) {
        if node.name == "mmultiscripts" { return try multiscriptPairs(node, context, depth: depth) }
        func script(_ child: MathMLNode, lower: Bool) throws -> MathBox? {
            guard child.name != "none" else { try countNodes(); return nil }
            let inner = scriptContext(context, cramped: lower ? true : nil)
            return try layout(child, inner, depth: depth + 1)
        }
        let sub: MathBox? = try node.name == "msup" ? nil : script(node.children[1], lower: true)
        let sup: MathBox? = try node.name == "msub" ? nil : script(node.children[node.name == "msup" ? 1 : 2], lower: false)
        return ([(sub, sup)], [])
    }

    @inline(never)
    private func multiscriptPairs(_ node: MathMLNode, _ context: LayoutContext, depth: Int) throws
        -> (post: [(MathBox?, MathBox?)], pre: [(MathBox?, MathBox?)]) {
        let children = node.children
        let subscriptContext = scriptContext(context, cramped: true), superscriptContext = scriptContext(context)
        func script(_ child: MathMLNode, lower: Bool) throws -> MathBox? {
            guard child.name != "none" else { try countNodes(); return nil }
            return try layout(child, lower ? subscriptContext : superscriptContext, depth: depth + 1)
        }
        var post: [(MathBox?, MathBox?)] = [], pre: [(MathBox?, MathBox?)] = []
        var isPre = false
        var pending: [MathMLNode] = []
        for child in children.dropFirst() {
            if child.name == "mprescripts" {
                // The marker and any incomplete pair it discards have been visited even
                // though none of them gets a box.
                try countNodes(1 + pending.count)
                isPre = true; pending = []; continue
            }
            pending.append(child)
            if pending.count == 2 {
                let pair = try (script(pending[0], lower: true), script(pending[1], lower: false))
                if isPre { pre.append(pair) } else { post.append(pair) }
                pending = []
            }
        }
        if !pending.isEmpty { throw MathLayoutError.invalidMarkup(node.name) }
        return (post, pre)
    }

    /// Places sub- and superscript pairs after (and before) a base. Shifts follow MathML Core
    /// 3.4.3, which is TeX's rule 18 in OpenType terms. A base's width includes its italic
    /// correction, so subscripts tuck under by that much and superscripts do not. Single-glyph
    /// pairs additionally use the font's height-dependent OpenType MATH corner kerning.
    func attachScripts(_ base: MathBox, post: [(MathBox?, MathBox?)], pre: [(MathBox?, MathBox?)],
                       _ context: LayoutContext) -> MathBox {
        let pairs = post + pre
        let subscripts = pairs.compactMap(\.0), superscripts = pairs.compactMap(\.1)
        var subShift: CGFloat = 0, superShift: CGFloat = 0
        if !subscripts.isEmpty {
            subShift = max(value(\.subscriptShiftDown, context), base.descent + value(\.subscriptBaselineDropMin, context),
                           subscripts.map { $0.ascent - value(\.subscriptTopMax, context) }.max()!)
        }
        if !superscripts.isEmpty {
            superShift = max(context.cramped ? value(\.superscriptShiftUpCramped, context) : value(\.superscriptShiftUp, context),
                             base.ascent - value(\.superscriptBaselineDropMax, context),
                             superscripts.map { $0.descent + value(\.superscriptBottomMin, context) }.max()!)
        }
        let minimumGap = value(\.subSuperscriptGapMin, context)
        for case (let sub?, let sup?) in pairs {
            let gap = (superShift - sup.descent) - (sub.ascent - subShift)
            guard gap < minimumGap else { continue }
            subShift += minimumGap - gap
            let lift = value(\.superscriptBottomMaxWithSubscript, context) - (superShift - sup.descent)
            if lift > 0 { superShift += lift; subShift -= lift }
        }
        let space = value(\.spaceAfterScript, context)
        var box = MathBox()
        var x: CGFloat = 0
        var ascent = base.ascent, descent = base.descent
        // A base that is a row may break across lines, as in a long bracketed sum squared. Its
        // scripts are then kept apart too, each raised or lowered as here and held to its neighbour,
        // so the exponent stays on the closing bracket wherever that lands.
        let breaks = base.row != nil && base.op == nil
        var parts: [BreakableRow.Child] = []
        func keep(_ part: MathBox, at point: CGPoint) {
            guard breaks else { return }
            var part = shifted(part, by: point.y)
            part.op = nil
            parts.append(BreakableRow.Child(box: part, x: point.x, isAttached: !parts.isEmpty))
        }
        func place(_ sub: MathBox?, _ sup: MathBox?, subX: CGFloat, supX: CGFloat) {
            if let sub {
                box.add(sub, at: CGPoint(x: subX, y: -subShift))
                keep(sub, at: CGPoint(x: subX, y: -subShift))
                descent = max(descent, subShift + sub.descent); ascent = max(ascent, sub.ascent - subShift)
            }
            if let sup {
                box.add(sup, at: CGPoint(x: supX, y: superShift))
                keep(sup, at: CGPoint(x: supX, y: superShift))
                ascent = max(ascent, superShift + sup.ascent); descent = max(descent, sup.descent - superShift)
            }
        }
        for (index, (sub, sup)) in pre.enumerated() {
            let adjacent = index == pre.count - 1
            let subKern = adjacent ? sub.map { scriptKern(base, $0, shift: -subShift, upper: false, before: true) } ?? 0 : 0
            let supKern = adjacent ? sup.map { scriptKern(base, $0, shift: superShift, upper: true, before: true) } ?? 0 : 0
            let width = max(0, (sub?.width ?? 0) + subKern, (sup?.width ?? 0) + supKern)
            place(sub, sup, subX: x + width - (sub?.width ?? 0) - subKern,
                  supX: x + width - (sup?.width ?? 0) - supKern)
            x += width + space
        }
        box.add(base, at: CGPoint(x: x, y: 0))
        if breaks { parts.append(BreakableRow.Child(box: base, x: x, isAttached: !parts.isEmpty)) }
        x += base.width
        for (index, (sub, sup)) in post.enumerated() {
            let subKern = index == 0 ? sub.map { scriptKern(base, $0, shift: -subShift, upper: false, before: false) } ?? 0 : 0
            let supKern = index == 0 ? sup.map { scriptKern(base, $0, shift: superShift, upper: true, before: false) } ?? 0 : 0
            let subX = x - (index == 0 ? base.italicCorrection : 0) + subKern
            let supX = x + supKern
            place(sub, sup, subX: subX, supX: supX)
            x = max(x, subX + (sub?.width ?? 0), supX + (sup?.width ?? 0)) + space
        }
        box.width = x
        box.ascent = ascent
        box.descent = descent
        box.op = base.op
        if breaks { box.row = BreakableRow(children: parts, itemCount: box.items.count, width: box.width, rtl: false, context) }
        return box
    }

    /// Opposite corners are sampled at the script's touching ink edge and the base's ink edge.
    /// Only an unmodified, single glyph of this math font supplies a corner. Compound boxes
    /// and positioned/assembled glyphs retain the existing zero-kern placement.
    func scriptKern(_ base: MathBox, _ script: MathBox, shift: CGFloat, upper: Bool, before: Bool) -> CGFloat {
        guard let table = font.table,
              let baseGlyph = singleGlyph(base), let scriptGlyph = singleGlyph(script),
              case .glyphs(let baseRun) = base.items[0], case .glyphs(let scriptRun) = script.items[0],
              baseRun.positions == [.zero], scriptRun.positions == [.zero],
              !baseRun.ink.isNull, !scriptRun.ink.isNull else { return 0 }
        let baseSize = CTFontGetSize(baseRun.font), scriptSize = CTFontGetSize(scriptRun.font)
        guard baseSize > 0, scriptSize > 0 else { return 0 }
        let baseCorner: MathKernCorner = upper ? (before ? .topLeft : .topRight) : (before ? .bottomLeft : .bottomRight)
        let scriptCorner: MathKernCorner = upper ? (before ? .bottomRight : .bottomLeft) : (before ? .topRight : .topLeft)
        let scriptEdge = upper ? scriptRun.ink.minY : scriptRun.ink.maxY
        let baseEdge = upper ? baseRun.ink.maxY : baseRun.ink.minY
        func sum(at height: CGFloat) -> CGFloat {
            font.points(table.kern(baseGlyph, corner: baseCorner, height: height * font.unitsPerEm / baseSize), size: baseSize)
                + font.points(table.kern(scriptGlyph, corner: scriptCorner, height: (height - shift) * font.unitsPerEm / scriptSize), size: scriptSize)
        }
        return min(sum(at: shift + scriptEdge), sum(at: baseEdge))
    }

    // MARK: Under and over

    /// `munder`, `mover` and `munderover`: limits on large operators in display style (as
    /// scripts in text style when `movablelimits`), accents, and stretchy arrows and braces
    /// sized to the widest child (MathML Core 3.4.4).
    ///
    /// A script's distance from its base is picked by the base, in Core's order (3.4.2.3 to
    /// 3.4.2.5): the limit constants for a large operator, the StretchStack constants for an
    /// operator that stretches horizontally (a labelled arrow), and otherwise the accent rule
    /// or the over- and underbar gaps. Two readings differ from Core's text, both settled in
    /// https://github.com/w3c/mathml-core/issues/121:
    /// - The StretchStack shifts are from the base's baseline, as OpenType means them, not from
    ///   its ink: STIX Two Math's `stretchStackTopShiftUp` is 0.8em, well above an arrow.
    /// - `stretchStackGapAboveMin` is the gap to the script above the stretched operator and
    ///   `stretchStackGapBelowMin` to the one below, as OpenType defines them. Core swaps them.
    ///
    /// The same definitions give a script that is itself the stretched operator (a brace or an
    /// arrow over an expression) the gap towards its base. Core has no such case.
    func underOver(_ node: MathMLNode, _ context: LayoutContext, _ embellishment: Embellishment,
                   depth: Int) throws -> MathBox {
        let plan = try underOverPlan(node, context, embellishment)
        if plan.coreFlags.contains(.movablelimits), !context.display {
            return try movableLimits(plan.nodes[0]!, under: plan.nodes[1], over: plan.nodes[2],
                                     context, embellishment, depth: depth)
        }
        // Preparation returned before recursion, leaving only the heap plan and child boxes.
        let nodes = plan.nodes, contexts = plan.contexts, stretchy = plan.stretchy
        var boxes: [MathBox?] = [nil, nil, nil]
        for index in 0..<3 where !stretchy[index] {
            guard let child = nodes[index] else { continue }
            boxes[index] = try layout(child, contexts[index], index == 0 ? embellishment : .none, depth: depth + 1)
        }
        let widest = boxes.compactMap { $0?.width }.max()
        for index in 0..<3 where stretchy[index] {
            guard let child = nodes[index] else { continue }
            var stretch = Embellishment(form: index == 0 ? embellishment.form : nil)
            stretch.stretch = widest.map { .horizontal(width: $0) } ?? (index == 0 ? embellishment.stretch : nil)
            boxes[index] = try layout(child, contexts[index], stretch, depth: depth + 1)
        }
        return assembleUnderOver(boxes, context, coreFlags: plan.coreFlags, stretchy: stretchy,
                                 accent: plan.accent, accentUnder: plan.accentUnder)
    }

    private final class UnderOverPlan {
        let nodes: [MathMLNode?]
        let contexts: [LayoutContext]
        let stretchy: [Bool]
        let coreFlags: OperatorFlags
        let accent: Bool
        let accentUnder: Bool
        init(nodes: [MathMLNode?], contexts: [LayoutContext], stretchy: [Bool], coreFlags: OperatorFlags,
             accent: Bool, accentUnder: Bool) {
            self.nodes = nodes; self.contexts = contexts; self.stretchy = stretchy; self.coreFlags = coreFlags
            self.accent = accent; self.accentUnder = accentUnder
        }
    }

    @inline(never)
    private func underOverPlan(_ node: MathMLNode, _ context: LayoutContext, _ embellishment: Embellishment) throws -> UnderOverPlan {
        try arity(node, node.name == "munderover" ? 3 : 2)
        let children = node.children
        let baseNode = children[0]
        let underNode = node.name == "mover" ? nil : children[1]
        let overNode = node.name == "munder" ? nil : children[node.name == "mover" ? 1 : 2]
        let coreFlags = embellishedCore(baseNode).map { operatorFlags($0, form: embellishment.form) } ?? []
        func isAccent(_ script: MathMLNode?, _ attribute: String) -> Bool {
            guard let script else { return false }
            return node.attributes.flag(attribute)
                ?? embellishedCore(script).map { operatorFlags($0, form: nil).contains(.accent) } ?? false
        }
        let accent = isAccent(overNode, "accent"), accentUnder = isAccent(underNode, "accentunder")
        let baseContext = accent ? context.with(cramped: true) : context
        let overContext = scriptContext(context, levels: accent ? 0 : 1)
        let underContext = scriptContext(context, levels: accentUnder ? 0 : 1, cramped: true)

        let nodes: [MathMLNode?] = [baseNode, underNode, overNode]
        return UnderOverPlan(nodes: nodes, contexts: [baseContext, underContext, overContext],
                             stretchy: nodes.map { $0.map(isHorizontallyStretchy) ?? false }, coreFlags: coreFlags,
                             accent: accent, accentUnder: accentUnder)
    }

    @inline(never)
    private func movableLimits(_ baseNode: MathMLNode, under underNode: MathMLNode?, over overNode: MathMLNode?,
                               _ context: LayoutContext, _ embellishment: Embellishment, depth: Int) throws -> MathBox {
        let base = try layout(baseNode, context, embellishment, depth: depth + 1)
        let sub = try underNode.map { try layout($0, scriptContext(context, cramped: true), depth: depth + 1) }
        let sup = try overNode.map { try layout($0, scriptContext(context), depth: depth + 1) }
        return attachScripts(base, post: [(sub, sup)], pre: [], context)
    }

    @inline(never)
    private func assembleUnderOver(_ boxes: [MathBox?], _ context: LayoutContext,
                                   coreFlags: OperatorFlags, stretchy: [Bool], accent: Bool, accentUnder: Bool) -> MathBox {
        let base = boxes[0]!
        let isLimits = coreFlags.contains(.largeop)
        let isStretchStack = !isLimits && stretchy[0]
        let rule = value(\.fractionRuleThickness, context)
        var ascent = base.ascent, descent = base.descent
        var overY: CGFloat = 0, underY: CGFloat = 0
        if let over = boxes[2] {
            if isLimits {
                overY = base.ascent + max(value(\.upperLimitBaselineRiseMin, context), value(\.upperLimitGapMin, context) + over.descent)
            } else if isStretchStack {
                overY = max(value(\.stretchStackTopShiftUp, context),
                            base.ascent + value(\.stretchStackGapAboveMin, context) + over.descent)
            } else if accent {
                overY = max(0, base.ascent - value(\.accentBaseHeight, context), base.ascent + rule + over.descent)
            } else {
                let gap = stretchy[2] ? value(\.stretchStackGapBelowMin, context) : value(\.overbarVerticalGap, context)
                overY = base.ascent + gap + over.descent
            }
            ascent = max(ascent, overY + over.ascent + (accent || isLimits || isStretchStack ? 0 : value(\.overbarExtraAscender, context)))
            descent = max(descent, over.descent - overY)
        }
        if let under = boxes[1] {
            if isLimits {
                underY = -(base.descent + max(value(\.lowerLimitBaselineDropMin, context), value(\.lowerLimitGapMin, context) + under.ascent))
            } else if isStretchStack {
                underY = -max(value(\.stretchStackBottomShiftDown, context),
                              base.descent + value(\.stretchStackGapBelowMin, context) + under.ascent)
            } else if accentUnder {
                underY = min(0, -(base.descent + rule / 2 + under.ascent))
            } else {
                let gap = stretchy[1] ? value(\.stretchStackGapAboveMin, context) : value(\.underbarVerticalGap, context)
                underY = -(base.descent + gap + under.ascent)
            }
            descent = max(descent, under.descent - underY + (accentUnder || isLimits || isStretchStack ? 0 : value(\.underbarExtraDescender, context)))
            ascent = max(ascent, under.ascent + underY)
        }
        // Centre everything; limits of a slanted integral lean with it, and an accent sits on
        // the base glyph's accent attachment point.
        let width = boxes.compactMap { $0?.width }.max() ?? 0
        let italic = isLimits ? base.italicCorrection : 0
        let baseX = (width - base.width) / 2
        var overX = boxes[2].map { (width - $0.width) / 2 + italic / 2 } ?? 0
        let underX = boxes[1].map { (width - $0.width) / 2 - italic / 2 } ?? 0
        if accent, let over = boxes[2] {
            overX = baseX + (base.topAccentAttachment ?? base.width / 2) - (over.topAccentAttachment ?? over.width / 2)
        }
        let minX = min(baseX, boxes[2] == nil ? baseX : overX, boxes[1] == nil ? baseX : underX)
        var box = MathBox()
        box.add(base, at: CGPoint(x: baseX - minX, y: 0))
        if let under = boxes[1] { box.add(under, at: CGPoint(x: underX - minX, y: underY)) }
        if let over = boxes[2] { box.add(over, at: CGPoint(x: overX - minX, y: overY)) }
        box.width = max(baseX + base.width, boxes[2].map { overX + $0.width } ?? 0, boxes[1].map { underX + $0.width } ?? 0) - minX
        box.ascent = ascent
        box.descent = descent
        box.op = base.op
        if boxes[1] == nil, !isLimits { box.italicCorrection = base.italicCorrection }
        return box
    }

    // MARK: Padding

    /// `mpadded` with MathML 3's relative values and pseudo-units (`+0.5width`). A width, height
    /// or depth decremented past zero is zero (MathML 3, 3.3.6.2), so what follows the box is
    /// never placed before where it began. `lspace` and `voffset` may be negative.
    func padded(_ node: MathMLNode, _ context: LayoutContext, _ embellishment: Embellishment,
                depth: Int, singleChild: MathBox? = nil) throws -> MathBox {
        let content = try row(node.children, context, embellishment, depth: depth, singleChild: singleChild)
        // Default padding is an inferred row, including its spacing and break opportunities.
        // Explicit dimensions/offsets remain atomic: their interaction with fragmentation is
        // unspecified by MathML 3, 3.3.6.3.
        if !["width", "height", "depth", "lspace", "voffset"].contains(where: { node.attributes[$0] != nil }) {
            return content
        }
        let dimensions = (width: content.width, height: content.ascent, depth: content.descent)
        func resolve(_ name: String, _ current: CGFloat, reference: CGFloat, nonNegative: Bool = false) -> CGFloat {
            guard let attribute = node.attributes[name], let length = MathLength(attribute),
                  let value = length.resolve(em: context.fontSize, ex: xHeight(context), reference: reference,
                                             content: dimensions) else { return current }
            let resolved = length.isRelative ? current + value : value
            return nonNegative ? max(0, resolved) : resolved
        }
        var box = MathBox(width: resolve("width", content.width, reference: content.width, nonNegative: true),
                          ascent: resolve("height", content.ascent, reference: content.ascent, nonNegative: true),
                          descent: resolve("depth", content.descent, reference: content.descent, nonNegative: true))
        box.add(content, at: CGPoint(x: resolve("lspace", 0, reference: content.width),
                                     y: resolve("voffset", 0, reference: content.ascent)))
        box.op = content.op
        return box
    }

    // MARK: Enclosures

    /// `menclose` notations: box, roundedbox, circle, the four sides, strikes, longdiv,
    /// actuarial and madruwb. Unknown notations are ignored, as MathML Core asks.
    func enclose(_ node: MathMLNode, _ context: LayoutContext, depth: Int, singleChild: MathBox? = nil) throws -> MathBox {
        var content = try row(node.children, context, depth: depth, singleChild: singleChild)
        let notations = Set((node.attributes["notation"] ?? "longdiv").split(whereSeparator: \.isWhitespace).map(String.init))
        if notations == ["radical"] { return radical(base: content, index: nil, context) }
        let stroke = value(\.overbarRuleThickness, context)
        let em = context.fontSize
        let framed: Set<String> = ["box", "roundedbox", "circle", "left", "right", "top", "bottom", "longdiv",
                                   "actuarial", "madruwb", "radical"]
        let pad = notations.isDisjoint(with: framed) ? 0 : max(stroke * 3, em * 0.12)
        var left = pad, right = pad, top = pad, bottom = pad
        if notations.contains("longdiv") { left += em * 0.3 }
        if notations.contains("radical") { left += em * 0.6 }
        // Content too wide for the line stacks in lines inside the one enclosure. A circle is √2 times
        // as wide as its padded content, so it leaves that share of the line.
        let budget = nextWrapWidth
        let bulge = notations.contains("circle") && budget.isFinite ? (budget - left - right + 2 * pad) * (1 - 0.5.squareRoot()) : 0
        content = wrapped(content, beside: left + right + bulge, align: .left) ?? content
        if notations.contains("circle") {
            // An ellipse through the padded box's corners.
            let width = content.width + 2 * pad, height = content.height + 2 * pad
            let dx = width * (2.squareRoot() - 1) / 2, dy = height * (2.squareRoot() - 1) / 2
            left += dx; right += dx; top += dy; bottom += dy
        }
        let width = left + content.width + right
        let ascent = content.ascent + top, descent = content.descent + bottom
        var inner = CGRect(x: stroke / 2, y: -descent + stroke / 2, width: width - stroke, height: ascent + descent - stroke)
        // An arrow's head is two barbs back from its tip, each 27° off the shaft. Where the shaft is
        // within 27° of level or of upright, one barb passes the corner the arrow points at; where the
        // content is smaller than the head, a barb passes the corner the arrow starts from. This
        // notation has no padding to hold them, and the shaft is the up-diagonal strike's, which
        // converters write with the arrow, so the tip cannot draw back: the box grows by what the head
        // needs, as Gecko and MathJax make room for theirs. Wrapping content is not told of that room
        // as it is of a circle's: it depends on how tall wrapping leaves the content, so what was set
        // aside would not be what was taken, and a formula laid out again at the width it measured
        // would wrap another way. `lines` narrows for it as for anything else beside what wraps.
        var barbs: [CGPoint] = []
        var room = (left: CGFloat(0), right: CGFloat(0), top: CGFloat(0), bottom: CGFloat(0))
        if notations.contains("updiagonalarrow") {
            let head = em * 0.25, angle = atan2(inner.height, inner.width)
            for turn in [CGFloat.pi * 0.85, -CGFloat.pi * 0.85] {
                let barb = CGPoint(x: head * cos(angle + turn), y: head * sin(angle + turn))
                barbs.append(barb)
                room = (max(room.left, -barb.x - inner.width), max(room.right, barb.x), max(room.top, barb.y), max(room.bottom, -barb.y - inner.height))
            }
            inner = inner.offsetBy(dx: room.left, dy: 0)
        }
        var box = MathBox(width: room.left + width + room.right, ascent: ascent + room.top, descent: descent + room.bottom)
        box.add(content, at: CGPoint(x: room.left + left, y: 0))
        let path = CGMutablePath()
        func line(_ from: CGPoint, _ to: CGPoint) { path.move(to: from); path.addLine(to: to) }
        for notation in notations.sorted() {
            switch notation {
            case "box": path.addRect(inner)
            case "roundedbox":
                let radius = min(em * 0.3, inner.width / 2, inner.height / 2)
                path.addRoundedRect(in: inner, cornerWidth: radius, cornerHeight: radius)
            case "circle": path.addEllipse(in: inner)
            case "left": line(CGPoint(x: inner.minX, y: inner.minY), CGPoint(x: inner.minX, y: inner.maxY))
            case "right", "actuarial", "madruwb":
                line(CGPoint(x: inner.maxX, y: inner.minY), CGPoint(x: inner.maxX, y: inner.maxY))
                if notation == "actuarial" { line(CGPoint(x: inner.minX, y: inner.maxY), CGPoint(x: inner.maxX, y: inner.maxY)) }
                if notation == "madruwb" { line(CGPoint(x: inner.minX, y: inner.minY), CGPoint(x: inner.maxX, y: inner.minY)) }
            case "top": line(CGPoint(x: inner.minX, y: inner.maxY), CGPoint(x: inner.maxX, y: inner.maxY))
            case "bottom": line(CGPoint(x: inner.minX, y: inner.minY), CGPoint(x: inner.maxX, y: inner.minY))
            case "horizontalstrike":
                let y = (content.ascent - content.descent) / 2
                line(CGPoint(x: inner.minX, y: y), CGPoint(x: inner.maxX, y: y))
            case "verticalstrike": line(CGPoint(x: inner.midX, y: inner.minY), CGPoint(x: inner.midX, y: inner.maxY))
            case "updiagonalstrike", "updiagonalarrow":
                line(CGPoint(x: inner.minX, y: inner.minY), CGPoint(x: inner.maxX, y: inner.maxY))
                if notation == "updiagonalarrow" {
                    for barb in barbs { line(CGPoint(x: inner.maxX, y: inner.maxY), CGPoint(x: inner.maxX + barb.x, y: inner.maxY + barb.y)) }
                }
            case "downdiagonalstrike": line(CGPoint(x: inner.minX, y: inner.maxY), CGPoint(x: inner.maxX, y: inner.minY))
            case "longdiv":
                line(CGPoint(x: inner.minX, y: inner.maxY), CGPoint(x: inner.maxX, y: inner.maxY))
                path.move(to: CGPoint(x: inner.minX, y: inner.maxY))
                path.addQuadCurve(to: CGPoint(x: inner.minX, y: inner.minY),
                                  control: CGPoint(x: inner.minX + em * 0.35, y: inner.midY))
            case "radical":
                if let sign = drawnDelimiter("√", height: inner.height, context) {
                    box.add(sign, at: CGPoint(x: inner.minX, y: inner.minY))
                    line(CGPoint(x: inner.minX + sign.width, y: inner.maxY), CGPoint(x: inner.maxX, y: inner.maxY))
                }
            default: break
            }
        }
        if !path.isEmpty { box.items.append(.path(path, lineWidth: stroke, color: context.color, fill: false)) }
        return box
    }

    /// `merror`: its content in a red frame.
    func errorBox(_ node: MathMLNode, _ context: LayoutContext, depth: Int, singleChild: MathBox? = nil) throws -> MathBox {
        var content = try row(node.children, context, depth: depth, singleChild: singleChild)
        let stroke = max(value(\.overbarRuleThickness, context), 0.5), pad = context.fontSize * 0.1
        // Keep one frame around the whole stack rather than dropping error decoration.
        content = wrapped(content, beside: 2 * pad, align: .left) ?? content
        var box = MathBox(width: content.width + 2 * pad, ascent: content.ascent + pad, descent: content.descent + pad)
        box.add(content, at: CGPoint(x: pad, y: 0))
        let frame = CGRect(x: stroke / 2, y: -box.descent + stroke / 2, width: box.width - stroke, height: box.height - stroke)
        box.items.append(.path(CGPath(rect: frame, transform: nil), lineWidth: stroke,
                               color: CGColor(srgbRed: 0.85, green: 0, blue: 0, alpha: 1), fill: false))
        return box
    }

    // MARK: Tables

    /// `mtable`: a grid with vertically aligned rows with `columnalign`, `rowspacing`,
    /// `columnspacing`, lines and frame, centred on the math axis by default. `mlabeledtr`
    /// labels form a column at the side. Spanning cells reserve rectangles in a bounded grid.
    func table(_ node: MathMLNode, _ context: LayoutContext, depth: Int) throws -> MathBox {
        guard depth + 2 < MathLimits.depth else { throw MathLayoutError.limitExceeded }
        let attributes = node.attributes
        // Cells are in text style whatever surrounds the table, unless the table itself says otherwise
        // (MathML Core 3.5.1). `context` cannot tell the two apart: `inherit` put the table's own
        // `displaystyle` where the surroundings' was.
        var cellContext = context
        cellContext.display = attributes.flag("displaystyle") ?? false
        cellContext.trackAlignment = true
        cellContext.alignmentBaseline = true
        let tableGroups = AlignmentValues.columns(attributes["groupalign"] ?? context.tableGroupAlign)
        func list(_ name: String, in attributes: [String: String], fallback: String? = nil) -> [String] {
            (attributes[name] ?? fallback ?? "").split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        }
        func pick(_ values: [String], _ index: Int) -> String? { values.isEmpty ? nil : values[min(index, values.count - 1)] }
        func vertical(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  ["top", "bottom", "center", "baseline", "axis"].contains(value) else { return nil }
            return value
        }
        let tableRowAlign = list("rowalign", in: attributes, fallback: context.tableRowAlign)
        var rowAxes: [CGFloat] = []
        var cells = try TableGrid(rowCount: node.children.count)
        var labels: [TableCell?] = []
        var sources: [[TableCellSource]] = []
        let cached = isCellRebuild ? tableMeasurements.lookup(node, context) : nil
        if let cached {
            try countCellRebuildNodes(cached.descendantNodes)
            try countTableWork(cached.tableWork)
            cells = cached.cells; labels = cached.labels; sources = cached.sources; rowAxes = cached.rowAxes
            // A fresh cell engine has its own sequence. Cached source priorities must not
            // collide with new siblings or another cache hit in that same engine.
            for row in cells.rows.indices {
                for index in cells.rows[row].indices {
                    restampAlignment(&cells.rows[row][index].box)
                }
            }
        } else {
            let startNodes = visitedNodes, startWork = remainingTableWork
            for (rowIndex, rowNode) in node.children.enumerated() {
                let rowContext: LayoutContext
                var cellNodes: [MathMLNode]
                var label: MathMLNode?
                switch rowNode.name {
                case "mtr", "mlabeledtr":
                    // A row is a node as its cells are, though only they are laid out.
                    try visit(cellContext, depth: depth + 1)
                    rowContext = inherit(rowNode, cellContext)
                    cellNodes = rowNode.children
                    if rowNode.name == "mlabeledtr", !cellNodes.isEmpty { label = cellNodes.removeFirst() }
                default:
                    rowContext = cellContext
                    cellNodes = [rowNode]
                }
                let rowAlign = list("columnalign", in: rowNode.attributes)
                let rowGroups = AlignmentValues.columns(rowNode.attributes["groupalign"])
                let rowVertical = ((rowNode.name == "mtr" || rowNode.name == "mlabeledtr")
                    ? vertical(rowNode.attributes["rowalign"]) : nil)
                    ?? vertical(pick(tableRowAlign, rowIndex)) ?? "baseline"
                rowAxes.append(value(\.axisHeight, rowContext))
                var rowSources: [TableCellSource] = []
                for cell in cellNodes {
                    rowSources.append(TableCellSource(node: cell, context: rowContext, depth: depth + 2))
                    let box = try layout(cell, rowContext, depth: depth + 2)
                    let rowSpan = try TableGrid.span(cell.attributes["rowspan"])
                    let columnSpan = try TableGrid.span(cell.attributes["columnspan"])
                    let align = cell.attributes["columnalign"]?.trimmingCharacters(in: .whitespaces).lowercased()
                    let alignment = vertical(cell.attributes["rowalign"]) ?? rowVertical
                    let oldWork = cells.work
                    try cells.insert(box, row: rowIndex, rowSpan: rowSpan,
                                     columnSpan: columnSpan, align: align, rowAlign: alignment,
                                     workBudget: remainingTableWork)
                    try countTableWork(cells.work - oldWork)
                    // Row alignment lists address grid columns, including occupied ones.
                    let index = cells.rows[rowIndex].count - 1
                    let column = cells.rows[rowIndex][index].column
                    cells.rows[rowIndex][index].groupAlign = cell.attributes["groupalign"].map { AlignmentValues.list($0) }
                        ?? AlignmentValues.pick(rowGroups, column) ?? AlignmentValues.pick(tableGroups, column) ?? ["left"]
                    cells.rows[rowIndex][index].axis = value(\.axisHeight, inherit(cell, rowContext))
                    if cells.rows[rowIndex][index].align == nil {
                        cells.rows[rowIndex][index].align = pick(rowAlign, cells.rows[rowIndex][index].column)
                    }
                }
                sources.append(rowSources)
                labels.append(try label.map {
                    // Labels have their own gutter; neither their spans nor previous grid spans reserve
                    // a position for the next label (MathML 3, 3.5.4.2).
                    let rowSpan = min(try TableGrid.span($0.attributes["rowspan"]), cells.rows.count - rowIndex)
                    _ = try TableGrid.span($0.attributes["columnspan"])
                    // Label spans also touch row tracks, even though they do not occupy main-grid slots.
                    try countTableWork(rowSpan)
                    var labelBox = try layout($0, rowContext, depth: depth + 2)
                    labelBox.alignment = []
                    return TableCell(box: labelBox, align: nil,
                                     rowAlign: vertical($0.attributes["rowalign"]) ?? rowVertical,
                                     column: 0, rowSpan: rowSpan, columnSpan: 1,
                                     axis: value(\.axisHeight, inherit($0, rowContext)))
                })
            }
            tableMeasurements.keep(node, context, cells: cells, labels: labels, sources: sources,
                                   rowAxes: rowAxes, descendantNodes: visitedNodes - startNodes,
                                   tableWork: startWork - remainingTableWork)
        }
        return try assembleTable(node, context, cells: cells, labels: labels, sources: sources, rowAxes: rowAxes)
    }

    @inline(never)
    private func assembleTable(_ node: MathMLNode, _ context: LayoutContext, cells: TableGrid,
                               labels: [TableCell?], sources: [[TableCellSource]], rowAxes: [CGFloat]) throws -> MathBox {
        var cells = cells
        let attributes = node.attributes
        func list(_ name: String, in attributes: [String: String]) -> [String] {
            (attributes[name] ?? "").split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        }
        func pick(_ values: [String], _ index: Int) -> String? { values.isEmpty ? nil : values[min(index, values.count - 1)] }
        let columns = cells.columns
        let ex = xHeight(context), em = context.fontSize
        func spacing(_ name: String, _ standard: CGFloat, count: Int) -> [CGFloat] {
            let values = list(name, in: attributes)
            return (0..<max(count, 0)).map { index in
                pick(values, index).flatMap { length($0, context, reference: em) }.map { max($0, 0) } ?? standard
            }
        }
        let rowGaps = spacing("rowspacing", ex, count: cells.rows.count - 1)
        let columnGaps = spacing("columnspacing", 0.8 * em, count: columns - 1)
        let rowLines = list("rowlines", in: attributes), columnLines = list("columnlines", in: attributes)
        let frame = attributes["frame"]?.trimmingCharacters(in: .whitespaces).lowercased() ?? "none"
        let framing = list("framespacing", in: attributes)
        let frameX = frame == "none" ? 0 : (pick(framing, 0).flatMap { length($0, context) } ?? 0.4 * em)
        let frameY = frame == "none" ? 0 : (pick(framing, 1).flatMap { length($0, context) } ?? 0.5 * ex)
        let tableAlign = list("columnalign", in: attributes)
        let labelGap = length(attributes["minlabelspacing"], context, reference: em) ?? 0.8 * em
        let labelWidth = labels.compactMap { $0?.box.width }.max().map { $0 + labelGap } ?? 0
        // Resolve breaks before measuring group side widths. Every fragment of a source
        // group then moves together, including fragments on later cell lines.
        let minimum = try wrapCells(&cells, sources: sources, columnAlign: tableAlign, gaps: columnGaps,
                                    fixed: columnGaps.reduce(0, +) + 2 * frameX + labelWidth,
                                    scopes: list("alignmentscope", in: attributes), rtl: context.alignmentRTL)
        let widths = cells.widths(gaps: columnGaps) { _, _, cell in cell.box.width }
        var ascents = [CGFloat](repeating: 0, count: cells.rows.count), descents = ascents
        for (rowIndex, row) in cells.rows.enumerated() {
            var tallest: CGFloat = 0
            for cell in row + (labels[rowIndex].map { [$0] } ?? []) {
                if cell.rowSpan == 1 { tallest = max(tallest, cell.box.height) }
                guard cell.rowAlign == "baseline" || cell.rowAlign == "axis" else { continue }
                let shift = cell.rowAlign == "axis" ? rowAxes[rowIndex] - cell.axis : 0
                ascents[rowIndex] = max(ascents[rowIndex], cell.box.ascent + shift)
                if cell.rowSpan == 1 { descents[rowIndex] = max(descents[rowIndex], cell.box.descent - shift) }
            }
            let extra = max(0, tallest - ascents[rowIndex] - descents[rowIndex]) / 2
            ascents[rowIndex] += extra
            descents[rowIndex] += extra
        }
        for (rowIndex, row) in cells.rows.enumerated() {
            for cell in row + (labels[rowIndex].map { [$0] } ?? []) where cell.rowSpan > 1 {
                let end = rowIndex + cell.rowSpan
                let anchored = cell.rowAlign == "baseline" || cell.rowAlign == "axis"
                let shift = cell.rowAlign == "axis" ? rowAxes[rowIndex] - cell.axis : 0
                let available = descents[rowIndex..<end].reduce(0, +)
                    + ascents[(rowIndex + 1)..<end].reduce(0, +) + rowGaps[rowIndex..<(end - 1)].reduce(0, +)
                    + (anchored ? 0 : ascents[rowIndex])
                let required = anchored ? cell.box.descent - shift : cell.box.height
                let extra = max(0, required - available) / CGFloat(cell.rowSpan)
                for row in rowIndex..<end { descents[row] += extra }
            }
        }

        let gridWidth = widths.reduce(0, +) + columnGaps.reduce(0, +)
        let height = ascents.reduce(0, +) + descents.reduce(0, +) + rowGaps.reduce(0, +) + 2 * frameY
        // `align`: axis (default), center or baseline, top, bottom, for the whole table or for the row
        // whose number follows, counted from the bottom when it is negative. A row's axis is as far
        // above its baseline as its row context's; numbered `axis` accounts for size changes. A
        // number that names no row is ignored (MathML 3, 3.5.1.2).
        let alignParts = list("align", in: attributes)
        var top: CGFloat
        var baselines: [CGFloat] = []
        var y = frameY
        for index in cells.rows.indices {
            baselines.append(y + ascents[index])
            y += ascents[index] + descents[index] + (index < rowGaps.count ? rowGaps[index] : 0)
        }
        let axis = value(\.axisHeight, context)
        let alignment = alignParts.first ?? "axis"
        if alignParts.count > 1, let number = Int(alignParts[1]), number != 0, (-cells.rows.count...cells.rows.count).contains(number) {
            let row = number > 0 ? number - 1 : cells.rows.count + number
            top = switch alignment {
            case "top": baselines[row] - ascents[row]
            case "bottom": baselines[row] + descents[row]
            case "center": baselines[row] + (descents[row] - ascents[row]) / 2
            case "axis": baselines[row] - rowAxes[row] + axis
            default: baselines[row]
            }
        } else {
            top = switch alignment {
            case "top": 0
            case "bottom": height
            case "center", "baseline": height / 2
            default: height / 2 + axis
            }
        }
        var box = MathBox()
        let labelsLeft = attributes["side"]?.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("left") == true
        let gridX = labelsLeft ? labelWidth : 0
        var columnStarts: [CGFloat] = [], columnEnds: [CGFloat] = []
        var x = gridX + frameX
        for column in widths.indices {
            columnStarts.append(x)
            columnEnds.append(x + widths[column])
            x += widths[column] + (column < columnGaps.count ? columnGaps[column] : 0)
        }
        // Grid indices stay in source order. Reflect track edges without reflecting cells,
        // physical column alignment, or the independently positioned label gutters.
        if context.alignmentRTL {
            for column in widths.indices {
                let start = columnStarts[column]
                columnStarts[column] = 2 * gridX + gridWidth + 2 * frameX - columnEnds[column]
                columnEnds[column] = 2 * gridX + gridWidth + 2 * frameX - start
            }
        }
        func cellBaseline(_ cell: TableCell, row: Int) -> CGFloat {
            let end = row + cell.rowSpan - 1
            let cellTop = top - baselines[row] + ascents[row]
            let cellBottom = top - baselines[end] - descents[end]
            return switch cell.rowAlign ?? "baseline" {
            case "top": cellTop - cell.box.ascent
            case "bottom": cellBottom + cell.box.descent
            case "center": (cellTop + cellBottom - cell.box.ascent + cell.box.descent) / 2
            case "axis": top - baselines[row] + rowAxes[row] - cell.axis
            default: top - baselines[row]
            }
        }
        for (rowIndex, row) in cells.rows.enumerated() {
            for cell in row {
                let width = cells.spanWidth(cell, widths: widths, gaps: columnGaps)
                let align = cell.align ?? pick(tableAlign, cell.column) ?? "center"
                let offset: CGFloat = switch align {
                case "left": 0
                case "right": width - cell.box.width
                default: (width - cell.box.width) / 2
                }
                box.add(cell.box, at: CGPoint(x: columnStarts[context.alignmentRTL ? cell.column + cell.columnSpan - 1 : cell.column] + offset, y: cellBaseline(cell, row: rowIndex)))
            }
            if let label = labels[rowIndex] {
                let labelX = labelsLeft ? 0 : gridX + gridWidth + 2 * frameX + labelGap
                box.add(label.box, at: CGPoint(x: labelX, y: cellBaseline(label, row: rowIndex)))
            }
        }
        // Lines, half-way through the gaps. A stroke reaches half its thickness to either side of its
        // path and, with round caps, as far past the path's ends. So a line's path is kept that far
        // inside the table's edges, as the frame's is: the line ends at the edge, and the line of a gap
        // of no width at the edge runs inside it, not half outside. A table too small to hold a line
        // that way has none.
        let stroke = value(\.fractionRuleThickness, context)
        let solid = CGMutablePath(), dashed = CGMutablePath()
        let gridLeft = gridX, gridRight = gridX + gridWidth + 2 * frameX
        let inside = (left: gridLeft + stroke / 2, right: gridRight - stroke / 2, top: top - stroke / 2, bottom: top - height + stroke / 2)
        let hasRoom = inside.left <= inside.right && inside.bottom <= inside.top
        var rowBlocks = [[ClosedRange<CGFloat>]](repeating: [], count: rowGaps.count)
        var columnBlocks = [[ClosedRange<CGFloat>]](repeating: [], count: columnGaps.count)
        for (rowIndex, row) in cells.rows.enumerated() {
            for cell in row {
                let lastColumn = cell.column + cell.columnSpan - 1
                let leading = cell.column == 0 ? (context.alignmentRTL ? inside.right : inside.left)
                    : (context.alignmentRTL ? columnEnds[cell.column] + columnGaps[cell.column - 1] / 2
                       : columnStarts[cell.column] - columnGaps[cell.column - 1] / 2)
                let trailing = lastColumn == columns - 1 ? (context.alignmentRTL ? inside.left : inside.right)
                    : (context.alignmentRTL ? columnStarts[lastColumn] - columnGaps[lastColumn] / 2
                       : columnEnds[lastColumn] + columnGaps[lastColumn] / 2)
                let left = min(leading, trailing), right = max(leading, trailing)
                for boundary in rowIndex..<(rowIndex + cell.rowSpan - 1) {
                    if left <= right { rowBlocks[boundary].append(left...right) }
                }
                let lastRow = rowIndex + cell.rowSpan - 1
                let upper = rowIndex == 0 ? inside.top : top - baselines[rowIndex] + ascents[rowIndex] + rowGaps[rowIndex - 1] / 2
                let lower = lastRow == cells.rows.count - 1 ? inside.bottom : top - baselines[lastRow] - descents[lastRow] - rowGaps[lastRow] / 2
                for boundary in cell.column..<lastColumn {
                    if lower <= upper { columnBlocks[boundary].append(lower...upper) }
                }
            }
        }
        // Subtract merged blocked intervals, keeping round caps outside the spanning rectangle.
        func segments(_ range: ClosedRange<CGFloat>, excluding blocks: [ClosedRange<CGFloat>],
                      draw: (CGFloat, CGFloat) -> Void) {
            var cursor = range.lowerBound
            for block in blocks.sorted(by: { $0.lowerBound < $1.lowerBound }) {
                let start = max(range.lowerBound, block.lowerBound - stroke / 2)
                let end = min(range.upperBound, block.upperBound + stroke / 2)
                guard start <= end else { continue }
                if start > cursor { draw(cursor, start) }
                cursor = max(cursor, end)
            }
            if cursor < range.upperBound { draw(cursor, range.upperBound) }
        }
        var lineY = top - frameY
        for index in rowGaps.indices {
            lineY -= ascents[index] + descents[index] + rowGaps[index] / 2
            if let style = pick(rowLines, index), style != "none", hasRoom {
                let path = style == "dashed" ? dashed : solid, y = min(max(lineY, inside.bottom), inside.top)
                segments(inside.left...inside.right, excluding: rowBlocks[index]) { left, right in
                    path.move(to: CGPoint(x: left, y: y)); path.addLine(to: CGPoint(x: right, y: y))
                }
            }
            lineY -= rowGaps[index] / 2
        }
        var lineX = gridX + frameX
        for index in columnGaps.indices {
            lineX += widths[index] + columnGaps[index] / 2
            if let style = pick(columnLines, index), style != "none", hasRoom {
                let physicalX = context.alignmentRTL ? gridLeft + gridRight - lineX : lineX
                let path = style == "dashed" ? dashed : solid, x = min(max(physicalX, inside.left), inside.right)
                segments(inside.bottom...inside.top, excluding: columnBlocks[index]) { bottom, top in
                    path.move(to: CGPoint(x: x, y: top)); path.addLine(to: CGPoint(x: x, y: bottom))
                }
            }
            lineX += columnGaps[index] / 2
        }
        if frame != "none", hasRoom {
            let rect = CGRect(x: gridLeft + stroke / 2, y: top - height + stroke / 2, width: gridRight - gridLeft - stroke,
                              height: height - stroke)
            (frame == "dashed" ? dashed : solid).addRect(rect)
        }
        if !solid.isEmpty { box.items.append(.path(solid, lineWidth: stroke, color: context.color, fill: false)) }
        // Dashed when it is drawn, never here: see `MathItem.dashes`.
        if !dashed.isEmpty {
            box.items.append(.dashes(dashed, lineWidth: stroke, color: context.color, lengths: [stroke * 4, stroke * 3]))
        }
        box.width = gridWidth + 2 * frameX + labelWidth
        box.ascent = top
        box.descent = height - top
        box.tableMinimumWidth = minimum
        return box
    }
}
