import CoreGraphics
import Foundation
import MathMLLayout

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
