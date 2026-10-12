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
