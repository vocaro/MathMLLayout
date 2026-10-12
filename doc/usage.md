# Usage

See [Drawing.swift](examples/Drawing.swift) for the complete Swift example.

- `MathMLNode` is a parser-independent tree. Build it from your own DOM, or parse XML with
  `MathMLNode.parse(xml:)`.
- `MathLayout` is immutable and thread-safe.
- Unsupported markup throws `MathLayoutError.unsupported(element)`; show the formula's `alttext`
  instead. `accessibilityDescription` is a spoken reading for formulas without one.

[Documentation index](../README.md#documentation)
