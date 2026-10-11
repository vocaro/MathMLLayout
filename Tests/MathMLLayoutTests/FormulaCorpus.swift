import Foundation

/// A formula of the corpus: real-world presentation MathML, written the way converters and
/// authors write it, with the facts its layout must show.
///
/// Parts of a formula are marked with `mathcolor` (red, lime, blue), which changes nothing
/// about the layout; an expectation then relates the ink of two parts. `.rest` is everything
/// left in the default colour.
struct Formula {
    enum Part { case red, green, blue, rest }

    enum Expectation {
        /// `a` ends before `b` begins.
        case leftOf(Part, Part)
        /// `a` is wholly above `b`.
        case above(Part, Part)
        /// `a`'s bottom is above `b`'s middle: a superscript, an upper limit, an accent.
        case raised(Part, over: Part)
        /// `a`'s top is below `b`'s middle: a subscript, a lower limit.
        case lowered(Part, under: Part)
        /// `a` and `b` share a vertical centre line.
        case centred(Part, Part)
        /// `a` reaches as high and as low as `b`, within TeX's delimiter shortfall: a fence, a
        /// radical sign.
        case coversVertically(Part, Part)
        /// `a` is at least nine tenths as wide as `b` and over it: a bar, a brace, an arrow.
        case coversHorizontally(Part, Part)
        /// `a` and `b` stand on one baseline (for parts without descenders).
        case sameBaseline(Part, Part)
        /// `a`'s ink is inside `b`'s: an enclosure's content.
        case inside(Part, Part)
        /// `a` is drawn smaller than `b` (the same glyphs at a script size).
        case smaller(Part, than: Part)
    }

    let name: String
    /// The children of the `math` element.
    let markup: String
    /// Checked in display style.
    var expectations: [Expectation] = []

    init(_ name: String, _ markup: String, _ expectations: [Expectation] = []) {
        self.name = name; self.markup = markup; self.expectations = expectations
    }
}

enum FormulaCorpus {
    static let all: [Formula] = algebra + calculus + linearAlgebra + physics + logicAndSets + decorated + structural

    // MARK: Algebra and arithmetic

    static let algebra: [Formula] = [
        Formula("quadratic formula", #"""
            <mi>x</mi><mo>=</mo>
            <mfrac>
              <mrow mathcolor="red"><mo>−</mo><mi>b</mi><mo>±</mo><msqrt><msup><mi>b</mi><mn>2</mn></msup><mo>−</mo><mn>4</mn><mi>a</mi><mi>c</mi></msqrt></mrow>
              <mrow mathcolor="blue"><mn>2</mn><mi>a</mi></mrow>
            </mfrac>
            """#, [.above(.red, .blue), .centred(.red, .blue)]),
        Formula("Pythagorean theorem", #"""
            <msup><mi mathcolor="blue">a</mi><mn mathcolor="red">2</mn></msup><mo>+</mo>
            <msup><mi>b</mi><mn>2</mn></msup><mo>=</mo><msup><mi>c</mi><mn>2</mn></msup>
            """#, [.raised(.red, over: .blue), .leftOf(.blue, .red)]),
        Formula("Euler's identity", #"""
            <msup><mi mathcolor="blue">e</mi><mrow mathcolor="red"><mi>i</mi><mi>π</mi></mrow></msup><mo>+</mo><mn>1</mn><mo>=</mo><mn>0</mn>
            """#, [.raised(.red, over: .blue), .leftOf(.blue, .red)]),
        Formula("binomial coefficient", #"""
            <mrow><mo mathcolor="lime">(</mo><mfrac linethickness="0"><mi mathcolor="red">n</mi><mi mathcolor="blue">k</mi></mfrac><mo mathcolor="lime">)</mo></mrow>
            <mo>=</mo>
            <mfrac><mrow><mi>n</mi><mo>!</mo></mrow><mrow><mi>k</mi><mo>!</mo><mo stretchy="false">(</mo><mi>n</mi><mo>−</mo><mi>k</mi><mo stretchy="false">)</mo><mo>!</mo></mrow></mfrac>
            """#, [.above(.red, .blue), .coversVertically(.green, .red), .coversVertically(.green, .blue), .centred(.red, .blue)]),
        Formula("binomial theorem", #"""
            <msup><mrow><mo>(</mo><mi>x</mi><mo>+</mo><mi>y</mi><mo>)</mo></mrow><mi>n</mi></msup><mo>=</mo>
            <munderover><mo>∑</mo><mrow mathcolor="blue"><mi>k</mi><mo>=</mo><mn>0</mn></mrow><mi mathcolor="red">n</mi></munderover>
            <mrow><mo>(</mo><mfrac linethickness="0"><mi>n</mi><mi>k</mi></mfrac><mo>)</mo></mrow>
            <msup><mi>x</mi><mrow><mi>n</mi><mo>−</mo><mi>k</mi></mrow></msup><msup><mi>y</mi><mi>k</mi></msup>
            """#, [.above(.red, .blue), .centred(.red, .blue)]),
        Formula("continued fraction", #"""
            <mi>φ</mi><mo>=</mo><mn mathcolor="red">1</mn><mo>+</mo>
            <mfrac><mn>1</mn><mrow><mn>1</mn><mo>+</mo><mfrac><mn>1</mn><mrow><mn>1</mn><mo>+</mo><mfrac><mn>1</mn><mrow><mn>1</mn><mo>+</mo><mi mathcolor="blue">x</mi></mrow></mfrac></mrow></mfrac></mrow></mfrac>
            """#, [.above(.red, .blue), .leftOf(.red, .blue), .smaller(.blue, than: .red)]),
        Formula("golden ratio", #"""
            <mi>φ</mi><mo>=</mo><mfrac><mrow><mn>1</mn><mo>+</mo><msqrt><mn mathcolor="red">5</mn></msqrt></mrow><mn mathcolor="blue">2</mn></mfrac>
            <mo>≈</mo><mn>1.618</mn>
            """#, [.above(.red, .blue)]),
        Formula("nested radicals", #"""
            <msqrt><mn>1</mn><mo>+</mo><msqrt><mn>1</mn><mo>+</mo><msqrt><mn>1</mn><mo>+</mo><mi mathcolor="red">x</mi></msqrt></msqrt></msqrt>
            """#, [.coversVertically(.rest, .red), .coversHorizontally(.rest, .red)]),
        Formula("cube root", #"""
            <mroot><mrow mathcolor="red"><mi>a</mi><mo>+</mo><mi>b</mi></mrow><mn mathcolor="blue">3</mn></mroot>
            <mo>≠</mo><mroot><mi>a</mi><mn>3</mn></mroot><mo>+</mo><mroot><mi>b</mi><mn>3</mn></mroot>
            """#, [.leftOf(.blue, .red), .raised(.blue, over: .red)]),
        Formula("factorial as a product", #"""
            <mi>n</mi><mo>!</mo><mo>=</mo>
            <munderover><mo>∏</mo><mrow mathcolor="blue"><mi>k</mi><mo>=</mo><mn>1</mn></mrow><mi mathcolor="red">n</mi></munderover><mi>k</mi>
            """#, [.above(.red, .blue), .centred(.red, .blue)]),
        Formula("Stirling's approximation", #"""
            <mi>n</mi><mo>!</mo><mo>∼</mo><msqrt><mn>2</mn><mi>π</mi><mi>n</mi></msqrt>
            <msup><mrow><mo mathcolor="lime">(</mo><mfrac><mi mathcolor="red">n</mi><mi mathcolor="blue">e</mi></mfrac><mo mathcolor="lime">)</mo></mrow><mi>n</mi></msup>
            """#, [.above(.red, .blue), .coversVertically(.green, .red), .coversVertically(.green, .blue)]),
        Formula("bevelled fraction in a sentence", #"""
            <mtext>about </mtext><mfrac bevelled="true"><mn mathcolor="red">1</mn><mn mathcolor="blue">3</mn></mfrac><mtext> of the total</mtext>
            """#, [.leftOf(.red, .blue), .raised(.red, over: .blue)]),
        Formula("floor and ceiling", #"""
            <mrow><mo>⌊</mo><mi mathcolor="red">x</mi><mo>⌋</mo></mrow><mo>≤</mo><mi mathcolor="lime">x</mi><mo>≤</mo><mrow><mo>⌈</mo><mi mathcolor="blue">x</mi><mo>⌉</mo></mrow>
            """#, [.leftOf(.red, .green), .leftOf(.green, .blue), .sameBaseline(.red, .blue), .sameBaseline(.red, .green)]),
    ]

    // MARK: Calculus and analysis

    static let calculus: [Formula] = [
        Formula("sum of squares", #"""
            <munderover><mo>∑</mo><mrow mathcolor="blue"><mi>i</mi><mo>=</mo><mn>1</mn></mrow><mi mathcolor="red">n</mi></munderover>
            <msup><mi>i</mi><mn>2</mn></msup><mo>=</mo>
            <mfrac><mrow><mi>n</mi><mo stretchy="false">(</mo><mi>n</mi><mo>+</mo><mn>1</mn><mo stretchy="false">)</mo><mo stretchy="false">(</mo><mn>2</mn><mi>n</mi><mo>+</mo><mn>1</mn><mo stretchy="false">)</mo></mrow><mn>6</mn></mfrac>
            """#, [.above(.red, .blue), .centred(.red, .blue)]),
        Formula("fundamental theorem of calculus", #"""
            <msubsup><mo>∫</mo><mi mathcolor="blue">a</mi><mi mathcolor="red">b</mi></msubsup>
            <mi>f</mi><mo>⁡</mo><mrow><mo>(</mo><mi>x</mi><mo>)</mo></mrow><mspace width="0.167em"/><mi mathvariant="normal">d</mi><mi>x</mi>
            <mo>=</mo><mi>F</mi><mo>⁡</mo><mrow><mo>(</mo><mi>b</mi><mo>)</mo></mrow><mo>−</mo><mi>F</mi><mo>⁡</mo><mrow><mo>(</mo><mi>a</mi><mo>)</mo></mrow>
            """#, [.above(.red, .blue)]),
        Formula("limit of sin x over x", #"""
            <munder><mo>lim</mo><mrow mathcolor="blue"><mi>x</mi><mo>→</mo><mn>0</mn></mrow></munder>
            <mfrac><mrow mathcolor="red"><mi>sin</mi><mo>⁡</mo><mi>x</mi></mrow><mi mathcolor="lime">x</mi></mfrac><mo>=</mo><mn>1</mn>
            """#, [.above(.red, .green), .centred(.red, .green), .lowered(.blue, under: .red)]),
        Formula("definition of the derivative", #"""
            <msup><mi>f</mi><mo>′</mo></msup><mo>⁡</mo><mrow><mo>(</mo><mi>x</mi><mo>)</mo></mrow><mo>=</mo>
            <munder><mo>lim</mo><mrow><mi>h</mi><mo>→</mo><mn>0</mn></mrow></munder>
            <mfrac>
              <mrow mathcolor="red"><mi>f</mi><mo>⁡</mo><mrow><mo>(</mo><mi>x</mi><mo>+</mo><mi>h</mi><mo>)</mo></mrow><mo>−</mo><mi>f</mi><mo>⁡</mo><mrow><mo>(</mo><mi>x</mi><mo>)</mo></mrow></mrow>
              <mi mathcolor="blue">h</mi>
            </mfrac>
            """#, [.above(.red, .blue), .centred(.red, .blue)]),
        Formula("Gaussian integral", #"""
            <msubsup><mo>∫</mo><mrow mathcolor="blue"><mo>−</mo><mi>∞</mi></mrow><mi mathcolor="red">∞</mi></msubsup>
            <msup><mi>e</mi><mrow><mo>−</mo><msup><mi>x</mi><mn>2</mn></msup></mrow></msup><mspace width="0.167em"/><mi mathvariant="normal">d</mi><mi>x</mi>
            <mo>=</mo><msqrt><mi mathcolor="lime">π</mi></msqrt>
            """#, [.above(.red, .blue), .leftOf(.red, .green)]),
        Formula("Cauchy's integral formula", #"""
            <mi>f</mi><mo>⁡</mo><mrow><mo>(</mo><mi>a</mi><mo>)</mo></mrow><mo>=</mo>
            <mfrac><mn>1</mn><mrow><mn>2</mn><mi>π</mi><mi>i</mi></mrow></mfrac>
            <msub><mo>∮</mo><mi mathcolor="blue">γ</mi></msub>
            <mfrac><mrow mathcolor="red"><mi>f</mi><mo>⁡</mo><mrow><mo>(</mo><mi>z</mi><mo>)</mo></mrow></mrow><mrow mathcolor="lime"><mi>z</mi><mo>−</mo><mi>a</mi></mrow></mfrac>
            <mspace width="0.167em"/><mi mathvariant="normal">d</mi><mi>z</mi>
            """#, [.above(.red, .green), .leftOf(.blue, .red)]),
        Formula("Taylor series", #"""
            <mi>f</mi><mo>⁡</mo><mrow><mo>(</mo><mi>x</mi><mo>)</mo></mrow><mo>=</mo>
            <munderover><mo>∑</mo><mrow mathcolor="blue"><mi>n</mi><mo>=</mo><mn>0</mn></mrow><mi mathcolor="red">∞</mi></munderover>
            <mfrac><mrow><msup><mi>f</mi><mrow><mo stretchy="false">(</mo><mi>n</mi><mo stretchy="false">)</mo></mrow></msup><mo>⁡</mo><mrow><mo>(</mo><mi>a</mi><mo>)</mo></mrow></mrow><mrow><mi>n</mi><mo>!</mo></mrow></mfrac>
            <msup><mrow><mo>(</mo><mi>x</mi><mo>−</mo><mi>a</mi><mo>)</mo></mrow><mi>n</mi></msup>
            """#, [.above(.red, .blue), .centred(.red, .blue)]),
        Formula("Fourier transform", #"""
            <mover><mi mathcolor="blue">f</mi><mo mathcolor="red">^</mo></mover><mo>⁡</mo><mrow><mo>(</mo><mi>ξ</mi><mo>)</mo></mrow><mo>=</mo>
            <msubsup><mo>∫</mo><mrow><mo>−</mo><mi>∞</mi></mrow><mi>∞</mi></msubsup>
            <mi>f</mi><mo>⁡</mo><mrow><mo>(</mo><mi>x</mi><mo>)</mo></mrow>
            <msup><mi>e</mi><mrow><mo>−</mo><mn>2</mn><mi>π</mi><mi>i</mi><mi>x</mi><mi>ξ</mi></mrow></msup><mspace width="0.167em"/><mi mathvariant="normal">d</mi><mi>x</mi>
            """#, [.raised(.red, over: .blue)]),
        Formula("Laplace's equation", #"""
            <mfrac><mrow mathcolor="red"><msup><mo>∂</mo><mn>2</mn></msup><mi>u</mi></mrow><mrow mathcolor="blue"><mo>∂</mo><msup><mi>x</mi><mn>2</mn></msup></mrow></mfrac>
            <mo>+</mo>
            <mfrac><mrow><msup><mo>∂</mo><mn>2</mn></msup><mi>u</mi></mrow><mrow><mo>∂</mo><msup><mi>y</mi><mn>2</mn></msup></mrow></mfrac>
            <mo>=</mo><mn mathcolor="lime">0</mn>
            """#, [.above(.red, .blue), .leftOf(.red, .green), .leftOf(.blue, .green)]),
        Formula("Riemann zeta function", #"""
            <mi>ζ</mi><mo>⁡</mo><mrow><mo>(</mo><mi>s</mi><mo>)</mo></mrow><mo>=</mo>
            <munderover><mo>∑</mo><mrow><mi>n</mi><mo>=</mo><mn>1</mn></mrow><mi>∞</mi></munderover><mfrac><mn>1</mn><msup><mi>n</mi><mi>s</mi></msup></mfrac>
            <mo>=</mo>
            <munder><mo>∏</mo><mrow mathcolor="blue"><mi>p</mi><mtext> prime</mtext></mrow></munder>
            <mfrac><mn mathcolor="red">1</mn><mrow mathcolor="lime"><mn>1</mn><mo>−</mo><msup><mi>p</mi><mrow><mo>−</mo><mi>s</mi></mrow></msup></mrow></mfrac>
            """#, [.above(.red, .green), .centred(.red, .green)]),
        Formula("evaluation bar", #"""
            <msubsup>
              <mrow><mo fence="true" stretchy="true" lspace="0" rspace="0"></mo><mfrac mathcolor="red"><msup><mi>x</mi><mn>3</mn></msup><mn>3</mn></mfrac><mo mathcolor="lime">|</mo></mrow>
              <mn>0</mn><mn mathcolor="blue">1</mn>
            </msubsup>
            <mo>=</mo><mfrac><mn>1</mn><mn>3</mn></mfrac>
            """#, [.coversVertically(.green, .red), .leftOf(.red, .green), .leftOf(.green, .blue)]),
    ]

    // MARK: Matrices and tables

    static let linearAlgebra: [Formula] = [
        Formula("matrix in brackets", #"""
            <mi>A</mi><mo>=</mo>
            <mrow><mo mathcolor="lime">[</mo>
              <mtable>
                <mtr><mtd><mi mathcolor="red">a</mi></mtd><mtd><mi mathcolor="red">b</mi></mtd></mtr>
                <mtr><mtd><mi mathcolor="blue">c</mi></mtd><mtd><mi mathcolor="blue">d</mi></mtd></mtr>
              </mtable>
            <mo mathcolor="lime">]</mo></mrow>
            """#, [.above(.red, .blue), .coversVertically(.green, .red), .coversVertically(.green, .blue), .centred(.red, .blue)]),
        Formula("determinant", #"""
            <mrow><mo mathcolor="lime">|</mo>
              <mtable>
                <mtr><mtd><mi mathcolor="red">a</mi></mtd><mtd><mi>b</mi></mtd></mtr>
                <mtr><mtd><mi mathcolor="blue">c</mi></mtd><mtd><mi>d</mi></mtd></mtr>
              </mtable>
            <mo mathcolor="lime">|</mo></mrow>
            <mo>=</mo><mi>a</mi><mi>d</mi><mo>−</mo><mi>b</mi><mi>c</mi>
            """#, [.above(.red, .blue), .coversVertically(.green, .red), .coversVertically(.green, .blue)]),
        Formula("identity matrix with dots", #"""
            <msub><mi>I</mi><mi>n</mi></msub><mo>=</mo>
            <mfenced open="(" close=")">
              <mtable>
                <mtr><mtd><mn mathcolor="red">1</mn></mtd><mtd><mn>0</mn></mtd><mtd><mo>⋯</mo></mtd><mtd><mn>0</mn></mtd></mtr>
                <mtr><mtd><mn>0</mn></mtd><mtd><mn>1</mn></mtd><mtd><mo>⋯</mo></mtd><mtd><mn>0</mn></mtd></mtr>
                <mtr><mtd><mo>⋮</mo></mtd><mtd><mo>⋮</mo></mtd><mtd><mo>⋱</mo></mtd><mtd><mo>⋮</mo></mtd></mtr>
                <mtr><mtd><mn>0</mn></mtd><mtd><mn>0</mn></mtd><mtd><mo>⋯</mo></mtd><mtd><mn mathcolor="blue">1</mn></mtd></mtr>
              </mtable>
            </mfenced>
            """#, [.above(.red, .blue), .leftOf(.red, .blue), .coversVertically(.rest, .red), .coversVertically(.rest, .blue)]),
        Formula("piecewise definition", #"""
            <mrow><mo>|</mo><mi>x</mi><mo>|</mo></mrow><mo>=</mo>
            <mrow><mo mathcolor="lime">{</mo>
              <mtable columnalign="left left" columnspacing="1em">
                <mtr><mtd><mi mathcolor="red">x</mi></mtd><mtd><mtext>if </mtext><mi>x</mi><mo>≥</mo><mn>0</mn></mtd></mtr>
                <mtr><mtd><mrow mathcolor="blue"><mo>−</mo><mi>x</mi></mrow></mtd><mtd><mtext>otherwise</mtext></mtd></mtr>
              </mtable>
            </mrow>
            """#, [.above(.red, .blue), .coversVertically(.green, .red), .coversVertically(.green, .blue), .leftOf(.green, .red)]),
        Formula("aligned equations", #"""
            <mtable columnalign="right left" columnspacing="0em" rowspacing="0.5em">
              <mtr><mtd><mi mathcolor="red">x</mi><mo>+</mo><mi>y</mi></mtd><mtd><mo>=</mo><mn mathcolor="lime">5</mn></mtd></mtr>
              <mtr><mtd><mn>2</mn><mi mathcolor="blue">x</mi><mo>−</mo><mi>y</mi></mtd><mtd><mo>=</mo><mn>1</mn></mtd></mtr>
            </mtable>
            """#, [.above(.red, .blue), .leftOf(.red, .green), .sameBaseline(.red, .green)]),
        Formula("numbered equation", #"""
            <mtable side="right">
              <mlabeledtr>
                <mtd><mtext mathcolor="blue">(1)</mtext></mtd>
                <mtd><mi mathcolor="red">E</mi><mo>=</mo><mi>m</mi><msup><mi>c</mi><mn>2</mn></msup></mtd>
              </mlabeledtr>
            </mtable>
            """#, [.leftOf(.red, .blue)]),
        Formula("vector as a column", #"""
            <mover><mi>v</mi><mo>→</mo></mover><mo>=</mo>
            <mrow><mo mathcolor="lime">(</mo><mtable><mtr><mtd><msub><mi mathcolor="red">v</mi><mn>1</mn></msub></mtd></mtr><mtr><mtd><msub><mi>v</mi><mn>2</mn></msub></mtd></mtr><mtr><mtd><msub><mi mathcolor="blue">v</mi><mn>3</mn></msub></mtd></mtr></mtable><mo mathcolor="lime">)</mo></mrow>
            """#, [.above(.red, .blue), .centred(.red, .blue), .coversVertically(.green, .red), .coversVertically(.green, .blue)]),
        Formula("Euclidean norm", #"""
            <mrow><mo>‖</mo><mi>v</mi><mo>‖</mo></mrow><mo>=</mo>
            <msqrt><mrow mathcolor="red"><msubsup><mi>v</mi><mn>1</mn><mn>2</mn></msubsup><mo>+</mo><mo>⋯</mo><mo>+</mo><msubsup><mi>v</mi><mi>n</mi><mn>2</mn></msubsup></mrow></msqrt>
            """#, [.coversHorizontally(.rest, .red)]),
    ]

    // MARK: Physics and chemistry

    static let physics: [Formula] = [
        Formula("Schrödinger equation", #"""
            <mi>i</mi><mi>ℏ</mi><mfrac><mo mathcolor="red">∂</mo><mrow mathcolor="blue"><mo>∂</mo><mi>t</mi></mrow></mfrac><mi mathvariant="normal">Ψ</mi><mo>=</mo>
            <mover><mi>H</mi><mo>^</mo></mover><mi mathvariant="normal">Ψ</mi>
            """#, [.above(.red, .blue)]),
        Formula("Einstein field equations", #"""
            <msub><mi mathcolor="blue">R</mi><mrow mathcolor="red"><mi>μ</mi><mi>ν</mi></mrow></msub><mo>−</mo><mfrac><mn>1</mn><mn>2</mn></mfrac><mi>R</mi><msub><mi>g</mi><mrow><mi>μ</mi><mi>ν</mi></mrow></msub>
            <mo>+</mo><mi mathvariant="normal">Λ</mi><msub><mi>g</mi><mrow><mi>μ</mi><mi>ν</mi></mrow></msub><mo>=</mo>
            <mfrac><mrow><mn>8</mn><mi>π</mi><mi>G</mi></mrow><msup><mi>c</mi><mn>4</mn></msup></mfrac><msub><mi>T</mi><mrow><mi>μ</mi><mi>ν</mi></mrow></msub>
            """#, [.lowered(.red, under: .blue), .leftOf(.blue, .red)]),
        Formula("Christoffel symbol", #"""
            <mmultiscripts><mi mathvariant="normal">Γ</mi><mrow mathcolor="blue"><mi>μ</mi><mi>ν</mi></mrow><mi mathcolor="red">λ</mi></mmultiscripts>
            <mo>=</mo><mfrac><mn>1</mn><mn>2</mn></mfrac>
            <msup><mi>g</mi><mrow><mi>λ</mi><mi>σ</mi></mrow></msup>
            <mrow><mo>(</mo><msub><mo>∂</mo><mi>μ</mi></msub><msub><mi>g</mi><mrow><mi>σ</mi><mi>ν</mi></mrow></msub><mo>+</mo><msub><mo>∂</mo><mi>ν</mi></msub><msub><mi>g</mi><mrow><mi>σ</mi><mi>μ</mi></mrow></msub><mo>−</mo><msub><mo>∂</mo><mi>σ</mi></msub><msub><mi>g</mi><mrow><mi>μ</mi><mi>ν</mi></mrow></msub><mo>)</mo></mrow>
            """#, [.above(.red, .blue)]),
        Formula("Riemann tensor indices", #"""
            <mmultiscripts><mi mathcolor="lime">R</mi><none/><mi mathcolor="red">α</mi><mrow mathcolor="blue"><mi>σ</mi><mi>μ</mi><mi>ν</mi></mrow><none/></mmultiscripts>
            """#, [.leftOf(.green, .red), .leftOf(.red, .blue), .raised(.red, over: .green), .lowered(.blue, under: .green)]),
        Formula("carbon-14 decay", #"""
            <mmultiscripts><mi mathvariant="normal" mathcolor="lime">C</mi><mprescripts/><mn mathcolor="blue">6</mn><mn mathcolor="red">14</mn></mmultiscripts>
            <mo>→</mo>
            <mmultiscripts><mi mathvariant="normal">N</mi><mprescripts/><mn>7</mn><mn>14</mn></mmultiscripts>
            <mo>+</mo><msup><mi>e</mi><mo>−</mo></msup><mo>+</mo><msub><mover><mi>ν</mi><mo>¯</mo></mover><mi>e</mi></msub>
            """#, [.leftOf(.red, .green), .leftOf(.blue, .green), .above(.red, .blue)]),
        // The equilibrium arrow does not stretch to its labels until https://github.com/vocaro/MathMLLayout/issues/13 is fixed.
        Formula("chemical equilibrium", #"""
            <msub><mi mathvariant="normal">N</mi><mn>2</mn></msub><mo>+</mo><mn>3</mn><msub><mi mathvariant="normal">H</mi><mn>2</mn></msub>
            <munderover><mo mathcolor="lime">⇌</mo><mtext mathcolor="blue">catalyst</mtext><mtext mathcolor="red">450 °C, 200 atm</mtext></munderover>
            <mn>2</mn><msub><mi mathvariant="normal">N</mi><mn>2</mn></msub><msub><mi mathvariant="normal">H</mi><mn>3</mn></msub>
            """#, [.above(.red, .green), .above(.green, .blue), .coversHorizontally(.green, .red), .centred(.red, .blue)]),
        Formula("dot product", #"""
            <mover><mi mathcolor="blue">a</mi><mo mathcolor="red">→</mo></mover><mo>⋅</mo><mover><mi>b</mi><mo>→</mo></mover><mo>=</mo>
            <mrow><mo>|</mo><mi>a</mi><mo>|</mo></mrow><mrow><mo>|</mo><mi>b</mi><mo>|</mo></mrow><mi>cos</mi><mo>⁡</mo><mi>θ</mi>
            """#, [.raised(.red, over: .blue), .centred(.red, .blue)]),
        Formula("Dirac notation", #"""
            <mrow><mo>⟨</mo><mi mathcolor="red">ψ</mi><mo>|</mo><mover><mi>H</mi><mo>^</mo></mover><mo>|</mo><mi mathcolor="blue">φ</mi><mo>⟩</mo></mrow>
            <mo>=</mo><msup><mrow><mo>⟨</mo><mi>φ</mi><mo>|</mo><mover><mi>H</mi><mo>^</mo></mover><mo>|</mo><mi>ψ</mi><mo>⟩</mo></mrow><mo>*</mo></msup>
            """#, [.leftOf(.red, .blue), .coversVertically(.rest, .red)]),
        Formula("mass–energy in a box", #"""
            <menclose notation="box"><mrow mathcolor="red"><mi>E</mi><mo>=</mo><mi>m</mi><msup><mi>c</mi><mn>2</mn></msup></mrow></menclose>
            """#, [.inside(.red, .rest)]),
    ]

    // MARK: Logic, sets and probability

    static let logicAndSets: [Formula] = [
        Formula("set-builder notation", #"""
            <mrow><mo>{</mo><mi mathcolor="red">x</mi><mo>∈</mo><mi mathvariant="double-struck">R</mi><mo>|</mo><msup><mi>x</mi><mn>2</mn></msup><mo>&lt;</mo><mn mathcolor="blue">2</mn><mo>}</mo></mrow>
            """#, [.leftOf(.red, .blue), .coversVertically(.rest, .red)]),
        Formula("epsilon–delta continuity", #"""
            <mo>∀</mo><mi mathcolor="red">ε</mi><mo>&gt;</mo><mn>0</mn><mspace width="0.5em"/><mo>∃</mo><mi mathcolor="lime">δ</mi><mo>&gt;</mo><mn>0</mn><mo>:</mo>
            <mrow><mo>|</mo><mi>x</mi><mo>−</mo><mi>a</mi><mo>|</mo></mrow><mo>&lt;</mo><mi>δ</mi><mo>⇒</mo>
            <mrow><mo>|</mo><mi>f</mi><mo>⁡</mo><mrow><mo>(</mo><mi>x</mi><mo>)</mo></mrow><mo>−</mo><mi>f</mi><mo>⁡</mo><mrow><mo>(</mo><mi>a</mi><mo>)</mo></mrow><mo>|</mo></mrow><mo>&lt;</mo><mi mathcolor="blue">ε</mi>
            """#, [.leftOf(.red, .green), .leftOf(.green, .blue), .sameBaseline(.red, .blue)]),
        Formula("Bayes' theorem", #"""
            <mi>P</mi><mo>⁡</mo><mrow><mo>(</mo><mi>A</mi><mo>|</mo><mi>B</mi><mo>)</mo></mrow><mo>=</mo>
            <mfrac>
              <mrow mathcolor="red"><mi>P</mi><mo>⁡</mo><mrow><mo>(</mo><mi>B</mi><mo>|</mo><mi>A</mi><mo>)</mo></mrow><mi>P</mi><mo>⁡</mo><mrow><mo>(</mo><mi>A</mi><mo>)</mo></mrow></mrow>
              <mrow mathcolor="blue"><mi>P</mi><mo>⁡</mo><mrow><mo>(</mo><mi>B</mi><mo>)</mo></mrow></mrow>
            </mfrac>
            """#, [.above(.red, .blue), .centred(.red, .blue)]),
        Formula("standard deviation", #"""
            <mi>σ</mi><mo>=</mo>
            <msqrt>
              <mfrac><mn mathcolor="red">1</mn><mi mathcolor="blue">N</mi></mfrac>
              <munderover><mo>∑</mo><mrow><mi>i</mi><mo>=</mo><mn>1</mn></mrow><mi>N</mi></munderover>
              <msup><mrow><mo>(</mo><msub><mi>x</mi><mi>i</mi></msub><mo>−</mo><mi>μ</mi><mo>)</mo></mrow><mn>2</mn></msup>
            </msqrt>
            """#, [.above(.red, .blue), .coversVertically(.rest, .red), .coversVertically(.rest, .blue)]),
        Formula("De Morgan's law", #"""
            <mover><mrow mathcolor="blue"><mi>A</mi><mo>∪</mo><mi>B</mi></mrow><mo mathcolor="red">¯</mo></mover><mo>=</mo>
            <mover><mi>A</mi><mo>¯</mo></mover><mo>∩</mo><mover><mi>B</mi><mo>¯</mo></mover>
            """#, [.raised(.red, over: .blue), .coversHorizontally(.red, .blue)]),
        Formula("interval and tuple with mfenced", #"""
            <mi mathcolor="red">x</mi><mo>∈</mo><mfenced open="[" close=")"><mn>0</mn><mn>1</mn></mfenced><mo>,</mo>
            <mspace width="1em"/><mi>p</mi><mo>=</mo><mfenced separators=";,"><mi>x</mi><mi>y</mi><mi mathcolor="blue">z</mi></mfenced>
            """#, [.leftOf(.red, .blue)]),
    ]

    // MARK: Braces, strikes, styles and spacing

    static let decorated: [Formula] = [
        Formula("underbrace with a label", #"""
            <munder>
              <munder><mrow mathcolor="blue"><mi>a</mi><mo>+</mo><mi>a</mi><mo>+</mo><mo>⋯</mo><mo>+</mo><mi>a</mi></mrow><mo mathcolor="lime">⏟</mo></munder>
              <mrow mathcolor="red"><mi>n</mi><mtext> times</mtext></mrow>
            </munder>
            <mo>=</mo><mi>n</mi><mi>a</mi>
            """#, [.above(.blue, .green), .above(.green, .red), .coversHorizontally(.green, .blue), .centred(.green, .blue)]),
        Formula("overbrace with a label", #"""
            <mover>
              <mover><mrow mathcolor="blue"><mi>x</mi><mo>+</mo><mi>y</mi><mo>+</mo><mi>z</mi></mrow><mo mathcolor="lime">⏞</mo></mover>
              <mn mathcolor="red">3</mn>
            </mover>
            """#, [.above(.red, .green), .above(.green, .blue), .coversHorizontally(.green, .blue), .centred(.red, .blue)]),
        Formula("labelled arrow", #"""
            <mi mathcolor="blue">A</mi><mover><mo mathcolor="lime">⟶</mo><mtext mathcolor="red">a long label</mtext></mover><mi>B</mi>
            """#, [.above(.red, .green), .coversHorizontally(.green, .red), .leftOf(.blue, .green)]),
        Formula("cancelled fraction", #"""
            <mfrac>
              <mrow><mn>2</mn><menclose notation="updiagonalstrike"><mi mathcolor="red">x</mi></menclose></mrow>
              <mrow><mn>4</mn><menclose notation="updiagonalstrike"><mi mathcolor="blue">x</mi></menclose></mrow>
            </mfrac>
            <mo>=</mo><mfrac><mn>1</mn><mn>2</mn></mfrac>
            """#, [.above(.red, .blue)]),
        Formula("styled text and symbols", #"""
            <mstyle mathcolor="blue"><mi mathvariant="double-struck">N</mi><mo>⊂</mo><mi mathvariant="double-struck">Z</mi></mstyle>
            <mo>⊂</mo><mstyle mathsize="150%"><mi mathvariant="script" mathcolor="red">L</mi></mstyle>
            <mo>⊂</mo><mi mathvariant="fraktur">g</mi><mo>,</mo><mi mathvariant="bold">v</mi><mo>,</mo><mi mathvariant="monospace">code</mi>
            """#, [.leftOf(.blue, .red)]),
        Formula("phantom alignment", #"""
            <mtable columnalign="left">
              <mtr><mtd><mi mathcolor="red">x</mi><mo>=</mo><mn>1</mn><mo>+</mo><mn>2</mn></mtd></mtr>
              <mtr><mtd><mphantom><mi>x</mi></mphantom><mo>=</mo><mn mathcolor="blue">3</mn></mtd></mtr>
            </mtable>
            """#, [.above(.red, .blue), .leftOf(.red, .blue)]),
        Formula("padded and spaced", #"""
            <mi mathcolor="red">a</mi><mspace width="2em"/><mpadded width="+1em" lspace="0.5em"><mi mathcolor="lime">b</mi></mpadded><mspace width="thickmathspace"/><mi mathcolor="blue">c</mi>
            """#, [.leftOf(.red, .green), .leftOf(.green, .blue), .sameBaseline(.red, .blue)]),
        Formula("wide accents", #"""
            <mover><mrow mathcolor="blue"><mi>A</mi><mi>B</mi></mrow><mo mathcolor="red">→</mo></mover><mo>+</mo>
            <mover><mrow><mi>x</mi><mi>y</mi><mi>z</mi></mrow><mo>^</mo></mover><mo>+</mo>
            <munder><mrow><mi>u</mi><mi>v</mi></mrow><mo>_</mo></munder><mo>+</mo>
            <mover><mi>q</mi><mo>~</mo></mover><mo>+</mo><mover><mi>x</mi><mo>˙</mo></mover><mo>+</mo><mover><mi>x</mi><mo>¨</mo></mover>
            """#, [.raised(.red, over: .blue), .coversHorizontally(.red, .blue)]),
    ]

    // MARK: Semantics, actions and errors

    static let structural: [Formula] = [
        Formula("semantics with annotations", #"""
            <semantics>
              <mrow><mfrac><mn mathcolor="red">1</mn><mn mathcolor="blue">2</mn></mfrac><mo>+</mo><mi>x</mi></mrow>
              <annotation encoding="application/x-tex">\frac{1}{2}+x</annotation>
              <annotation-xml encoding="MathML-Content"><apply><plus/><cn type="rational">1<sep/>2</cn><ci>x</ci></apply></annotation-xml>
            </semantics>
            """#, [.above(.red, .blue)]),
        Formula("action and error", #"""
            <maction actiontype="toggle" selection="2"><mi>hidden</mi><mrow><mi mathcolor="lime">a</mi><mo>+</mo><mi>b</mi></mrow></maction>
            <mo>=</mo><merror><mtext mathcolor="blue">undefined</mtext></merror>
            """#, [.leftOf(.green, .blue), .inside(.blue, .red)]),
        Formula("strings and numbers", #"""
            <ms mathcolor="red">hello</ms><mo>+</mo><ms lquote="‘" rquote="’">x</ms><mo>=</mo><mn>3.14</mn><mo>×</mo><msup><mn>10</mn><mrow><mo>−</mo><mn mathcolor="blue">5</mn></mrow></msup>
            """#, [.leftOf(.red, .blue)]),
        Formula("non-Latin text", #"""
            <mtext mathcolor="red">速度</mtext><mo>=</mo><mfrac><mtext>距離</mtext><mtext mathcolor="blue">時間</mtext></mfrac><mo>,</mo>
            <mspace width="1em"/><mi>скорость</mi><mo>=</mo><mi>α</mi><mi>β</mi><mi mathvariant="normal">Ω</mi>
            """#, [.leftOf(.red, .blue)]),
    ]
}
