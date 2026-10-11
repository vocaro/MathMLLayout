import CoreGraphics
import CoreText
import Foundation

/// Where a carry goes around the character it annotates (MathML 3, 3.6.5.2): a compass point.
private enum CarryLocation: String {
    case w, nw, n, ne, e, se, s, sw

    init?(attribute: String?) {
        guard let attribute else { return nil }
        self.init(rawValue: attribute.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

/// How the character under a carry is struck out (3.6.5.2). Several may be drawn at once.
private struct Crossout: OptionSet {
    let rawValue: UInt8
    static let up = Crossout(rawValue: 1), down = Crossout(rawValue: 2)
    static let vertical = Crossout(rawValue: 4), horizontal = Crossout(rawValue: 8)

    init(rawValue: UInt8) { self.rawValue = rawValue }

    /// nil without the attribute, so an `mscarry` takes its `mscarries`' value. `none` and
    /// unknown values add nothing.
    init?(attribute: String?) {
        guard let attribute else { return nil }
        self = []
        for value in attribute.split(whereSeparator: \.isWhitespace) {
            switch value.lowercased() {
            case "updiagonalstrike": insert(.up)
            case "downdiagonalstrike": insert(.down)
            case "verticalstrike": insert(.vertical)
            case "horizontalstrike": insert(.horizontal)
            default: break
            }
        }
    }
}

private struct Carry {
    var box: MathBox
    var location: CarryLocation
    var crossout: Crossout
    /// Its `mathcolor`, which also draws its crossout.
    var color: CGColor
}

/// One line of a stack, top to bottom: a row of digits, a row of carries, or a rule.
private struct StackLine {
    enum Kind { case digits, carries, rule }
    var kind: Kind
    /// The font size its strut, leading and strokes scale with.
    var em: CGFloat
    /// A rule's colour.
    var color: CGColor
    /// The column of its first cell, counted rightwards from the stack's alignment column, and
    /// how many columns it spans. A rule across the whole stack spans none of its own.
    var start = 0, count = 0
    /// What stands on the line's baseline in each column: digits, or the carries that go above
    /// the line below. nil is an empty column.
    var cells: [MathBox?] = []
    /// The cells that are characters of a number. They size their columns.
    var digits: Set<Int> = []
    /// A carries line's carries by column, before `arrange` decides which stay on the line.
    var carries: [Carry?] = []
    /// Carries of the line above that go beside or below this line's characters or strike them
    /// out, with their columns.
    var attached: [(column: Int, carry: Carry)] = []
    /// A carries line that another annotates takes room even when it draws nothing (3.6.5.1).
    var isAnnotated = false
    /// `mathbackground` of the row, its `mstyle`s and its numbers, by range of cells. A rule has
    /// no cells, and its own is behind the whole of it.
    var backgrounds: [(cells: Range<Int>, color: CGColor)] = []
    /// `mathbackground` of each `msgroup` whose first line this is, outermost first, with the
    /// number of lines in the group.
    var groups: [(lines: Int, color: CGColor)] = []
    /// A rule's thickness, and how far it runs past its columns.
    var thickness: CGFloat = 0
    var overhang: (left: CGFloat, right: CGFloat) = (0, 0)
}

/// What an `mstack` or `mlongdiv` settles for all its lines (3.6.1.2).
private struct StackStyle {
    enum Align { case left, center, right, decimalPoint }
    var align = Align.decimalPoint
    /// Where a cell narrower than its column goes: 0 left, 0.5 centre, 1 right (`charalign`).
    var charAlign: CGFloat = 1
    /// The space between columns (`charspacing`), and whether it grows to fit the widest carry.
    var gap: CGFloat
    var fitsCarries = true
    /// The `decimalpoint` character when the stack names one.
    var decimalPoint: String?
    /// The width of a column that holds no character: a "0"'s.
    var zeroWidth: CGFloat
    /// The height of the digits in ems. Every row is at least this tall, so rows are evenly spaced.
    var digitAscent: CGFloat

    /// The column a line of `count` cells starts in (`stackalign`): flush left or right of the
    /// alignment column, with its middle cell (the one right of the middle of an even count)
    /// there, or with its decimal point there. `position` then moves it that many columns
    /// towards the tens (3.6.3.2). `decimalPoint` is the cell holding the point, or the one
    /// after the first number when the point is implied; a line with neither ends at the point.
    func firstColumn(count: Int, decimalPoint: Int?, position: Int) -> Int {
        let anchor = switch align {
        case .left: 0
        case .center: count / 2
        case .right: count
        case .decimalPoint: decimalPoint ?? count
        }
        return -anchor - position
    }

    /// Whether a cell's text is the decimal point: the `decimalpoint` in effect, else "." (the
    /// default) or U+066B, which is nothing but a decimal separator.
    static func isDecimalPoint(_ text: String, _ decimalPoint: String?) -> Bool {
        decimalPoint.map { text == $0 } ?? (text == "." || text == "\u{066B}")
    }
}

/// A laid-out stack. `box` has its origin at the stack's top-left corner, so its content is at
/// or below y = 0; `aligned` then gives it a baseline.
private struct Stack {
    /// A line's extent, measured down from the top of the stack, and that of the columns its
    /// cells are in (the stack's when it has none).
    struct Band {
        var top: CGFloat, baseline: CGFloat, bottom: CGFloat
        var left: CGFloat, right: CGFloat

        func moved(by offset: CGFloat) -> Band {
            Band(top: top + offset, baseline: baseline + offset, bottom: bottom + offset, left: left, right: right)
        }
    }
    var box = MathBox()
    var width: CGFloat = 0
    var height: CGFloat = 0
    /// One for each line.
    var bands: [Band] = []
    /// Those of the rows of digits, the rows `align` counts.
    var rows: [Band] = []
}

/// `longdivstyle` (3.6.2.2): where the divisor and the result go around the dividend.
private enum LongDivision: String {
    case leftTop = "lefttop", stackedRightRight = "stackedrightright"
    case mediumStackedRightRight = "mediumstackedrightright", shortStackedRightRight = "shortstackedrightright"
    case rightTop = "righttop", leftSlashRight = "left/\\right", leftParenRight = "left)(right"
    case colonRightEqualsRight = ":right=right", stackedLeftLeft = "stackedleftleft"
    case stackedLeftLineTop = "stackedleftlinetop"

    /// An unknown value is ignored, as the specification allows. Its list of notations also
    /// calls the medium one "mediumrightright".
    init(attribute: String?) {
        let name = attribute?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        self = name == "mediumrightright" ? .mediumStackedRightRight : LongDivision(rawValue: name) ?? .leftTop
    }

    /// The result is a row of the dividend's stack, above it, so their digits share columns.
    var hasResultOnTop: Bool { self == .leftTop || self == .rightTop || self == .stackedLeftLineTop }
}

/// Elementary math (MathML 3, 3.6): `mstack` and `mlongdiv` with their `msgroup`, `msrow`,
/// `mscarries`, `mscarry` and `msline` children. MathML Core leaves these out, so the rules are
/// MathML 3's, with choices of this engine's where it says nothing: the leading between rows,
/// the room `charspacing`'s keywords give a carry, and the drawing of each division notation.
extension LayoutEngine {
    /// An `mstack` or `mlongdiv`, as one box. One of their children met outside them is laid
    /// out as a stack of its own, as an `mtr` is outside a table.
    func elementaryMath(_ node: MathMLNode, _ context: LayoutContext, depth: Int) throws -> MathBox {
        switch node.name {
        case "mstack": break
        case "mlongdiv": return try longDivision(node, context, depth: depth)
        default:
            // `layout` has applied the element's own size and level, which are relative, and
            // paints its background over the whole box.
            var child = node
            for name in ["mathbackground", "mathsize", "fontsize", "scriptlevel"] { child.attributes[name] = nil }
            if child.name == "mscarry" { child = MathMLNode(name: "mscarries", children: [child]) }
            return try elementaryMath(MathMLNode(name: "mstack", children: [child]), context, depth: depth)
        }
        let style = stackStyle(node, context)
        var lines: [StackLine] = []
        try collect(node.children, position: 0, shift: 0, style, context, depth: depth + Self.stackDepth, into: &lines)
        let stack = try arrange(lines, style, context)
        return aligned(stack.box, width: stack.width, height: stack.height, rows: stack.rows, node, context)
    }

    /// How far down a stack's or a long division's children count. Depth is what bounds the
    /// stack layout uses (`MathLimits.depth`), and a child here is reached through several frames
    /// of this file where another element's is through one: about twice the stack a level, which
    /// nested 45 deep overflowed a secondary thread's half megabyte. So they count as two levels.
    private static let stackDepth = 2

    private static let uncounted = MathMLNode(name: "none")

    /// Counts an element that is walked without `layout` (a group, a row, a rule or a `none`
    /// here, and a table's row) against the node and depth limits. Only `layout` keeps that
    /// count, so it lays out an empty element.
    func visit(_ context: LayoutContext, depth: Int) throws {
        _ = try layout(Self.uncounted, context, depth: depth)
    }

    /// An attribute that counts columns (`position`, `shift`, `length`), bounded so that sums
    /// of them cannot overflow. What a stack may span is bounded in `arrange`.
    private static func columns(_ node: MathMLNode, _ name: String) -> Int {
        let value = node.attributes[name].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0
        return min(max(value, -(1 << 31)), 1 << 31)
    }

    /// A token's characters for the grid: whitespace collapsed and trimmed, without the marker
    /// that stands for an `mglyph` child. A column of digits draws no image.
    private static func characters(_ node: MathMLNode) -> String {
        normalized(node.text.replacingOccurrences(of: "\u{FFFC}", with: ""))
            .trimmingCharacters(in: CharacterSet(charactersIn: " "))
    }

    /// An element's `decimalpoint` (3.3.4.2), when it names a character.
    private static func decimalPoint(_ node: MathMLNode) -> String? {
        node.attributes["decimalpoint"].map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The attributes of the stack itself. `decimalpoint` is `mstyle`'s to set (3.3.4.2), so it
    /// comes down the context; one on the stack, or on an `mstyle` in a row, takes its place.
    private func stackStyle(_ node: MathMLNode, _ context: LayoutContext) -> StackStyle {
        func keyword(_ name: String) -> String? { node.attributes[name]?.trimmingCharacters(in: .whitespaces).lowercased() }
        let em = context.fontSize
        let zero = textBox("0", context).width
        // `charspacing`'s keywords are this engine's: digits that touch, a tenth or a quarter
        // of an em apart, each widened by what the widest carry needs. A length is used as is.
        var style = StackStyle(gap: 0.1 * em, decimalPoint: Self.decimalPoint(node) ?? context.decimalPoint, zeroWidth: zero,
                               digitAscent: textBox("0123456789", context).ascent / em)
        switch keyword("charspacing") {
        case nil, "medium": break
        case "tight": style.gap = 0
        case "loose": style.gap = 0.25 * em
        case let attribute?:
            guard let fixed = length(attribute, context, reference: zero) else { break }
            style.gap = max(fixed, 0)
            style.fitsCarries = false
        }
        switch keyword("stackalign") {
        case "left": style.align = .left
        case "center": style.align = .center
        case "right": style.align = .right
        default: break
        }
        switch keyword("charalign") {
        case "left": style.charAlign = 0
        case "center": style.charAlign = 0.5
        default: break
        }
        return style
    }

    // MARK: Lines

    /// Appends the lines of a stack's or a group's `children`, top to bottom (3.6.1.1). They
    /// start at `position`, and each child after the first is `shift` columns further than the
    /// one before, whatever it is (3.6.3.2). Anything but a group, a row, carries or a rule is
    /// a row of its own.
    private func collect(_ children: [MathMLNode], position: Int, shift: Int, _ style: StackStyle,
                         _ context: LayoutContext, depth: Int, into lines: inout [StackLine]) throws {
        for (index, child) in children.enumerated() {
            let position = position + index * shift
            switch child.name {
            case "msgroup":
                try visit(context, depth: depth)
                let start = lines.count
                try collect(child.children, position: position + Self.columns(child, "position"),
                            shift: Self.columns(child, "shift"), style, inherit(child, context), depth: depth + 1, into: &lines)
                // A group draws nothing of its own, so its background is that of its lines together.
                if let background = child.attributes["mathbackground"].flatMap(MathColor.parse), lines.count > start {
                    lines[start].groups.insert((lines.count - start, background), at: 0)
                }
            case "msrow":
                try visit(context, depth: depth)
                var line = try digitRow(child.children, position: position + Self.columns(child, "position"), style,
                                        inherit(child, context), depth: depth + 1)
                if let background = child.attributes["mathbackground"].flatMap(MathColor.parse) {
                    line.backgrounds.insert((0..<line.cells.count, background), at: 0)
                }
                lines.append(line)
            case "mscarries":
                lines.append(try carriesRow(child, position: position + Self.columns(child, "position"), style, context,
                                            depth: depth))
            case "msline":
                lines.append(try rule(child, position: position + Self.columns(child, "position"), style, context,
                                      depth: depth))
            default:
                lines.append(try digitRow([child], position: position, style, context, depth: depth))
            }
        }
    }

    /// A row of digits (3.6.4): each character of an `mn` takes a column, any other element
    /// takes one, `none` leaves one empty, and an `mstyle` only styles its children, which are
    /// the row's. The digits of a number are laid out as numbers of one character, so they keep
    /// the `mn`'s attributes and count as nodes and text like any token.
    private func digitRow(_ children: [MathMLNode], position: Int, _ style: StackStyle, _ context: LayoutContext,
                          depth: Int) throws -> StackLine {
        var line = StackLine(kind: .digits, em: context.fontSize, color: context.color)
        var point: Int?
        func append(_ children: [MathMLNode], _ context: LayoutContext, decimalPoint: String?, depth: Int) throws {
            for child in children {
                let first = line.cells.count
                var background = child.attributes["mathbackground"].flatMap(MathColor.parse)
                switch child.name {
                case "mstyle":
                    try visit(context, depth: depth)
                    try append(child.children, inherit(child, context), decimalPoint: Self.decimalPoint(child) ?? decimalPoint,
                               depth: depth + 1)
                case "none":
                    try visit(context, depth: depth)
                    line.cells.append(nil)
                case "mn":
                    var attributes = child.attributes
                    attributes["mathbackground"] = nil
                    let text = Self.characters(child)
                    if text.isEmpty { try visit(context, depth: depth) }
                    for character in text {
                        let digit = String(character)
                        let cell = try layout(MathMLNode(name: "mn", attributes: attributes, text: digit), context, depth: depth)
                        // A space in a number (between groups of three, say) is a column as wide as a space.
                        line.digits.insert(line.cells.count)
                        line.cells.append(digit == " " ? .empty(width: textBox(digit, inherit(child, context)).width) : cell)
                        if point == nil, StackStyle.isDecimalPoint(digit, decimalPoint) { point = line.cells.count - 1 }
                    }
                default:
                    // The element paints its own background.
                    background = nil
                    line.cells.append(try layout(child, context, depth: depth))
                    if point == nil, Self.tokens.contains(child.name),
                       StackStyle.isDecimalPoint(Self.characters(child), decimalPoint) { point = first }
                }
                if let background, first < line.cells.count { line.backgrounds.append((first..<line.cells.count, background)) }
            }
        }
        try append(children, context, decimalPoint: style.decimalPoint, depth: depth)
        line.count = line.cells.count
        // Without a point, one is implied after the row's first number (3.6.1.2): here its
        // first run of digits, so a number written as one `mn` a digit aligns like any other.
        if point == nil, var end = line.digits.min() {
            while line.digits.contains(end) { end += 1 }
            point = end
        }
        line.start = style.firstColumn(count: line.count, decimalPoint: point, position: position)
        return line
    }

    /// An `mscarries` (3.6.5): its children are not in display style, a script level down, at
    /// 0.6 of the size unless a `scriptsizemultiplier` is set on it or inherited. Each child but
    /// `none` is a carry, and an `mscarry` may give its own `location` and `crossout` (3.6.6).
    private func carriesRow(_ node: MathMLNode, position: Int, _ style: StackStyle, _ outer: LayoutContext,
                            depth: Int) throws -> StackLine {
        try visit(outer, depth: depth)
        var context = inherit(node, outer)
        context.display = false
        let multiplier = node.attributes["scriptsizemultiplier"].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        context.sizeMultiplier = multiplier.flatMap { $0 > 0.1 && $0 <= 10 ? CGFloat($0) : nil } ?? context.sizeMultiplier ?? 0.6
        setScriptLevel(&context, context.scriptLevel + 1)
        let location = CarryLocation(attribute: node.attributes["location"]) ?? .n
        let crossout = Crossout(attribute: node.attributes["crossout"]) ?? []
        var line = StackLine(kind: .carries, em: context.fontSize, color: context.color)
        for child in node.children {
            switch child.name {
            case "none":
                try visit(context, depth: depth + 1)
                line.carries.append(nil)
            case "mscarry":
                try visit(context, depth: depth + 1)
                let inner = inherit(child, context)
                var box = try child.children.count == 1 ? layout(child.children[0], inner, depth: depth + 2)
                    : layout(MathMLNode(name: "mrow", children: child.children), inner, depth: depth + 1)
                if let background = child.attributes["mathbackground"].flatMap(MathColor.parse), box.width > 0 {
                    box.items.insert(.rect(CGRect(x: 0, y: -box.descent, width: box.width, height: box.height), background), at: 0)
                }
                line.carries.append(Carry(box: box, location: CarryLocation(attribute: child.attributes["location"]) ?? location,
                                          crossout: Crossout(attribute: child.attributes["crossout"]) ?? crossout,
                                          color: inner.color))
            default:
                line.carries.append(Carry(box: try layout(child, context, depth: depth + 1), location: location,
                                          crossout: crossout, color: context.color))
            }
        }
        line.count = line.carries.count
        line.start = style.firstColumn(count: line.count, decimalPoint: nil, position: position)
        if let background = node.attributes["mathbackground"].flatMap(MathColor.parse) {
            line.backgrounds.append((0..<line.count, background))
        }
        return line
    }

    /// An `msline` (3.6.7): `length` columns, placed as a number of that many digits would be,
    /// or the whole width of the stack when 0. Thickness keywords are `mfrac`'s.
    private func rule(_ node: MathMLNode, position: Int, _ style: StackStyle, _ outer: LayoutContext,
                      depth: Int) throws -> StackLine {
        try visit(outer, depth: depth)
        let context = inherit(node, outer)
        let standard = value(\.fractionRuleThickness, context)
        var line = StackLine(kind: .rule, em: context.fontSize, color: context.color)
        line.thickness = switch node.attributes["mslinethickness"]?.trimmingCharacters(in: .whitespaces).lowercased() {
        case nil, "medium": standard
        case "thin": standard / 2
        case "thick": standard * 2
        case let attribute?: min(max(length(attribute, context, reference: standard) ?? standard, 0), context.fontSize)
        }
        line.count = max(Self.columns(node, "length"), 0)
        line.start = style.firstColumn(count: line.count, decimalPoint: nil, position: position)
        line.overhang = (length(node.attributes["leftoverhang"], context, reference: style.zeroWidth) ?? 0,
                         length(node.attributes["rightoverhang"], context, reference: style.zeroWidth) ?? 0)
        if let background = node.attributes["mathbackground"].flatMap(MathColor.parse) { line.backgrounds.append((0..<0, background)) }
        return line
    }

    // MARK: The grid

    /// Places `lines` in a grid of columns (3.6.1.1). A column is as wide as its widest digit,
    /// or as a "0" when it is empty; carries have no width, so the grid does not grow for
    /// them, though `charspacing`'s keywords space the columns to fit them. Rows are a strut
    /// high with leading above and below, so they are evenly spaced and a rule between two
    /// adds only its thickness.
    private func arrange(_ lines: [StackLine], _ style: StackStyle, _ context: LayoutContext) throws -> Stack {
        var lines = lines
        // Carries annotate the line after them (3.6.5.1). Those that go above it stay on their
        // own line; the others, and every crossout, go with the line they annotate. With no row
        // to annotate (a rule follows, or nothing) they all stay, as a row of small digits.
        for index in lines.indices where lines[index].kind == .carries {
            let annotates = index + 1 < lines.count && lines[index + 1].kind != .rule
            if annotates, lines[index + 1].kind == .carries { lines[index + 1].isAnnotated = true }
            for (offset, carry) in lines[index].carries.enumerated() {
                let isAbove = carry.map { !annotates || $0.location == .n } ?? false
                lines[index].cells.append(isAbove ? carry?.box : nil)
                guard var carry, annotates, !isAbove || !carry.crossout.isEmpty else { continue }
                // A carry that leaves its line takes the background of its `mscarries` with it, behind its own.
                if !isAbove, carry.box.width > 0, let background = lines[index].backgrounds.first?.color {
                    let box = carry.box
                    carry.box.items.insert(.rect(CGRect(x: 0, y: -box.descent, width: box.width, height: box.height), background), at: 0)
                }
                lines[index + 1].attached.append((lines[index].start + offset, carry))
            }
        }
        // The columns any line reaches. `position`, `shift` and `length` cost an author nothing,
        // so a stack may span no more columns than a formula may have nodes, and each column
        // beyond its cells, which are nodes already, counts as one: or every stack of a formula
        // could span that many, 200 million columns for 20,000 nodes.
        let spanning = lines.filter { $0.count > 0 }
        let first = spanning.map(\.start).min() ?? 0
        let columns = spanning.map { $0.start + $0.count - first }.max() ?? 0
        guard columns <= MathLimits.nodes else { throw MathLayoutError.limitExceeded }
        for _ in 0..<max(0, columns - lines.reduce(0) { $0 + $1.cells.count }) { try visit(context, depth: 0) }
        // Digits size their columns. Anything else (an operator, say) sizes only a column that
        // holds no digit, and elsewhere overflows, so a sign beside one number leaves no gap in
        // another.
        var widths = [CGFloat](repeating: 0, count: columns)
        var hasDigits = [Bool](repeating: false, count: columns)
        for sizing in [true, false] {
            for line in lines where line.kind == .digits {
                for (offset, cell) in line.cells.enumerated() where line.digits.contains(offset) == sizing {
                    let column = line.start - first + offset
                    if let cell, sizing || !hasDigits[column] { widths[column] = max(widths[column], cell.width) }
                }
            }
            if sizing { hasDigits = widths.map { $0 > 0 } }
        }
        for column in widths.indices where widths[column] <= 0 { widths[column] = style.zeroWidth }
        var gap = style.gap
        if style.fitsCarries {
            // A carry above or below a column may be as wide as the column and the gap; one
            // beside a character needs the whole gap.
            var widest: CGFloat = 0
            for line in lines {
                for (offset, cell) in line.cells.enumerated() where line.kind == .carries {
                    if let cell { widest = max(widest, cell.width - widths[line.start - first + offset]) }
                }
                for (column, carry) in line.attached where carry.location != .n {
                    widest = max(widest, carry.box.width - (carry.location == .s ? widths[column - first] : 0))
                }
            }
            gap += widest
        }
        var lefts = [CGFloat](repeating: 0, count: columns)
        for column in widths.indices.dropFirst() { lefts[column] = lefts[column - 1] + widths[column - 1] + gap }
        let width = columns > 0 ? lefts[columns - 1] + widths[columns - 1] : 0

        // Where each cell starts, from the last line up. A carry is centred over the character
        // under it. A digit goes where `charalign` says, and so does what is too wide for its
        // column, overflowing on the other side (3.6.1.2), except at an end of a row, where
        // it overflows away from the row: a leading sign to the left, a trailing one to the right.
        var origins = [[CGFloat]](repeating: [], count: lines.count)
        /// The character line `index` has in `column`, and where it starts.
        func character(_ index: Int, _ column: Int) -> (x: CGFloat, box: MathBox)? {
            guard lines.indices.contains(index) else { return nil }
            let offset = column - lines[index].start
            guard lines[index].cells.indices.contains(offset), let box = lines[index].cells[offset],
                  !box.items.isEmpty else { return nil }
            return (origins[index][offset], box)
        }
        for index in lines.indices.reversed() {
            let line = lines[index]
            let leading = line.cells.firstIndex { $0 != nil }, trailing = line.cells.lastIndex { $0 != nil }
            origins[index] = line.cells.enumerated().map { offset, box in
                let column = line.start - first + offset
                guard let box else { return lefts[column] }
                if line.kind == .carries {
                    guard let below = character(index + 1, line.start + offset) else {
                        return lefts[column] + (widths[column] - box.width) / 2
                    }
                    return below.x + (below.box.width - box.width) / 2
                }
                var align = style.charAlign
                if box.width > widths[column], leading != trailing {
                    if offset == leading { align = 1 } else if offset == trailing { align = 0 }
                }
                return lefts[column] + (widths[column] - box.width) * align
            }
        }
        /// Where a carry attached to line `index` goes around the character in `column`,
        /// from the left end of the line's baseline: beside it at mid-height (w, e), raised
        /// or lowered as a script would be (nw, ne, sw, se), or centred under it (s).
        func origin(of carry: Carry, on index: Int, _ column: Int) -> CGPoint {
            let em = lines[index].em, target = character(index, column), box = carry.box
            let left = target?.x ?? lefts[column - first], width = target?.box.width ?? widths[column - first]
            let ascent = target?.box.ascent ?? style.digitAscent * em, descent = target?.box.descent ?? 0
            let x: CGFloat = switch carry.location {
            case .nw, .w, .sw: left - box.width
            case .ne, .e, .se: left + width
            case .n, .s: left + (width - box.width) / 2
            }
            let y: CGFloat = switch carry.location {
            case .nw, .ne: constants.superscriptShiftUp * em
            case .sw, .se: -constants.subscriptShiftDown * em
            case .w, .e: (ascent - descent) / 2 - (box.ascent - box.descent) / 2
            case .s: -(max(descent, 0) + 0.1 * em + box.ascent)
            case .n: 0
            }
            return CGPoint(x: x, y: y)
        }

        var stack = Stack(width: width)
        var y: CGFloat = 0
        var isUnderCarries = false
        for (index, line) in lines.enumerated() {
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let isDrawn = line.cells.contains { $0.map { !$0.items.isEmpty } ?? false }
            if line.kind == .rule {
                // Two rules in a row are a double rule, not a thick one.
                if index > 0, lines[index - 1].kind == .rule { y += max(2 * line.thickness, 0.1 * line.em) }
                descent = line.thickness
            } else if line.kind == .digits || isDrawn || line.isAnnotated {
                ascent = style.digitAscent * line.em
                for case let cell? in line.cells {
                    ascent = max(ascent, cell.ascent); descent = max(descent, cell.descent)
                }
                for (column, carry) in line.attached where carry.location != .n {
                    let at = origin(of: carry, on: index, column)
                    ascent = max(ascent, at.y + carry.box.ascent); descent = max(descent, carry.box.descent - at.y)
                }
                // Digits get a fifth of an em above (half that under their carries) and stand a
                // quarter of an em above the next line, which clears a comma. Carries sit on
                // the line they annotate.
                ascent += (isUnderCarries ? 0.1 : 0.2) * line.em
                if line.kind == .digits { descent = max(0.25 * line.em, descent + 0.1 * line.em) }
            }
            isUnderCarries = line.kind == .carries && ascent > 0
            var band = Stack.Band(top: y, baseline: y + ascent, bottom: y + ascent + descent, left: 0, right: width)
            if let leading = line.cells.firstIndex(where: { $0 != nil }),
               let trailing = line.cells.lastIndex(where: { $0 != nil }) {
                band.left = lefts[line.start - first + leading]
                band.right = lefts[line.start - first + trailing] + widths[line.start - first + trailing]
            }
            stack.bands.append(band)
            if line.kind == .digits { stack.rows.append(band) }
            y = band.bottom
        }
        stack.height = y

        /// The ends of the columns that the cells `range` of line `index` are in.
        func ends(ofColumns range: Range<Int>, on index: Int) -> (left: CGFloat, right: CGFloat) {
            let from = lines[index].start - first + range.lowerBound, to = lines[index].start - first + range.upperBound - 1
            return (lefts[from], lefts[to] + widths[to])
        }
        /// How far the cells `range` of line `index` reach: the ends of their columns, or of a
        /// cell that overflows them. A background is behind all of what it is the background of.
        func ends(of range: Range<Int>, on index: Int) -> (left: CGFloat, right: CGFloat) {
            var (left, right) = ends(ofColumns: range, on: index)
            for offset in range {
                guard let cell = lines[index].cells[offset] else { continue }
                left = min(left, origins[index][offset]); right = max(right, origins[index][offset] + cell.width)
            }
            return (left, right)
        }
        /// The ends of the rule that is line `index`, with its overhangs.
        func ends(ofRule index: Int) -> (left: CGFloat, right: CGFloat) {
            let line = lines[index]
            let (left, right) = line.count > 0 ? ends(ofColumns: 0..<line.count, on: index) : (0, width)
            return (left - line.overhang.left, right + line.overhang.right)
        }
        var backgrounds: [MathItem] = [], groups: [MathItem] = []
        for (index, line) in lines.enumerated() {
            let band = stack.bands[index]
            // A group's background goes behind those of its lines: from the top of its first line
            // to the bottom of its last, and as far each way as any of them reaches, which for a
            // row counts the carries of the group that stand beside its characters.
            for (count, color) in line.groups {
                var left = CGFloat.infinity, right = -CGFloat.infinity
                for member in index..<index + count {
                    let inner = lines[member]
                    if inner.kind == .rule || !inner.cells.isEmpty {
                        let reach = inner.kind == .rule ? ends(ofRule: member) : ends(of: inner.cells.indices, on: member)
                        if reach.left < reach.right { left = min(left, reach.left); right = max(right, reach.right) }
                    }
                    for (column, carry) in inner.attached where member > index && carry.location != .n && carry.box.width > 0 {
                        let x = origin(of: carry, on: member, column).x
                        left = min(left, x); right = max(right, x + carry.box.width)
                    }
                }
                let bottom = stack.bands[index + count - 1].bottom
                if left < right, band.top < bottom {
                    groups.append(.rect(CGRect(x: left, y: -bottom, width: right - left, height: bottom - band.top), color))
                }
            }
            if line.kind == .rule {
                let (left, right) = ends(ofRule: index)
                if left < right, line.thickness > 0 {
                    let rect = CGRect(x: left, y: -band.bottom, width: right - left, height: line.thickness)
                    backgrounds += line.backgrounds.map { .rect(rect, $0.color) }
                    stack.box.items.append(.rect(rect, line.color))
                }
                continue
            }
            // A row of carries that all stand beside the characters under them has no height to fill.
            for (cells, color) in line.backgrounds where !cells.isEmpty && band.top < band.bottom {
                let (left, right) = ends(of: cells, on: index)
                backgrounds.append(.rect(CGRect(x: left, y: -band.bottom, width: right - left, height: band.bottom - band.top), color))
            }
            for (offset, cell) in line.cells.enumerated() {
                if let cell { stack.box.add(cell, at: CGPoint(x: origins[index][offset], y: -band.baseline)) }
            }
            for (column, carry) in line.attached {
                if carry.location != .n {
                    let at = origin(of: carry, on: index, column)
                    stack.box.add(carry.box, at: CGPoint(x: at.x, y: at.y - band.baseline))
                }
                // A crossout strikes the character under the carry, a little past its corners.
                guard !carry.crossout.isEmpty, let target = character(index, column) else { continue }
                let pad = 0.08 * line.em
                let frame = CGRect(x: target.x, y: -band.baseline - target.box.descent, width: target.box.width,
                                   height: target.box.height).insetBy(dx: -pad, dy: -pad)
                let path = CGMutablePath()
                func strike(_ from: CGPoint, _ to: CGPoint) { path.move(to: from); path.addLine(to: to) }
                if carry.crossout.contains(.up) {
                    strike(CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.maxY))
                }
                if carry.crossout.contains(.down) {
                    strike(CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.minY))
                }
                if carry.crossout.contains(.vertical) {
                    strike(CGPoint(x: frame.midX, y: frame.minY), CGPoint(x: frame.midX, y: frame.maxY))
                }
                if carry.crossout.contains(.horizontal) {
                    strike(CGPoint(x: frame.minX, y: frame.midY), CGPoint(x: frame.maxX, y: frame.midY))
                }
                stack.box.items.append(.path(path, lineWidth: constants.overbarRuleThickness * line.em, color: carry.color,
                                             fill: false))
            }
        }
        stack.box.items.insert(contentsOf: groups + backgrounds, at: 0)
        return stack
    }

    /// The finished box: `content`, whose origin is its top-left corner, with the baseline that
    /// `align` asks for (3.6.1.2). The values are `mtable`'s: `top`, `bottom`, `center` or
    /// `baseline` (the default; both put the middle on the baseline) and `axis`, each for the
    /// whole stack or for the row whose number follows. A row's axis is as far above its
    /// baseline as the surrounding one's, so `axis` with a row is `baseline` with it.
    ///
    /// The specification leaves what overflows a column out of the stack's size (3.6.1.1). A
    /// host clips to the formula's box, so this box grows to cover it.
    private func aligned(_ content: MathBox, width: CGFloat, height: CGFloat, rows: [Stack.Band], _ node: MathMLNode,
                         _ context: LayoutContext) -> MathBox {
        let parts = (node.attributes["align"] ?? "").split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        let alignment = parts.first ?? "baseline"
        let ascent: CGFloat
        if parts.count > 1, let number = Int(parts[1]), number != 0, !rows.isEmpty {
            let row = rows[number > 0 ? min(number, rows.count) - 1 : max(rows.count + number, 0)]
            ascent = switch alignment {
            case "top": row.top
            case "bottom": row.bottom
            case "center": (row.top + row.bottom) / 2
            default: row.baseline
            }
        } else {
            ascent = switch alignment {
            case "top": 0
            case "bottom": height
            case "axis": height / 2 + value(\.axisHeight, context)
            default: height / 2
            }
        }
        let ink = content.inkBounds?.offsetBy(dx: 0, dy: ascent) ?? .zero
        let left = max(0, -ink.minX)
        var box = MathBox(width: max(width + left, ink.maxX + left), ascent: max(ascent, ink.maxY),
                          descent: max(height - ascent, -ink.minY))
        box.add(content, at: CGPoint(x: left, y: ascent))
        return box
    }

    // MARK: Long division

    /// `mlongdiv` (3.6.2): a divisor and a result around the stack of the dividend and the
    /// work under it. Where the result goes above the dividend it is a row of that stack, so
    /// their digits share columns; elsewhere it and the divisor are stacks of their own, level
    /// with the dividend or stacked beside it. The specification names ten notations and shows
    /// one figure of each (3.6.8.3); the proportions here are this engine's.
    private func longDivision(_ node: MathMLNode, _ context: LayoutContext, depth: Int) throws -> MathBox {
        guard node.children.count >= 2 else { throw MathLayoutError.invalidMarkup(node.name) }
        let style = stackStyle(node, context), form = LongDivision(attribute: node.attributes["longdivstyle"])
        let em = context.fontSize, rule = value(\.fractionRuleThickness, context), pad = 0.2 * em, color = context.color
        func collected(_ children: [MathMLNode]) throws -> [StackLine] {
            var lines: [StackLine] = []
            try collect(children, position: 0, shift: 0, style, context, depth: depth + Self.stackDepth, into: &lines)
            return lines
        }
        /// The divisor or the result as a stack of its own; nil for `none`.
        func part(_ child: MathMLNode) throws -> Stack? {
            if child.name == "none" { try visit(context, depth: depth + 1); return nil }
            return try arrange(collected([child]), style, context)
        }
        let divisor = try part(node.children[0])
        var result: Stack?
        var lines: [StackLine] = []
        // Above the dividend, the result is the first of the stack's rows, and the bar under
        // it is a rule of the stack that runs on to meet the rest of the frame.
        var bar: Int?
        var left: CGFloat = 0
        if form.hasResultOnTop {
            lines = try collected(node.children[1].name == "none" ? [] : [node.children[1]])
            if lines.isEmpty { try visit(context, depth: depth + 1) }
            var line = StackLine(kind: .rule, em: em, color: color, thickness: rule)
            switch form {
            case .leftTop:
                left = (divisor.map { $0.width + 0.1 * em } ?? 0) + 0.3 * em + rule
                line.overhang.left = 0.3 * em + rule
            case .stackedLeftLineTop:
                left = pad + (divisor?.width ?? 0) + pad + rule + pad
                line.overhang.left = rule + pad
            default:
                line.overhang.right = 2 * pad + rule + pad + (divisor?.width ?? 0) + pad
            }
            bar = lines.count
            lines.append(line)
        } else {
            result = try part(node.children[1])
        }
        lines += try collected(Array(node.children.dropFirst(2)))
        // The dividend is the first row of digits. Without one, an empty row keeps the frame.
        var dividend = lines.indices.first { $0 > bar ?? -1 && lines[$0].kind == .digits }
        if dividend == nil {
            lines.append(StackLine(kind: .digits, em: em, color: color))
            dividend = lines.count - 1
        }
        let stack = try arrange(lines, style, context)
        let row = stack.bands[dividend!]

        // Everything is placed y down from the top of the dividend's stack, then moved so that
        // the top of the whole is at 0.
        var box = MathBox()
        var top: CGFloat = 0, bottom = stack.height, right: CGFloat = 0
        func place(_ part: Stack?, x: CGFloat, y: CGFloat) {
            guard let part else { return }
            box.add(part.box, at: CGPoint(x: x, y: -y))
            top = min(top, y); bottom = max(bottom, y + part.height); right = max(right, x + part.width)
        }
        /// The top of a part whose first row shares the dividend's baseline.
        func level(_ part: Stack?) -> CGFloat { row.baseline - (part?.rows.first?.baseline ?? part?.height ?? 0) }
        func horizontal(from start: CGFloat, to end: CGFloat, y: CGFloat) {
            box.items.append(.rect(CGRect(x: start, y: -y - rule, width: end - start, height: rule), color))
            bottom = max(bottom, y + rule); right = max(right, end)
        }
        func vertical(x: CGFloat, from start: CGFloat, to end: CGFloat) {
            box.items.append(.rect(CGRect(x: x, y: -end, width: rule, height: end - start), color))
            top = min(top, start); bottom = max(bottom, end); right = max(right, x + rule)
        }
        let divisorWidth = divisor?.width ?? 0, resultWidth = result?.width ?? 0
        /// The line under the divisor: below the dividend's row, and below the divisor.
        let under = max(row.bottom, level(divisor) + (divisor?.height ?? 0))
        switch form {
        case .leftTop:
            // divisor ) dividend, under a bar that carries the result.
            place(divisor, x: 0, y: level(divisor))
            let x = left - 0.3 * em - rule / 2, barY = stack.bands[bar!].top + rule / 2
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: -barY))
            path.addQuadCurve(to: CGPoint(x: x, y: -row.bottom), control: CGPoint(x: x + 0.35 * em, y: -(barY + row.bottom) / 2))
            box.items.append(.path(path, lineWidth: rule, color: color, fill: false))
            bottom = max(bottom, row.bottom + rule / 2)
        case .stackedLeftLineTop:
            // The divisor, underlined, left of a bar that turns down into a line before the
            // dividend; the result above the bar.
            let x = left - pad - rule
            place(divisor, x: pad, y: level(divisor))
            horizontal(from: 0, to: x + rule, y: under)
            vertical(x: x, from: stack.bands[bar!].top, to: under + rule)
        case .rightTop:
            // The result over a bar; under it the dividend, then the divisor in a corner of
            // the bar, a line before it and a line below it.
            let x = stack.width + 2 * pad
            place(divisor, x: x + rule + pad, y: level(divisor))
            vertical(x: x, from: stack.bands[bar!].top, to: under + rule)
            horizontal(from: x, to: x + rule + pad + divisorWidth + pad, y: under)
        case .stackedRightRight, .mediumStackedRightRight, .shortStackedRightRight:
            // The dividend, a vertical line, then the divisor over a line over the result. The
            // vertical line runs the height of the work, of the divisor and result, or of the
            // divisor alone, which then stands right after the dividend with the work free to
            // run on under it.
            let x = (form == .shortStackedRightRight ? row.right : stack.width) + pad
            place(divisor, x: x + rule + pad, y: level(divisor))
            horizontal(from: x, to: x + rule + pad + max(divisorWidth, resultWidth) + pad, y: under)
            place(result, x: x + rule + pad, y: under + rule)
            let resultBottom = under + rule + (result?.height ?? 0)
            switch form {
            case .stackedRightRight: vertical(x: x, from: min(0, level(divisor)), to: max(stack.height, resultBottom))
            case .mediumStackedRightRight: vertical(x: x, from: min(row.top, level(divisor)), to: resultBottom)
            default: vertical(x: x, from: min(row.top, level(divisor)), to: under + rule)
            }
        case .stackedLeftLeft:
            // The same, mirrored: divisor over result, flush against the line, then the dividend.
            let x = pad + max(divisorWidth, resultWidth) + pad
            left = x + rule + pad
            place(divisor, x: x - pad - divisorWidth, y: level(divisor))
            horizontal(from: 0, to: x, y: under)
            place(result, x: x - pad - resultWidth, y: under + rule)
            vertical(x: x, from: min(0, level(divisor)), to: max(stack.height, under + rule + (result?.height ?? 0)))
        case .leftSlashRight, .leftParenRight, .colonRightEqualsRight:
            // One line: divisor / dividend \ result, divisor ) dividend ( result, or
            // dividend : divisor = result. The signs go around the dividend's own digits, and
            // the work hangs under it, wherever it reaches.
            var x: CGFloat = 0
            let space = 0.25 * em
            func sign(_ text: String) {
                let glyph = textBox(text, context)
                box.add(glyph, at: CGPoint(x: x, y: -row.baseline))
                top = min(top, row.baseline - glyph.ascent); bottom = max(bottom, row.baseline + glyph.descent)
                x += glyph.width + space
            }
            func side(_ part: Stack?) {
                place(part, x: x, y: level(part))
                if let part { x += part.width + space }
            }
            if form == .colonRightEqualsRight {
                x = row.right + space
                sign(":"); side(divisor); sign("="); side(result)
            } else {
                side(divisor); sign(form == .leftSlashRight ? "/" : ")")
                left = x - row.left
                x += row.right - row.left + space
                sign(form == .leftSlashRight ? "\\" : "("); side(result)
            }
            right = max(right, x - space)
        }
        box.add(stack.box, at: CGPoint(x: left, y: 0))
        // Work that reaches left of the dividend, under the divisor, may start before it.
        let shift = max(0, -left)
        var content = MathBox()
        content.add(box, at: CGPoint(x: shift, y: top))
        return aligned(content, width: max(right, left + stack.width) + shift, height: bottom - top,
                       rows: stack.rows.map { $0.moved(by: -top) }, node, context)
    }
}
