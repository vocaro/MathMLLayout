# Images

An `mglyph` draws the image its `src` names, which the host supplies:

See [Images.swift](examples/Images.swift) for the complete Swift example.

- The image is sized by the `mglyph`'s `width`, `height` and `valign`, sitting on the baseline
  unless raised or lowered. It may stand in any token, among its text, or alone in a row.
- `MathImageProvider { source in images[source] }` keeps the original one-pixel-per-point sizing.
  Use `MathImageProvider.resolving` to return a `MathImage` with intrinsic sizing metadata:

  ```swift
  let provider = MathImageProvider.resolving { source in
      images[source].map { MathImage($0, scale: 2) }
  }
  ```

  A 40-by-20-pixel image at scale 2 occupies 20-by-10 points. Alternatively,
  `MathImage(image, logicalSize: CGSize(width: 12, height: 18))` specifies its intrinsic size
  directly, including an aspect ratio different from the pixels.
- `MathImage` also accepts optional renderer-specific source metadata:

  ```swift
  MathImage(image, scale: 2, stretchDirection: .horizontal,
            italicCorrection: 3, topAccentAttachment: 8)
  ```

  The direction is a hint for a single-image `mo`, with markup and actual operator text taking
  precedence. It requires the `mo`'s explicit `stretchy="true"`; see [Image operators](image-operators.md).
  Attachment values are **intrinsic logical points**, after interpreting `scale` or
  `logicalSize`, never pixels or em units. Italic correction is physical right-side script
  clearance, added to image advance; top-accent attachment is x from its physical left edge.
  Each must be finite and between zero and the sanitized intrinsic logical width, inclusive.
  An invalid value is ignored independently, keeping the image and other valid metadata.
  Dimension fallback happens before validating these bounds.
- Metrics scale by rendered-image width divided by intrinsic logical width. Authored height
  changes and `valign` shifts do not alter x metrics; aspect-preserving width changes, display
  enlargement and horizontal affine stretching do. RTL placement retains physical x
  coordinates and right-side clearance. The image and clearance scale down together if their
  combined advance would exceed the normal extent bound.
  Source metrics become whole-token metrics only when the complete displayed token content is
  exactly one resolved image. Mixed text/image tokens and multiple images use zero
  whole-token correction and the geometric accent center; a source coordinate
  does not describe an arbitrary compound token. Each source's advance still includes its
  supplied clearance when composing a mixed token. Missing-image fallbacks receive no image
  metadata; ordinary fallback text retains its existing font-metric behavior.
  No image metrics are inferred from pixels, text or
  `alt`, and no font glyph metrics or corner kerning are fabricated for an image. The general
  unit rules are in
  [shared text layout and Unicode](https://github.com/vocaro/vocaro-engineering/blob/main/knowledge/apple/text-layout-and-unicode.md#font-and-image-metrics-have-different-units).
- Explicit `width` and `height` take precedence over the intrinsic size. With one dimension,
  the other preserves the **logical** aspect ratio. Percentages and unitless multiples refer
  to the logical size: `width="50%"` halves both dimensions, while two explicit dimensions
  can stretch the image. Neither scale nor logical size changes `valign` or shrinks an unsized
  image in a script. Images remain subject to the normal extent bound and are scaled down
  together when needed.
- A scale that is zero, negative, or nonfinite falls back to pixel dimensions. The same holds
  if division by the scale produces a nonpositive or nonfinite dimension, or if either explicit
  logical dimension is nonpositive or nonfinite. Invalid metadata keeps the image available;
  it does not trigger `alt` text. Both provider forms resolve each distinct `src` at most once
  per formula, including missing images.
- Inside an `mn` in `mstack` or the working rows of `mlongdiv`, each image occupies one
  numeric column between the surrounding characters. The column grows to its width, just as
  it does for a digit, and uses the stack's alignment, spacing and carry placement. With no
  image, the entire fallback occupies that same single column, even when it has several
  characters or contains a decimal separator.
- With no provider, or when it returns nil, the `alt` text is drawn in its place, or U+25AF when
  there is none. Nothing throws.
- `src` reaches the provider as written. It is as untrusted as the rest of the markup: resolve
  it against the document yourself, and refuse what the document may not load
  ([shared untrusted-markup screening](https://github.com/vocaro/vocaro-engineering/blob/main/knowledge/apple/document-parsing.md#screen-untrusted-markup-before-any-parser-sees-it)).
- In a `MathMLNode` you build yourself, mark each `mglyph`'s place in its token's `text` with
  U+FFFC and keep the element, with its attributes, among the token's `children`.
  `MathMLNode.parse(xml:)` does this.

For `mo` geometry opt-ins and attribute precedence, see [Image operators](image-operators.md).

[Documentation index](../README.md#documentation)
