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
  instead. `accessibilityDescription` is a spoken reading for formulas without one.

## Line breaking

Give a layout the width of its line and it breaks into rows that fit:

```swift
func drawBroken(_ formula: MathMLNode, style: MathStyle, in context: CGContext) throws {
    // A display formula in a 320-point column: every row, stacked under the first row's baseline.
    let block = try MathLayout(formula, style: style, maximumWidth: 320)
    block.draw(in: context, baselineOrigin: CGPoint(x: 0, y: block.descent))

    // An inline formula that starts where 90 points are left on its text line. Each row is a
    // fragment with its own box: place one on each following text line and draw it there.
    let inline = try MathLayout(formula, style: style, maximumWidth: 320, firstRowMaximumWidth: 90)
    var baseline = CGPoint(x: 230, y: 400)
    for row in inline.rows {
        row.draw(in: context, baselineOrigin: baseline)
        baseline = CGPoint(x: 0, y: baseline.y - 24)
    }
}
```

- **Where it breaks.** Where the markup says (`linebreak="newline"`, at any width), and otherwise
  at operators ranked by the operator dictionary: at a relation sooner than at `+` or `−`, and
  there sooner than at `×` or an invisible times, with a penalty for each level of nesting. Never
  before a sign, after an opening fence, before a closing fence, or between a function and its
  argument. Separators break after; other operators start the next row and keep their spacing.
- **How deep.** Inside nested `mrow`, `mstyle` and `mfenced`, and inside the base of a script. A
  bracket pair split across rows keeps one size. Long `mtext` wraps at its spaces. A table wider
  than the line narrows its columns and wraps its cells; fraction parts, radicands and
  `menclose` contents wrap the same way.
- **Attributes** (MathML 3 §3.1.7): `linebreak`, `linebreakstyle`, `linebreakmultchar`,
  `lineleading`, `indentalign`, `indentshift`, `indenttarget` and their `first`/`last` forms, on
  `mo` and `mspace` or inherited from `mstyle` and `math`. Unless they say otherwise rows align
  left, and a display formula indents the rows after its first by one em.
- **Rows.** `rows` gives each row's `origin` (its baseline's left end, relative to the layout's),
  `width`, `ascent` and `descent`. The layout's baseline is its first row's, so `descent` reaches
  down through the last row. Each row's box covers its own ink.
- **Too wide anyway.** A unit that cannot break (a long number, a wide radical) makes its row
  overflow. `widestUnbreakableWidth` is the narrowest `maximumWidth` at which none does; when it
  is more than the line, scale the formula.
- `axisHeight` is the math axis's height above the baseline, for centring rows as a table does.

## Images

An `mglyph` draws the image its `src` names, which the host supplies:

```swift
func style(images: [String: CGImage]) -> MathStyle {
    let provider = MathImageProvider { source in images[source] }
    return MathStyle(fontSize: 17, color: CGColor(gray: 0, alpha: 1), imageProvider: provider)
}
```

- The image is sized by the `mglyph`'s `width`, `height` and `valign`; without them it is one
  pixel to the point, sitting on the baseline. It may stand in any token, among its text, or
  alone in a row.
- With no provider, or when it returns nil, the `alt` text is drawn in its place, or U+25AF when
  there is none. Nothing throws.
- `src` reaches the provider as written. It is as untrusted as the rest of the markup: resolve
  it against the document yourself, and refuse what the document may not load.
- In a `MathMLNode` you build yourself, mark each `mglyph`'s place in its token's `text` with
  U+FFFC and keep the element, with its attributes, among the token's `children`.
  `MathMLNode.parse(xml:)` does this.

## Spoken readings

```swift
func reading(of formula: MathMLNode) -> String {
    let reading = formula.accessibilityDescription(locale: Locale(identifier: "fr-CA"))
    // reading.language is "fr": speak reading.text with a French voice.
    return reading.text // "début de fraction a sur b au carré fin de fraction"
}
```

`accessibilityDescription(locale:)` reads a formula in English, French, German, Spanish or Italian
(`MathReading.languages`), whatever the locale's region. For any other language it returns the
English reading with `language` set to `"en"`, so the voice can match the words.
`accessibilityDescription` is the English reading. Stacks and long divisions are read row by row,
and an `mglyph` by its `alt`.

## Supported markup

- **Tokens:** `mi`, `mn`, `mo`, `mtext`, `ms`, `mspace`, `mglyph`.
- **Grouping:** `math`, `mrow`, `mstyle`, `mpadded`, `mphantom`, `semantics`, `maction`, `merror`.
- **Scripts and limits:** `msup`, `msub`, `msubsup`, `mmultiscripts` (with `mprescripts`/`none`),
  `mover`, `munder`, `munderover`.
- **Fractions and roots:** `mfrac` (including `linethickness` and `bevelled`), `msqrt`, `mroot`.
- **Fences and enclosures:** `mfenced`, `menclose`.
- **Tables:** `mtable`, `mtr`, `mtd`, `mlabeledtr`.
- **Elementary math** (MathML 3 §3.6): `mstack`, `mlongdiv`, `msgroup`, `msrow`, `mscarries`,
  `mscarry`, `msline`: digit columns with `stackalign`, `charalign`, `charspacing`, `position` and
  `shift`; lines with their length, overhangs and thickness; carries with `location`, `crossout`
  and `scriptsizemultiplier`; and all ten `longdivstyle` values.

`mo` follows an operator dictionary for form, spacing, stretchiness, large operators and fences.
Stretchy operators use the font's MATH variants and assemblies. Attributes include `displaystyle`,
`scriptlevel`, `mathvariant`, `mathsize`, `mathcolor`, `columnalign` and table spacing.

Layout follows MathML Core with TeX's choices where it leaves room: a unary minus after `=` or
`(`, and a delimiter factor and shortfall so `f(x)` keeps plain parentheses. Text is an operand
to the operators beside it, so a word equation (`<mtext>` operands) is spaced like any other.
A label on a stretchy arrow is placed by the MATH table's StretchStack constants as OpenType
defines them, with the shifts from the baseline
([w3c/mathml-core#121](https://github.com/w3c/mathml-core/issues/121)); Core's text has them
from the arrow's ink, which sets the label far too high with STIX Two Math.

## Font

MathML layout needs an OpenType MATH font. iOS and macOS both install STIX Two Math, so nothing
is bundled. `MathStyle.fontName` selects another installed MATH font by PostScript name. A font
without a MATH table still lays out, with built-in constants and drawn stretchy operators.

## Bounds

Input is treated as untrusted. A formula deeper than 64 levels, larger than 20,000 nodes, longer
than 50,000 UTF-16 units of text, more than 50,000 points in any dimension, or with more than
100,000 drawing items throws `MathLayoutError.limitExceeded`. So does one nested deeper than the
calling thread's stack has room for, within those 64 levels: a thread other than the main one
has 512 KB, which an unoptimized build spends in about twenty levels. Readings are bounded the
same way and leave out what is past the bounds. `MathMLNode.parse(xml:)` refuses document type
declarations in any encoding, so no entity expands and nothing external loads; it reads at most
4 MiB.

## Limitations

- **Line breaking.** No breaks inside `mpadded`, `mphantom`, `merror`, `munder`/`mover`/
  `munderover`, a script, or a row with a `mathbackground`; none between adjacent identifiers or
  inside a number. A stretchy operator keeps the size it has in the unbroken row, so brackets
  whose tall content moved to another row stay tall. `indenttarget` must name a child of a row
  being broken, on an earlier row. `malignmark` and `maligngroup` align nothing. A table inside
  a table cell does not narrow, and `mtext` with a right-to-left run or an image does not wrap.
  Where several wrapping units share a row (two radicals side by side), a row can still run a
  few percent past `widestUnbreakableWidth`.
- **`mglyph`.** MathML 2's `fontfamily` and `index` glyphs have no image and show their `alt`.
  An image has no scale of its own: size a 2x asset with `width` and `height`.
- **Elementary math.** Columns run left to right only. `decimalpoint` names one character. An
  `mglyph` in a stack's number is not drawn. Division frames are drawn, not font glyphs.
- **Speech.** Five languages, without regional variants or grammatical agreement. Token text and
  `alt` are spoken as written. A stack's reading gives its rows, carries and lines in order,
  not their column positions.
- Cell spans in `mtable` are ignored, and rows align on their baselines only.
- No kerning from the font's MathKernInfo.

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
