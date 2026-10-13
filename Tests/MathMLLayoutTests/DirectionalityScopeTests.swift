import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

final class DirectionalityScopeTests: XCTestCase {
    /// Invalid direction attributes must preserve both token and alignment direction.
    /// Otherwise an RTL table silently changes its alignment order.
    func testInvalidDirectionKeepsInheritedRTLAlignmentPolicy() throws {
        func space(_ width: Int) -> String { "<mspace width='\(width)em'/>" }
        let first = "<maligngroup/>" + space(1) + "<maligngroup/>" + space(2)
        let second = "<maligngroup/>" + space(3) + "<maligngroup/>" + space(1)
        let table = "<mtable><mtr><mtd>\(first)</mtd></mtr><mtr><mtd>\(second)</mtd></mtr></mtable>"
        let reference = try innerBox("<mstyle dir='rtl'>\(table)</mstyle>")
        XCTAssertEqual(reference.width, 5 * em, accuracy: 0.001)
        for value in ["invalid", "", "auto"] {
            for element in ["mtable", "mtr", "mtd"] {
                let invalid = table.replacingOccurrences(of: "<\(element)>", with: "<\(element) dir='\(value)'>")
                let box = try innerBox("<mstyle dir='rtl'>\(invalid)</mstyle>")
                XCTAssertEqual(box.width, reference.width, accuracy: 0.001, "\(element) dir='\(value)'")
            }
            let box = try innerBox("<mstyle dir='rtl'><mstyle dir='\(value)'>\(table)</mstyle></mstyle>")
            XCTAssertEqual(box.width, reference.width, accuracy: 0.001, "mstyle dir='\(value)'")
        }
        // A valid descendant override still changes the table back to LTR alignment.
        let overridden = try innerBox("<mstyle dir='rtl'><mstyle dir='ltr'>\(table)</mstyle></mstyle>")
        XCTAssertEqual(overridden.width, 5 * em, accuracy: 0.001)
    }
}
