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

Tables reserve at most 20,000 occupied grid slots apiece and perform at most 200,000 occupancy
probes and label-span row visits across all tables in a layout pass. A valid span above 20,000, a larger occupied area,
or a conflict search beyond that work budget throws `MathLayoutError.limitExceeded`. Zero and
malformed spans use one; a row span stops at the last source row. Subsequent cells start at
the first fully vacant rectangle after the preceding cell, so overlapping requests move right
instead of overwriting an earlier cell. Sparse grid slots are not materialized.

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
- **Speech.** Five languages, without regional variants or grammatical agreement. Token text and
  `alt` are spoken as written. A stack's reading gives its rows, carries and lines in order,
  not their column positions.
- Table label columns remain independent gutters: `columnspan` on a label does not add grid
  columns. `axis` cell alignment currently shares the row baseline, including when cell font
  sizes differ. Stretchy operators in table cells do not stretch to match neighboring cells.
- No kerning from the font's MathKernInfo.

[Documentation index](../README.md#documentation)
