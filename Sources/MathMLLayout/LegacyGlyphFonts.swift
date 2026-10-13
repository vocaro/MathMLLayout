import CoreText
import Foundation

/// Per-layout, bounded lookup for mglyph's explicitly requested installed font. CoreText may
/// substitute a missing name, so its actual name must match before a glyph index is used.
final class LegacyGlyphFonts {
    private var bases: [String: CTFont?] = [:]

    func font(name: String, variant: MathVariant?, size: CGFloat) -> CTFont? {
        // One name only; CSS lists, generic families and escaped CSS strings are unsupported.
        guard name.utf8.count <= 256 else { return nil }
        var name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = name.first, first == "\"" || first == "'", name.last == first, name.count >= 2 {
            name.removeFirst(); name.removeLast()
        }
        guard !name.isEmpty, !name.contains(","), !name.contains("\\") else { return nil }
        let traits: CTFontSymbolicTraits
        switch variant {
        case nil, .normal: traits = []
        case .bold: traits = .traitBold
        case .italic: traits = .traitItalic
        case .boldItalic: traits = [.traitBold, .traitItalic]
        default: return nil
        }
        let base: CTFont?
        if let cached = bases[name] { base = cached }
        else {
            let candidate = CTFontCreateWithNameAndOptions(name as CFString, 1, nil, .preventAutoActivation)
            let matches = [CTFontCopyPostScriptName(candidate), CTFontCopyFullName(candidate), CTFontCopyFamilyName(candidate)]
                .contains { $0 as String == name }
            base = matches ? candidate : nil
            if bases.count >= 128 { bases.removeAll(keepingCapacity: true) }
            bases.updateValue(base, forKey: name)
        }
        guard let base else { return nil }
        let sized = CTFontCreateCopyWithAttributes(base, size, nil, nil)
        guard !traits.isEmpty else { return sized }
        // An unavailable inherited face may be ignored (MathML 2, 3.2.9.2). Never leave the
        // requested family or synthesize a new glyph through Unicode style substitution.
        if let styled = CTFontCreateCopyWithSymbolicTraits(sized, size, nil, traits, traits),
           CTFontCopyFamilyName(styled) == CTFontCopyFamilyName(base) { return styled }
        return sized
    }
}
