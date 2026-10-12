#!/usr/bin/env python3
"""Create a standalone comparison gallery; numerical assertions decide outcomes, pixels aid review.
Pillow supplies baseline-aligned image overlays/differences (never a pixel-equality pass criterion).
"""
import argparse
import base64
import html
import hashlib
import io
import json
import math
from collections import Counter, defaultdict
from pathlib import Path
from PIL import Image, ImageChops


def image_data(image):
    data = io.BytesIO(); image.save(data, format='PNG')
    return 'data:image/png;base64,' + base64.b64encode(data.getvalue()).decode()


def aligned(a, b, first, second, report1, report2):
    scale = report1['scale']
    if report2['scale'] != scale: raise ValueError('Different image scales cannot be overlaid')
    # Use the actual pixel origin: native ceil rounding and browser line boxes can
    # put the baseline somewhere other than margin + MathML ascent.
    x1, y1 = (round(first['imageOrigin'][axis]) for axis in ('x', 'y'))
    x2, y2 = (round(second['imageOrigin'][axis]) for axis in ('x', 'y'))
    origin_x, baseline = max(x1, x2), max(y1, y2)
    w = max(a.width + origin_x-x1, b.width + origin_x-x2)
    h = max(a.height + baseline-y1, b.height + baseline-y2)
    left = Image.new('RGBA', (w, h), 'white'); right = left.copy()
    left.alpha_composite(a, (origin_x-x1, baseline-y1)); right.alpha_composite(b, (origin_x-x2, baseline-y2))
    return left, right


def validate_reports(raw, manifest, native, reference):
    digest = hashlib.sha256(raw).hexdigest()
    ids = [c['id'] for c in manifest['cases']]
    if len(set(ids)) != len(ids): raise ValueError('Duplicate manifest IDs')
    for report in (native, reference):
        if report['manifestSHA256'] != digest:
            raise ValueError('Report does not describe the supplied manifest')
        reported = [c['id'] for c in report['cases']]
        if len(set(reported)) != len(reported) or set(reported) != set(ids):
            raise ValueError('Report must contain each manifest ID exactly once')


def outcome(case, native, reference):
    if 'error' in reference: return 'unsuitable reference/test', None
    if 'error' in native: return 'unreviewed', None
    if 'expected' not in case: return 'unreviewed', None
    rectangles = native.get('rectangles', {})
    try:
        actual = rectangles['red'][case['firstMetric']] - rectangles['blue'][case['secondMetric']]
    except KeyError:
        return 'unreviewed', None
    if not math.isfinite(actual): return 'unreviewed', None
    if reference.get('meetsAssertion') is not True:
        return 'unsuitable reference/test', actual
    if native.get('clipped') is not False: return 'unreviewed', actual
    passes = abs(actual - case['expected']) <= case['tolerance']
    if case['classification'] == 'pass': return ('pass' if passes else 'unreviewed'), actual
    # Match XCTest: newly passing or changed known discrepancies need review.
    if passes or not case.get('issue') or 'observed' not in case:
        return 'unreviewed', actual
    if abs(actual - case['observed']) > case['tolerance']: return 'unreviewed', actual
    return case['classification'], actual


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--reference', default='chromium')
    args = parser.parse_args()
    raw = args.manifest.read_bytes()
    manifest = json.loads(raw)
    native = json.loads((args.directory/'mathmllayout.json').read_text())
    reference = json.loads((args.directory/(args.reference+'.json')).read_text())
    validate_reports(raw, manifest, native, reference)
    references = {c['id']: c for c in reference['cases']}
    local = {c['id']: c for c in native['cases']}
    groups, articles, records = defaultdict(Counter), [], []
    for case in manifest['cases']:
        first, second = local[case['id']], references[case['id']]
        category, actual = outcome(case, first, second)
        discrepancy = actual - case['expected'] if actual is not None else None
        groups[case.get('feature', 'corpus')][category] += 1
        record = {'id': case['id'], 'classification': category, 'actual': actual,
                  'expected': case.get('expected'), 'discrepancy': discrepancy,
                  'referenceActual': second.get('actual'), 'referenceMeetsAssertion': second.get('meetsAssertion'),
                  'issue': case.get('issue'), 'clipped': first.get('clipped'),
                  'nativeError': first.get('error'), 'referenceError': second.get('error'),
                  'widthDifference': first['width']-second['width'] if 'width' in first and 'width' in second else None}
        records.append(record)
        pictures = ''
        if first.get('image') and second.get('image'):
            a = Image.open(args.directory/first['image']).convert('RGBA')
            b = Image.open(args.directory/second['image']).convert('RGBA')
            a, b = aligned(a, b, first, second, native, reference)
            pictures = ''.join(f'<figure><figcaption>{name}</figcaption><img src="{image_data(img)}" width="{img.width/native["scale"]}" alt="{name}"></figure>'
                for name, img in [('MathMLLayout', a), (args.reference, b), ('50% overlay', Image.blend(a,b,.5)),
                                  ('Absolute RGB difference (review only)', ImageChops.difference(a.convert('RGB'), b.convert('RGB')))])
        link = f'<a href="{html.escape(case.get("source", ""), quote=True)}">Upstream assertion</a>' if case.get('source') else ''
        articles.append(f'<article data-outcome="{html.escape(category)}"><h2>{html.escape(case["id"])}</h2>'
                        f'<p>{html.escape(category)} {link}</p><pre>{html.escape(json.dumps(record, indent=2))}</pre>'
                        f'<div class="pictures">{pictures}</div><details><summary>Source MathML</summary><pre>{html.escape(case["markup"])}</pre></details></article>')
    summary = {'features': {f: dict(c) for f,c in groups.items()}, 'exclusions': manifest.get('exclusions', []),
               'engines': [{k:v for k,v in r.items() if k != 'cases'} for r in [native, reference]], 'cases': records}
    (args.directory/'comparison.json').write_text(json.dumps(summary, indent=2)+'\n')
    page = ('<!doctype html><meta charset="utf-8"><title>External MathML validation</title>'
        '<style>body{font:15px system-ui;margin:24px;max-width:1600px}article{border-top:1px solid #aaa;padding:16px 0}'
        '.pictures{display:flex;gap:16px;overflow:auto}figure{margin:0}img{max-width:none}pre{white-space:pre-wrap;font-size:12px}'
        'figcaption{padding-bottom:8px}h2{font-size:18px}</style>'
        '<h1>External MathML validation</h1><p>Geometry assertions use upstream expectations. '
        'DOM boxes and ink bounds are distinct; width differences require review. Images are aligned to their baseline. '
        'Pixel differences include rasterization noise and do not decide pass/fail. Corpus renderings remain unreviewed.</p>'
        f'<pre>{html.escape(json.dumps({"features":summary["features"],"engines":summary["engines"],"exclusions":summary["exclusions"]},indent=2))}</pre>'
        '<label>Show <select id="filter"><option value="all">All outcomes</option>' +
        ''.join(f'<option>{html.escape(c)}</option>' for c in sorted({r["classification"] for r in records})) +
        '</select></label>' + ''.join(articles) +
        '<script>document.querySelector("#filter").onchange=e=>document.querySelectorAll("article").forEach(a=>a.hidden=e.target.value!=="all"&&a.dataset.outcome!==e.target.value)</script>')
    (args.directory/'index.html').write_text(page)
    print(json.dumps(summary['features']))

if __name__ == '__main__': main()
