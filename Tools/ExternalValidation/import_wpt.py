#!/usr/bin/env python3
"""Port the reviewed numeric WPT subset from a local checkout; never executes upstream JS.
Requires lxml. Download the exact revision in manifest.json before invoking this tool.
"""
import argparse
import ast
import copy
import hashlib
import json
import math
import re
from pathlib import Path
from lxml import etree, html

REVISION = '38d608e1005d6d7f0fecefb3b7b14109ab3c3b1d'
SOURCES = [
    'fractions/frac-parameters-1.html',
    'fractions/frac-parameters-2.html',
    'scripts/subsup-parameters-1.html',
    'scripts/underover-parameters-1.html',
    'radicals/root-parameters-1.html',
]


def number(expression, values):
    """Only numeric arithmetic and previously decoded variable names are accepted."""
    def visit(node):
        if isinstance(node, ast.Constant) and type(node.value) in (int, float):
            return node.value
        if isinstance(node, ast.Name):
            return values[node.id]
        if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub, ast.Mult, ast.Div)):
            a, b = visit(node.left), visit(node.right)
            return {ast.Add: lambda: a+b, ast.Sub: lambda: a-b,
                    ast.Mult: lambda: a*b, ast.Div: lambda: a/b}[type(node.op)]()
        raise ValueError(f'Unreviewed expression: {expression}')
    return visit(ast.parse(expression.strip(), mode='eval').body)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def apply_reviewed(cases, reviewed):
    unknown = set(reviewed) - {case['id'] for case in cases}
    if unknown: raise ValueError(f'Reviewed outcomes refer to absent cases: {sorted(unknown)}')
    for case in cases:
        outcome = reviewed.get(case['id'])
        if outcome is None: continue
        if set(outcome) != {'classification', 'issue', 'observed'} or outcome['classification'] != 'bug':
            raise ValueError('Reviewed outcomes may only record issue-linked bug observations')
        if not isinstance(outcome['issue'], str) or not outcome['issue'] or type(outcome['observed']) not in (int, float) or not math.isfinite(outcome['observed']):
            raise ValueError('A reviewed bug requires an issue and numeric observation')
        if abs(outcome['observed'] - case['expected']) <= case['tolerance']:
            raise ValueError('A reviewed bug observation must fail the upstream assertion')
        case.update(outcome)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('checkout', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    pins = json.loads((Path(__file__).parent / 'wpt-pins.json').read_text())
    if pins['revision'] != REVISION:
        raise ValueError('Pin revision does not match importer revision')
    out = args.destination
    (out / 'upstream').mkdir(parents=True, exist_ok=True)
    cases, fonts, exclusions = [], {}, []
    reviewed_path = out / 'reviewed-outcomes.json'
    reviewed = json.loads(reviewed_path.read_text()) if reviewed_path.exists() else {}
    for source in SOURCES:
        path = 'mathml/presentation-markup/' + source
        raw = (args.checkout / path).read_bytes()
        if sha(raw) != pins['files'][path]:
            raise ValueError(f'Pinned source hash mismatch: {path}')
        text = raw.decode('utf-8')
        (out / 'upstream' / Path(source).name).write_bytes(raw)
        doc = html.fromstring(raw)
        families = dict(re.findall(r'font-family:\s*([\w-]+);\s*src: url\("/([^\"]+)"\)', text))
        blocks = re.findall(r'test\(function\(\)\s*\{(.*?)\},\s*"([^"]+)"\);', text, re.S)
        for block, title in blocks:
            assertions = re.findall(
                r'assert_approx_equals\(getBox\("([^"]+)"\)\.(\w+)\s*-\s*'
                r'getBox\("([^"]+)"\)\.(\w+),\s*([^,]+),\s*epsilon,\s*"([^"]+)"\)', block)
            if not assertions:
                exclusions.append({'feature': source, 'upstreamTest': title,
                    'classification': 'unsuitable reference/test',
                    'reason': 'This initial importer handles rectangle differences; symbolic radical-width expressions await a reviewed port.'})
                continue
            values = {'emToPx': .01}
            for name, expr in re.findall(r'var (\w+) = ([^;]+);', block):
                def fixed_height(match):
                    element = doc.xpath('//*[@id=$id]', id=match.group(1))[0]
                    assert element.tag == 'mspace'
                    height = element.get('height', '0em')
                    assert height.endswith('em')
                    return str(float(height[:-2]) * 10)
                expr = re.sub(r'getBox\("([^"]+)"\)\.height', fixed_height, expr)
                values[name] = number(expr, values)
            for first, metric1, second, metric2, expected, label in assertions:
                roots = [m for m in doc.iter('math') if m.xpath('.//*[@id=$a]', a=first)
                         and m.xpath('.//*[@id=$b]', b=second)]
                if len(roots) != 1:
                    raise ValueError(f'Assertion crosses formula boundaries: {first}, {second}')
                original = etree.tostring(roots[0], encoding='unicode', with_tail=False)
                root = copy.deepcopy(roots[0])
                family = re.search(r'font-family:\s*([\w-]+)', root.get('style', '')).group(1)
                font_path = families[family]
                fonts[font_path] = {'path': 'fonts/' + Path(font_path).stem + '.otf',
                                    'upstreamPath': font_path}
                for element in root.iter():
                    # WPT's math,mspace {font-size:10px} holds script boxes at 10px.
                    # Only the two measured rectangles receive backgrounds, eliminating
                    # overlapping colors without changing any layout geometry.
                    element.attrib.pop('style', None)
                    if element.tag == 'mspace':
                        element.set('mathsize', '10px')
                    if element.get('id') in (first, second):
                        if element.tag not in {'mspace', 'msqrt', 'mroot'}:
                            raise ValueError('Unreviewed measured element')
                        element.set('mathbackground', 'red' if element.get('id') == first else 'blue')
                root.set('xmlns', 'http://www.w3.org/1998/Math/MathML')
                markup = etree.tostring(root, encoding='unicode', with_tail=False)
                case_id = Path(source).stem + '-' + first + '-' + second
                if any(c['id'] == case_id for c in cases):
                    raise ValueError(f'Duplicate ID: {case_id}')
                cases.append({'id': case_id, 'feature': source.split('/')[0],
                    'source': f'https://github.com/web-platform-tests/wpt/blob/{REVISION}/{path}',
                    'upstreamTest': title, 'assertion': label,
                    'specification': doc.xpath('//link[@rel="help"]/@href')[0],
                    'sourceSHA256': sha(raw), 'originalMarkup': original,
                    'markup': markup, 'sha256': sha(markup.encode()),
                    'normalization': ['standalone XML namespace', 'font selected by PostScript name',
                                      'CSS 10px mspace size to mathsize',
                                      'measured rectangle backgrounds to red/blue; other backgrounds removed',
                                      'DOM y-down coordinates to baseline-relative y-down ink rectangles'],
                    'font': fonts[font_path]['path'], 'fontSize': 10,
                    'firstMetric': metric1, 'secondMetric': metric2,
                    'expected': number(expected, values), 'tolerance': 1,
                    'classification': 'pass', 'issue': None})
    apply_reviewed(cases, reviewed)
    manifest = {'schemaVersion': 1, 'revision': REVISION, 'license': 'WPT-LICENSE.md',
        'cases': cases, 'fonts': list(fonts.values()),
        'exclusions': exclusions + [
            {'feature': 'DOM/CSS integration', 'classification': 'unsuitable reference/test',
             'reason': 'Events, CSS cascading, dynamic mutation and browser line boxes are outside the API.'},
            {'feature': 'mtable spans', 'classification': 'unsupported feature',
             'reason': 'rowspan/columnspan ignored (doc/limits.md); no span test imported.'},
            {'feature': 'unary/lone operator spacing, ordinary delimiter sizing',
             'classification': 'intentional difference', 'reason': 'Specific TeX choices documented in doc/markup.md; not counted as passes.'},
            {'feature': 'stretchy arrow labels', 'classification': 'intentional difference',
             'reason': 'Uses OpenType baseline shifts; doc/markup.md and existing ScriptAndLimitTests.'},
            {'feature': 'MathKernInfo', 'classification': 'unsupported feature',
             'reason': 'No MathKernInfo positioning (doc/limits.md).'}]}
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Imported {len(cases)} numeric assertions, {len(fonts)} fonts')


if __name__ == '__main__':
    main()
