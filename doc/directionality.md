# Directionality

`dir="rtl"` changes structural progression independently of token text. A valid `ltr` or
`rtl` value is inherited; a descendant can override it, including directly on a schema.
Invalid values preserve the inherited policy. The default structural direction is LTR.
This follows [MathML 3 §3.1.5](https://www.w3.org/TR/MathML3/chapter3.html#presm.bidi):
vertical shifts stay the same, and leading/trailing placement reverses. Components are
placed individually; no complete formula or token bitmap is reflected.

| Elements | Direction policy |
| --- | --- |
| `math`, `mrow`, inferred rows, `mstyle` | Children progress in source order from the leading side: right in RTL. |
| `msub`, `msup`, `msubsup` | Postscripts attach on the left in RTL. Subscript depth, superscript height and pair gaps use the same MATH constants as LTR. |
| `mmultiscripts`, `mprescripts`, `none` | Postscripts go on the left, prescripts on the right in RTL. Each list keeps source progression order; prescripts progress toward the base and postscripts away from it. Empty slots retain the existing pair spacing. |
| `msqrt`, `mroot` | The surd goes on the right in RTL, its bar extends left over the radicand, and the degree sits at the sign's upper right. Only the generated surd outline is reflected, including MATH variants/assemblies and drawn fallbacks. Wrapped radicands align toward the sign. |
| `mfrac` | Stacked numerator and denominator remain vertically arranged. `numalign` and `denomalign` use physical left/right. A bevelled numerator leads on the right in RTL, the denominator follows on the left, and the generated slash reverses its slope. A literal slash in `mo` retains Unicode's text policy. |
| `munder`, `mover`, `munderover` | Children inherit their own direction and remain vertically stacked and centered. Accents use the actual glyph's physical attachment point; limits retain the actual glyph's slant correction. Inline movable limits use the script policy, attaching on the left in RTL. |
| `mpadded` | `lspace` is leading space: content's physical left edge is `width − lspace − content.width` in RTL. Relative/pseudo-unit dimensions and vertical offsets retain their existing meaning. |
| `menclose` | Surds and long-division curves move to the leading/right side in RTL; actuarial and madruwb vertical sides move to the trailing/left side. Only these directional decorations change. Explicit `left`/`right`, top/bottom, strikes and `updiagonalarrow` remain physical. Combined notations retain each notation's policy. |
| `mfenced` | Fences and separators use ordinary row progression and token shaping. Stretched font glyphs and drawn fence fallbacks use the corresponding physical RTL fence. |
| `mphantom`, `merror`, `semantics`, `maction` | Content or the selected child inherits direction. Phantom geometry, symmetric error frames and selection policies retain their existing meaning. |
| `mtable`, `mtr`, `mlabeledtr`, `mtd` | Columns follow structural progression; source attribute lists keep source order. Alignment modes and label sides remain physical. See [alignment groups](alignment-groups.md). |
| Elementary math | Grids, digits, carries' column order and division frames retain the explicit LTR policy, independently of surrounding direction. Carry/token contents still inherit text direction. See [elementary direction](elementary-direction.md). |

CoreText shapes each token separately, preserving Arabic joining, Hebrew ordering, combining
marks and Unicode mirroring. Numbers remain LTR. Latin letters, digits and host images keep
their drawing orientation when their component moves. Local overrides can therefore put an
LTR expression inside an RTL radical, or an RTL expression inside an LTR script base.

Script corner kerning samples the physical adjoining corners: an RTL postscript uses the
base's left corners and the script's right corners. A glyph's right-side italic correction
does not become a left overhang when that unchanged glyph acquires a left-side postscript.
Accent attachment and limit slant are likewise font/glyph geometry, not reflected child
coordinates. Compound/fallback/assembled boxes retain the documented zero-corner-kern policy.

Explicit alignment marks within a schema are translated with the child that owns them.
Groups inside a schema do not subdivide the outer table cell; the explicit mark can still
align the entire schema. Direction-changing rows/styles retain the existing atomic scope
policy. Same-direction script bases can fragment in source order, holding scripts to the
last base fragment; opposite-direction rows and locally overridden script structures resolve
their internal breaks before joining the enclosing paragraph. Root `math` establishes the
paragraph direction without prematurely stacking it. Existing ID-anchor scope limitations
continue to apply.

Restrictions remain the same in both directions: under/over structures are centered (`align`
on them is not implemented), script annotations and operator bases stay atomic, and unknown
enclosure notations are ignored. Breakable under/over bases repeat their attached annotations;
explicit padding resolves against each host-row fragment. Mixed image/text bidi tokens use
logical paragraph ranges and per-line shaping, preserving local fallback backgrounds and
image baseline placement. Direction does not add CSS layout or arbitrary Unicode glyph
substitutions beyond CoreText shaping. See the [fragmentation policy](line-breaking.md).
The node, text/assembly work, drawing-item, extent, retry and stack limits remain in force.
See [bounds and limitations](limits.md) for measured worker coverage.

`RTLSchemaTests` checks numeric component placements, sign contours, Arabic/Hebrew and mixed
nesting, token shaping, explicit table marks, wrapping minima and ink containment with STIX
and a non-MATH fallback font. `MathKernTests` independently checks physical RTL corners with
synthetic font data. `WorkerDepthTests` compares the 64-level RTL schema matrix on exact
512 KB and 8 MB stacks, including geometry, drawing items, ink, pixels and all base-language
readings.

[Documentation index](../README.md#documentation)
