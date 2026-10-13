# Bounds and limitations

## Bounds

Input is treated as untrusted. A formula deeper than 64 levels, larger than 20,000 nodes, longer
than 50,000 UTF-16 units of text, more than 50,000 points in any dimension, or with more than
100,000 drawing items throws `MathLayoutError.limitExceeded`. The calling thread's stack can
be exhausted within the depth ceiling. Readings obey the source node, depth, text and stack
bounds, leaving out content past them. `MathMLNode.parse(xml:)` refuses document type
declarations in any encoding, so no entity expands and nothing external loads; it reads at most
4 MiB.

Width fitting permits at most 1,114 complete layout passes. Within each pass, tables reserve at
most 20,000 occupied grid slots apiece; initial table construction shares 200,000 occupancy
probes/label-span row visits. Valid spans above 20,000, excessive occupied area or exhausted
work throw
`MathLayoutError.limitExceeded`; malformed/zero spans use one, and row spans stop at the last
source row. Cell rebuilds share separate limits of 1,280,000 node visits and 200,000 table-work
visits per pass; cached tables charge their original descendant count and measured grid work.
Logical text shaping and row assembly share 2,000,000 units of work per pass, including cached range visits
and assembly visits. Narrow paragraphs can exhaust that budget before reaching the input limit.

### Worker stack coverage

Layout runs on the calling thread. Single-child wrapper descent, line-breaking descent and
drawing-item traversal use heap cursors; structural elements and speech still recurse. The
stack guard retains a 128 KB reserve for remaining work, font operations and host callbacks.
The engine neither enlarges the caller's stack nor moves layout to another thread.

`WorkerDepthTests` asserts these 64-level shapes on an **exactly 512 KB** worker in debug and
release, against an 8 MB reference worker. Leaves are `mi` containing `x`; structural siblings
are `mn` containing `1`. Fixtures use the default math font, 12-point style, default attributes,
no images and unconstrained width. Geometry, drawing-item counts, ink bounds, a 128×128-pixel
rendering and all five base-language readings are compared with the reference and repeated runs.

| Shape | Wrappers above the leaf |
| --- | --- |
| Single-child `mrow`, `msqrt`, `mstyle`, `mpadded`, `semantics` | 63 |
| Numerator-nested `mfrac`, base-nested `msup`, radicand-nested `mroot` | 63 |
| Single-cell `mtable` → `mtr` → `mtd` | 21 tables (63 element levels) |
| Script-nested `msub`, base-nested `munderover` | 48, plus 15 outer `mrow` |

This is a tested matrix, not universal 64-level coverage. Pure subscript/under-over chains and
different attributes, fonts, stretched operators, width constraints or callbacks can exhaust the
stack sooner. Smaller workers may safely reject bounded inputs; tests include exact 128 KB and
256 KB stacks and the requested-stack sweep down to 16 KB. Stack-sensitive results require
remeasurement after compiler/platform changes; see [Worker depth](testing.md#worker-depth).

## Limitations

- **Wrapping and widths.** Default `mpadded` and `mphantom` can fragment across host rows;
  phantom fragments stay invisible. Explicit padding dimensions/offsets, including no-op
  values, stay atomic. Errors and background-bearing rows wrap internally into one decorated
  stack, rather than fragmenting the decoration across host rows. Under/over structures and
  script annotations remain atomic; no breaks occur between adjacent identifiers or inside
  numbers. Plain `mtext` wraps at logical U+0020 spaces with full-paragraph bidi context and
  per-line shaping. Inline images and decorated `alt` break at ordinary spaces in the separate
  segmented-text path, keeping each image and no-break segment whole. Undecorated plain
  `alt` can use logical bidi shaping; mixed image/decorated RTL tokens or unrecoverable segment
  origins remain atomic. Nested tables narrow inside breakable cell rows, retaining unbreakable
  content and fixed frame/label space. Root `maxwidth` can narrow the
  host budgets; a smaller authored cap must be removed/enlarged when retrying at
  `widestUnbreakableWidth`. `overflow` remains a host concern. See [Line breaking](line-breaking.md).
- **Indentation.** `indenttarget` resolves unique descendant IDs on earlier output lines of
  the same broken paragraph. Unwrapped backgrounds retain descendant anchors, but independently
  wrapped paragraphs (including internally wrapped background stacks), script arguments outside
  the flattened base and unselected content have no shared anchor coordinates. Absent, duplicate,
  same-line and later-line targets fall back to `auto`. Indexing and final placement are bounded
  and add no wrapping retries. Unbounded/internal center/right alignment uses a common frame
  chosen before ID placement; an ID continuation can extend the returned width beyond that
  frame. See [Line breaking](line-breaking.md).
- **Direction and elementary math.** Inherited `dir` sets direction within shaped token text;
  general layout schemata still progress LTR. Elementary grids, numeric text and frame sides
  retain the LTR policy. `decimalpoint` names one character. A number's `mglyph` occupies one
  column, sized to its image or entire fallback; its `alt` supplies neither a decimal separator
  nor several digit columns. Division frames are drawn, not font glyphs. See
  [Direction and columns](elementary-direction.md).
- **Tables.** Spans use a bounded sparse grid; overlapping requests move right to a vacant
  rectangle. Label columns remain independent gutters, so a label's `columnspan` adds no grid
  columns. Row/cell vertical alignment is supported; a row with only top/bottom/center entries
  uses a midpoint baseline, and labels contribute to row height. Equal tracks, authored
  table/column widths and stretching cell operators to neighboring cells remain unsupported;
  overlap label sides reserve the same space as non-overlap forms. LTR alignment groups and
  marks are supported, but aligned cells stay indivisible under automatic wrapping. Forced
  breaks and non-default spans opt out. RTL alignment and token marks mixed with `mglyph`
  remain staged. See [Alignment groups](alignment-groups.md).
- **Images and legacy glyphs.** Intrinsic image scale/logical size is supplied by the host;
  markup can override image dimensions. An `mo` containing `mglyph` preserves author sizing
  and baseline by default; explicit `stretchy="true"`/`largeop="true"` opts into whole-token
  affine stretch/display enlargement. Dictionary defaults alone do not alter that geometry.
  Image-only horizontal direction requires surrounding operator text. Images supply no font
  italic-correction or accent-attachment metrics. Legacy font/index glyphs use one installed
  font's exact PostScript/full/family name and a bounded decimal glyph ID; unsupported fonts,
  variants, indices or legacy dimension/offset combinations use `alt`. No font is downloaded
  or auto-activated; `src` presence selects the image path even when unresolved. See
  [Images](images.md) and [Image operators](image-operators.md).
- **Script kerning.** MathKernInfo applies to pairs of single, unpositioned math-font glyphs.
  Compound expressions, fallback runs and glyph assemblies use zero corner kerning.
  Device/variation corrections in MATH value records remain ignored.
- **Speech.** English, French, German, Spanish and Italian, plus a narrow `en-GB` bracket
  vocabulary. Complete custom languages and regional compositions use the per-call
  [vocabulary extension contract](speech-locales.md). Selection tries the exact supported
  canonical locale, then its base language, then English for the whole reading; it does not
  borrow individual English terms into a selected language. Recognized mathematical symbols
  in `mi`/`mo` have localized names; unknown identifiers, `mtext`, `ms` and ordinary token
  `alt` retain author wording. In elementary numeric rows, embedded `mglyph` content and its
  atomic column are omitted from spatial speech, including image/font glyphs and fallback
  `alt`; spoken column alignment can therefore differ from the drawing. Stacks and divisions
  describe logical columns, carries, crossouts, line
  endpoints and frames without inferring arithmetic meaning. French root/limit templates
  elide `de` before written vowels except `oui`, `onze` and `onzième`; they do not infer silent/
  aspirated `h`, unwritten letter pronunciations or author-text language. Custom composers are
  trusted host code and must produce output proportional to bounded operands. Letter-name
  usage, regional naturalness and novel spatial wording still need human validation in
  [issue #63](https://github.com/vocaro/MathMLLayout/issues/63). See [Spoken readings](speech.md).

[Documentation index](../README.md#documentation)
