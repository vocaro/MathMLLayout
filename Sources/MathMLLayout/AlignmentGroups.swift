import CoreGraphics
import CoreText
import Foundation

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
}

extension MathBox {
    var alignmentEdges: (left: CGFloat, right: CGFloat) {
        let edges = alignment.compactMap { event -> (CGFloat, CGFloat)? in
            if case .extent(let width) = event.kind { return (event.x, event.x + width) }
            return nil
        }
        let ink = inkBounds
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
    func aligning(_ groups: [AlignmentGroup], shifts: [CGFloat], width: CGFloat) -> MathBox {
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
        func append(_ box: MathBox, at origin: CGPoint, path: [Int]) {
            for (index, item) in box.items.enumerated() {
                let here = path + [index]
                while group + 1 < groups.count && precedes(groups[group + 1].path, here) { group += 1 }
                if case .box(let child, let point) = item {
                    append(child, at: CGPoint(x: origin.x + point.x, y: origin.y + point.y), path: here)
                } else {
                    var leaf = MathBox()
                    leaf.items = [item]
                    // A background surrounding several groups expands with their contents.
                    if case .rect(let rect, let color) = item, rect.minX == 0, rect.width == box.width,
                       let range = ranges[path] {
                        let first = range.first, last = range.last
                        leaf.items = [.rect(CGRect(x: rect.minX, y: rect.minY,
                            width: path.isEmpty ? width : max(0, rect.width + shifts[last] - shifts[first]), height: rect.height), color)]
                        result.add(leaf, at: CGPoint(x: origin.x + (path.isEmpty ? 0 : shifts[first]), y: origin.y))
                    } else {
                        result.add(leaf, at: CGPoint(x: origin.x + shifts[group], y: origin.y))
                    }
                }
            }
        }
        append(self, at: .zero, path: [])
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
        guard context.trackAlignment && !context.alignmentRTL else { return .empty() }
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

    func finishAlignment(_ box: inout MathBox, node: MathMLNode, context: LayoutContext) {
        guard context.trackAlignment && !context.alignmentRTL else { box.alignment = []; return }
        guard node.name != "maligngroup", node.name != "malignmark" else { return }
        let groupContainers: Set<String> = ["math", "mrow", "mstyle", "mtd", "mphantom", "mfenced", "maction", "semantics"]
        if !groupContainers.contains(node.name) || (node.name == "mrow" || node.name == "mstyle") && node.attributes["dir"] != nil {
            box.alignment.removeAll { if case .group = $0.kind { return true }; return false }
        }
        let numberContainers: Set<String> = ["math", "mrow", "mstyle", "mtd", "mpadded", "mphantom", "menclose", "mfenced", "msqrt",
            "msub", "msup", "msubsup", "munder", "mover", "munderover", "mmultiscripts", "mroot", "semantics", "maction", "mn"]
        if !numberContainers.contains(node.name) {
            box.alignment.removeAll { if case .number = $0.kind { return true }; return false }
        }
        guard !box.alignment.contains(where: { if case .group = $0.kind { return true }; return false }) else { return }
        var edges = box.alignmentEdges
        if node.name == "mn" || node.name == "mspace" || node.name == "mtext" { edges = (min(0, edges.left), max(box.width, edges.right)) }
        box.alignment.removeAll { if case .extent = $0.kind { return true }; return false }
        box.alignment.append(AlignmentEvent(kind: .extent(edges.right - edges.left), x: edges.left))
    }

    /// One CoreText line supplies all offsets, preserving kerning and fallback-font shaping.
    /// Token marks use advances, including constant-width decimal digits in the math font.
    func tokenAlignment(_ box: inout MathBox, node: MathMLNode, text: String, context: LayoutContext) throws {
        guard context.trackAlignment && !context.alignmentRTL else { return }
        let marks = node.children.filter { $0.name == "malignmark" }
        guard node.name == "mn" || !marks.isEmpty else { return }
        guard !Self.hasGlyph(node) else { return } // image-token offsets are a documented staged case
        let attributes = [kCTFontAttributeName: ctFont(context)] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes))
        func offset(_ count: Int) -> CGFloat {
            // Single-glyph operators may have been enlarged or assembled after shaping.
            if node.name == "mo", text.unicodeScalars.count == 1, count >= text.utf16.count { return box.width }
            return CTLineGetOffsetForStringIndex(line, min(max(0, count), text.utf16.count), nil)
        }
        if let mark = marks.first {
            let raw = node.text.utf16
            let index = min(max(0, mark.tokenTextOffset ?? raw.count), raw.count)
            var prefix = Self.normalized(String(decoding: raw.prefix(index), as: UTF16.self), trimming: false)
            if node.name != "mtext" && node.name != "ms", prefix.hasPrefix(" ") { prefix.removeFirst() }
            if let variant = context.variant { prefix = variant.apply(to: prefix) }
            if node.name == "ms" { prefix = Self.unmarked(node.attributes["lquote"] ?? "\"") + prefix }
            alignmentSequence += 1
            box.alignment.append(AlignmentEvent(kind: .mark, x: offset(prefix.utf16.count), order: alignmentSequence))
        }
        if node.name == "mn", context.alignmentBaseline {
            let decimal = context.decimalPoint ?? "."
            let prefix = text.range(of: decimal).map { String(text[..<$0.lowerBound]) } ?? text
            alignmentSequence += 1
            box.alignment.append(AlignmentEvent(kind: .number, x: offset(prefix.utf16.count), order: alignmentSequence))
        }
    }

    func alignColumns(_ cells: inout TableGrid, scopes: [String]) throws {
        var columns: [Int: [(row: Int, index: Int, groups: [MathBox.AlignmentGroup])]] = [:]
        for row in cells.rows.indices {
            for column in cells.rows[row].indices {
                let gridColumn = cells.rows[row][column].column
                let scope = scopes.isEmpty || scopes[min(gridColumn, scopes.count - 1)] != "false"
                if scope && cells.rows[row][column].box.row?.hasForced != true {
                    let groups = cells.rows[row][column].box.alignmentGroups(cells.rows[row][column].groupAlign)
                    if !groups.isEmpty { columns[gridColumn, default: []].append((row, column, groups)) }
                }
                if !scope {
                    cells.rows[row][column].box.alignment.removeAll { if case .mark = $0.kind { return false }; return true }
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
                var position: CGFloat = 0, shifts: [CGFloat] = []
                for (index, group) in entry.groups.enumerated() {
                    shifts.append(position + left[index] - group.point)
                    position += left[index] + right[index]
                }
                cells.rows[entry.row][index].box = cells.rows[entry.row][index].box.aligning(entry.groups, shifts: shifts, width: width)
            }
        }
        for row in cells.rows.indices {
            for column in cells.rows[row].indices where scopes.isEmpty || scopes[min(cells.rows[row][column].column, scopes.count - 1)] != "false" {
                cells.rows[row][column].box.alignment = []
            }
        }
    }
}
