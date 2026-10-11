import Foundation

/// A spoken reading of a formula and the language it is written in.
public struct MathReading: Equatable, Sendable {
    public var text: String
    /// BCP 47 tag of the language `text` is in: the requested locale's language when the engine has its
    /// vocabulary, else "en".
    public var language: String
    public init(text: String, language: String) { self.text = text; self.language = language }

    /// The languages the engine has a vocabulary for, as BCP 47 tags.
    public static let languages: [String] = vocabularies.map { $0.language }

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

    /// The same reading in the locale's language, whatever its region or script: "x au carré plus 1"
    /// for `fr-CA`. A language without a vocabulary gets the English reading whole, and its
    /// `language` says so, for a host to speak it with a voice that matches the words.
    public func accessibilityDescription(locale: Locale) -> MathReading {
        let code = locale.language.languageCode?.identifier
        let words = MathReading.vocabularies.first { $0.language == code } ?? EnglishVocabulary.self
        var speaker = Speaker(words: words)
        return MathReading(text: speaker.reading(of: self, depth: 0), language: words.language)
    }
}

private struct Speaker {
    let words: any MathVocabulary.Type
    private var count = 0

    init(words: any MathVocabulary.Type) { self.words = words }

    /// A row of a stack, and the depth it is read at.
    private typealias StackRow = (node: MathMLNode, depth: Int)

    /// A token's text. Speech cannot show an image, so a U+FFFC, which stands for the `mglyph`
    /// child at its position, is read as that glyph's `alt`. Glyphs past the last marker follow
    /// the text, for a tree built without markers; a marker without a glyph says nothing.
    private mutating func text(of node: MathMLNode) -> String {
        let marker = LayoutEngine.glyphMarker
        guard LayoutEngine.tokens.contains(node.name),
              node.text.unicodeScalars.contains(marker) || LayoutEngine.hasGlyph(node) else {
            return LayoutEngine.normalized(node.text)
        }
        var glyphs = node.children.lazy.filter { $0.name == "mglyph" }.makeIterator()
        /// The next glyph's `alt`, counted against the node bound like any element that is read.
        func alt() -> String? {
            guard let glyph = glyphs.next() else { return nil }
            count += 1
            return count <= MathLimits.nodes ? glyph.attributes["alt"] ?? "" : ""
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

    /// Whether `node` reads as one word, so that what encloses it need not say where it ends. The
    /// walk is bounded: hosts may build trees deeper than the parser allows.
    private func isSimple(_ node: MathMLNode) -> Bool {
        var node = node
        for _ in 0..<MathLimits.depth {
            guard ["mrow", "mstyle"].contains(node.name), node.children.count == 1 else { break }
            node = node.children[0]
        }
        return LayoutEngine.tokens.contains(node.name) || node.name == "mglyph"
    }

    private mutating func row(_ nodes: [MathMLNode], depth: Int) -> String {
        words.phrase(nodes.map { reading(of: $0, depth: depth) })
    }

    /// The readings of `nodes` with a comma between each, which a voice renders as a pause.
    private mutating func list(_ nodes: [MathMLNode], depth: Int) -> String {
        var parts: [String] = []
        for (index, node) in nodes.enumerated() {
            if index > 0 { parts.append(",") }
            parts.append(reading(of: node, depth: depth))
        }
        return words.phrase(parts)
    }

    mutating func reading(of node: MathMLNode, depth: Int) -> String {
        count += 1
        guard depth < MathLimits.depth, count <= MathLimits.nodes else { return "" }
        let children = node.children
        func child(_ index: Int) -> String {
            children.indices.contains(index) ? reading(of: children[index], depth: depth + 1) : ""
        }
        switch node.name {
        case "mi", "mn", "mtext", "ms":
            return text(of: node)
        case "mo":
            let value = text(of: node)
            return ["\u{2061}", "\u{2062}", "\u{2063}", "\u{2064}"].contains(value) ? "" : symbol(value)
        case "mglyph":
            return LayoutEngine.normalized(node.attributes["alt"] ?? "")
        case "mfrac":
            let simple = children.count == 2 && isSimple(children[0]) && isSimple(children[1])
            return words.fraction(child(0), child(1), simple: simple)
        case "msup":
            let base = child(0), power = children.count > 1 ? children[1] : MathMLNode(name: "none")
            switch (power.name, text(of: power)) {
            case ("mn", "2"): return words.squared(base)
            case ("mn", "3"): return words.cubed(base)
            case ("mo", "′"), ("mo", "'"): return words.primed(base)
            default: return words.power(base, child(1), simple: isSimple(power))
            }
        case "msub":
            return words.subscripted(child(0), child(1))
        case "msubsup":
            return words.power(words.subscripted(child(0), child(1)), child(2), simple: true)
        case "msqrt":
            let closed = children.count != 1 || !isSimple(children[0])
            return words.squareRoot(row(children, depth: depth + 1), closed: closed)
        case "mroot":
            switch children.count > 1 ? text(of: children[1]) : "" {
            case "2": return words.squareRoot(child(0), closed: true)
            case "3": return words.cubeRoot(child(0))
            default:
                let index = child(1)
                return words.root(child(0), index: index)
            }
        case "munder", "mover", "munderover":
            let base = child(0), over = node.name == "munder" ? nil : children.last
            if node.name == "mover", let over, let accent = words.accents[text(of: over)] {
                return accent.reading(on: base)
            }
            switch node.name {
            case "munder": return words.under(base, child(1))
            case "mover": return over.map { words.over(base, reading(of: $0, depth: depth + 1)) } ?? base
            default:
                let lower = child(1)
                return words.limits(base, from: lower, to: over.map { reading(of: $0, depth: depth + 1) } ?? "")
            }
        case "mmultiscripts":
            var parts = [child(0)]
            for item in children.dropFirst() where item.name != "none" && item.name != "mprescripts" {
                parts.append(words.script(reading(of: item, depth: depth + 1)))
            }
            return words.phrase(parts)
        case "mtable":
            var parts = [words.table(rows: children.count)]
            for (index, row) in children.enumerated() {
                parts += [words.row(index + 1), list(row.children, depth: depth + 2)]
            }
            return words.phrase(parts)
        case "mfenced":
            let open = symbol(node.attributes["open"] ?? "("), close = symbol(node.attributes["close"] ?? ")")
            return words.phrase(open, list(children, depth: depth + 1), close)
        case "mstack":
            var rows: [StackRow] = []
            gather(children, depth: depth + 1, into: &rows)
            let opening = words.stack(rows: rows.count { isDigits($0.node) })
            return words.phrase([opening] + read(rows[...]) + [words.endStack])
        case "mlongdiv":
            // MathML 3 §3.6.2: the divisor, the result, then a stack whose first row of digits is the
            // dividend. The result is named after the dividend, the order a division is said in.
            let divisor = child(0), result = child(1)
            var rows: [StackRow] = []
            gather(children.dropFirst(2), depth: depth + 1, into: &rows)
            let dividend = rows.firstIndex { isDigits($0.node) } ?? rows.endIndex
            let working = rows.dropFirst(dividend + 1)
            var parts = [words.longDivision(rows: working.count { isDigits($0.node) })]
            if !divisor.isEmpty { parts.append(words.divisor(divisor)) }
            // Borrows may be marked above the dividend; they are read before it, as they are written.
            parts += read(rows[..<dividend])
            if dividend < rows.endIndex { parts.append(words.dividend(digits(rows[dividend]))) }
            if !result.isEmpty { parts.append(words.result(result)) }
            return words.phrase(parts + read(working) + [words.endLongDivision])
        case "semantics", "maction":
            return child(0)
        case "mphantom", "mspace", "none", "mprescripts", "annotation", "annotation-xml":
            return ""
        default:
            return row(children, depth: depth + 1)
        }
    }

    // MARK: Elementary math

    /// Collects the rows under `nodes` in reading order. An `msgroup` only shifts the rows it
    /// holds, so they are read where it stands.
    private mutating func gather(_ nodes: some Sequence<MathMLNode>, depth: Int, into rows: inout [StackRow]) {
        for node in nodes where rows.count < MathLimits.nodes {
            guard node.name == "msgroup" else { rows.append((node, depth)); continue }
            count += 1
            guard depth < MathLimits.depth, count <= MathLimits.nodes else { continue }
            gather(node.children, depth: depth + 1, into: &rows)
        }
    }

    /// Whether a row holds digits, rather than being a line or the carries of the row after it.
    private func isDigits(_ node: MathMLNode) -> Bool { node.name != "msline" && node.name != "mscarries" }

    /// Whether a row or a carry is nothing but empty columns.
    private func isBlank(_ node: MathMLNode) -> Bool {
        if node.name == "none" { return true }
        return ["msrow", "mscarry"].contains(node.name) && node.children.allSatisfy { $0.name == "none" }
    }

    /// A row of digits and operators. A number is read whole, as it is anywhere else, and so in
    /// the voice's own way with decimal points and digit grouping.
    private mutating func digits(_ row: StackRow) -> String {
        let text = reading(of: row.node, depth: row.depth)
        return isBlank(row.node) ? words.blank : text
    }

    /// Reads `rows` in order, numbering the rows of digits from 1. Lines and carries are announced
    /// where they fall but not numbered: a sighted reader sees them between the rows, not as rows.
    private mutating func read(_ rows: ArraySlice<StackRow>) -> [String] {
        var parts: [String] = [], number = 0
        for row in rows where row.depth < MathLimits.depth && count < MathLimits.nodes {
            switch row.node.name {
            case "msline":
                count += 1
                parts.append(words.line)
            case "mscarries":
                parts.append(carries(row.node, depth: row.depth))
            default:
                number += 1
                parts += [words.row(number), digits(row)]
            }
        }
        return parts
    }

    /// An `mscarries` row: its carries in order, a column without one said as blank so the
    /// listener can count along the row below. `crossout` strikes the digit under a carry, not
    /// the carry itself (MathML 3 §3.6.5), which is how a borrow replaces the digit it changes.
    private mutating func carries(_ node: MathMLNode, depth: Int) -> String {
        count += 1
        guard depth + 1 < MathLimits.depth else { return "" }
        var parts: [String] = []
        for (index, carry) in node.children.enumerated() where count < MathLimits.nodes {
            if index > 0 { parts.append(",") }
            let text = reading(of: carry, depth: depth + 1), entry = isBlank(carry) ? words.blank : text
            // An `mscarry` may override the row's crossout, with "none" to spare its digit.
            let own = carry.name == "mscarry" ? carry.attributes["crossout"] : nil
            let crossout = own ?? node.attributes["crossout"] ?? "none"
            let isStruck = crossout.split(whereSeparator: \.isWhitespace).contains { $0 != "none" }
            parts.append(isStruck ? words.crossedOut(entry) : entry)
        }
        return words.carries(words.phrase(parts))
    }
}
