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
  `mglyph` keeps the size its author gave it: it is not stretched, enlarged or centred on the
  axis.
- **Elementary math.** Columns run left to right only. `decimalpoint` names one character. An
  `mglyph` in a stack's number is not drawn. Division frames are drawn, not font glyphs.
- **Speech.** English, French, German, Spanish and Italian, plus a narrow `en-GB` bracket
  vocabulary. Complete custom languages and regional compositions use the
  [vocabulary extension contract](speech-locales.md). Locale matching selects the exact supported
  tag, then its base language, then whole-reading English. Recognized mathematical
  symbols in `mi` and `mo` have localized names; unknown identifiers, `mtext`, `ms` and image
  `alt` retain author wording and are not translated. Stacks and long divisions describe logical
  columns, carry locations and crossouts, line endpoints and division frames, without inferring
  arithmetic meaning. French root and limit templates elide `de` before a written vowel,
  preserving `de` before `oui`, `onze` and `onzième`; they do not infer silent/aspirated `h`,
  unwritten letter pronunciations or the language of author text. Letter-name usage, regional
  naturalness and the novel spatial wording still need human validation in
  [issue #63](https://github.com/vocaro/MathMLLayout/issues/63). See [Spoken readings](speech.md)
  for the supported templates and remaining review scope. Readings obey source node, depth,
  text and thread-stack bounds, leaving out content past them.
- Cell spans in `mtable` are ignored, and rows align on their baselines only.
- MathKernInfo script kerning applies to pairs of single, unpositioned glyphs of the math font.
  Compound expressions, font fallback runs and glyph assemblies use zero corner kerning.
  Device and variation corrections in MATH value records are ignored.

[Documentation index](../README.md#documentation)
