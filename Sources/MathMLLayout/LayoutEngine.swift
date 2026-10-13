import CoreGraphics
import CoreText
import Foundation

/// Bounds on untrusted input. A formula beyond them throws `MathLayoutError.limitExceeded`.
enum MathLimits {
    /// Element nesting. Layout recurses per level, so this also bounds stack use.
    static let depth = 64
    static let nodes = 20_000
    /// UTF-16 units of token text in one formula.
    static let textLength = 50_000
    /// Points, any dimension of the result.
    static let extent: CGFloat = 50_000
    /// Drawing items (glyph runs, rules, paths, images, nested boxes) in one formula.
    static let items = 100_000
    /// Bytes of stack that must be left when an element starts to lay out or to be read. `depth`
    /// counts levels, and a level is as large as the build makes it: unoptimized, 63 levels of
    /// `munderover` use 1.7 MB, and optimized 600 KB, where a thread that is not the main one has
    /// 512 KB. The margin is for what an element does before it reaches another: its own frames
    /// (27 KB at most, unoptimized), CoreText shaping its text (some 45 KB), and the host's image
    /// provider.
    static let stackMargin = 128 << 10

    /// The lowest address the calling thread's stack may reach and leave `stackMargin`; zero, which
    /// no stack reaches, when this is not running on the thread's own stack and nothing is known.
    static func stackFloor() -> UInt {
        let thread = pthread_self()
        let top = UInt(bitPattern: pthread_get_stackaddr_np(thread)), size = UInt(pthread_get_stacksize_np(thread))
        var marker = 0
        let here = withUnsafeMutablePointer(to: &marker) { UInt(bitPattern: $0) }
        guard here <= top, top - here <= size, size <= top else { return 0 }
        return (top - size) &+ UInt(stackMargin)
    }

    /// Whether the stack has grown down past `floor`: one comparison, so every element can ask.
    @inline(__always) static func isStackSpent(_ floor: UInt) -> Bool {
        var marker = 0
        return withUnsafeMutablePointer(to: &marker) { UInt(bitPattern: $0) } < floor
    }
}

/// The inherited state of layout at one element: MathML's `displaystyle`, `scriptlevel`,
/// `math-shift` (cramped), `mathvariant`, `mathcolor` and the font size they produce.
struct LayoutContext {
    var fontSize: CGFloat
    /// The size scriptlevel changes compute before the minimum applies.
    var unclampedSize: CGFloat
    /// `scriptminsize`: script level changes never shrink text below it.
    var minSize: CGFloat
    /// `scriptsizemultiplier`; nil uses the font's MATH percentages.
    var sizeMultiplier: CGFloat?
    var scriptLevel = 0
    var display: Bool
    /// TeX's cramped style: superscripts sit lower (under a bar or radical, in subscripts).
    var cramped = false
    var variant: MathVariant?
    var color: CGColor
    /// MathML 3's line-breaking and indentation attributes, which `mo` and `mspace` read.
    var lines = LineStyle()
    /// `decimalpoint`: the character a stack's rows align on (`stackalign="decimalpoint"`); nil is ".".
    var decimalPoint: String?
}

/// What an embellished operator learns from where it sits: its form from its position in a
/// row, and the size to stretch to.
struct Embellishment {
    enum Stretch {
        /// Cover these extents around the baseline (fences, bars, vertical arrows).
        case vertical(ascent: CGFloat, descent: CGFloat)
        /// Cover this width (arrows, braces and wide accents in under- and overscripts).
        case horizontal(width: CGFloat)
    }
    var form: OperatorForm?
    var stretch: Stretch?
    static let none = Embellishment()
}

/// Rebuilds an entire embellished fence, including its scripts, in its original inherited style.
/// The outer context is retained: applying the element's own relative size twice would change it.
final class FenceLayout {
    let node: MathMLNode
    let context: LayoutContext
    let form: OperatorForm?
    let engine: LayoutEngine
    let lineWidth: CGFloat
    let wrapWidth: CGFloat
    let wrapParts: Range<Int>
    let wrapOverrides: [Int: CGFloat]
    /// This box directly draws the core fence, including through `semantics` or `maction`.
    /// Other embellished boxes contain their core as a child and also draw scripts or labels.
    let isCoreGeometry: Bool

    init(node: MathMLNode, context: LayoutContext, form: OperatorForm?, engine: LayoutEngine,
         lineWidth: CGFloat, wrapWidth: CGFloat, wrapParts: Range<Int>, wrapOverrides: [Int: CGFloat],
         isCoreGeometry: Bool) {
        self.node = node; self.context = context; self.form = form; self.engine = engine
        self.lineWidth = lineWidth; self.wrapWidth = wrapWidth
        self.wrapParts = wrapParts; self.wrapOverrides = wrapOverrides
        self.isCoreGeometry = isCoreGeometry
    }

    func box(ascent: CGFloat, descent: CGFloat) -> MathBox? {
        let fresh = LayoutEngine(font: engine.font)
        fresh.imageProvider = engine.imageProvider
        fresh.imageCache = engine.imageCache
        fresh.lineWidth = lineWidth
        fresh.wrapWidth = wrapWidth
        // A wrapping retry's part indices are relative to the complete formula; the rebuilt
        // subtree starts at zero, but must keep the budgets that produced the chosen boxes.
        for part in wrapParts {
            if let width = wrapOverrides[part] { fresh.wrapOverrides[part - wrapParts.lowerBound] = width }
        }
        return try? fresh.layout(node, context, Embellishment(form: form,
            stretch: .vertical(ascent: ascent, descent: descent)), depth: 0)
    }
}

/// What was found of each of a formula's lists of children, kept so that it is found once.
///
/// A node is a value: it has no identity to keep an answer by, and comparing two reads both to
/// the bottom. A list of children has the address of its storage, which every copy of the array
/// shares, so an answer here is one that the list alone decides, whatever element it is the
/// children of. The list is held with its answer: no other list is then given that storage, and
/// with it that address, while the answer is kept. The same list in two places, as a tree built
/// by hand may have it, is read once.
private struct ListMemo<Answer> {
    private var kept: [UInt: (list: [MathMLNode], answer: Answer)] = [:]

    private static func address(_ list: [MathMLNode]) -> UInt { list.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) } }

    /// nil when nothing has been kept for `list`.
    func answer(for list: [MathMLNode]) -> Answer? { kept[Self.address(list)]?.answer }

    mutating func keep(_ answer: Answer, for list: [MathMLNode]) { kept[Self.address(list)] = (list, answer) }
}

/// Lays out one formula. Not shared: each `MathLayout` makes its own, so it needs no locking.
///
/// The algorithms follow MathML Core (https://www.w3.org/TR/mathml-core/) and the OpenType MATH
/// specification, with TeX's rules (The TeXbook, appendix G) where those leave a choice.
final class LayoutEngine {
    let font: MathFont
    let constants: MathConstants
    private var nodeCount = 0
    private var textLength = 0
    /// `MathLimits.stackFloor` of the thread that lays out, found as the root starts.
    private var stackFloor: UInt = 0
    /// `MathStyle.imageProvider`, and what it has returned for each `src` it was asked for.
    var imageProvider: MathImageProvider? { didSet { if imageProvider != oldValue { imageCache = [:] } } }
    var imageCache: [String: CGImage?] = [:]

    init(fontName: String?) {
        font = MathFont.named(fontName)
        constants = font.constants
    }

    fileprivate init(font: MathFont) {
        self.font = font
        constants = font.constants
    }

    /// The style's font size as layout takes it: between 1 and 1000 points, and 1 when it is no
    /// number at all, which `min` and `max` would hand on to every measure of the formula.
    static func fontSize(_ style: MathStyle) -> CGFloat { style.fontSize.isNaN ? 1 : min(max(style.fontSize, 1), 1000) }

    func layoutRoot(_ root: MathMLNode, style: MathStyle) throws -> MathBox {
        imageProvider = style.imageProvider
        let size = Self.fontSize(style)
        let context = LayoutContext(fontSize: size, unclampedSize: size, minSize: min(size, max(8, size * 0.6)),
                                    display: style.isDisplay || root.attributes["display"]?.trimmingCharacters(in: .whitespaces).lowercased() == "block",
                                    color: style.color)
        // One unbroken row: `lines` breaks it, makes each row cover its ink and checks the result's size.
        return try layout(root, context, depth: 0)
    }

    // MARK: Context

    func value(_ constant: KeyPath<MathConstants, CGFloat>, _ context: LayoutContext) -> CGFloat {
        constants[keyPath: constant] * context.fontSize
    }

    func ctFont(_ context: LayoutContext) -> CTFont { font.font(size: context.fontSize, scriptLevel: context.scriptLevel) }

    func xHeight(_ context: LayoutContext) -> CGFloat {
        let height = CTFontGetXHeight(font.base) * context.fontSize
        return height > 0 ? height : context.fontSize / 2
    }

    func length(_ attribute: String?, _ context: LayoutContext, reference: CGFloat? = nil) -> CGFloat? {
        guard let attribute, let length = MathLength(attribute) else { return nil }
        return length.resolve(em: context.fontSize, ex: xHeight(context), reference: reference)
    }

    /// The size factor of a script level relative to level 0: the MATH table's percentages
    /// for levels 1 and 2, then 0.71 a level (MathML Core's `math-depth`).
    private func scale(_ level: Int, _ context: LayoutContext) -> CGFloat {
        if let multiplier = context.sizeMultiplier { return pow(multiplier, CGFloat(level)) }
        switch level {
        case ...0: return pow(0.71, CGFloat(level))
        case 1: return constants.scriptPercentScaleDown / 100
        default: return constants.scriptScriptPercentScaleDown / 100 * pow(0.71, CGFloat(level - 2))
        }
    }

    func setScriptLevel(_ context: inout LayoutContext, _ level: Int) {
        let level = min(max(level, -8), 16)
        guard level != context.scriptLevel else { return }
        context.unclampedSize *= scale(level, context) / scale(context.scriptLevel, context)
        context.fontSize = max(context.unclampedSize, min(context.fontSize, context.minSize))
        context.scriptLevel = level
    }

    /// Context for scripts, limits, fraction parts and radical indexes: not display style,
    /// `levels` script levels deeper.
    func scriptContext(_ context: LayoutContext, levels: Int = 1, cramped: Bool? = nil) -> LayoutContext {
        var result = context
        result.display = false
        if levels != 0 { setScriptLevel(&result, context.scriptLevel + levels) }
        if let cramped { result.cramped = cramped }
        return result
    }

    /// MathML's attributes that every element may carry and its descendants inherit.
    func inherit(_ node: MathMLNode, _ outer: LayoutContext) -> LayoutContext {
        let attributes = node.attributes
        guard !attributes.isEmpty else { return outer }
        var context = outer
        if node.name == "mstyle" {
            if let multiplier = attributes["scriptsizemultiplier"].flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }),
               multiplier > 0.1, multiplier <= 10 {
                context.sizeMultiplier = CGFloat(multiplier)
            }
            if let minimum = length(attributes["scriptminsize"], context, reference: context.fontSize) {
                context.minSize = max(1, minimum)
            }
        }
        if node.name == "mstyle" || node.name == "math",
           let point = attributes["decimalpoint"]?.trimmingCharacters(in: .whitespaces), !point.isEmpty {
            context.decimalPoint = point
        }
        if let display = attributes.flag("displaystyle") { context.display = display }
        if let level = attributes["scriptlevel"]?.trimmingCharacters(in: .whitespaces), let parsed = Int(level) {
            // Levels stay within -8...16, so a change of 24 reaches either end from the other, and a
            // number bounded so cannot overflow the sum: "+9223372036854775807" is markup too.
            let number = min(max(parsed, -24), 24)
            setScriptLevel(&context, level.hasPrefix("+") || level.hasPrefix("-") ? context.scriptLevel + number : number)
        }
        if let size = attributes["mathsize"] ?? attributes["fontsize"] {
            let resolved: CGFloat? = switch size.trimmingCharacters(in: .whitespaces).lowercased() {
            case "small": context.fontSize / 1.2
            case "normal": context.fontSize
            case "big": context.fontSize * 1.2
            default: length(size, context, reference: context.fontSize)
            }
            if let resolved, resolved > 0 {
                context.fontSize = min(resolved, 1000); context.unclampedSize = context.fontSize
            }
        }
        if let color = (attributes["mathcolor"] ?? attributes["color"]).flatMap(MathColor.parse) { context.color = color }
        if let variant = attributes["mathvariant"].flatMap(MathVariant.init(attribute:)) {
            context.variant = variant
        } else if attributes["fontweight"] != nil || attributes["fontstyle"] != nil {
            let bold = attributes["fontweight"] == "bold", italic = attributes["fontstyle"] == "italic"
            context.variant = bold ? (italic ? .boldItalic : .bold) : (italic ? .italic : .normal)
        }
        inheritLineStyle(node, &context)
        return context
    }

    // MARK: Dispatch

    static let tokens: Set<String> = ["mi", "mn", "mo", "mtext", "ms"]
    /// Elements that draw nothing.
    private static let empty: Set<String> = ["none", "mprescripts", "annotation", "annotation-xml", "malignmark", "maligngroup"]

    /// The child that stands for a `semantics` or an `maction`: the first child of `semantics` that
    /// is not an annotation, and the child of `maction` that `selection` names, counted from 1, or
    /// its first when `selection` is missing, no number, or names no child. nil when there is no
    /// such child, and for every other element. Layout draws this child and a reading says it
    /// (`Speaker`), and both ask here, so that what is read aloud is what is drawn.
    static func shownChild(_ node: MathMLNode) -> MathMLNode? { shownIndex(node).map { node.children[$0] } }

    /// Where among its children `shownChild` is. For a `semantics` that is also how many
    /// annotations come before the child: they are passed over to find it, not laid out and not
    /// read, but they are nodes of the formula all the same. Layout and a reading count them
    /// toward the node bound, as the parser counts every element: a tree built by hand may put
    /// thousands of them before the child, under thousands of parents.
    static func shownIndex(_ node: MathMLNode) -> Int? {
        let children = node.children
        switch node.name {
        case "semantics":
            return children.firstIndex { $0.name != "annotation" && $0.name != "annotation-xml" }
        case "maction":
            let selection = node.attributes["selection"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 1
            // Compared, not subtracted from first: a `selection` of `Int.min` has no number before it.
            return selection >= 1 && selection <= children.count ? selection - 1 : (children.isEmpty ? nil : 0)
        default:
            return nil
        }
    }

    /// Elements visited without a box still count toward the formula's node bound.
    func countNodes(_ count: Int = 1) throws {
        nodeCount += count
        guard nodeCount <= MathLimits.nodes else { throw MathLayoutError.limitExceeded }
    }

    func layout(_ node: MathMLNode, _ outer: LayoutContext, _ embellishment: Embellishment = .none,
                depth: Int) throws -> MathBox {
        guard depth < MathLimits.depth else { throw MathLayoutError.limitExceeded }
        // The depth bound counts levels, not bytes, and a thread's stack may be spent well within it.
        if depth == 0 { stackFloor = MathLimits.stackFloor() }
        guard !MathLimits.isStackSpent(stackFloor) else { throw MathLayoutError.limitExceeded }
        try countNodes()
        let context = inherit(node, outer)
        let wrapStart = wrapParts.count
        let children = node.children
        var box: MathBox
        switch node.name {
        case "math", "mrow", "mstyle", "mtd":
            box = try row(children, context, embellishment, depth: depth)
        case "mi", "mn", "mtext", "ms":
            box = try token(node, context)
        case "mglyph":
            // MathML 2 listed `mglyph` among the tokens (3.1.6), so one may stand alone in a row.
            // It is laid out as the `mtext` it would now be in, not as an element of its own: the
            // style it would hand down has no effect on an `mglyph` (MathML 3, 3.2.1.2.2). That
            // `mtext` is no node of the formula's, so it is not laid out as one, which would count it.
            return try token(MathMLNode(name: "mtext", children: [node]), outer)
        case "mo":
            box = try operatorBox(node, context, embellishment)
        case "mspace":
            box = MathBox(width: length(node.attributes["width"], context) ?? 0,
                          ascent: length(node.attributes["height"], context) ?? 0,
                          descent: length(node.attributes["depth"], context) ?? 0)
        case "mfrac":
            box = try fraction(node, context, embellishment, depth: depth)
        case "msqrt":
            let base = try row(children, context.with(cramped: true), depth: depth)
            box = radical(base: base, index: nil, context)
        case "mroot":
            try arity(node, 2)
            let base = try layout(children[0], context.with(cramped: true), depth: depth + 1)
            let index = try layout(children[1], scriptContext(context, levels: 2), depth: depth + 1)
            box = radical(base: base, index: index, context)
        case "msub", "msup", "msubsup", "mmultiscripts":
            box = try scripts(node, context, embellishment, depth: depth)
        case "munder", "mover", "munderover":
            box = try underOver(node, context, embellishment, depth: depth)
        case "mpadded":
            box = try padded(node, context, embellishment, depth: depth)
        case "mphantom":
            box = try row(children, context, embellishment, depth: depth)
            box.isPhantom = true
        case "menclose":
            box = try enclose(node, context, depth: depth)
        case "mtable":
            box = try table(node, context, depth: depth)
        case "mtr", "mlabeledtr":
            // The inferred table applies the row's attributes itself, as an explicit table does.
            // Passing `context` would apply relative sizes and script levels a second time.
            box = try table(MathMLNode(name: "mtable", children: [node]), outer, depth: depth)
        case "mstack", "mlongdiv", "msgroup", "msrow", "mscarries", "mscarry", "msline":
            box = try elementaryMath(node, context, depth: depth)
        case "mfenced":
            box = try row(fenced(node), context, embellishment, depth: depth)
        case "semantics", "maction":
            let shown = shownIndex(of: node)
            if node.name == "semantics" {
                // The annotations before the child, or all of them when there is no child.
                nodeCount += shown ?? children.count
                guard nodeCount <= MathLimits.nodes else { throw MathLayoutError.limitExceeded }
            }
            box = try shown.map { try layout(children[$0], context, embellishment, depth: depth + 1) } ?? .empty()
        case "merror":
            box = try errorBox(node, context, depth: depth)
        case let name where Self.empty.contains(name):
            box = .empty()
        default:
            throw MathLayoutError.unsupported(node.name)
        }
        if let background = node.attributes["mathbackground"].flatMap(MathColor.parse) {
            // A background encloses one stack, including gaps between its lines. It is never
            // discarded by flattening, nor painted on unrelated neighbours.
            box = wrapped(box, beside: 0, align: .left) ?? box
            if box.isPhantom {
                let hidden = box
                box.isPhantom = false
                box.items = []
                box.add(hidden, at: .zero)
            }
            box.row = nil
            box.items.insert(.rect(CGRect(x: 0, y: -box.descent, width: box.width, height: box.height), background), at: 0)
        }
        if box.op?.has(.fence) == true, case .vertical = embellishment.stretch,
           isStretchy(node, form: embellishment.form, horizontal: false) {
            let isCoreGeometry = node.name == "mo" && !children.contains(where: { $0.name == "mglyph" })
                || box.fenceLayout?.isCoreGeometry == true
            box.fenceLayout = FenceLayout(node: node, context: outer, form: embellishment.form, engine: self,
                                          lineWidth: lineWidth, wrapWidth: wrapWidth, wrapParts: wrapStart..<wrapParts.count,
                                          wrapOverrides: wrapOverrides, isCoreGeometry: isCoreGeometry)
        }
        return box
    }

    func arity(_ node: MathMLNode, _ count: Int) throws {
        guard node.children.count == count else { throw MathLayoutError.invalidMarkup(node.name) }
    }

    /// The width lines break to, `MathLayout`'s `maximumWidth`, and the width a table, fraction,
    /// radical or enclosure wraps its content to stay within: the same, or less to leave room
    /// for what stands beside it.
    var lineWidth = CGFloat.infinity, wrapWidth = CGFloat.infinity
    /// The widest of those that could be narrower still, the least it can be, and whether it is a table.
    var narrowable: (width: CGFloat, minimum: CGFloat, isTable: Bool)?
    /// Whether anything that wraps (a table, a fraction's part, a radicand, an enclosure's content)
    /// is wider than the least it can be, in any pass: a narrower `wrapWidth` may then narrow the
    /// formula. And the widest such thing in this pass: no `wrapWidth` beyond it changes anything.
    var mayNarrow = false
    var loosest: CGFloat = 0
    /// Stable traversal indices give each wrapping part its own budget on a retry.
    var wrapOverrides: [Int: CGFloat] = [:]
    var wrapParts: [(natural: CGFloat, width: CGFloat, minimum: CGFloat)] = []
    var nextWrapWidth: CGFloat { wrapOverrides[wrapParts.count] ?? wrapWidth }

    /// Starts the counts of untrusted input again, to lay the same formula out once more.
    func restart() {
        nodeCount = 0
        textLength = 0
        narrowable = nil
        loosest = 0
        wrapParts.removeAll(keepingCapacity: true)
    }

    // MARK: Embellished operators

    // These look down a subtree before it is laid out, which may be deeper than layout will go.
    // They are loops, not recursions: nothing stands between them and the end of the stack but
    // the margin `layout` asks for, and 64 levels of their frames were most of that.
    //
    // What they find of a list of children they keep. A row asks what each of its children is, and
    // for a child that is itself a row the answer may lie at the bottom of it; that row then asks
    // the same of its own children. Rows of spaces nested sixty deep were read once for every row
    // around them, and by `embellishedCore` once more for each of those: the cube of the depth.
    // The lists are the formula's own, so what is kept holds for every pass over it.

    /// For each list of children read so far: nil when some child is not space-like, else whether
    /// any says something. It is what `spaceLike` is of an `mrow` of them.
    private var spaceLikeLists = ListMemo<Bool?>()
    /// For each list of children asked about: where its one child in flow is, nil unless it has
    /// exactly one.
    private var flowOfLists = ListMemo<Int?>()
    /// For each list of children that a `semantics` has: where the first that is no annotation is.
    private var shownOfLists = ListMemo<Int?>()

    /// `shownIndex`, with what it finds of a `semantics`'s children kept: the look-ahead asks it
    /// of the same element from every row around it, and of the same list wherever a tree built
    /// by hand has it. Which child an `maction` shows is its attribute's to say, and takes no search.
    private func shownIndex(of node: MathMLNode) -> Int? {
        guard node.name == "semantics" else { return Self.shownIndex(node) }
        if let known = shownOfLists.answer(for: node.children) { return known }
        let index = Self.shownIndex(node)
        shownOfLists.keep(index, for: node.children)
        return index
    }

    /// The core `mo` of an embellished operator (MathML Core 3.2.4), or nil.
    func embellishedCore(_ node: MathMLNode) -> MathMLNode? {
        var node = node
        for _ in 0..<MathLimits.depth {
            switch node.name {
            case "mo": return node
            case "msub", "msup", "msubsup", "munder", "mover", "munderover", "mmultiscripts", "mfrac":
                guard let first = node.children.first else { return nil }
                node = first
            case "semantics", "maction":
                // The child that is drawn, which need not be the first (`shownChild`).
                guard let shown = shownIndex(of: node) else { return nil }
                node = node.children[shown]
            case "mrow", "mstyle", "mphantom", "mpadded":
                // Its one child in flow, when it has exactly one.
                guard let only = onlyInFlow(node.children) else { return nil }
                node = node.children[only]
            default: return nil
            }
        }
        return nil
    }

    /// Where in `children` the one that is not space-like is, when there is exactly one.
    private func onlyInFlow(_ children: [MathMLNode]) -> Int? {
        if let known = flowOfLists.answer(for: children) { return known }
        var only: Int?
        for index in children.indices where !isSpaceLike(children[index]) {
            guard only == nil else { only = nil; break }
            only = index
        }
        flowOfLists.keep(only, for: children)
        return only
    }

    /// Space-like elements (MathML Core 3.2.5) do not count when inferring an operator's form.
    /// An `mglyph` outside a token is the `mtext` it is laid out as.
    func isSpaceLike(_ node: MathMLNode) -> Bool { spaceLike(node) != nil }

    /// nil when `node` is not space-like, else whether it says something: an `mtext` with text or
    /// an `mglyph` in it, or what wraps one. MathML leaves such a child out when an operator
    /// takes its form from its place in the row, but beside an operator it is an operand, as
    /// TeX's `\text` is an ordinary atom: the `×` of
    /// "<mtext>principal</mtext><mo>×</mo><mtext>rate</mtext>" multiplies, it is not a sign.
    /// Phantom text retains the same operand spacing as visible text (MathML 3, 3.3.7.1).
    ///
    /// One walk of the subtree answers both, from a list of what is still to visit at each level:
    /// a row's children left to right, so the first that is not space-like ends the walk as early
    /// as it can end. What the walk finds of each list of children is kept (`spaceLikeLists`), and
    /// a list is read once however many rows there are around it to ask. So the walk needs no
    /// bound of its own: it uses no stack, and what is too deep layout refuses when it gets there.
    func spaceLike(_ node: MathMLNode) -> Bool? {
        // Most children of a row are tokens: no list for those.
        switch node.name {
        case "mtext": return Self.hasGlyph(node) || node.text.unicodeScalars.contains { !$0.properties.isWhitespace }
        case "mglyph": return true
        case "mspace", "maligngroup", "malignmark": return false
        case "mrow", "mstyle", "mphantom", "mpadded", "maction", "semantics": break
        default: return nil
        }
        // The lists being read, the innermost last: what is left of each, the whole of it when
        // what it turns out to be is to be kept, whether text in it is shown, and whether any
        // has been found there.
        var pending: [(rest: ArraySlice<MathMLNode>, whole: [MathMLNode]?, shows: Bool, says: Bool)] = [([node][...], nil, true, false)]
        walk: while let level = pending.indices.last {
            guard let node = pending[level].rest.popFirst() else {
                // Read to its end: all of it is space-like.
                let read = pending.removeLast()
                if let whole = read.whole { spaceLikeLists.keep(read.says, for: whole) }
                guard level > 0 else { return read.says }
                if read.says, read.shows { pending[level - 1].says = true }
                continue
            }
            switch node.name {
            case "mtext":
                if !pending[level].says {
                    pending[level].says = Self.hasGlyph(node) || node.text.unicodeScalars.contains { !$0.properties.isWhitespace }
                }
            case "mglyph": pending[level].says = true
            case "mspace", "maligngroup", "malignmark": break
            case "mrow", "mstyle", "mphantom", "mpadded":
                let children = node.children, shows = true
                guard let known = spaceLikeLists.answer(for: children) else {
                    pending.append((children[...], children, shows, false))
                    continue
                }
                guard let says = known else { break walk }
                if says, shows { pending[level].says = true }
            case "maction", "semantics":
                // Only what is shown (`shownChild`). Which child that is depends on the element and
                // not on its list of children alone, so nothing is kept for the list.
                guard let shown = shownIndex(of: node) else { break walk }
                pending.append((node.children[shown...shown], nil, true, false))
            default: break walk
            }
        }
        // Not space-like, and so neither is any list it was found in.
        for case let whole? in pending.map(\.whole) { spaceLikeLists.keep(nil, for: whole) }
        return nil
    }

    /// An `mo`'s text as drawn: hyphen-minus and apostrophe become the minus sign and prime,
    /// as browsers draw them. An `mglyph` is no part of it: an image names no operator, so the
    /// dictionary sees the text alone, and an `mo` of only an image is an unknown operator.
    func operatorText(_ node: MathMLNode) -> String {
        let text = Self.normalized(Self.unmarked(node.text))
        switch text {
        case "-": return "\u{2212}"
        case "'": return "\u{2032}"
        default: return text
        }
    }

    /// The form an `mo`'s own attribute names; nil without one, or with one that is not a form.
    func explicitForm(_ node: MathMLNode) -> OperatorForm? {
        switch node.attributes["form"]?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "prefix": .prefix
        case "postfix": .postfix
        case "infix": .infix
        default: nil
        }
    }

    func operatorForm(_ node: MathMLNode, _ inferred: OperatorForm?) -> OperatorForm {
        explicitForm(node) ?? inferred ?? .infix
    }

    func operatorFlags(_ core: MathMLNode, form: OperatorForm?) -> OperatorFlags {
        var flags = OperatorDictionary.entry(operatorText(core), form: operatorForm(core, form)).flags
        let attributes: [(String, OperatorFlags)] = [
            ("stretchy", .stretchy), ("symmetric", .symmetric), ("fence", .fence), ("separator", .separator),
            ("largeop", .largeop), ("movablelimits", .movablelimits), ("accent", .accent),
        ]
        for (name, flag) in attributes {
            if let value = core.attributes.flag(name) { if value { flags.insert(flag) } else { flags.remove(flag) } }
        }
        return flags
    }

    func properties(_ core: MathMLNode, form inferred: OperatorForm?, _ context: LayoutContext) -> OperatorProperties {
        let text = operatorText(core)
        let form = operatorForm(core, inferred)
        let entry = OperatorDictionary.entry(text, form: form)
        let flags = operatorFlags(core, form: inferred)
        // TeX drops binary and relation spacing in scripts; large operators keep theirs.
        let scale = context.scriptLevel > 0 && !flags.contains(.largeop) ? 0 : context.fontSize / 18
        let ownLspace = length(core.attributes["lspace"], context, reference: context.fontSize)
        let ownRspace = length(core.attributes["rspace"], context, reference: context.fontSize)
        let lspace = ownLspace ?? CGFloat(entry.lspace) * scale, rspace = ownRspace ?? CGFloat(entry.rspace) * scale
        let isBinary = entry.lspace == 4 && entry.rspace == 4
            && core.attributes["lspace"] == nil && core.attributes["rspace"] == nil
        return OperatorProperties(form: form, lspace: lspace, rspace: rspace, flags: flags,
                                  isHorizontal: OperatorDictionary.isHorizontal(text), isBinary: isBinary,
                                  isMarkedInfix: explicitForm(core) == .infix,
                                  dictionarySpacing: (entry.lspace, entry.rspace), ownSpacing: (ownLspace != nil, ownRspace != nil),
                                  breakPoint: BreakPoint(operator: text, entry, form: form, flags: flags, context.lines))
    }

    private func isStretchy(_ node: MathMLNode, form: OperatorForm?, horizontal: Bool) -> Bool {
        guard let core = embellishedCore(node) else { return false }
        return operatorFlags(core, form: form).contains(.stretchy)
            && OperatorDictionary.isHorizontal(operatorText(core)) == horizontal
    }

    func isHorizontallyStretchy(_ node: MathMLNode) -> Bool { isStretchy(node, form: nil, horizontal: true) }

    // MARK: Rows

    /// An `mrow` or inferred row: operators take their form from their position, vertical
    /// stretchy operators grow to cover the other children, and embellished operators get
    /// their spacing. A row whose only in-flow child is an embellished operator is one itself
    /// and passes `embellishment` down to it. An enclosing row then spaces it as a whole; with
    /// none (the root, a table cell, a radicand) it spaces the operator from its space-like
    /// neighbours itself, so "<mtext>a</mtext><mo>=</mo><mtext>b</mtext>" keeps its relation space.
    /// Text beside an operator is its operand (`spaceLike`), so every operator of a word equation,
    /// "assets − liabilities = equity", is spaced as it is between identifiers.
    ///
    /// Being an operator is a matter of form and spacing. Stretching is another: the one operator
    /// of such a row covers its space-like neighbours like any other (MathML 3, 3.2.5.8.2), so a
    /// bar beside a strut of `mspace` is as tall as the strut, and it covers with them what the
    /// enclosing row has the row cover. Operators with nothing at all to cover stretch to a size
    /// of zero, as in MathML Core 3.3.1.2, and that is their natural size unless a `minsize` asks
    /// for more: TeX's `\big(` is written `<mo minsize="1.2em" maxsize="1.2em">(</mo>`.
    func row(_ children: [MathMLNode], _ context: LayoutContext, _ embellishment: Embellishment = .none,
             depth: Int) throws -> MathBox {
        // Asked once of each child: nil when it is in flow, else whether it is text.
        let spaces = children.map { spaceLike($0) }
        let inFlow = children.indices.filter { spaces[$0] == nil }
        let core = inFlow.count == 1 && embellishedCore(children[inFlow[0]]) != nil ? inFlow[0] : nil
        // A row gives each child a form, so a form here means an enclosing row applies the spacing.
        let spacedByParent = embellishment.form != nil
        var forms = [OperatorForm](repeating: .infix, count: children.count)
        let texts = spaces.map { $0 == true }
        if inFlow.count > 1 {
            // Between two texts an operator is infix, though it is the first or last in-flow child.
            for (index, form) in [(inFlow[0], OperatorForm.prefix), (inFlow[inFlow.count - 1], .postfix)]
            where !(index > 0 && index + 1 < children.count && texts[index - 1] && texts[index + 1]) {
                forms[index] = form
            }
        }
        var boxes = [MathBox](repeating: .empty(), count: children.count)
        var deferred: [Int] = []
        for (index, child) in children.enumerated() {
            // The core is where this row is, in the row around it; any other child where it is in this one.
            let place = index == core ? embellishment : Embellishment(form: forms[index])
            if isStretchy(child, form: place.form, horizontal: false) {
                deferred.append(index)
            } else {
                boxes[index] = try layout(child, context, place, depth: depth + 1)
            }
        }
        if !deferred.isEmpty {
            // A set: a row may be ten thousand fences, and each child was looked for among them all.
            let stretched = Set(deferred)
            let others = boxes.indices.filter { !stretched.contains($0) }
            var ascents = others.map { boxes[$0].ascent }, descents = others.map { boxes[$0].descent }
            // The core covers its space-like neighbours, and with them what the row around this one
            // has the whole row cover.
            if let core, stretched.contains(core), case .vertical(let ascent, let descent) = embellishment.stretch {
                ascents.append(ascent); descents.append(descent)
            }
            // With nothing to cover the size to stretch to is zero (MathML Core 3.3.1.2), which
            // leaves an operator as it is unless it has a `minsize`.
            let stretch = Embellishment.Stretch.vertical(ascent: ascents.max() ?? 0, descent: descents.max() ?? 0)
            for index in deferred {
                let form = index == core ? embellishment.form : forms[index]
                boxes[index] = try layout(children[index], context, Embellishment(form: form, stretch: stretch),
                                          depth: depth + 1)
            }
        }
        // TeX's rule 5: a binary operator first, last, or after another operator or an opening
        // fence is unary and unspaced, as in "x = −3" or "(−3 + x)". Text counts among the atoms.
        // An operator whose `form` attribute says infix is what its author says it is.
        var unary = Set<Int>()
        let atoms = children.indices.filter { spaces[$0] != false }
        for (position, index) in atoms.enumerated()
        where boxes[index].op?.isBinary == true && boxes[index].op?.isMarkedInfix != true && index != core {
            let follows = position > 0 ? boxes[atoms[position - 1]].op.map(isOperatorLike) ?? false : true
            if follows || position == atoms.count - 1 { unary.insert(index) }
        }
        // The sides of the core operator this row spaces itself: those with something beside it.
        var spacesCore = (left: false, right: false)
        if let core, !spacedByParent {
            // And a side its author gave a space of its own (`lspace`, `rspace`), neighbour or none:
            // that is no inference from the dictionary for a row to withhold.
            let own = boxes[core].op?.ownSpacing ?? (lspace: false, rspace: false)
            spacesCore = (own.lspace || boxes[..<core].contains { $0.width > 0 }, own.rspace || boxes[(core + 1)...].contains { $0.width > 0 })
        }
        var box = MathBox()
        var x: CGFloat = 0
        var offsets: [CGFloat] = []
        for (index, child) in boxes.enumerated() {
            var lspace = child.op?.lspace ?? 0, rspace = child.op?.rspace ?? 0
            if index == core {
                if !spacesCore.left { lspace = 0 }
                if !spacesCore.right { rspace = 0 }
            } else if unary.contains(index) { lspace = 0; rspace = 0 }
            if children[index].name == "mo", operatorText(children[index]) == "\u{2061}", context.scriptLevel == 0,
               index > 0, index + 1 < children.count, !startsWithFence(children[index + 1]) {
                rspace = context.fontSize * 3 / 18 // A thin space after a function name, as TeX's \sin x.
            }
            x += lspace
            offsets.append(x)
            box.add(child, at: CGPoint(x: x, y: 0))
            x += child.width + rspace
            box.ascent = index == 0 ? child.ascent : max(box.ascent, child.ascent)
            box.descent = index == 0 ? child.descent : max(box.descent, child.descent)
        }
        box.width = x
        if boxes.count == 1 {
            box.italicCorrection = boxes[0].italicCorrection
            box.topAccentAttachment = boxes[0].topAccentAttachment
        }
        if let core {
            box.op = boxes[core].op
            // Spacing applied here is spent; the rest is for whoever lays this row out.
            if spacesCore.left { box.op?.lspace = 0 }
            if spacesCore.right { box.op?.rspace = 0 }
        }
        box.row = try breakableRow(children, boxes, at: offsets, unary: unary, box, context, depth: depth)
        return box
    }

    /// Operators after which a binary operator is unary: TeX's Bin, Rel, Open, Punct and Op
    /// atoms. Ellipses, closing fences and postfix operators are ordinary.
    private func isOperatorLike(_ op: OperatorProperties) -> Bool {
        op.isBinary || op.dictionarySpacing.lspace >= 5 || op.has(.separator) || op.has(.largeop)
            || op.has(.movablelimits) || (op.has(.fence) && op.form == .prefix)
    }

    private func startsWithFence(_ node: MathMLNode) -> Bool {
        switch node.name {
        case "mfenced": return true
        case "mrow": return node.children.first.map(startsWithFence) ?? false
        case "mo": return operatorFlags(node, form: .prefix).contains(.fence)
        default: return false
        }
    }

    /// `mfenced` as the row it abbreviates (MathML 3, 3.3.8).
    private func fenced(_ node: MathMLNode) -> [MathMLNode] {
        let open = node.attributes["open"] ?? "(", close = node.attributes["close"] ?? ")"
        let separators = Array((node.attributes["separators"] ?? ",").filter { !$0.isWhitespace })
        var inner: [MathMLNode] = []
        for (index, child) in node.children.enumerated() {
            if index > 0, !separators.isEmpty {
                inner.append(MathMLNode(name: "mo", attributes: ["separator": "true"],
                                        text: String(separators[min(index - 1, separators.count - 1)])))
            }
            inner.append(child)
        }
        var row: [MathMLNode] = []
        if !open.isEmpty { row.append(MathMLNode(name: "mo", attributes: ["fence": "true", "form": "prefix"], text: open)) }
        row.append(contentsOf: inner.count == 1 ? inner : [MathMLNode(name: "mrow", children: inner)])
        if !close.isEmpty { row.append(MathMLNode(name: "mo", attributes: ["fence": "true", "form": "postfix"], text: close)) }
        return row
    }

    // MARK: Tokens

    /// Token text with runs of XML whitespace collapsed to one space, and trimmed unless
    /// `trimming` is off: `mtext` keeps an edge space as browsers do, so "if " stays apart
    /// from what follows.
    static func normalized(_ text: String, trimming: Bool = true) -> String {
        guard text.unicodeScalars.contains(where: isXMLSpace) else { return text }
        var result = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if isXMLSpace(scalar) { pendingSpace = !trimming || !result.isEmpty; continue }
            if pendingSpace { result.append(" "); pendingSpace = false }
            result.append(scalar)
        }
        if pendingSpace, !trimming { result.append(" ") }
        return String(result)
    }

    private static func isXMLSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
    }

    func countText(_ text: String) throws {
        textLength += text.utf16.count
        guard textLength <= MathLimits.textLength else { throw MathLayoutError.limitExceeded }
    }

    /// `mi`, `mn`, `mtext` and `ms`. A single-character `mi` is italic unless a `mathvariant`
    /// says otherwise, and its width includes its italic correction (TeX's rule 17). An `mglyph`
    /// is not a character, so an `mi` of one stays upright even when its `alt` is drawn instead.
    private func token(_ node: MathMLNode, _ context: LayoutContext) throws -> MathBox {
        var (text, images) = try glyphContent(of: node, trimming: node.name != "mtext" && node.name != "ms", context)
        if node.name == "ms" {
            // The quotes are text, whatever they hold: only `mglyph`s have markers.
            text = Self.unmarked(node.attributes["lquote"] ?? "\"") + text + Self.unmarked(node.attributes["rquote"] ?? "\"")
        }
        try countText(text)
        var variant = context.variant
        if node.name == "mi", variant == nil, text.unicodeScalars.count == 1, !Self.hasGlyph(node) { variant = .italic }
        if let variant { text = variant.apply(to: text) }
        guard images.isEmpty else { return textBox(text, images: images, context, retainSegments: node.name == "mtext") }
        var box = textBox(text, context, retainSegments: node.name == "mtext")
        if let glyph = singleGlyph(box), let table = font.table {
            let size = context.fontSize
            if node.name == "mi", let correction = table.italicsCorrection(glyph) {
                box.italicCorrection = max(0, font.points(correction, size: size))
                box.width += box.italicCorrection
            }
            box.topAccentAttachment = table.topAccentAttachment(glyph).map { font.points($0, size: size) }
        }
        return box
    }

    /// Text shaped by CoreText with the math font; characters it lacks come from the
    /// system's fallback fonts.
    func textBox(_ text: String, _ context: LayoutContext, retainSegments: Bool = false) -> MathBox {
        guard !text.isEmpty else { return .empty() }
        let attributes = [kCTFontAttributeName: ctFont(context)] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes))
        var box = MathBox(width: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        var ink: CGRect?
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            let runAttributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = runAttributes[kCTFontAttributeName] as! CTFont
            var rects = [CGRect](repeating: .zero, count: count)
            CTFontGetBoundingRectsForGlyphs(runFont, .horizontal, glyphs, &rects, count)
            var runInk: CGRect?
            for (rect, position) in zip(rects, positions) where !rect.isEmpty {
                let placed = rect.offsetBy(dx: position.x, dy: position.y)
                runInk = runInk.map { $0.union(placed) } ?? placed
            }
            if let runInk { ink = ink.map { $0.union(runInk) } ?? runInk }
            box.items.append(.glyphs(GlyphRun(font: runFont, glyphs: glyphs, positions: positions,
                                              color: context.color, ink: runInk ?? .null)))
        }
        box.ascent = ink?.maxY ?? 0
        box.descent = ink.map { -$0.minY } ?? 0
        if retainSegments { box.textSegments = textSegments(text, line: line, box: box) }
        return box
    }

    /// The glyph when `box` is exactly one glyph of the math font.
    func singleGlyph(_ box: MathBox) -> CGGlyph? {
        guard box.items.count == 1, case .glyphs(let run) = box.items[0], run.glyphs.count == 1,
              CTFontCopyPostScriptName(run.font) == CTFontCopyPostScriptName(font.base) else { return nil }
        return run.glyphs[0]
    }

    /// One glyph of the math font at the context's size. A zero-advance glyph (a combining
    /// accent) is moved so its ink starts at the origin and its width is its ink's.
    func glyphBox(_ glyph: CGGlyph, _ context: LayoutContext) -> MathBox {
        let ctFont = font.font(size: context.fontSize)
        var glyph = glyph
        var rect = CGRect.zero, advance = CGSize.zero
        CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &glyph, &rect, 1)
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &advance, 1)
        let italic = font.table?.italicsCorrection(glyph).map { max(0, font.points($0, size: context.fontSize)) } ?? 0
        let shift = advance.width <= 0 && !rect.isEmpty ? -rect.minX : 0
        var box = MathBox(width: advance.width <= 0 ? rect.width : advance.width + italic,
                          ascent: rect.isEmpty ? 0 : rect.maxY, descent: rect.isEmpty ? 0 : -rect.minY)
        box.italicCorrection = italic
        box.topAccentAttachment = font.table?.topAccentAttachment(glyph).map { font.points($0, size: context.fontSize) + shift }
        box.items = [.glyphs(GlyphRun(font: ctFont, glyphs: [glyph], positions: [CGPoint(x: shift, y: 0)],
                                      color: context.color, ink: rect.isEmpty ? .null : rect.offsetBy(dx: shift, dy: 0)))]
        return box
    }

    // MARK: Operators

    private static let invisible: Set<String> = ["\u{2061}", "\u{2062}", "\u{2063}", "\u{2064}", ""]

    /// An `mo`: dictionary properties, the display size of large operators, and stretching.
    /// One with an `mglyph` is drawn as its author sized it, neither enlarged nor stretched.
    private func operatorBox(_ node: MathMLNode, _ context: LayoutContext, _ embellishment: Embellishment) throws -> MathBox {
        var text = operatorText(node)
        let properties = properties(node, form: embellishment.form, context)
        if Self.hasGlyph(node) {
            let content = try operatorGlyphContent(of: node, context)
            try countText(content.text)
            var box = textBox(context.variant?.apply(to: content.text) ?? content.text, images: content.images, context)
            box.op = properties
            return box
        }
        try countText(text)
        guard !Self.invisible.contains(text) else {
            var box = MathBox.empty()
            box.op = properties
            return box
        }
        if let variant = context.variant { text = variant.apply(to: text) }
        var box = textBox(text, context)
        let scalar = text.unicodeScalars.count == 1 ? text.unicodeScalars.first : nil
        let glyph = singleGlyph(box)
        if let glyph {
            box = glyphBox(glyph, context)
            if properties.has(.largeop), context.display { box = displayOperator(glyph, context) ?? box }
        }
        if properties.has(.stretchy), let stretch = embellishment.stretch {
            switch stretch {
            case .vertical(let ascent, let descent) where !properties.isHorizontal:
                box = stretchVertically(node, glyph: glyph, scalar: scalar, natural: box, ascent: ascent, descent: descent,
                                        symmetric: properties.has(.symmetric), context) ?? box
            case .horizontal(let width) where properties.isHorizontal:
                box = stretchHorizontally(glyph: glyph, scalar: scalar, natural: box, width: width, context) ?? box
            default: break
            }
        }
        // Inline operators keep their font baseline; axis-centering here belongs to
        // display-style large operators (MathML Core 3.2.4.3).
        if properties.has(.largeop), context.display { box = centered(box, on: value(\.axisHeight, context)) }
        box.op = properties
        return box
    }

    /// `box` moved vertically so its ink's middle is at `center`.
    func centered(_ box: MathBox, on center: CGFloat) -> MathBox {
        shifted(box, by: center - (box.ascent - box.descent) / 2)
    }

    func shifted(_ box: MathBox, by dy: CGFloat) -> MathBox {
        guard dy != 0 else { return box }
        var result = MathBox(width: box.width, ascent: box.ascent + dy, descent: box.descent - dy)
        result.italicCorrection = box.italicCorrection
        result.topAccentAttachment = box.topAccentAttachment
        result.op = box.op
        result.add(box, at: CGPoint(x: 0, y: dy))
        return result
    }
}

extension LayoutContext {
    func with(cramped: Bool) -> LayoutContext {
        var context = self
        context.cramped = cramped
        return context
    }
}

/// MathML colors: `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa` and the HTML 4 color keywords.
enum MathColor {
    private static let names: [String: UInt32] = [
        "black": 0x000000, "silver": 0xC0C0C0, "gray": 0x808080, "grey": 0x808080, "white": 0xFFFFFF,
        "maroon": 0x800000, "red": 0xFF0000, "purple": 0x800080, "fuchsia": 0xFF00FF, "magenta": 0xFF00FF,
        "green": 0x008000, "lime": 0x00FF00, "olive": 0x808000, "yellow": 0xFFFF00, "navy": 0x000080,
        "blue": 0x0000FF, "teal": 0x008080, "aqua": 0x00FFFF, "cyan": 0x00FFFF, "orange": 0xFFA500,
    ]

    static func parse(_ value: String) -> CGColor? {
        let text = value.trimmingCharacters(in: .whitespaces).lowercased()
        if text == "transparent" { return CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0) }
        if let rgb = names[text] { return color(rgb << 8 | 0xFF) }
        // Digits only: an integer may have a sign, and a colour may not.
        guard text.hasPrefix("#"), text.dropFirst().allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let number = UInt32(text.dropFirst(), radix: 16) else { return nil }
        switch text.count - 1 {
        case 3, 4:
            let digits = text.count - 1
            var expanded: UInt32 = 0
            for index in 0..<digits {
                let nibble = number >> (4 * UInt32(digits - 1 - index)) & 0xF
                expanded = expanded << 8 | nibble << 4 | nibble
            }
            return color(digits == 3 ? expanded << 8 | 0xFF : expanded)
        case 6: return color(number << 8 | 0xFF)
        case 8: return color(number)
        default: return nil
        }
    }

    private static func color(_ rgba: UInt32) -> CGColor {
        func channel(_ shift: UInt32) -> CGFloat { CGFloat(rgba >> shift & 0xFF) / 255 }
        return CGColor(srgbRed: channel(24), green: channel(16), blue: channel(8), alpha: channel(0))
    }
}
