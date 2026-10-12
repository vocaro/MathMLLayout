#!/usr/bin/env python3
"""Repackage pinned WPT WOFF fonts as sfnt for CoreText, preserving MATH and glyph metrics."""
import argparse
import hashlib
import json
from pathlib import Path
import fontTools
from fontTools.ttLib import TTFont

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('checkout', type=Path)
parser.add_argument('fixtures', type=Path)
args = parser.parse_args()
path = args.fixtures / 'manifest.json'
manifest = json.loads(path.read_text())
pins = json.loads((Path(__file__).parent / 'wpt-pins.json').read_text())
if manifest['revision'] != pins['revision']:
    raise ValueError('Pin revision does not match manifest revision')
for item in manifest['fonts']:
    source = args.checkout / item['upstreamPath']
    if hashlib.sha256(source.read_bytes()).hexdigest() != pins['files'][item['upstreamPath']]:
        raise ValueError(f'Pinned font hash mismatch: {source}')
    font = TTFont(source, recalcTimestamp=False)
    math = font.getTableData('MATH')
    metrics = {tag: font.getTableData(tag) for tag in ['MATH', 'hhea', 'hmtx', 'vhea', 'vmtx', 'cmap', 'CFF ', 'glyf'] if tag in font}
    item.update({'upstreamSHA256': hashlib.sha256(source.read_bytes()).hexdigest(),
                 'postScriptName': font['name'].getDebugName(6),
                 'copyright': font['name'].getDebugName(0),
                 'unitsPerEm': font['head'].unitsPerEm,
                 'mathSHA256': hashlib.sha256(math).hexdigest(),
                 'conversion': f'fontTools {fontTools.__version__}; flavor=None; recalcTimestamp=False'})
    font.flavor = None
    dest = args.fixtures / item['path']
    dest.parent.mkdir(parents=True, exist_ok=True)
    font.save(dest)
    result = TTFont(dest)
    assert result.getTableData('MATH') == math
    assert all(result.getTableData(tag) == value for tag, value in metrics.items())
    item['sha256'] = hashlib.sha256(dest.read_bytes()).hexdigest()
path.write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Converted {len(manifest["fonts"])} fonts; MATH bytes unchanged')
