# Elementary direction and columns

MathML 3 makes elementary math an explicit exception to overall layout direction.
[Section 3.6](https://www.w3.org/TR/MathML3/chapter3.html#presm.elemmath) requires
columns, operators and carries to retain left-to-right order even in an RTL context.
The same rules apply to `mlongdiv` by
[section 3.6.2.1](https://www.w3.org/TR/MathML3/chapter3.html#presm.mlongdiv).
Changing `dir` therefore does not reverse digits or mirror a completed stack image.
Arabic and Hebrew text can appear inside its cells and carries.

| Feature | LTR and RTL elementary contexts |
| --- | --- |
| Digits and other row cells | Source order, from physical left to right. Each character of `mn` takes a column; other elements take one cell. |
| Logical column | Zero is the alignment reference; larger coordinates lie physically right. |
| `position` and `shift` | Positive values move towards the tens digit, physically left; negative values move right. Group shifts accumulate for every sibling, including rules. |
| `stackalign` | `left` and `right` mean physical sides; center uses the middle cell (right of the middle for even counts). |
| Decimal alignment | The separator occupies column zero before position offsets. An absent separator is implied after the first number, on its physical right. |
| `charalign` | `left`, `center`, `right` select the physical alignment within a column. |
| Carries | Associate with successive columns from left to right. Compass points retain physical north/east/south/west. |
| Crossouts | Strike the associated column's character; upward and downward diagonals retain their physical slope. |
| Rule overhang | `leftoverhang` extends physical left and `rightoverhang` extends physical right. |
| Spoken columns | Use these same coordinates and compass locations in either direction. Source text is spoken as written. |

`longdivstyle` controls physical operand and separator placement in either context:

| Style | Divisor | Result |
| --- | --- | --- |
| `lefttop` | Left | Above dividend |
| `righttop` | Right | Above dividend |
| `stackedrightright` | Right, above result | Right, below divisor |
| `mediumstackedrightright` / `mediumrightright` | Right, above result, shortened side rule | Right, below divisor |
| `shortstackedrightright` | Right, above result, divisor-height side rule | Right, below divisor |
| `stackedleftleft` | Left, above result | Left, below divisor |
| `stackedleftlinetop` | Left, underlined | Above dividend |
| `left/\right` | Left, followed by slash | Right, preceded by backslash |
| `left)(right` | Left, followed by closing parenthesis | Right, preceded by opening parenthesis |
| `:right=right` | Right, preceded by colon | Further right, preceded by equals |

Frame separators retain their specified shapes rather than adopting an operand's bidi
direction. Operand contents retain their inherited token direction. The two stacked-left
notations are among the Arabic-country conventions listed by MathML 3.

MathML 3 distinguishes overall schema direction from token base direction in
[section 3.1.5](https://www.w3.org/TR/MathML3/chapter3.html#presm.bidi).
In this engine, `dir="rtl"` and `dir="ltr"` inherit through `math`, `mstyle`, stacks,
groups, rows and carries; a child's valid value overrides its parent's. The engine also
accepts explicit direction on elementary containers to set their descendants' token
direction. Invalid values, including the unsupported `auto`, inherit both text direction
and layout direction. Shaped
text uses the specified base direction with Unicode bidi processing, so a mixed token
such as `<mtext>+ 12 אב</mtext>` can change internal visual order without changing its
column. Numeric tokens retain LTR progression. With no explicit direction, existing
CoreText natural-direction shaping is preserved.

The supported scope for [issue #75](https://github.com/vocaro/MathMLLayout/issues/75)
is inherited bidi **token contents** and MathML 3's physical elementary column policy.
Rows and tables now follow inherited layout direction, including compound rows inside
one elementary cell. The enclosing elementary columns themselves still progress LTR.
Scripts, radicals and other schemata retain their existing geometric policies, so complete
RTL schema mirroring remains unsupported. Reversing elementary columns would instead require an explicitly chosen
extension to MathML 3.

## Regression coverage

`ElementaryMathTests` verifies the physical policy under inherited LTR and RTL contexts:

| Requirement | Coverage |
| --- | --- |
| Column coordinates and alignment | Every `stackalign` and `charalign`, signed positions and group shifts, source operator order, Arabic digits and inherited decimal separators. |
| Carries and rules | Every compass point, overridden carry locations, all crossout slopes, asymmetric overhang and ink containment. |
| Long division | Every supported frame with numeric operands; inherited Arabic/Hebrew mixed token operands and carries, explicit token overrides, frame separators and ink containment. |
| Speech | Identical logical stack coordinates in all five base languages and identical division frame coordinates under either direction. |

`DirectionalityScopeTests` checks that invalid direction attributes on table, row, cell
and style contexts retain inherited RTL alignment policy, while a valid LTR override
changes back to LTR column and group progression. `BidiTextTests` checks logical token wrapping
with paragraph bidi context and numeric parentheses in an RTL stack. These tests verify
the supported token and elementary scope; they do not establish general RTL schema support.

[Documentation index](../README.md#documentation)
