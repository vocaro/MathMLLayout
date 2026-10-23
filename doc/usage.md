# Usage

See [Drawing.swift](examples/Drawing.swift) for the complete Swift example.

- `MathMLNode` is a parser-independent tree. Build it from your own DOM, or parse XML with
  `MathMLNode.parse(xml:)`.
- `MathLayout` is immutable and thread-safe.
- Unsupported markup throws `MathLayoutError.unsupported(element)`; show the formula's `alttext`
  instead. `accessibilityDescription` is a spoken reading for formulas without one.

## Regenerating the README gallery

The [README gallery](../README.md#rendering-examples) renders the checked-in
[MathML examples](examples/mathml) with [RenderGallery.swift](examples/RenderGallery.swift).
On macOS 27 with Xcode 27, run these commands from the repository root:

```sh
swift build
gallery_build="$(swift build --show-bin-path)"
swiftc -swift-version 6 -target "$(uname -m)-apple-macosx27.0" -parse-as-library \
  -I "$gallery_build" -L "$gallery_build" -lMathMLLayout \
  doc/examples/RenderGallery.swift -o .build/render-gallery
.build/render-gallery
```

This writes three PNGs to `doc/renderings/`. Each uses STIX Two Math at 28 points,
centered on a white 320 × 120-point canvas at 2× resolution. If you change a MathML
example, update the corresponding markup in the README as well.

[Documentation index](../README.md#documentation)
