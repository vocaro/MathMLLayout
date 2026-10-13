# Image operators

MathMLLayout preserves an `mo` containing `mglyph` at its author-sized dimensions and baseline
by default, in inline and display math. This includes text beside the image. `width`, `height`
and `valign` first establish each image's geometry according to
[MathML 3 §3.2.1.2.2](https://www.w3.org/TR/MathML3/chapter3.html#presm.mglyph).
Dictionary defaults continue to supply spacing, fences, accents and limit behavior, but do not
scale or reposition image tokens.

An explicit `stretchy="true"` on the `mo` opts into MathMLLayout's affine geometry extension.
[MathML 3 §3.2.5.8](https://www.w3.org/TR/MathML3/chapter3.html#presm.mo.stretch) leaves reasonable
stretch directions to the renderer. We use the direction of the operator's surrounding text:
a single recognized horizontal arrow/accent character stretches horizontally in under/over
structures; other text and image-only operators stretch vertically to row siblings. `alt` does
not name an operator or choose a direction. To make an image-only horizontal arrow, include arrow text in the token.

The complete token stretches along that axis, including every image, surrounding text and image
background. Vertical stretching covers sibling height/depth exactly; `symmetric` uses the
resolved operator property and centers about the math axis. `symmetric="false"` uses the
siblings' vertical center instead. With no siblings the center is the math axis. Horizontal
stretching retains the token baseline. The default minimum is the complete author's token size;
`minsize` and `maxsize` resolve relative values against that size, before any display enlargement.
Explicit bounds can shrink the token below its author size when `minsize` allows it. A negative
minimum is zero, and minimum wins when bounds conflict. Output remains subject to layout bounds.

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

No image is treated as a font construction. Neither italic correction nor top-accent attachment
is inferred from an image or from neighboring text. Limits and accents use the complete token's
width and geometric center. Image-only horizontal direction cannot currently be requested
without adding text. In elementary-math numbers, each resolved `mglyph` or its fallback occupies
one numeric column; see [Images](images.md).

[Documentation index](../README.md#documentation)
