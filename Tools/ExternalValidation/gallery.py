#!/usr/bin/env python3
"""Create a standalone comparison gallery; numerical assertions decide outcomes, pixels aid review.
Pillow supplies baseline-aligned image overlays/differences (never a pixel-equality pass criterion).
"""
import argparse
import base64
import html
import io
import json
from collections import Counter, defaultdict
from pathlib import Path
from PIL import Image, ImageChops


def image_data(image):
    data = io.BytesIO(); image.save(data, format='PNG')
    return 'data:image/png;base64,' + base64.b64encode(data.getvalue()).decode()


def aligned(a, b, first, second, report1, report2):
    scale = report1['scale']
    if report2['scale'] != scale: raise ValueError('Different image scales cannot be overlaid')
    # PNG baselines are measured down from their padded top edge. Both engines emit 16-unit margins.
    y1 = round((first['ascent'] + report1['margin']) * scale)
    y2 = round((second['ascent'] + report2['margin']) * scale)
    baseline = max(y1, y2)
    w = max(a.width, b.width); h = max(a.height + baseline-y1, b.height + baseline-y2)
    left = Image.new('RGBA', (w, h), 'white'); right = left.copy()
    left.alpha_composite(a, (0, baseline-y1)); right.alpha_composite(b, (0, baseline-y2))
    return left, right


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--reference', default='chromium')
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    native = json.loads((args.directory/'mathmllayout.json').read_text())
    reference = json.loads((args.directory/(args.reference+'.json')).read_text())
    if native['manifestSHA256'] != reference['manifestSHA256']:
        raise ValueError('Reports do not describe the same manifest')
    references = {c['id']: c for c in reference['cases']}
    local = {c['id']: c for c in native['cases']}
    groups, articles, records = defaultdict(Counter), [], []
    for case in manifest['cases']:
        first, second = local[case['id']], references[case['id']]
        actual, discrepancy = None, None
        if 'error' in first or 'error' in second:
            category = 'unsuitable reference/test' if 'error' in second else 'unreviewed'
        elif 'expected' in case and 'red' in first['rectangles'] and 'blue' in first['rectangles']:
            actual = first['rectangles']['red'][case['firstMetric']] - first['rectangles']['blue'][case['secondMetric']]
            discrepancy = actual - case['expected']
            category = 'pass' if abs(discrepancy) <= case['tolerance'] else (case['classification'] if case['classification'] != 'pass' else 'unreviewed')
            if category == 'pass' and not second.get('meetsAssertion'):
                category = 'unsuitable reference/test'
        else:
            category = 'unreviewed'
        groups[case.get('feature', 'corpus')][category] += 1
        record = {'id': case['id'], 'classification': category, 'actual': actual,
                  'expected': case.get('expected'), 'discrepancy': discrepancy,
                  'referenceActual': second.get('actual'), 'referenceMeetsAssertion': second.get('meetsAssertion'),
                  'issue': case.get('issue'), 'clipped': first.get('clipped'),
                  'widthDifference': first.get('width', 0)-second.get('width', 0)}
        records.append(record)
        pictures = ''
        if first.get('image') and second.get('image'):
            a = Image.open(args.directory/first['image']).convert('RGBA')
            b = Image.open(args.directory/second['image']).convert('RGBA')
            a, b = aligned(a, b, first, second, native, reference)
            pictures = ''.join(f'<figure><figcaption>{name}</figcaption><img src="{image_data(img)}" width="{img.width/4}" alt="{name}"></figure>'
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
