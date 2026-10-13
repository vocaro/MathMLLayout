"""Generate the original, CC0 bidi test font with fontTools 4.66.1.
No system font or library output supplies the expected order. See doc/bidi-text-tests.md.
"""
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString

root = Path(__file__).resolve().parents[2]
chars = ' ABCDEF1234().-+אבגדהוبت'
cmap = {ord(c): ('space' if c == ' ' else f'uni{ord(c):04X}') for c in chars}
cmap[0xA0] = 'space'
cmap[0x202F] = 'space'
order = ['.notdef'] + list(dict.fromkeys(cmap.values()))
for name in ['uni0628', 'uni062A']:
    for form in ['isol', 'init', 'medi', 'fina']:
        order.append(f'{name}.{form}')
fb = FontBuilder(1000, isTTF=True)
fb.setupGlyphOrder(order)
fb.setupCharacterMap(cmap)
glyphs = {}
metrics = {}
for i, name in enumerate(order):
    pen = TTGlyphPen(None)
    if name != 'space':
        top = 400 + (i % 5) * 50
        pen.moveTo((20, -100)); pen.lineTo((450, -100))
        pen.lineTo((450, top)); pen.lineTo((20, top)); pen.closePath()
    glyphs[name] = pen.glyph()
    metrics[name] = (250 if name == 'space' else 500, 0)
fb.setupGlyf(glyphs)
fb.setupHorizontalMetrics(metrics)
fb.setupHorizontalHeader(ascent=800, descent=-200)
fb.setupNameTable({'familyName':'MathML Bidi Test','styleName':'Regular',
                  'uniqueFontIdentifier':'MathMLBidiTest-Regular-1',
                  'fullName':'MathML Bidi Test Regular','psName':'MathMLBidiTest-Regular'})
fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
fb.setupPost()
fb.setupMaxp()
features = 'languagesystem DFLT dflt; languagesystem arab dflt; languagesystem hebr dflt;\n'
for form in ['isol', 'init', 'medi', 'fina']:
    features += f'feature {form} {{\n'
    for name in ['uni0628', 'uni062A']:
        features += f' sub {name} by {name}.{form};\n'
    features += f'}} {form};\n'
addOpenTypeFeaturesFromString(fb.font, features)
# Deterministic sfnt timestamps.
fb.font['head'].created = fb.font['head'].modified = 3786912000
fb.font.recalcTimestamp = False
fb.save(root / 'Tests/MathMLLayoutTests/ExternalFixtures/fonts/MathMLBidiTest.ttf')
