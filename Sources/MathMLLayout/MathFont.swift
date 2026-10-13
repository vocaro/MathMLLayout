import CoreGraphics
import CoreText
import Foundation

/// A math font and its MATH table, shared by every layout that uses it.
///
/// Apple platforms ship STIX Two Math (SIL Open Font License 1.1): macOS in
/// `/System/Library/Fonts/Supplemental`, iOS among its Unicode-support fonts, which is also the
/// font WebKit's MathML uses there. It is not bundled. A font without a MATH table still lays
/// out, with `MathConstants.fallback` and drawn stretchy operators.
final class MathFont: @unchecked Sendable {
    /// PostScript names tried in order when the caller names no font.
    static let defaultNames = ["STIXTwoMath-Regular", "STIXTwoMath", "LatinModernMath-Regular", "CambriaMath"]
    /// The last resort when no math font is installed: a serif text font.
    static let fallbackName = "TimesNewRomanPSMT"

    /// The font at 1 point. CTFont is immutable and thread-safe.
    let base: CTFont
    let table: MathTable?
    var constants: MathConstants { table?.constants ?? .fallback }
    let unitsPerEm: CGFloat
    private let lock = NSLock()
    private struct SizedFontKey: Hashable {
        let size: CGFloat
        let scriptLevel: Int
    }
    private var sized: [SizedFontKey: CTFont] = [:]
    private var sizedConstants: [CGFloat: MathConstants] = [:]

    private convenience init(base: CTFont, deviceScale: CGFloat? = nil) {
        let units = CGFloat(CTFontGetUnitsPerEm(base))
        let data = CTFontCopyTable(base, CTFontTableTag(kCTFontTableMATH), [])
        let gdef = CTFontCopyTable(base, CTFontTableTag(0x47444546), []).map { [UInt8]($0 as Data) }
        let variation = MathVariationCoordinates.normalized(font: base).flatMap { coordinates in
            gdef.flatMap { MathVariationStore(gdef: $0, normalizedCoordinates: coordinates) }
        }
        self.init(base: base, table: data.flatMap {
            MathTable(data: [UInt8]($0 as Data), unitsPerEm: units, variationStore: variation, deviceScale: deviceScale)
        })
    }

    /// An uncached font with independently supplied MATH data.
    init(base: CTFont, table: MathTable?) {
        self.base = base
        unitsPerEm = CGFloat(CTFontGetUnitsPerEm(base))
        self.table = table
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: MathFont] = [:]

    /// The named font when it is installed (an exact PostScript-name match), else the platform's
    /// math font, else a serif fallback.
    static func named(_ name: String?, variations: [UInt32: CGFloat] = [:], deviceScale: CGFloat? = nil) -> MathFont {
        // Include every effective instance/configuration input; cached fonts are immutable.
        let axes = variations.filter { $0.value.isFinite }.sorted { $0.key < $1.key }.prefix(64)
        let scale = deviceScale.flatMap { $0.isFinite && (1.0 / 64...64).contains($0) ? $0 : nil }
        let key = (name ?? "") + "|" + axes.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            + "|" + (scale.map { String(describing: $0) } ?? "")
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let font = cache[key] { return font }
        let candidates = (name.map { [$0] } ?? []) + defaultNames + [fallbackName]
        var chosen: CTFont?
        for candidate in candidates {
            let font = CTFontCreateWithName(candidate as CFString, 1, nil)
            if CTFontCopyPostScriptName(font) as String == candidate { chosen = font; break }
        }
        var base = chosen ?? CTFontCreateWithName(fallbackName as CFString, 1, nil)
        if !axes.isEmpty {
            let requested = Dictionary(uniqueKeysWithValues: axes.map { (NSNumber(value: $0.key), NSNumber(value: Double($0.value))) })
            let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: requested] as CFDictionary)
            base = CTFontCreateCopyWithAttributes(base, 1, nil, descriptor)
        }
        let font = MathFont(base: base, deviceScale: scale)
        if cache.count > 16 { cache.removeAll() }
        cache[key] = font
        return font
    }

    /// Device adjustments depend on the inherited font size, including scripts and mathsize.
    func constants(size: CGFloat) -> MathConstants {
        guard table?.deviceScale != nil else { return constants }
        lock.lock(); defer { lock.unlock() }
        if let cached = sizedConstants[size] { return cached }
        let result = table?.constants(size: size) ?? constants
        if sizedConstants.count > 128 { sizedConstants.removeAll() }
        sizedConstants[size] = result
        return result
    }

    /// The font at `size` points; with `scriptLevel` 1 or 2 its OpenType `ssty` script forms on.
    func font(size: CGFloat, scriptLevel: Int = 0) -> CTFont {
        let level = min(max(scriptLevel, 0), 2)
        // Device selection must distinguish sizes on opposite sides of a PPEM boundary.
        // Preserve the existing approximate cache for resolution-independent fonts.
        let key = SizedFontKey(size: table?.deviceScale == nil ? (size * 64).rounded() / 64 : size,
                               scriptLevel: level)
        lock.lock(); defer { lock.unlock() }
        if let font = sized[key] { return font }
        var font = CTFontCreateCopyWithAttributes(base, size, nil, nil)
        if level > 0, table != nil {
            let feature: [CFString: Any] = [kCTFontOpenTypeFeatureTag: "ssty", kCTFontOpenTypeFeatureValue: level]
            let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFeatureSettingsAttribute: [feature]] as CFDictionary)
            font = CTFontCreateCopyWithAttributes(font, size, nil, descriptor)
        }
        if sized.count > 128 { sized.removeAll() }
        sized[key] = font
        return font
    }

    /// The font's glyph for one Unicode scalar, or nil when the font lacks it.
    func glyph(for scalar: Unicode.Scalar) -> CGGlyph? {
        var units = Array(String(scalar).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        guard CTFontGetGlyphsForCharacters(base, &units, &glyphs, units.count), glyphs[0] != 0 else { return nil }
        return glyphs[0]
    }

    /// A design-unit measurement in points at `size`.
    func points(_ designUnits: CGFloat, size: CGFloat) -> CGFloat { designUnits * size / unitsPerEm }
}
