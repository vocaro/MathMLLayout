# MathMLLayout

Native presentation-MathML layout and drawing for iOS/iPadOS and macOS 27+. It typesets with
CoreText and the OpenType MATH table of the system's STIX Two Math font. There is no web view,
no script engine and no UI framework: lay a formula out on any thread, then draw it into any
`CGContext`. Requires Swift 6.2 and Xcode 27. MIT licensed.

[EPUBLib](https://github.com/vocaro/EPUBLib) uses it to show MathML in its native EPUB viewer.

## Usage

```swift
import CoreGraphics
import Foundation
import MathMLLayout

func drawQuotient(in context: CGContext) throws {
    let markup = #"<math display="block"><mfrac><mi>a</mi><msup><mi>b</mi><mn>2</mn></msup></mfrac></math>"#
    let formula = try MathMLNode.parse(xml: Data(markup.utf8))
    let layout = try MathLayout(formula, style: MathStyle(
        fontSize: 17, color: CGColor(gray: 0, alpha: 1), isDisplay: true))
    // The box covers all the ink: `width` wide, `ascent` above and `descent` below the baseline.
    // The context's y axis points up; put the baseline `descent` above the box's bottom.
    layout.draw(in: context, baselineOrigin: CGPoint(x: 0, y: layout.descent))
    print(formula.accessibilityDescription) // "start fraction a over b squared end fraction"
}
```

- `MathMLNode` is a parser-independent tree. Build it from your own DOM, or parse XML with
  `MathMLNode.parse(xml:)`.
- `MathLayout` is immutable and thread-safe.
- Unsupported markup throws `MathLayoutError.unsupported(element)`; show the formula's `alttext`
  instead. `accessibilityDescription` is an English spoken reading for formulas without one.

## Supported markup

- **Tokens:** `mi`, `mn`, `mo`, `mtext`, `ms`, `mspace`.
- **Grouping:** `math`, `mrow`, `mstyle`, `mpadded`, `mphantom`, `semantics`, `maction`, `merror`.
- **Scripts and limits:** `msup`, `msub`, `msubsup`, `mmultiscripts` (with `mprescripts`/`none`),
  `mover`, `munder`, `munderover`.
- **Fractions and roots:** `mfrac` (including `linethickness` and `bevelled`), `msqrt`, `mroot`.
- **Fences and enclosures:** `mfenced`, `menclose`.
- **Tables:** `mtable`, `mtr`, `mtd`, `mlabeledtr`.

`mo` follows an operator dictionary for form, spacing, stretchiness, large operators and fences.
Stretchy operators use the font's MATH variants and assemblies. Attributes include `displaystyle`,
`scriptlevel`, `mathvariant`, `mathsize`, `mathcolor`, `columnalign` and table spacing.

Layout follows MathML Core with TeX's choices where it leaves room: a unary minus after `=` or
`(`, and a delimiter factor and shortfall so `f(x)` keeps plain parentheses.

## Font

MathML layout needs an OpenType MATH font. iOS and macOS both install STIX Two Math, so nothing
is bundled. `MathStyle.fontName` selects another installed MATH font by PostScript name. A font
without a MATH table still lays out, with built-in constants and drawn stretchy operators.

## Bounds

Input is treated as untrusted. A formula deeper than 64 levels, larger than 20,000 nodes, longer
than 50,000 UTF-16 units of text, more than 50,000 points in any dimension, or with more than
100,000 drawing items throws `MathLayoutError.limitExceeded`. `MathMLNode.parse(xml:)` refuses
document type declarations, so no entity expands and nothing external loads; it reads at most
4 MiB.

## Limitations

- No line breaking. Hosts scale a formula that is too wide.
- No `mglyph`, and no elementary-math elements (`mstack`, `mlongdiv`, `msgroup`, `msrow`, `mscarries`).
- Cell spans in `mtable` are ignored, and rows align on their baselines only.
- No kerning from the font's MathKernInfo.
- The spoken reading is English only.

## Testing

```sh
swift test
```

For iOS, run the same tests on a simulator, for example:

```sh
xcodebuild test -scheme MathMLLayout -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Notices

MathMLLayout contains no third-party code. Its layout follows the W3C MathML Core and OpenType
MATH table specifications and appendix G of *The TeXbook*. It draws with the copy of STIX Two
Math (SIL Open Font License 1.1, Copyright 2001–2021 The STIX Fonts Project Authors) that Apple's
platforms install; it does not distribute the font.
