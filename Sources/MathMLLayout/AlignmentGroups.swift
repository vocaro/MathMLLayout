import CoreGraphics
import CoreText
import Foundation

/// Shared across event copies so fragment assembly can recover the parent's source priority.
final class AlignmentIdentity {}

/// Source-ordered events survive ordinary layout, including nested rows. Drawing-item paths
/// distinguish groups even when their x positions coincide (empty groups or negative space).
struct AlignmentEvent {
    enum Kind {
        case group(String?)
        case mark
        case number
        case extent(CGFloat)
    }
    var kind: Kind
    var x: CGFloat
    var order = 0
    var path: [Int] = []
    var tokenEdgeRight = false
    var identity: AlignmentIdentity?

    init(kind: Kind, x: CGFloat, order: Int = 0, path: [Int] = [], tokenEdgeRight: Bool = false) {
        self.kind = kind; self.x = x; self.order = order; self.path = path; self.tokenEdgeRight = tokenEdgeRight
        switch kind {
        case .mark, .number: identity = AlignmentIdentity()
        default: identity = nil
        }
    }
}

/// A span participates only with cells covering the same source-column interval. A mixed
/// scope span is opaque; an entirely unscoped interval exports its explicit marks.
struct TableAlignmentScopes {
    enum Scope { case local, inherited, mixed }
    private let unscoped: [Int]

    init(_ values: [String], columns: Int) {
        var counts = [0]
        for column in 0..<columns {
            let isFalse = !values.isEmpty && values[min(column, values.count - 1)] == "false"
            counts.append(counts.last! + (isFalse ? 1 : 0))
        }
        unscoped = counts
    }

    func scope(_ cell: TableCell) -> Scope {
        let count = unscoped[cell.column + cell.columnSpan] - unscoped[cell.column]
        return count == 0 ? .local : count == cell.columnSpan ? .inherited : .mixed
    }
}

extension MathBox {
    var alignmentEdges: (left: CGFloat, right: CGFloat) {
        let edges = alignment.compactMap { event -> (CGFloat, CGFloat)? in
            if case .extent(let width) = event.kind { return (event.x, event.x + width) }
            return nil
        }
        let ink = spacingInkBounds
        if !edges.isEmpty {
            return (min(edges.map(\.0).min()!, ink?.minX ?? .infinity),
                    max(edges.map(\.1).max()!, ink?.maxX ?? -.infinity))
        }
        return (ink?.minX ?? 0, ink?.maxX ?? width)
    }

    struct AlignmentGroup {
        var path: [Int]
        var start: CGFloat
        var end: CGFloat
        var point: CGFloat
    }

    /// MathML 3 3.5.5.10: measure each group's effective edges and its alignment point.
    func alignmentGroups(_ inherited: [String]) -> [AlignmentGroup] {
        // Malformed content before the first group remains ordinary cell content.
        var started = false
        for event in alignment {
            if case .group = event.kind { started = true; break }
            if case .extent = event.kind { return [] }
        }
        guard started else { return [] }
        var groups: [AlignmentGroup] = []
        var mark: (x: CGFloat, order: Int)?, number: (x: CGFloat, order: Int)?, edges: (left: CGFloat, right: CGFloat)?
        var mode = "left"
        func close() {
            guard !groups.isEmpty else { return }
            let index = groups.count - 1
            let left = edges?.left ?? groups[index].start
            let right = edges?.right ?? groups[index].start
            let automatic: CGFloat = switch mode {
            case "right": edges?.right ?? right
            case "center": ((edges?.left ?? left) + (edges?.right ?? right)) / 2
            case "decimalpoint": number?.x ?? edges?.right ?? right
            default: edges?.left ?? left
            }
            let point = mark?.x ?? automatic
            // A missing mark neighbour is an effective zero-width element at the mark.
            groups[index].start = min(left, point)
            groups[index].end = max(right, point)
            groups[index].point = point
        }
        for event in alignment {
            switch event.kind {
            case .group(let own):
                close()
                let fallback = inherited.isEmpty ? "left" : inherited[min(groups.count, inherited.count - 1)]
                mode = AlignmentValues.mode(own) ?? fallback
                groups.append(AlignmentGroup(path: event.path, start: event.x, end: event.x, point: event.x))
                mark = nil; number = nil; edges = nil
            case .mark: if mark == nil || event.order < mark!.order { mark = (event.x, event.order) }
            case .number: if number == nil || event.order < number!.order { number = (event.x, event.order) }
            case .extent(let width):
                edges = (min(edges?.left ?? event.x, event.x), max(edges?.right ?? event.x + width, event.x + width))
            }
        }
        close()
        return groups
    }

    /// Translate leaf drawing items by their source group, rather than their x coordinate:
    /// fractions and scripts can overhang, and two empty groups can share an x coordinate.
    func aligning(_ groups: [AlignmentGroup], shifts: [CGFloat], width: CGFloat, rtl: Bool = false,
                  sections: [(left: CGFloat, right: CGFloat)] = []) -> MathBox {
        var result = MathBox(width: width, ascent: ascent, descent: descent)
        var group = 0
        // Prefix ranges are built once, O(groups × depth), rather than searching all groups
        // separately for every background in adversarial deeply nested rows.
        var ranges: [[Int]: (first: Int, last: Int)] = [:]
        for (index, entry) in groups.enumerated() {
            for length in 0..<entry.path.count {
                let prefix = Array(entry.path.prefix(length))
                ranges[prefix] = (ranges[prefix]?.first ?? index, index)
            }
        }
        func precedes(_ a: [Int], _ b: [Int]) -> Bool { a == b || a.lexicographicallyPrecedes(b) }
        // One cursor per active ancestor retains source order without recursive frames.
        // A hidden ancestor still contributes spacing and groups, but never paints its leaves.
        struct Cursor {
            let box: MathBox
            let origin: CGPoint
            let path: [Int]
            let isPhantom: Bool
            var index = 0
        }
        var pending = [Cursor(box: self, origin: .zero, path: [], isPhantom: isPhantom)]
        while !pending.isEmpty {
            let last = pending.count - 1
            guard pending[last].index < pending[last].box.items.count else {
                pending.removeLast()
                continue
            }
            let cursor = pending[last]
            let item = cursor.box.items[cursor.index]
            let here = cursor.path + [cursor.index]
            pending[last].index += 1
            while group + 1 < groups.count && precedes(groups[group + 1].path, here) { group += 1 }
            if case .box(let child, let point) = item {
                pending.append(Cursor(box: child,
                    origin: CGPoint(x: cursor.origin.x + point.x, y: cursor.origin.y + point.y),
                    path: here, isPhantom: cursor.isPhantom || child.isPhantom))
                continue
            }
            var leaf = MathBox()
            leaf.items = [item]
            leaf.isPhantom = cursor.isPhantom
            // A background surrounding several groups expands with their contents.
            if case .rect(let rect, let color) = item, rect.minX == 0, rect.width == cursor.box.width,
               let range = ranges[cursor.path] {
                let first = range.first, last = range.last
                var left = cursor.path.isEmpty ? 0 : cursor.origin.x + shifts[rtl ? last : first]
                var right = cursor.path.isEmpty ? width
                    : left + max(0, rect.width + (rtl ? shifts[first] - shifts[last] : shifts[last] - shifts[first]))
                // RTL automatic left alignment can insert blank space at the right edge
                // without translating either endpoint. A background containing complete
                // groups must cover those reserved sections as well as their shifted ink.
                if rtl, !sections.isEmpty {
                    if groups[first].start >= cursor.origin.x, groups[first].end <= cursor.origin.x + rect.width {
                        right = max(right, sections[first].right)
                    }
                    if groups[last].start >= cursor.origin.x, groups[last].end <= cursor.origin.x + rect.width {
                        left = min(left, sections[last].left)
                    }
                }
                leaf.items = [.rect(CGRect(x: 0, y: rect.minY, width: max(0, right - left), height: rect.height), color)]
                result.add(leaf, at: CGPoint(x: left, y: cursor.origin.y))
            } else {
                result.add(leaf, at: CGPoint(x: cursor.origin.x + shifts[group], y: cursor.origin.y))
            }
        }
        return result
    }
}

/// Table and row attributes are lists of braced lists; a cell has an unbraced list. At each
/// level the last value repeats, while an explicit inner setting replaces the inherited list.
enum AlignmentValues {
    static func mode(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["left", "right", "center", "decimalpoint"].contains(normalized) ? normalized : nil
    }
    static func list(_ value: String?) -> [String] {
        (value ?? "").split(whereSeparator: { $0.isWhitespace || $0 == "{" || $0 == "}" }).compactMap { mode(String($0)) }
    }
    static func columns(_ value: String?) -> [[String]] {
        (value ?? "").split(separator: "}").map { list(String($0)) }.filter { !$0.isEmpty }
    }
    static func column(_ value: String?, index: Int) -> [String]? {
        let lists = columns(value)
        return pick(lists, index)
    }
    static func pick(_ lists: [[String]], _ index: Int) -> [String]? {
        lists.isEmpty ? nil : lists[min(index, lists.count - 1)]
    }
}

extension LayoutEngine {
    /// A selected action stands in place of its subexpression in an enclosing row.
    static func alignmentMark(_ node: MathMLNode) -> MathMLNode? {
        var selected = node
        for _ in 0..<MathLimits.depth {
            if selected.name == "malignmark" { return selected }
            guard let shown = shownChild(selected) else { return nil }
            selected = shown
        }
        return nil
    }

    func alignmentElement(_ node: MathMLNode, _ context: LayoutContext) -> MathBox {
        guard context.trackAlignment else { return .empty() }
        alignmentSequence += 1
        var box = MathBox()
        box.alignment = [AlignmentEvent(kind: node.name == "maligngroup"
            ? .group(node.attributes["groupalign"]) : .mark, x: 0, order: alignmentSequence)]
        return box
    }

    func background(_ box: inout MathBox, node: MathMLNode) {
        guard node.name != "maligngroup", node.name != "malignmark",
              let color = node.attributes["mathbackground"].flatMap(MathColor.parse) else { return }
        for index in box.alignment.indices where !box.alignment[index].path.isEmpty {
            box.alignment[index].path[0] += 1
        }
        box.items.insert(.rect(CGRect(x: 0, y: -box.descent, width: box.width, height: box.height), color), at: 0)
    }

    /// Retained natural table cells enter a fresh relayout engine with new neighbouring events.
    /// Keep their source priority while assigning sequence IDs unique to that engine.
    func restampAlignment(_ box: inout MathBox) {
        let priorities = box.alignment.indices.filter { index in
            switch box.alignment[index].kind { case .mark, .number: return true; default: return false }
        }.sorted { box.alignment[$0].order < box.alignment[$1].order }
        for index in priorities {
            alignmentSequence += 1
            box.alignment[index].order = alignmentSequence
        }
    }

    /// Deferred stretchy children may be laid out after their siblings. Re-establish child
    /// source order while preserving each child's base-before-script mark priority.
    func orderAlignment(_ children: [MathBox], box: inout MathBox) {
        guard !box.alignment.isEmpty else { return }
        var orders: [Int: Int] = [:]
        for child in children {
            let priorities = child.alignment.compactMap { event -> Int? in
                switch event.kind { case .mark, .number: return event.order; default: return nil }
            }.sorted()
            for priority in priorities {
                alignmentSequence += 1
                orders[priority] = alignmentSequence
            }
        }
        for index in box.alignment.indices {
            if let order = orders[box.alignment[index].order] { box.alignment[index].order = order }
        }
    }

    func finishAlignment(_ box: inout MathBox, node: MathMLNode, outer: LayoutContext, context: LayoutContext) {
        guard context.trackAlignment else {
            if !box.alignment.isEmpty { box.alignment = [] }
            return
        }
        let changesDirection = (node.name == "mrow" || node.name == "mstyle")
            && context.alignmentRTL != outer.alignmentRTL
        if changesDirection {
            // A direction-changing row is one atomic element of its surrounding group.
            box.alignment = []
        }
        guard node.name != "maligngroup", node.name != "malignmark" else { return }
        let groupContainers: Set<String> = ["math", "mrow", "mstyle", "mtd", "mphantom", "mfenced", "maction", "semantics"]
        if !groupContainers.contains(node.name) || (node.name == "mrow" || node.name == "mstyle") && context.alignmentRTL != outer.alignmentRTL {
            box.alignment.removeAll { if case .group = $0.kind { return true }; return false }
        }
        let numberContainers: Set<String> = ["math", "mrow", "mstyle", "mtd", "mpadded", "mphantom", "menclose", "mfenced", "msqrt",
            "msub", "msup", "msubsup", "munder", "mover", "munderover", "mmultiscripts", "mroot", "semantics", "maction", "mn"]
        if !numberContainers.contains(node.name) {
            box.alignment.removeAll { if case .number = $0.kind { return true }; return false }
        }
        guard !box.alignment.contains(where: { if case .group = $0.kind { return true }; return false }) else { return }
        var edges = box.alignmentEdges
        if node.name == "mn" || node.name == "mspace" || node.name == "mtext" || changesDirection {
            edges = (min(0, edges.left), max(box.width, edges.right))
        }
        box.alignment.removeAll { if case .extent = $0.kind { return true }; return false }
        box.alignment.append(AlignmentEvent(kind: .extent(edges.right - edges.left), x: edges.left))
    }

    /// One CoreText line per textual part supplies offsets using the same attributes as
    /// drawing. Inline images, legacy glyphs and decorated fallbacks contribute their advances.
    func tokenAlignment(_ box: inout MathBox, node: MathMLNode, text: String,
                        images: [MathBox] = [], markOffset: Int? = nil, context: LayoutContext) throws {
        guard context.trackAlignment else { return }
        let mark = node.children.first { $0.name == "malignmark" }
        guard node.name == "mn" || mark != nil else { return }
        struct Part {
            let start: Int
            let end: Int
            let x: CGFloat
            let line: CTLine
        }
        var parts: [Part] = [], index = 0, x: CGFloat = 0, image = 0
        var imageEdges: [Int: CGFloat] = [:]
        let pieces = images.isEmpty ? [text] : text.unicodeScalars
            .split(separator: Self.glyphMarker, omittingEmptySubsequences: false).map(String.init)
        for (number, piece) in pieces.enumerated() {
            if number > 0 {
                imageEdges[index] = x
                x += images[image].width
                image += 1; index += 1
                imageEdges[index] = x
            }
            let line = CTLineCreateWithAttributedString(attributedText(piece, context))
            let end = index + piece.utf16.count
            parts.append(Part(start: index, end: end, x: x, line: line))
            x += CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            index = end
        }
        func offset(_ count: Int) -> CGFloat {
            let count = min(max(0, count), text.utf16.count)
            // At an attachment boundary, a neighbouring RTL run's logical caret may
            // lie at its opposite visual edge. The rendered attachment edge is exact.
            if let edge = imageEdges[count] { return edge }
            // Single-glyph operators may have been enlarged or assembled after shaping.
            if node.name == "mo", images.isEmpty, text.unicodeScalars.count == 1, let part = parts.first {
                let advance = CGFloat(CTLineGetTypographicBounds(part.line, nil, nil, nil))
                guard advance > 0 else { return 0 }
                return CTLineGetOffsetForStringIndex(part.line, count, nil) / advance * box.width
            }
            guard let part = parts.first(where: { count <= $0.end }) else { return x }
            return part.x + CTLineGetOffsetForStringIndex(part.line, max(0, count - part.start), nil)
        }
        if let mark {
            let position: Int
            if let markOffset {
                position = markOffset
            } else {
                // Plain operators still normalize their authored text separately from token content.
                let index = min(max(0, mark.tokenTextOffset ?? node.text.utf16.count), node.text.utf16.count)
                var raw = String.UnicodeScalarView(), consumed = 0
                for scalar in node.text.unicodeScalars {
                    consumed += scalar.utf16.count
                    guard consumed <= index else { break }
                    raw.append(scalar)
                }
                var prefix = Self.normalized(String(raw), trimming: false)
                if node.name != "mtext" && node.name != "ms", prefix.hasPrefix(" ") { prefix.removeFirst() }
                if let variant = context.variant { prefix = variant.apply(to: prefix) }
                position = prefix.utf16.count
            }
            alignmentSequence += 1
            let event = AlignmentEvent(kind: .mark, x: offset(position), order: alignmentSequence,
                                       tokenEdgeRight: mark.attributes["edge"]?.lowercased() == "right")
            box.alignment.append(event)
            box.logicalTextSlice?.source.setAlignmentMark(position, event: event)
        }
        if node.name == "mn", context.alignmentBaseline {
            let decimal = context.decimalPoint ?? "."
            let prefix = text.range(of: decimal).map { String(text[..<$0.lowerBound]) } ?? text
            alignmentSequence += 1
            box.alignment.append(AlignmentEvent(kind: .number, x: offset(prefix.utf16.count), order: alignmentSequence))
        }
    }

    func alignColumns(_ cells: inout TableGrid, scopes: [String], rtl: Bool = false) throws {
        struct Interval: Hashable { let column: Int; let span: Int }
        let scopes = TableAlignmentScopes(scopes, columns: cells.columns)
        var columns: [Interval: [(row: Int, index: Int, groups: [MathBox.AlignmentGroup])]] = [:]
        for row in cells.rows.indices {
            for column in cells.rows[row].indices {
                let cell = cells.rows[row][column]
                switch scopes.scope(cell) {
                case .local:
                    let groups = cell.box.alignmentGroups(cell.groupAlign)
                    if !groups.isEmpty {
                        columns[Interval(column: cell.column, span: cell.columnSpan), default: []].append((row, column, groups))
                    }
                case .inherited:
                    cells.rows[row][column].box.alignment.removeAll { if case .mark = $0.kind { return false }; return true }
                case .mixed:
                    cells.rows[row][column].box.alignment = []
                }
            }
        }
        for entries in columns.values {
            let count = entries.map { $0.groups.count }.max() ?? 0
            var left = [CGFloat](repeating: 0, count: count), right = left
            for entry in entries {
                for (index, group) in entry.groups.enumerated() {
                    left[index] = max(left[index], group.point - group.start)
                    right[index] = max(right[index], group.end - group.point)
                }
            }
            let width = left.reduce(0, +) + right.reduce(0, +)
            guard width.isFinite, width <= MathLimits.extent else { throw MathLayoutError.limitExceeded }
            for entry in entries {
                let index = entry.index
                var position: CGFloat = rtl ? width : 0, shifts: [CGFloat] = []
                var sections: [(left: CGFloat, right: CGFloat)] = []
                for (index, group) in entry.groups.enumerated() {
                    let size = left[index] + right[index]
                    sections.append(rtl ? (position - size, position) : (position, position + size))
                    shifts.append(position + (rtl ? -right[index] : left[index]) - group.point)
                    position += (rtl ? -1 : 1) * size
                }
                cells.rows[entry.row][index].box = cells.rows[entry.row][index].box.aligning(entry.groups, shifts: shifts, width: width, rtl: rtl, sections: sections)
            }
        }
        for row in cells.rows.indices {
            for column in cells.rows[row].indices where scopes.scope(cells.rows[row][column]) != .inherited {
                cells.rows[row][column].box.alignment = []
            }
        }
    }
}
