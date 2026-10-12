# MathMLLayout

MathMLLayout typesets and draws presentation MathML in native iOS, iPadOS and macOS apps.
It uses CoreText and the system's STIX Two Math font, and draws into any `CGContext`.
Layouts are immutable and thread-safe, so you can prepare formulas off the main thread.

Requires iOS/iPadOS or macOS 27+, Swift 6.2 and Xcode 27.

## Quick start

Parse a formula, create a layout, then draw it into a context whose y axis points up:

```swift
import CoreGraphics
import Foundation
import MathMLLayout

// `context` is the CGContext supplied by your drawing code.
let markup = #"<math display="block"><mfrac><mi>a</mi><msup><mi>b</mi><mn>2</mn></msup></mfrac></math>"#
let formula = try MathMLNode.parse(xml: Data(markup.utf8))
let layout = try MathLayout(formula, style: MathStyle(
    fontSize: 17, color: CGColor(gray: 0, alpha: 1), isDisplay: true))
layout.draw(in: context, baselineOrigin: CGPoint(x: 0, y: layout.descent))
```

See the [usage guide](doc/usage.md) and [complete drawing example](doc/examples/Drawing.swift)
for layout bounds, parsing and spoken readings.

## Documentation

- [Usage](doc/usage.md): parsing, layout and drawing.
- [Line breaking](doc/line-breaking.md): wrapping formulas and placing rows.
- [Images](doc/images.md): supplying images for `mglyph`.
- [Spoken readings](doc/speech.md): accessibility and language selection.
- [Supported markup](doc/markup.md): elements, attributes and layout rules.
- [Fonts](doc/fonts.md): font selection and fallbacks.
- [Bounds and limitations](doc/limits.md): input limits and unsupported behavior.
- [Testing](doc/testing.md): debug, release, simulator and fuzz testing.
- [Notices](doc/notices.md): specification and font acknowledgments.

The guides link to Swift source examples in [doc/examples](doc/examples).
Release history is in the [changelog](CHANGELOG.md).

## License

MathMLLayout is available under the [MIT license](LICENSE).
