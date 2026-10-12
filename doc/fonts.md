# Font

MathML layout needs an OpenType MATH font. iOS and macOS both install STIX Two Math, so nothing
is bundled. `MathStyle.fontName` selects another installed MATH font by PostScript name. A font
without a MATH table still lays out, with built-in constants and drawn stretchy operators.

[Documentation index](../README.md#documentation)
