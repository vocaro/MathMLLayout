# Font

MathML layout needs an OpenType MATH font. iOS and macOS both install STIX Two Math, so nothing
is bundled. `MathStyle.fontName` selects another installed MATH font by PostScript name. A font
without a MATH table still lays out, with built-in constants and drawn stretchy operators.

For single-glyph bases and scripts, MathKernInfo supplies height-dependent corner spacing
after vertical placement. Both glyphs contribute, at their own sizes; negative values tuck
scripts closer. Compound expressions and fallback-font glyphs retain zero corner kerning.

## MATH value adjustments

MATH MathValueRecords include signed font-unit values and optional adjustment references.
The reader applies supported VariationIndex records using the selected font's GDEF 1.3
ItemVariationStore. `MathStyle.fontVariations` supplies OpenType axis tags and user-coordinate
values; CoreText selects the instance. The reader uses that instance's actual coordinates,
normalizes them in `fvar` axis order and applies `avar` 1.0 mappings before interpolating deltas.
Default instances are evaluated too. Unsupported axes have no effect on the selected font.
For example, the `wght` tag is `0x77676874`:

```swift
let style = MathStyle(fontSize: 20, color: color, fontName: "MyVariableMathFont",
                      fontVariations: [0x77676874: 650])
```

Device corrections are ignored by default, preserving resolution-independent geometry.
Opt into them with `MathStyle.mathDeviceScale`: a fixed number of output pixels per point,
from 1/64 through 64. At an inherited font size of 10 points and scale 2, the reader selects
20 PPEM. PPEM rounds to the nearest integer (half values round up); corrections outside the
record's inclusive size range are zero. A correction of -2 pixels at scale 2 subtracts
1 point, regardless of font units per em. Scripts and `mathsize` use their actual sizes.
Invalid scales act as nil. Rebuild a layout to choose another scale; drawing an existing
layout into any context keeps its measured positions, bounds and axis height unchanged.
This policy adjusts MATH metrics, without enabling glyph-outline grid fitting.

The same policy applies to constants, glyph italic corrections, accent attachments,
MathKern correction heights and values, and assembly italic corrections. Variation deltas
are design units; Device deltas are device pixels. Integer fields without a MathValueRecord
(such as script percentages and connector overlap) have no adjustment reference.
Missing, unsupported, out-of-range or truncated adjustment data retains the unadjusted value.
Kern heights must remain strictly ordered; invalid corrected ordering retains the original
ordered boundaries. Existing extent and drawing-item bounds still apply.

Supported Device formats are signed packed 2-, 4- and 8-bit records. Variation support is
limited to GDEF 1.3 stores with normal signed 16-/8-bit delta rows and `fvar`/`avar` 1.0;
`avar` 2.0 and LONG_WORDS records are ignored. Malformed normalization data disables variation
adjustments. Parsing bounds include 64 axes, 4096 regions/data subtables, 65,536 referenced
region indices and 1,000,000 delta cells/rows. Font instances, resolved variation deltas and
raw records are immutable; size caches use locks and fixed entry limits. Device-corrected
kerning evaluates at most 1024 heights per corner table, retaining four exact-size results;
larger tables keep selected-instance variation corrections and omit Device corrections.

The formats and units follow the primary OpenType specifications for
[MATH](https://learn.microsoft.com/en-us/typography/opentype/spec/math),
[Device and VariationIndex](https://learn.microsoft.com/en-us/typography/opentype/spec/chapter2#device-and-variationindex-tables),
[variation stores](https://learn.microsoft.com/en-us/typography/opentype/spec/otvarcommonformats)
and [coordinate normalization](https://learn.microsoft.com/en-us/typography/opentype/spec/otvaroverview).
The general unit and instance-selection lessons behind this policy are in
[shared text layout and Unicode](https://github.com/vocaro/apple-engineering/blob/main/knowledge/apple/text-layout-and-unicode.md#font-and-image-metrics-have-different-units).

[Documentation index](../README.md#documentation)
