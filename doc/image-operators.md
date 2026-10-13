# Image operators

MathMLLayout preserves an `mo` containing `mglyph` at its author-sized dimensions and baseline
by default, in inline and display math. This includes text beside the image. `width`, `height`
and `valign` first establish each image's geometry according to
[MathML 3 §3.2.1.2.2](https://www.w3.org/TR/MathML3/chapter3.html#presm.mglyph).
Dictionary defaults continue to supply spacing, fences, accents and limit behavior, but do not
scale or reposition image tokens.

An explicit `stretchy="true"` on the `mo` opts into MathMLLayout's affine geometry extension.
[MathML 3 §3.2.5.8](https://www.w3.org/TR/MathML3/chapter3.html#presm.mo.stretch) leaves reasonable
stretch directions to the renderer. The renderer-specific `imagestretchdirection="horizontal"`
or `"vertical"` attribute on the core `mo` chooses the whole token's axis. Invalid values are
ignored. This attribute is not inherited from `mstyle` or a wrapper; put it on the `mo`.
Without it, actual operator text determines direction: a recognized horizontal arrow/accent
character stretches horizontally; other nonempty text stretches vertically. An image-only
token with exactly one `mglyph` can instead use its host-supplied `MathImage.stretchDirection`.
Without a hint, or with multiple image children, the direction is vertical. `alt` does not name
an operator or choose a direction. Direction never enables geometry by itself: the core `mo`
still needs explicit `stretchy="true"`, and display enlargement still needs explicit
`largeop="true"`. These opt-ins are not inherited either; inherited `displaystyle`, `mathsize`
and script style continue to control layout normally.

For an image-only labelled arrow, no visible operator text is necessary:

```xml
<mover>
  <mo stretchy="true" imagestretchdirection="horizontal"><mglyph src="arrow" alt="maps to"/></mo>
  <mtext>label</mtext>
</mover>
```

The complete token stretches along that axis, including every image, surrounding text and image
background. Vertical stretching covers sibling height/depth exactly; `symmetric` uses the
resolved operator property and centers about the math axis. `symmetric="false"` uses the
siblings' vertical center instead. With no siblings the center is the math axis. Horizontal
stretching retains the token baseline. The default minimum is the complete author's token size;
`minsize` and `maxsize` resolve relative values against that size, before any display enlargement.
Explicit bounds can shrink the token below its author size when `minsize` allows it. A negative
minimum is zero, and minimum wins when bounds conflict. Output remains subject to layout bounds.
If a subnormal intrinsic size would require a nonfinite affine factor, its author-sized
geometry is retained rather than creating nonfinite coordinates.

An explicit `largeop="true"` opts into display enlargement: the whole token scales uniformly to
at least √2 times its author height and the font's DisplayOperatorMinHeight, then centers on the
math axis. Inline math retains author sizing. When both opt-ins are present, display enlargement
happens first; stretching and its min/max constraints then determine the final stretched axis,
and vertical stretch positioning supersedes display centering and image `valign`.
These are image-specific extension rules inspired by the font-operator metrics in
[MathML Core §3.2.4.3](https://www.w3.org/TR/mathml-core/#layout-of-operators); Core does not
define `mglyph` layout. They do not require image assets to supply OpenType MATH data.

`stretchy="false"` disables stretching, including min/max and symmetric effects;
`largeop="false"` disables display enlargement and its centering. These switches are independent.
Neither dictionary `largeop` nor dictionary `stretchy` alone changes an image token's geometry.
The same opt-in policy applies to every `mglyph` child, including deprecated `fontfamily`/`index`
forms and children falling back to `alt`; resolution does not change attribute semantics. This extension is renderer-specific: other MathML implementations may
retain author dimensions, scale differently, or ignore image operator geometry. Authors requiring
portable exact dimensions should use explicit false attributes.

No image is treated as a font construction. Optional host-supplied `MathImage.italicCorrection`
and `topAccentAttachment` provide genuine source metrics in intrinsic logical points; see
[Images](images.md) for bounds and composition rules. A token consisting of exactly one
resolved image preserves those metrics. They scale along x through authored image sizing,
uniform display enlargement and whole-token affine stretching; vertical scaling and baseline
shifts do not alter horizontal coordinates. Eligible scripts use italic clearance, limits use
half the correction on each side, and accents align the physical attachment coordinates.
RTL changes placement without mirroring the image, its physical right clearance or its
attachment coordinate. Mixed text/image and multiple-image tokens have no whole-token
attachment metrics: limits and accents retain geometric placement. Neither pixels,
neighboring text nor `alt` supplies inferred metrics. In elementary-math numbers, each resolved
`mglyph` or its fallback occupies one numeric column; see [Images](images.md).

[Documentation index](../README.md#documentation)
