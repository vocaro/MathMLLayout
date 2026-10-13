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

Per layout pass, logical text line shaping and row assembly are limited to 2,000,000 UTF-16
units of work (including cached range visits and units visited during row assembly). Candidate lines share that budget across tokens;
exhaustion throws `MathLayoutError.limitExceeded`. The existing complete-layout retry bound
also applies. Long paragraphs at very narrow widths can reach this work limit before the
input text limit.

## Limitations

- **Line breaking.** Default `mpadded` and `mphantom` flow across host rows with the same
  spacing as an `mrow`; phantom fragments remain invisible. An `mpadded` with any explicit
  `width`, `height`, `depth`, `lspace` or `voffset` stays atomic (including explicit no-op values).
  `merror` wraps its content into one stack inside one red frame. A background-bearing row
  similarly becomes one stack inside one background rectangle, including interline gaps; it
  remains one host row, so an inline first-row budget does not fragment that background.
  Both stacks honor supported forced breaks. These policies preserve nested decorations and
  never extend a background over neighbouring elements.
  `munder`/`mover`/`munderover` remain atomic so accents, braces and limits stay attached to
  their whole base; movable limits rendered as side scripts follow the existing side-script
  policy. No breaks inside script annotations, between adjacent identifiers or inside a number.
  `indenttarget` must name a child of a row being broken, on an earlier row. `malignmark` and `maligngroup` align nothing. A table inside
  a table cell does not narrow. Plain `mtext` wraps in logical text order with per-line
  shaping and bidirectional resolution; inherited `dir` selects its paragraph direction.
  Mathematical row geometry itself remains left to right.
  Text with inline images or decorated `alt` fallbacks breaks at ordinary spaces; images and
  segments joined by no-break spaces stay whole.
  `overflow` and `maxwidth` on `math` are not read:
  the host decides by the `maximumWidth` it passes.
- **`mglyph`.** MathML 2's `fontfamily` and `index` glyphs have no image and show their `alt`.
  An image has no scale of its own: size a 2x asset with `width` and `height`. An `mo` with an
  `mglyph` keeps the size its author gave it: it is not stretched, enlarged or centred on the
  axis.
- **Elementary math.** Columns run left to right only. `decimalpoint` names one character. An
  `mglyph` in a stack's number is not drawn. Division frames are drawn, not font glyphs.
- **Speech.** Five languages, without regional variants or grammatical agreement. Token text and
  `alt` are spoken as written. A stack's reading gives its rows, carries and lines in order,
  not their column positions.
- Cell spans in `mtable` are ignored, and rows align on their baselines only.
- No kerning from the font's MathKernInfo.

The default padding and phantom spacing follows [MathML 3, sections 3.3.6.3 and
3.3.7.1](https://www.w3.org/TR/MathML3/chapter3.html#presm.mpadded). MathML 3 leaves
non-default padding at line breaks unspecified; this implementation keeps it atomic.

[Documentation index](../README.md#documentation)
