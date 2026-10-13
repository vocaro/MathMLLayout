# Font

MathML layout needs an OpenType MATH font. iOS and macOS both install STIX Two Math, so nothing
is bundled. `MathStyle.fontName` selects another installed MATH font by PostScript name. A font
without a MATH table still lays out, with built-in constants and drawn stretchy operators.

For single-glyph bases and scripts, MathKernInfo supplies height-dependent corner spacing
after vertical placement. Both glyphs contribute, at their own sizes; negative values tuck
scripts closer. Compound expressions and fallback-font glyphs retain zero corner kerning.

[Documentation index](../README.md#documentation)
