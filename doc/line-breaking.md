# Line breaking

Give a layout the width of its line and it breaks into rows that fit:

See [LineBreaking.swift](examples/LineBreaking.swift) for the complete Swift example.

- **Where it breaks.** Where the markup says (`linebreak="newline"`, at any width), and otherwise
  at operators ranked by the operator dictionary: at a relation sooner than at `+` or `−`, and
  there sooner than at `×` or an invisible times, with a penalty for each level of nesting. Never
  before a sign, after an opening fence, before a closing fence, or between a function and its
  argument. Separators break after; other operators start the next row and keep their spacing.
- **How deep.** Inside nested `mrow`, `mstyle` and `mfenced`, and inside the base of a script. A
  bracket pair split across rows keeps one size; a pair wholly on one row shrinks to that row's
  content after the breaks are chosen. Long `mtext` wraps at its logical U+0020 spaces. Arabic, Hebrew and mixed direction
  text are resolved and shaped for each selected line from the full token paragraph. Numbers,
  punctuation, neutral characters and directional controls retain that paragraph context;
  no-break spaces keep adjacent words together. An inherited `dir="rtl"` or `dir="ltr"` sets
  the text paragraph direction. Text with inline images and decorated `alt` fallbacks wraps
  at ordinary spaces, keeping images whole and fallback backgrounds on each word. A table wider
  than the line narrows its columns and wraps its cells; fraction parts, radicands and
  `menclose` contents wrap the same way. Default `mpadded` and `mphantom` also flow across
  rows; phantoms keep the visible content's spacing while drawing nothing. `merror` contents
  stack inside one frame; background-bearing rows stack inside one filled rectangle.
  Explicit padding geometry and under/over annotations stay atomic; see the precise
  [wrapper policies](limits.md#limitations).
- **Attributes** (MathML 3 §3.1.7): `linebreak`, `linebreakstyle`, `linebreakmultchar`,
  `lineleading`, `indentalign`, `indentshift`, `indenttarget` and their `first`/`last` forms, on
  `mo` and `mspace` or inherited from `mstyle` and `math`. Unless they say otherwise rows align
  left, and a display formula indents the rows after its first by one em.
- **Rows.** `rows` gives each row's `origin` (its baseline's left end, relative to the layout's),
  `width`, `ascent` and `descent`. The layout's baseline is its first row's, so `descent` reaches
  down through the last row. Each row's box covers its own ink.
- **Clipping.** A box covers the ink as it is laid out. A bitmap context then moves each glyph
  onto its pixel grid, down and to the left, and on macOS font smoothing thickens it, so ink can
  fall up to two device pixels outside the box. A host that clips to a box allows that much
  around it, or turns off `setShouldSubpixelQuantizeFonts` and `setShouldSmoothFonts` in its own
  context before drawing.
- **Too wide anyway.** A unit that cannot break (a long number, a wide radical) makes its row
  overflow. `widestUnbreakableWidth` is the narrowest `maximumWidth` at which none does; when it
  is more than the line, scale the formula.
- `axisHeight` is the math axis's height above the baseline, for centring rows as a table does.

[Documentation index](../README.md#documentation)
