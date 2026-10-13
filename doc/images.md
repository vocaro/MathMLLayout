# Images

An `mglyph` draws the image its `src` names, which the host supplies:

See [Images.swift](examples/Images.swift) for the complete Swift example.

- The image is sized by the `mglyph`'s `width`, `height` and `valign`; without them it is one
  pixel to the point, sitting on the baseline. It may stand in any token, among its text, or
  alone in a row.
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

[Documentation index](../README.md#documentation)
