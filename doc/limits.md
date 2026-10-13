# Bounds and limitations

## Bounds

Input is treated as untrusted. A formula deeper than 64 levels, larger than 20,000 nodes, longer
than 50,000 UTF-16 units of text, more than 50,000 points in any dimension, or with more than
100,000 drawing items throws `MathLayoutError.limitExceeded`. So does one nested deeper than the
calling thread's stack has room for, within those 64 levels. Readings are bounded the same way
and leave out what is past the bounds. `MathMLNode.parse(xml:)` refuses document type declarations
in any encoding, so no entity expands and nothing external loads; it reads at most 4 MiB.

### Worker stack coverage

Layout runs on the calling thread. Single-child wrappers, line-breaking descent, and drawing-item
traversal use heap cursors; inherited layout context uses copy-on-write storage. Structural
elements and speech still recurse, with smaller frames. The stack guard retains a 128 KB reserve
for the remaining work, font operations, and host callbacks. The engine does not enlarge a caller's
stack or move layout to another thread.

`WorkerDepthTests` asserts the following 64-level coverage on a thread with **exactly 512 KB** of
stack, in debug and release. Each chain ends in `mi` containing `x`; structural siblings are `mn`
containing `1`. Tests use the default math font (STIX Two Math on the measured system), 12-point
style, default attributes, no images, and unconstrained width. Geometry, drawing-item counts,
ink bounds, a 128×128-pixel rendering, and all five readings match an 8 MB reference worker,
and repeated runs match each other.

| Shape | Wrappers above the leaf |
| --- | --- |
| Single-child `mrow`, `msqrt`, `mstyle`, `mpadded`, or `semantics` | 63 |
| `mfrac` nesting its numerator, `msup` nesting its base, or `mroot` nesting its radicand | 63 |
| Single-cell `mtable` → `mtr` → `mtd` | 21 tables (63 element levels) |
| `msub` nesting its subscript, or `munderover` nesting its base | 48 structural wrappers, then 15 outer single-child `mrow` wrappers |

This is a tested matrix, not a guarantee for every shape at 64 levels. In particular, pure
subscript and under-over chains consume more stack; combinations of attributes, fonts, stretched
operators, width constraints, and host callbacks can change stack use. The guard may reject those
within the depth ceiling. Tests also check rejection at 65 levels and safe success or rejection on
smaller workers, including exact 128 KB and 256 KB stacks and the existing requested-stack sweep
down to 16 KB.

On arm64 macOS 27 with Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), the on-demand measurement sweep
reports these deepest successful layout-only pure chains, including the leaf:

| Pure fixture | Debug levels | Release levels |
| --- | --- | --- |
| Subscript nested in its script | 60 | 64 |
| Under-over nested in its base | 54 | 64 |
| Other fixtures in the matrix above | 64 | 64 |

See [testing.md](testing.md#worker-depth) for the commands; stack-sensitive results must be
remeasured after compiler or platform changes.

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
- Cell spans in `mtable` are ignored, and rows align on their baselines only.
- No kerning from the font's MathKernInfo.

[Documentation index](../README.md#documentation)
