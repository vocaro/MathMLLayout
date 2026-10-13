# Table alignment groups

LTR and RTL table columns follow the side-width algorithm in
[MathML 3, section 3.5.5](https://www.w3.org/TR/MathML3/chapter3.html#presm.maligngroup).
Each `maligngroup` starts a group. Corresponding groups share the maximum widths on each side
of their alignment point; missing trailing groups act as empty groups. Ungrouped cells use
ordinary `columnalign`, and a wider heading shifts the complete aligned cells together.

`groupalign` resolves from table, row, cell, then group. An enclosing `mstyle` supplies a table
default, which an explicit table setting overrides. Table and row values are braced lists
such as `{right left} {decimalpoint}`; cells use unbraced lists. Last values and last lists
repeat. Explicit `malignmark` overrides automatic left, right, center, or decimal-point
alignment. Only the first mark in source order applies. A mark addresses the immediate
neighbour's edge; a missing neighbour contributes a zero-width edge at the mark.

The renderer uses glyph ink for ordinary element edges and advances for numeric digits,
explicit spaces, text whitespace, and embedded token marks. Internal spacing within a group
remains unchanged; group boundaries acquire the spacing required by the shared side widths.
Decimal alignment uses the first number reachable on the group's
baseline, its first inherited `decimalpoint` character, or the number's end when no decimal
is present. With no reachable number, it uses the group's right edge. Numbers in scripts and
fractions do not capture decimal alignment. Explicit marks may appear within these structures.

Groups can cross nested rows and styles, including redundant `dir="ltr"` declarations,
and pass through phantoms, expanded fences, selected
actions and semantics. Groups inside other layout schemata do not subdivide the outer cell.
A nested table consumes marks in its own alignment scopes. Its `alignmentscope="false"`
columns instead expose their explicit marks to the enclosing scope. Boolean scope lists
repeat their last value. Labeled-row labels do not participate in column alignment.

Embedded token marks preserve their raw UTF-16 position in the marker child's
`MathMLNode.tokenTextOffset`. The XML parser sets this field without changing token text.
A host building a tree may set the field directly; nil means the displayed token content's end,
including glyphs appended by the host-marker convention and excluding a string's closing quote.
Explicit positions are clamped to the raw text's bounds; positions inside a surrogate pair round
down to that scalar's start. Positions are mapped through whitespace normalization, glyph
fallback expansion, string quotes, and variant mapping. Inline images, legacy font glyphs, and
decorated fallbacks contribute their rendered box advances. Undecorated fallbacks retain
full-token shaping. Explicitly enlarged or stretched image operators scale their alignment
points with their drawing. Mapping never resolves a glyph or lays out a prefix again.

## Staged interactions

Aligned cells remain indivisible when a maximum width is supplied; overflow is reported through
the ordinary layout width. A cell with forced line breaks uses normal cell wrapping and opts out
of alignment groups. A cell declaring a non-default `rowspan` or `columnspan` also opts out.
MathML 3 leaves line-breaking and span interactions unspecified, so these policies retain
predictable content geometry until a fuller table grid implementation is available.

Rows, inferred rows and table columns progress in their inherited direction. Source group
indices and attribute lists retain source order: in an RTL table, the first column and first
group section are rightmost, and missing trailing groups reserve space on the left. `left`
and `right` remain physical edges; decimal numbers retain LTR digit order. Explicit row marks
select the physical neighbour specified by `edge`, so that neighbour changes source side in
RTL. Token marks retain their mapped positions within the token's shaped text or attachments.
Labels remain on their authored physical `side`, outside the reflected main grid. Column and
row rules, including interruptions for spans, use that grid's physical edges.

A nested row or style that changes effective direction forms an atomic extent in the enclosing
group. Its internal marks, numbers and groups do not propagate; its advance, ink overhang and
background do. A declaration that preserves direction retains groups. This rule applies in
both directions. Such rows resolve their own line breaks before joining an outer paragraph.
Ordinary RTL row breaks retain source order and place each line from right to left; glyphs and
images retain their original drawing orientation. Indentation and column alignment continue
to use physical left/right coordinates.

This support is scoped to rows and tables. Scripts, radicals and other layout schemata retain
their existing geometric policies; it does not implement full MathML 3 RTL schema mirroring.
Elementary grid columns retain MathML 3's explicit LTR policy. The staged group line-break
and span policies above remain unchanged.

Metadata visits only the laid-out tree and is retained inside cells. Group measurements and
column side-width scans are linear in event count; restoring source priority for deferred
children sorts marker events, bounded by the node limit. Drawing paths and background prefix ranges
add a factor bounded by the existing depth limit. The ordinary node, text, drawing-item,
stack, extent, and layout-retry bounds continue to apply. No new unrestricted subtree search
or layout retry is introduced. Token offset mapping scans bounded source and resolved text;
only the first mark is measured, using one shaping line per existing textual part.

[Documentation index](../README.md#documentation)
