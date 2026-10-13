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
  it against the document yourself, and refuse what the document may not load.
- In a `MathMLNode` you build yourself, mark each `mglyph`'s place in its token's `text` with
  U+FFFC and keep the element, with its attributes, among the token's `children`.
  `MathMLNode.parse(xml:)` does this.

For `mo` geometry opt-ins and attribute precedence, see [Image operators](image-operators.md).

[Documentation index](../README.md#documentation)
