import Foundation

/// Immutable, per-call vocabulary selection. Custom entries precede the built-ins; the first
/// complete entry for a canonical tag wins. There is no mutable process-wide registration.
/// Composition providers are trusted code: keep generated output bounded by the spoken operands.
public struct MathVocabularyCatalog: Sendable {
    private let entries: [(tag: String, words: any MathVocabulary.Type)]

    public static let standard = MathVocabularyCatalog(vocabularies: [])

    /// Add complete language providers or explicit regional overrides. Invalid tags and incomplete
    /// terminology tables are ignored, allowing selection to fall back before the tree is read.
    /// Tags support language, optional script/region, and BCP 47 variants. Extensions are voice
    /// preferences, not independent vocabularies; they are stripped from requested locales.
    public init(vocabularies: [any MathVocabulary.Type]) {
        let builtIns: [any MathVocabulary.Type] = MathReading.vocabularies + [EnglishUnitedKingdomVocabulary.self]
        var entries: [(tag: String, words: any MathVocabulary.Type)] = []
        for words in vocabularies + builtIns {
            guard let tag = Self.tag(words.language, stripExtensions: false),
                  !entries.contains(where: { $0.tag == tag }), Self.isComplete(words) else { continue }
            entries.append((tag, words))
        }
        self.entries = entries
    }

    /// Actual voice tags of the selectable complete vocabularies, in registration order.
    public var languages: [String] { entries.map(\.tag) }

    func vocabulary(for locale: Locale) -> (tag: String, words: any MathVocabulary.Type) {
        guard let tag = Self.tag(locale.identifier, stripExtensions: true) else {
            return ("en", EnglishVocabulary.self)
        }
        // Exact variant, then base language. No regional sibling is guessed.
        let base = String(tag.split(separator: "-")[0])
        for candidate in [tag, base] {
            if let entry = entries.first(where: { $0.tag == candidate }) { return entry }
        }
        return ("en", EnglishVocabulary.self)
    }

    private static func isComplete(_ words: any MathVocabulary.Type) -> Bool {
        let symbols = words.symbols
        guard MathSymbols.names.values.allSatisfy({ !symbols[keyPath: $0].isEmpty }),
              words.spatial.isComplete,
              words.ordinalRoots.values.allSatisfy({ !$0.isEmpty }),
              [words.endStack, words.line, words.blank, words.endLongDivision].allSatisfy({ !$0.isEmpty }) else { return false }
        let accents = words.accents
        return MathAccents.names.values.allSatisfy {
            switch accents[keyPath: $0] {
            case .after(let text), .before(let text): return !text.isEmpty
            }
        }
    }

    /// Canonical casing without adding likely script/region subtags. That distinction preserves
    /// base-language defaults and prevents `en` silently becoming a regional vocabulary.
    private static func tag(_ identifier: String, stripExtensions: Bool) -> String? {
        let identifier = stripExtensions ? String(identifier.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)[0]) : identifier
        var parts = identifier.replacingOccurrences(of: "_", with: "-").split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        func letters(_ part: String) -> Bool { !part.isEmpty && part.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) } }
        func digits(_ part: String) -> Bool { !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) } }
        func alphanumeric(_ part: String) -> Bool { part.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) } }
        if stripExtensions, let extensionIndex = parts.dropFirst().firstIndex(where: { $0.count == 1 }) {
            parts = Array(parts[..<extensionIndex])
        }
        guard let language = parts.first, (2...8).contains(language.count), letters(language) else { return nil }
        let canonicalLanguage = Locale.Language(identifier: language).languageCode?.identifier ?? language.lowercased()
        var result = [canonicalLanguage], index = 1
        if index < parts.count, parts[index].count == 4, letters(parts[index]) {
            result.append(parts[index].prefix(1).uppercased() + parts[index].dropFirst().lowercased()); index += 1
        }
        if index < parts.count, (parts[index].count == 2 && letters(parts[index])) || (parts[index].count == 3 && digits(parts[index])) {
            result.append(parts[index].uppercased()); index += 1
        }
        var variants = Set<String>()
        for part in parts.dropFirst(index) {
            let variant = part.lowercased()
            guard alphanumeric(part), (5...8).contains(part.count) || (part.count == 4 && part.first?.isNumber == true),
                  variants.insert(variant).inserted else { return nil }
            result.append(variant)
        }
        return result.joined(separator: "-")
    }
}
