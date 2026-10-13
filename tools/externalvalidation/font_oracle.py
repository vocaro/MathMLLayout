#!/usr/bin/env python3
"""Independently decode a real font with fontTools, without importing MathMLLayout."""
import argparse
import hashlib
import json
from pathlib import Path
import fontTools
from fontTools.ttLib import TTFont


def decode(path):
    font = TTFont(path)
    table = font['MATH'].table
    constants = {}
    for key, value in vars(table.MathConstants).items():
        name = key[0].lower() + key[1:]
        value = value.Value if hasattr(value, 'Value') else value
        if 'Percent' not in key:
            value /= font['head'].unitsPerEm
        constants[name] = value
    info = table.MathGlyphInfo
    def values(subtable, coverage, records):
        if subtable is None:
            return {}
        return {str(font.getGlyphID(g)): v.Value for g, v in zip(
            getattr(subtable, coverage).glyphs, getattr(subtable, records))}
    variants = table.MathVariants
    def constructions(axis):
        coverage = getattr(variants, axis + 'GlyphCoverage')
        if coverage is None:
            return {}
        result = {}
        for glyph, construction in zip(coverage.glyphs, getattr(variants, axis + 'GlyphConstruction')):
            assembly = construction.GlyphAssembly
            result[str(font.getGlyphID(glyph))] = {
                'variants': [{'glyph': font.getGlyphID(v.VariantGlyph), 'advance': v.AdvanceMeasurement}
                             for v in construction.MathGlyphVariantRecord],
                'parts': [{'glyph': font.getGlyphID(p.glyph), 'startConnector': p.StartConnectorLength,
                           'endConnector': p.EndConnectorLength, 'fullAdvance': p.FullAdvance,
                           'isExtender': bool(p.PartFlags & 1)} for p in assembly.PartRecords] if assembly else [],
                'assemblyItalicsCorrection': assembly.ItalicsCorrection.Value if assembly else 0}
        return result
    return {'schemaVersion': 1, 'decoder': f'fontTools {fontTools.__version__}',
            'source': path.name, 'postScriptName': font['name'].getDebugName(6),
            'fontVersion': font['name'].getDebugName(5),
            'copyright': font['name'].getDebugName(0),
            'fontSHA256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'mathSHA256': hashlib.sha256(font.getTableData('MATH')).hexdigest(),
            'unitsPerEm': font['head'].unitsPerEm, 'glyphCount': len(font.getGlyphOrder()),
            'constants': constants,
            'italics': values(info.MathItalicsCorrectionInfo, 'Coverage', 'ItalicsCorrection'),
            'accents': values(info.MathTopAccentAttachment, 'TopAccentCoverage', 'TopAccentAttachment'),
            'minConnectorOverlap': variants.MinConnectorOverlap,
            'vertical': constructions('Vert'), 'horizontal': constructions('Horiz'),
            'exclusions': ['This static-font oracle excludes MathKernInfo and Device/VariationIndex evaluation; synthetic tests cover the supported layout adjustment policies.']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('font', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    oracle = decode(args.font)
    args.output.write_text(json.dumps(oracle, indent=2, sort_keys=True) + '\n')
    print(f'Decoded {oracle["glyphCount"]} glyphs, {len(oracle["constants"])} constants')
