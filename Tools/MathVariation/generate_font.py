"""Generate the original CC0 variable MATH test font with fontTools.

The rectangle outline is deliberately invariant. AxisHeight is 200 units at
the default and receives a 400-unit VariationIndex delta at normalized weight 1.
avar remaps normalized 0.5 to 0.75, independently exposing incorrect coordinates.
"""
from pathlib import Path
from struct import pack

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import newTable
from fontTools.ttLib.tables.DefaultTable import DefaultTable

root = Path(__file__).resolve().parents[2]
fb = FontBuilder(1000, isTTF=True)
fb.setupGlyphOrder([".notdef", "x"])
fb.setupCharacterMap({ord("x"): "x"})
glyphs = {}
for name in [".notdef", "x"]:
    pen = TTGlyphPen(None)
    pen.moveTo((0, 0))
    pen.lineTo((500, 0))
    pen.lineTo((500, 700))
    pen.lineTo((0, 700))
    pen.closePath()
    glyphs[name] = pen.glyph()
fb.setupGlyf(glyphs)
fb.setupHorizontalMetrics({name: (500, 0) for name in glyphs})
fb.setupHorizontalHeader(ascent=800, descent=-200)
fb.setupNameTable({"familyName": "MathML Variation Test", "styleName": "Regular",
                   "uniqueFontIdentifier": "MathMLVariationTest-Regular-1",
                   "fullName": "MathML Variation Test Regular",
                   "psName": "MathMLVariationTest-Regular",
                   "licenseDescription": "Original test font dedicated to the public domain under CC0 1.0."})
fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
fb.setupPost()
fb.setupMaxp()
fb.setupFvar([("wght", 100, 400, 900, "Weight")], [])
fb.setupGvar({name: [] for name in glyphs})
avar = newTable("avar")
avar.majorVersion, avar.minorVersion = 1, 0
avar.segments = {"wght": {-1.0: -1.0, 0.0: 0.0, 0.5: 0.75, 1.0: 1.0}}
fb.font["avar"] = avar

# GDEF 1.3 header, ItemVariationStore header, one region, one delta row.
gdef = pack(">7HI", 1, 3, 0, 0, 0, 0, 0, 18)
gdef += pack(">HIHI", 1, 12, 1, 22)
gdef += pack(">HHhhh", 1, 1, 0, 16384, 16384)
gdef += pack(">HHHHh", 1, 1, 1, 0, 400)
table = DefaultTable("GDEF")
table.data = gdef
fb.font["GDEF"] = table

# MATH 1.0 header + 51 constants records. Device offsets use the MathConstants origin.
constants = pack(">4H", 70, 50, 1000, 1000)
for index in range(51):
    constants += pack(">hH", 200 if index == 1 else 0, 214 if index == 1 else 0)
constants += pack(">H", 60)
constants += pack(">3H", 0, 0, 0x8000)
table = DefaultTable("MATH")
table.data = pack(">5H", 1, 0, 10, 0, 0) + constants
fb.font["MATH"] = table
fb.font["head"].created = fb.font["head"].modified = 3786912000
fb.font.recalcTimestamp = False
fb.save(root / "Tests/MathMLLayoutTests/ExternalFixtures/fonts/MathMLVariationTest.ttf")
