import CoreGraphics
import Foundation
import MathMLLayout

func reading(of formula: MathMLNode) -> String {
    let reading = formula.accessibilityDescription(locale: Locale(identifier: "fr-CA"))
    // reading.language is "fr": speak reading.text with a French voice.
    return reading.text // "début de fraction a sur b au carré fin de fraction"
}

func regionalReading(of formula: MathMLNode) -> MathReading {
    let reading = formula.accessibilityDescription(locale: Locale(identifier: "en-GB"))
    // reading.language is "en-GB": use a matching host voice for British bracket names.
    return reading
}
