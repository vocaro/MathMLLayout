# Bounds and limitations

## Bounds

Input is treated as untrusted. A formula deeper than 64 levels, larger than 20,000 nodes, longer
than 50,000 UTF-16 units of text, more than 50,000 points in any dimension, or with more than
100,000 drawing items throws `MathLayoutError.limitExceeded`. So does one nested deeper than the
calling thread's stack has room for, within those 64 levels: a thread other than the main one
has 512 KB, which an unoptimized build spends in about twenty levels. Readings are bounded the
same way and leave out what is past the bounds. `MathMLNode.parse(xml:)` refuses document type
declarations in any encoding, so no entity expands and nothing external loads; it reads at most
4 MiB.

## Limitations

- **Line breaking.** No breaks inside `mpadded`, `mphantom`, `merror`, `munder`/`mover`/
  `munderover`, a script, or a row with a `mathbackground`; none between adjacent identifiers or
  inside a number. `indenttarget` must name a child of a row
  being broken, on an earlier row. `malignmark` and `maligngroup` align nothing. A table inside
  a table cell does not narrow, and `mtext` with a right-to-left run, an image, or an `alt`
  drawn on a `mathbackground` of its own, or a legacy font glyph, does not wrap.
  `overflow` and `maxwidth` on `math` are not read:
  the host decides by the `maximumWidth` it passes.
- **`mglyph`.** The [MathML 2 font/index form](https://www.w3.org/TR/MathML2/chapter3.html#presm.mglyph)
  supports one installed font's exact PostScript, full or family name (optionally quoted),
  and a decimal glyph ID (optional leading `+`) from 1 through the font's last glyph, at most
  65535. Names are bounded to 256 UTF-8 bytes and indices to 64 bytes, with at most ten digits.
  `index` is a position in that font, not a Unicode value; glyph 0 (`.notdef`) uses `alt`.
  The surrounding token supplies size, script sizing, foreground colour and normal/bold/italic/
  bold-italic traits; unavailable trait faces use the requested face. Other variants, CSS font
  lists/generic names, missing fonts, invalid indices and legacy `width`/`height`/`valign`
  combinations use `alt` (or U+25AF without it). No font is downloaded or auto-activated.
  Presence of `src` selects the image path even if empty or unresolved; legacy attributes
  never replace a missing image. An `mglyph`'s own size/variant/colour attributes have no effect,
  and its `mathbackground` fills its box. Glyph metrics and ink come directly from that font.
  Supply a 2x asset with `MathImageProvider.resolving` and `MathImage(image, scale: 2)`, or
  size it with markup `width` and `height`; see [Images](images.md). An `mo` with an
  `mglyph` preserves author sizing and baseline by default. Explicit `stretchy="true"` or
  `largeop="true"` opts into [whole-token image operator geometry](image-operators.md).
  Images provide no italic correction or accent attachment metrics.
- **Elementary math.** Columns run left to right only. `decimalpoint` names one character. A
  number's `mglyph` occupies one column, sized to its image or entire fallback text; its `alt`
  never supplies a decimal separator or several digit columns. Division frames are drawn,
  not font glyphs.
- **Speech.** Five languages, without regional variants or grammatical agreement. Token text and
  `alt` are spoken as written. A stack's reading gives its rows, carries and lines in order,
  not their column positions.
- Cell spans in `mtable` are ignored, and rows align on their baselines only.
- No kerning from the font's MathKernInfo.

[Documentation index](../README.md#documentation)
