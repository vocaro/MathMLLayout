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
  drawn on a `mathbackground` of its own does not wrap.
  `overflow` and `maxwidth` on `math` are not read:
  the host decides by the `maximumWidth` it passes.
- **`mglyph`.** MathML 2's `fontfamily` and `index` glyphs have no image and show their `alt`.
  An image has no scale of its own: size a 2x asset with `width` and `height`. An `mo` with an
  `mglyph` preserves author sizing and baseline by default. Explicit `stretchy="true"` or
  `largeop="true"` opts into [whole-token image operator geometry](image-operators.md).
  Images provide no italic correction or accent attachment metrics.
- **Elementary math.** Columns run left to right only. `decimalpoint` names one character. An
  `mglyph` in a stack's number is not drawn. Division frames are drawn, not font glyphs.
- **Speech.** Five languages, without regional variants or grammatical agreement. Token text and
  `alt` are spoken as written. A stack's reading gives its rows, carries and lines in order,
  not their column positions.
- Cell spans in `mtable` are ignored, and rows align on their baselines only.
- No kerning from the font's MathKernInfo.

[Documentation index](../README.md#documentation)
