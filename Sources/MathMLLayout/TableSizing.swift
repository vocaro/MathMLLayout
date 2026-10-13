import CoreGraphics
import Foundation

/// Authored widths are preferences above the content's feasible minima. Fixed column lengths
/// are floors; percentages divide the table's width, and fit columns take the remaining space.
/// Every operation is linear in the already bounded grid, except a fixed 48-step water fill.
struct TableSizing {
    enum Column {
        case auto, fit, fixed(CGFloat), fraction(CGFloat)
    }
    var equal = false
    var columns: [Column] = []
    var requested: CGFloat?
    var labelGutter: CGFloat = 0

    var isActive: Bool { equal || requested != nil || columns.contains { if case .auto = $0 { false } else { true } } }

    func minimum(_ content: [CGFloat]) -> [CGFloat] {
        var result = content
        for index in result.indices {
            if case .fixed(let width) = columns[index] { result[index] = max(result[index], width) }
        }
        if equal { result = Array(repeating: result.max() ?? 0, count: result.count) }
        return result
    }

    /// The allocation target includes an ordinary label gutter, which authored table widths
    /// and column percentages exclude. Without an authored
    /// table width, fit columns request the finite local budget; ordinary auto tables stay natural.
    func allocate(_ content: [CGFloat], minimum: [CGFloat], budget: CGFloat, fixed: CGFloat) -> [CGFloat] {
        guard !content.isEmpty else { return [] }
        let hasFit = columns.contains { if case .fit = $0 { true } else { false } }
        let preferred = content.indices.map { index in
            if case .fixed = columns[index] { return minimum[index] }
            if case .fit = columns[index] { return minimum[index] }
            return max(content[index], minimum[index])
        }
        let naturalTotal = preferred.reduce(fixed, +)
        let desired = requested ?? (hasFit && budget.isFinite ? budget : naturalTotal)
        let target = max(minimum.reduce(fixed, +), min(desired, budget))
        let room = max(0, target - fixed)
        if equal { return Array(repeating: max(minimum.max() ?? 0, room / CGFloat(content.count)), count: content.count) }
        var upper = zip(content, minimum).map { max($0.0, $0.1) }
        for index in upper.indices {
            switch columns[index] {
            case .fixed(let width): upper[index] = max(minimum[index], width)
            case .fraction(let fraction): upper[index] = max(minimum[index], fraction * max(0, target - labelGutter))
            case .fit: upper[index] = minimum[index]
            case .auto: break
            }
        }
        let occupied = upper.reduce(0, +)
        if occupied > room {
            // Even oversubscribed percentages remain bounded. Preserve content and fixed
            // floors, and reduce the preferences toward those floors to fit the target.
            var low: CGFloat = 0, high: CGFloat = 1
            for _ in 0..<48 {
                let level = (low + high) / 2
                let total = zip(upper, minimum).reduce(0) { $0 + $1.1 + ($1.0 - $1.1) * level }
                if total <= room { low = level } else { high = level }
            }
            return zip(upper, minimum).map { $0.1 + ($0.0 - $0.1) * low }
        }
        var flexible = upper.indices.filter { if case .fit = columns[$0] { true } else { false } }
        if flexible.isEmpty { flexible = upper.indices.filter { if case .auto = columns[$0] { true } else { false } } }
        if flexible.isEmpty { flexible = Array(upper.indices) }
        let extra = (room - occupied) / CGFloat(flexible.count)
        for index in flexible { upper[index] += extra }
        return upper
    }
}

extension LayoutEngine {
    func tableSizing(_ node: MathMLNode, _ context: LayoutContext, columns: Int, labelGutter: CGFloat = 0) -> TableSizing {
        func parse(_ text: String?, reference: CGFloat?) -> TableSizing.Column {
            guard let text else { return .auto }
            if text == "fit" { return .fit }
            guard let value = MathLength(text), value.value >= 0 else { return .auto }
            switch value.unit {
            case .percent, .multiple:
                return .fraction(min(value.value, 1000))
            case .points, .em, .ex:
                return value.resolve(em: context.fontSize, ex: xHeight(context), reference: reference).map(TableSizing.Column.fixed) ?? .auto
            default: return .auto
            }
        }
        let list = (node.attributes["columnwidth"] ?? "").split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        let values = (0..<columns).map { parse(list.isEmpty ? nil : list[min($0, list.count - 1)], reference: nil) }
        var requested: CGFloat?
        let reference = lineWidth.isFinite ? lineWidth : nil
        switch parse(node.attributes["width"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), reference: reference) {
        case .fixed(let width): requested = width
        case .fraction(let fraction): requested = reference.map { min(fraction * $0, 1000 * context.fontSize) }
        default: break
        }
        return TableSizing(equal: node.attributes.flag("equalcolumns") == true, columns: values,
                           requested: requested.map { $0 + labelGutter }, labelGutter: labelGutter)
    }
}
