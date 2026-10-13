import Foundation

/// A spoken reading of a formula and the language it is written in.
public struct MathReading: Equatable, Sendable {
    public var text: String
    /// Actual selected BCP 47 vocabulary tag, including a supported region/script/variant.
    /// Unsupported locales use the base language or a whole-reading English fallback ("en").
    /// Literal author text may use a different language; it is never translated.
    public var language: String
    public init(text: String, language: String) { self.text = text; self.language = language }

    /// The original built-in base languages, as BCP 47 tags. See `supportedLocales` for variants.
    public static let languages: [String] = vocabularies.map { $0.language }

    /// All built-in language and variant tags. `languages` retains the original base-language list.
    public static var supportedLocales: [String] { MathVocabularyCatalog.standard.languages }

    static let vocabularies: [any MathVocabulary.Type] = [
        EnglishVocabulary.self, FrenchVocabulary.self, GermanVocabulary.self, SpanishVocabulary.self,
        ItalianVocabulary.self,
    ]
}

extension MathMLNode {
    /// An English, spoken-style reading of the formula for assistive technologies when the
    /// markup has no `alttext`: "x squared plus 1", "start fraction a over b end fraction".
    /// Bounded like layout; content past the bounds is left out.
    public var accessibilityDescription: String {
        var speaker = Speaker(words: EnglishVocabulary.self)
        return speaker.reading(of: self, depth: 0)
    }

    /// Select a supported variant, then its base language, then English for the entire reading.
    /// `language` identifies the vocabulary actually used, so a host can select a matching voice.
    public func accessibilityDescription(locale: Locale) -> MathReading {
        accessibilityDescription(locale: locale, vocabularies: .standard)
    }

    /// Read with additional complete vocabularies or explicit regional overrides. Selection happens
    /// once before traversal; missing terminology never inserts another language into the reading.
    public func accessibilityDescription(locale: Locale, vocabularies: MathVocabularyCatalog) -> MathReading {
        let selected = vocabularies.vocabulary(for: locale)
        var speaker = Speaker(words: selected.words)
        return MathReading(text: speaker.reading(of: self, depth: 0), language: selected.tag)
    }
}

private struct Speaker {
    let words: any MathVocabulary.Type
    private var count = 0
    /// UTF-16 units of text read so far, bounded as layout bounds a formula's (`MathLimits.textLength`).
    private var textLength = 0
    /// Where the stack of the thread that reads is as good as spent (`MathLimits.stackFloor`). The
    /// reading recurses a level for each of the markup's, and the bound on depth counts levels, not
    /// the bytes they take: what lies deeper than the stack allows is left out, as what lies past
    /// the other bounds is.
    private let stackFloor = MathLimits.stackFloor()

    init(words: any MathVocabulary.Type) { self.words = words }

    /// A row of a stack, and the depth it is read at.
    private typealias StackRow = (node: MathMLNode, depth: Int, position: Int)
    private var decimalPoint: String?

    /// Past the bound on text none of the markup's is read, or looked at: a host's tree may hold
    /// one long string in every node, and be read at many times its size.
    private var isTextSpent: Bool { textLength > MathLimits.textLength }

    /// Text of the markup as it is read (a token's, an `alt`, a fence), counted against the bound.
    private mutating func said(_ text: String) -> String {
        guard !isTextSpent else { return "" }
        textLength += text.utf16.count
        return isTextSpent ? "" : text
    }

    /// A token's text. Speech cannot show an image, so a U+FFFC, which stands for the `mglyph`
    /// child at its position, is read as that glyph's `alt`. Glyphs past the last marker follow
    /// the text, for a tree built without markers; a marker without a glyph says nothing.
    private mutating func text(of node: MathMLNode) -> String {
        let marker = LayoutEngine.glyphMarker
        guard !isTextSpent else { return "" }
        guard LayoutEngine.tokens.contains(node.name),
              node.text.unicodeScalars.contains(marker) || LayoutEngine.hasGlyph(node) else {
            return LayoutEngine.normalized(node.text)
        }
        var glyphs = node.children.lazy.filter { $0.name == "mglyph" }.makeIterator()
        var gathered = textLength
        /// The next glyph's `alt`, counted against the node bound like any element that is read,
        /// and gathered no further than the bound on text: every glyph may have the same long one.
        func alt() -> String? {
            guard let glyph = glyphs.next() else { return nil }
            count += 1
            guard count <= MathLimits.nodes, gathered <= MathLimits.textLength, let alt = glyph.attributes["alt"] else { return "" }
            gathered += alt.utf16.count
            return alt
        }
        var parts: [String] = []
        let pieces = node.text.unicodeScalars.split(separator: marker, omittingEmptySubsequences: false)
        for (index, piece) in pieces.enumerated() {
            if index > 0, let alt = alt() { parts.append(alt) }
            parts.append(String(piece))
        }
        while let alt = alt() { parts.append(alt) }
        // A glyph is a word of its own, whatever it touches in the markup.
        return LayoutEngine.normalized(parts.joined(separator: " "))
    }

    private func symbol(_ text: String) -> String { words.symbols[text] ?? text }

    /// Only transparent single-child wrappers and the selected presentation child may
    /// participate in semantic shortcuts. A compound base is not a limit operator.
    private func simpleToken(_ node: MathMLNode) -> MathMLNode? {
        var current = node
        for _ in 0..<MathLimits.depth {
            if LayoutEngine.tokens.contains(current.name), !LayoutEngine.hasGlyph(current) { return current }
            if ["mrow", "mstyle"].contains(current.name), current.children.count == 1 {
                current = current.children[0]
            } else if let shown = LayoutEngine.shownChild(current) { current = shown }
            else { return nil }
        }
        return nil
    }

    private func isLimitOperator(_ node: MathMLNode) -> Bool {
        guard let token = simpleToken(node), token.name == "mo" else { return false }
        let text = LayoutEngine.normalized(token.text)
        return token.attributes.flag("largeop")
            ?? OperatorDictionary.entry(text, form: .prefix).flags.contains(.largeop)
    }

    private func primeCount(_ text: String) -> Int? {
        let value = LayoutEngine.normalized(text)
        guard !value.isEmpty else { return nil }
        var count = 0
        for character in value {
            switch character {
            case "′", "'": count += 1
            case "″": count += 2
            case "‴": count += 3
            case "⁗": count += 4
            default: return nil
            }
        }
        // The already-read exponent has consumed its source-text budget, so even
        // a long prime sequence has a bounded expansion (at most four per character).
        return count
    }

    private func accent(_ node: MathMLNode, under: Bool, explicit: Bool?) -> MathAccent? {
        guard let token = simpleToken(node), token.name == "mo" else { return nil }
        guard explicit ?? token.attributes.flag("accent") ?? true else { return nil }
        let text = LayoutEngine.normalized(token.text)
        guard let value = words.accents[text] else { return nil }
        if !under { return value }
        switch text {
        case "_", "¯", "‾", "\u{0305}", "\u{0332}": return words.accents.underbar
        case "⏟": return words.accents.underbrace
        default: return .after(words.under("", words.accent(value, on: "")))
        }
    }

    /// An `mfenced`'s fence, which is an attribute but text all the same.
    private mutating func fence(_ text: String) -> String { isTextSpent ? "" : symbol(said(text)) }

    /// Whether `node` reads as one word, so that what encloses it need not say where it ends. A
    /// `semantics` or an `maction` is read as the child that is drawn, and is as simple as that
    /// child, whichever of its children comes first. The walk is bounded: hosts may build trees
    /// deeper than the parser allows.
    private func isSimple(_ node: MathMLNode) -> Bool {
        var node = node
        for _ in 0..<MathLimits.depth {
            if ["mrow", "mstyle"].contains(node.name), node.children.count == 1 {
                node = node.children[0]
            } else if let shown = LayoutEngine.shownChild(node) {
                node = shown
            } else {
                break
            }
        }
        return LayoutEngine.tokens.contains(node.name) || node.name == "mglyph"
    }

    private mutating func row(_ nodes: [MathMLNode], depth: Int) -> String {
        words.phrase(nodes.map { reading(of: $0, depth: depth) })
    }

    /// The readings of `nodes` with a comma between each, which a voice renders as a pause.
    private mutating func list(_ nodes: [MathMLNode], depth: Int) -> String {
        var parts: [String] = []
        for (index, node) in nodes.enumerated() where count < MathLimits.nodes {
            if index > 0 { parts.append(",") }
            parts.append(reading(of: node, depth: depth))
        }
        return words.phrase(parts)
    }

    mutating func reading(of node: MathMLNode, depth: Int) -> String {
        count += 1
        guard depth < MathLimits.depth, count <= MathLimits.nodes, !MathLimits.isStackSpent(stackFloor) else { return "" }
        guard !isTextSpent else { return "" }
        let previousPoint = decimalPoint
        if ["math", "mstyle", "mstack", "mlongdiv"].contains(node.name),
           let point = node.attributes["decimalpoint"]?.trimmingCharacters(in: .whitespaces), !point.isEmpty {
            decimalPoint = point
        }
        defer { decimalPoint = previousPoint }
        let children = node.children
        func child(_ index: Int) -> String {
            children.indices.contains(index) ? reading(of: children[index], depth: depth + 1) : ""
        }
        switch node.name {
        case "mi":
            return symbol(said(text(of: node)))
        case "mn", "mtext", "ms":
            return said(text(of: node))
        case "mo":
            let value = said(text(of: node))
            return ["\u{2061}", "\u{2062}", "\u{2063}", "\u{2064}"].contains(value) ? "" : symbol(value)
        case "mglyph":
            return isTextSpent ? "" : said(LayoutEngine.normalized(node.attributes["alt"] ?? ""))
        case "mfrac":
            let simple = children.count == 2 && isSimple(children[0]) && isSimple(children[1])
            return words.fraction(child(0), child(1), simple: simple)
        case "msup":
            let base = child(0), power = children.count > 1 ? children[1] : MathMLNode(name: "none")
            let exponent = child(1)
            guard !exponent.isEmpty else { return base }
            switch (power.name, exponent) {
            case ("mn", "2"): return words.squared(base)
            case ("mn", "3"): return words.cubed(base)
            default:
                if let token = simpleToken(power), token.name == "mo", let primes = primeCount(token.text) {
                    return words.primed(base, count: primes)
                }
                return words.power(base, exponent, simple: isSimple(power))
            }
        case "msub":
            return words.subscripted(child(0), child(1))
        case "msubsup":
            let base = child(0), lower = child(1), upper = child(2)
            if children.first.map(isLimitOperator) == true {
                return words.limits(base, from: lower, to: upper)
            }
            return words.power(words.subscripted(base, lower), upper,
                               simple: children.count < 3 || isSimple(children[2]))
        case "msqrt":
            let closed = children.count != 1 || !isSimple(children[0])
            return words.squareRoot(row(children, depth: depth + 1), closed: closed)
        case "mroot":
            let radicand = child(0), index = child(1)
            guard !radicand.isEmpty else { return "" }
            guard !index.isEmpty else { return radicand }
            let token = children.count > 1 ? simpleToken(children[1]) : nil
            switch token?.name == "mn" ? index : "" {
            case "2": return words.squareRoot(radicand, closed: true)
            case "3": return words.cubeRoot(radicand)
            default:
                if let token,
                   ["mi", "mn"].contains(token.name), let ordinal = words.ordinalRoots[index] {
                    return words.ordinalRoot(radicand, ordinal: ordinal)
                }
                return words.root(radicand, index: index)
            }
        case "munder", "mover", "munderover":
            let base = child(0)
            switch node.name {
            case "munder", "mover":
                let script = child(1), under = node.name == "munder"
                guard !script.isEmpty else { return base }
                if children.count > 1, let accent = accent(children[1], under: under,
                   explicit: node.attributes.flag(under ? "accentunder" : "accent")) {
                    return words.accent(accent, on: base)
                }
                return under ? words.under(base, script) : words.over(base, script)
            default:
                let lower = child(1), upper = child(2)
                var result = base
                let lowerAccent = children.count > 1
                    ? accent(children[1], under: true, explicit: node.attributes.flag("accentunder")) : nil
                let upperAccent = children.count > 2
                    ? accent(children[2], under: false, explicit: node.attributes.flag("accent")) : nil
                if lowerAccent == nil && upperAccent == nil {
                    return words.limits(base, from: lower, to: upper)
                }
                if !lower.isEmpty { result = lowerAccent.map { words.accent($0, on: result) } ?? words.under(result, lower) }
                if !upper.isEmpty { result = upperAccent.map { words.accent($0, on: result) } ?? words.over(result, upper) }
                return result
            }
        case "mmultiscripts":
            // Base, right pairs, then left pairs, each in source order. In the LTR
            // layout, right pairs go outward and left pairs go toward the base.
            // A silent none still occupies a subscript or superscript slot.
            var parts = [child(0)], prescript = false, superscript = false
            for item in children.dropFirst() {
                guard count < MathLimits.nodes else { break }
                if item.name == "mprescripts" {
                    count += 1
                    prescript = true
                    superscript = false
                    continue
                }
                if item.name == "none" {
                    count += 1
                } else {
                    let position: MathScriptPosition = prescript
                        ? (superscript ? .leftSuperscript : .leftSubscript)
                        : (superscript ? .rightSuperscript : .rightSubscript)
                    let script = reading(of: item, depth: depth + 1)
                    // A silent or bounded-out expression must not leave a dangling label.
                    if !script.isEmpty {
                        parts.append(words.script(script, position: position, simple: isSimple(item)))
                    }
                }
                superscript.toggle()
            }
            return words.phrase(parts)
        case "mtable":
            // A row is not read as an element of its own, so it is counted here.
            var parts = [words.table(rows: children.count)]
            for (index, row) in children.enumerated() where count < MathLimits.nodes {
                count += 1
                parts += [words.row(index + 1), list(row.children, depth: depth + 2)]
            }
            return words.phrase(parts)
        case "mfenced":
            let open = fence(node.attributes["open"] ?? "(")
            let raw = said(node.attributes["separators"] ?? ",")
            let separators = Array(raw.filter { !$0.isWhitespace })
            var parts = [open]
            for (index, item) in children.enumerated() where count < MathLimits.nodes {
                let value = reading(of: item, depth: depth + 1)
                guard !value.isEmpty else { continue }
                if index > 0, !separators.isEmpty {
                    parts.append(symbol(String(separators[min(index - 1, separators.count - 1)])))
                }
                parts.append(value)
            }
            parts.append(fence(node.attributes["close"] ?? ")"))
            return words.phrase(parts)
        case "mstack":
            var rows: [StackRow] = []
            gather(children, depth: depth + 1, into: &rows)
            let alignment = MathStackAlignment(attribute: node.attributes["stackalign"])
            let opening = words.stack(rows: rows.count { isDigits($0.node) })
            return words.phrase([opening, words.alignment(alignment)] + read(rows[...], alignment: alignment) + [words.endStack])
        case "mlongdiv":
            // MathML 3 §3.6.2: the divisor, the result, then a stack whose first row of digits is the
            // dividend. The result is named after the dividend, the order a division is said in.
            let alignment = MathStackAlignment(attribute: node.attributes["stackalign"])
            let frame = LongDivision(attribute: node.attributes["longdivstyle"])
            let divisor = children.indices.contains(0) ? divisionOperand(children[0], depth: depth + 1, alignment: alignment) : ""
            let result: String
            if children.indices.contains(1), children[1].name == "mn", frame.hasResultOnTop {
                result = digits((children[1], depth + 1, 0), alignment: alignment)
            } else {
                result = children.indices.contains(1) ? divisionOperand(children[1], depth: depth + 1, alignment: alignment) : ""
            }
            var rows: [StackRow] = []
            gather(children.dropFirst(2), depth: depth + 1, into: &rows)
            let dividend = rows.firstIndex { isDigits($0.node) } ?? rows.endIndex
            let working = rows.dropFirst(min(dividend + 1, rows.count))
            var parts = [words.longDivision(rows: working.count { isDigits($0.node) }),
                         words.spatial.frames[frame] ?? "", words.alignment(alignment)]
            if !divisor.isEmpty { parts.append(words.divisor(divisor)) }
            // Borrows may be marked above the dividend; they are read before it, as they are written.
            parts += read(rows[..<dividend], alignment: alignment)
            if dividend < rows.endIndex { parts.append(words.dividend(digits(rows[dividend], alignment: alignment))) }
            if !result.isEmpty { parts.append(words.result(result)) }
            return words.phrase(parts + read(working, alignment: alignment) + [words.endLongDivision])
        case "semantics", "maction":
            // The child layout draws, which need not be the first: an annotation may come before
            // it, and `selection` may name another.
            let shown = LayoutEngine.shownIndex(node)
            // The annotations passed over to find it count as layout counts them: past the bound
            // the rest of the formula is left out.
            if node.name == "semantics" { count += shown ?? children.count }
            return shown.map { reading(of: children[$0], depth: depth + 1) } ?? ""
        case "mphantom", "mspace", "none", "mprescripts", "annotation", "annotation-xml":
            return ""
        default:
            return row(children, depth: depth + 1)
        }
    }

    // MARK: Elementary math

    /// Flatten groups while accumulating exactly the same positions as layout.
    /// Pending rows and visited groups share a finite collection budget.
    private mutating func gather(_ nodes: some Sequence<MathMLNode>, depth: Int, position: Int = 0,
                                 shift: Int = 0, into rows: inout [StackRow]) {
        for (index, node) in nodes.enumerated() {
            guard rows.count + count < MathLimits.nodes, depth < MathLimits.depth,
                  !MathLimits.isStackSpent(stackFloor), !isTextSpent else { break }
            let inherited = position + index * shift
            let own = ["msgroup", "msrow", "mscarries", "msline"].contains(node.name)
                ? MathStackAlignment.columns(node, "position") : 0
            if node.name == "msgroup" {
                count += 1
                gather(node.children, depth: depth + 1, position: inherited + own,
                       shift: MathStackAlignment.columns(node, "shift"), into: &rows)
            } else { rows.append((node, depth, inherited + own)) }
        }
    }

    private func isDigits(_ node: MathMLNode) -> Bool { node.name != "msline" && node.name != "mscarries" }

    private struct SpokenCell {
        var text: String
        var isNumber = false
        var isPoint = false
    }

    /// mstyle is transparent to the grid; mn characters each occupy a column;
    /// everything else, including a compound formula, occupies one column.
    private mutating func cells(_ nodes: [MathMLNode], depth: Int, point: String?, into cells: inout [SpokenCell]) {
        for node in nodes {
            guard count < MathLimits.nodes, depth < MathLimits.depth, !isTextSpent,
                  !MathLimits.isStackSpent(stackFloor) else { break }
            if node.name == "mstyle" {
                count += 1
                let ownPoint = node.attributes["decimalpoint"]?.trimmingCharacters(in: .whitespaces)
                self.cells(node.children, depth: depth + 1, point: ownPoint?.isEmpty == false ? ownPoint : point, into: &cells)
            } else if node.name == "mn" {
                count += 1
                let text = said(LayoutEngine.normalized(node.text.replacingOccurrences(of: "\u{FFFC}", with: "")))
                for character in text {
                    let value = String(character)
                    cells.append(SpokenCell(text: words.spatial.character(character), isNumber: true,
                                            isPoint: point.map { value == $0 } ?? (value == "." || value == "\u{066B}")))
                }
            } else {
                let text = reading(of: node, depth: depth)
                let value = LayoutEngine.normalized(node.text)
                cells.append(SpokenCell(text: node.name == "none" ? words.blank : text,
                                        isPoint: LayoutEngine.tokens.contains(node.name) &&
                                        (point.map { value == $0 } ?? (value == "." || value == "\u{066B}"))))
            }
        }
    }

    private mutating func digits(_ row: StackRow, alignment: MathStackAlignment) -> String {
        var cells: [SpokenCell] = []
        if row.node.name == "msrow" {
            count += 1
            guard row.depth + 1 < MathLimits.depth else { return "" }
            self.cells(row.node.children, depth: row.depth + 1, point: decimalPoint, into: &cells)
        } else { self.cells([row.node], depth: row.depth, point: decimalPoint, into: &cells) }
        guard !cells.isEmpty else {
            return isTextSpent || count > MathLimits.nodes || row.depth >= MathLimits.depth ? "" : words.blank
        }
        var point = cells.firstIndex { $0.isPoint }
        if point == nil, let first = cells.firstIndex(where: { $0.isNumber }) {
            var end = first
            while end < cells.count && cells[end].isNumber { end += 1 }
            point = end
        }
        let start = alignment.firstColumn(count: cells.count, decimalPoint: point, position: row.position)
        return words.phrase(cells.enumerated().compactMap { cell in
            cell.element.text.isEmpty ? nil : words.phrase(words.column(start + cell.offset), cell.element.text)
        })
    }

    /// The separate divisor and result are mathematical operands; simple numbers
    /// are spelled out without inventing columns shared with the dividend.
    private mutating func divisionOperand(_ node: MathMLNode, depth: Int,
                                         alignment: MathStackAlignment = .decimalPoint) -> String {
        if ["msrow", "msgroup", "msline", "mscarries", "mstyle"].contains(node.name) {
            var rows: [StackRow] = []
            gather([node], depth: depth, into: &rows)
            return words.phrase(read(rows[...], alignment: alignment))
        }
        if node.name == "mn" {
            count += 1
            guard depth < MathLimits.depth, count <= MathLimits.nodes, !isTextSpent,
                  !MathLimits.isStackSpent(stackFloor) else { return "" }
            return words.phrase(said(text(of: node)).map { words.spatial.character($0) })
        }
        if node.name == "mscarry" {
            count += 1
            guard depth < MathLimits.depth, count <= MathLimits.nodes, !isTextSpent,
                  !MathLimits.isStackSpent(stackFloor) else { return "" }
            var parts: [String] = []
            for child in node.children where count < MathLimits.nodes {
                parts.append(divisionOperand(child, depth: depth + 1, alignment: alignment))
            }
            return words.phrase(parts)
        }
        return reading(of: node, depth: depth)
    }

    private mutating func read(_ rows: ArraySlice<StackRow>, alignment: MathStackAlignment) -> [String] {
        var parts: [String] = [], number = 0
        for row in rows {
            guard row.depth < MathLimits.depth, count < MathLimits.nodes, !isTextSpent else { break }
            switch row.node.name {
            case "msline":
                count += 1
                let length = max(MathStackAlignment.columns(row.node, "length"), 0)
                if length == 0 { parts.append(words.phrase(words.line, words.spatial.fullWidth)) }
                else {
                    let start = alignment.firstColumn(count: length, decimalPoint: nil, position: row.position)
                    // Announce endpoints, never allocate an attribute-sized list of columns.
                    parts.append(words.phrase(words.line, words.column(start), words.column(start + length - 1)))
                }
            case "mscarries": parts.append(carries(row, alignment: alignment))
            default:
                number += 1
                let text = digits(row, alignment: alignment)
                if !text.isEmpty { parts += [words.row(number), text] }
            }
        }
        return parts
    }

    private static let strikes: [(Crossout, String)] = [
        (.up, "updiagonalstrike"), (.down, "downdiagonalstrike"),
        (.vertical, "verticalstrike"), (.horizontal, "horizontalstrike"),
    ]

    /// MathML does not encode whether an annotation is a carry or a borrow.
    /// Describe both possibilities and the geometry, without guessing the operation.
    private mutating func carries(_ row: StackRow, alignment: MathStackAlignment) -> String {
        let node = row.node
        count += 1
        guard row.depth + 1 < MathLimits.depth else { return "" }
        let start = alignment.firstColumn(count: node.children.count, decimalPoint: nil, position: row.position)
        let inheritedLocation = CarryLocation(attribute: node.attributes["location"]) ?? .n
        var parts: [String] = []
        for (index, carry) in node.children.enumerated() {
            guard count < MathLimits.nodes, !isTextSpent else { break }
            let text = divisionOperand(carry, depth: row.depth + 1)
            let blank = carry.name == "none" || (carry.name == "mscarry" && carry.children.allSatisfy { $0.name == "none" })
            guard !text.isEmpty || blank else { continue }
            let own = carry.name == "mscarry" ? carry.attributes["crossout"] : nil
            let crossout = carry.name == "none" ? "" : own ?? node.attributes["crossout"] ?? ""
            let strikes = Crossout(attribute: crossout) ?? []
            let styles = Self.strikes.filter { strikes.contains($0.0) }.compactMap { words.spatial.strikes[$0.1] }
            let location = CarryLocation(attribute: carry.name == "mscarry" ? carry.attributes["location"] : nil) ?? inheritedLocation
            var entry = blank ? words.blank : text
            if !styles.isEmpty { entry = words.phrase(words.crossedOut(entry), words.phrase(styles)) }
            parts.append(words.phrase(words.column(start + index), blank && carry.name == "none" ? "" : words.spatial.locations[location] ?? "", entry))
        }
        return parts.isEmpty ? "" : words.carries(words.phrase(parts))
    }
}
