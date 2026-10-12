#!/usr/bin/env python3
"""Port eight reviewed operator/table WPT checks, preserving the Ahem font.

Only the three supported grouping elements' in-flow cases are selected. Browser CSS,
unknown elements, phantom/error wrappers and out-of-flow children are not ported.
"""
import argparse
import copy
import hashlib
import json
import shutil
from pathlib import Path
from lxml import etree, html


def sha(data): return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('checkout', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    (args.destination / 'upstream').mkdir(parents=True, exist_ok=True)
    (args.destination / 'fonts').mkdir(parents=True, exist_ok=True)
    pins = json.loads((Path(__file__).parent / 'wpt-pins.json').read_text())
    sources = ['operators/embellished-operator-001.html', 'tables/table-cell-mrow-layout.html']
    cases = []
    for source in sources:
        path = 'mathml/presentation-markup/' + source
        raw = (args.checkout / path).read_bytes()
        if sha(raw) != pins['files'][path]: raise ValueError(f'Pinned source hash mismatch: {path}')
        (args.destination / 'upstream' / Path(source).name).write_bytes(raw)
        doc = html.fromstring(raw)
        def formula(element_id):
            return next(m for m in doc.iter('math') if m.xpath('.//*[@id=$id]', id=element_id))
        def normalize(root):
            root = copy.deepcopy(root)
            for e in root.iter():
                if not isinstance(e.tag, str): continue
                e.attrib.pop('style', None)
                e.attrib.pop('class', None)
                # Same fixed size as upstream CSS; script sizing is not under test.
                e.set('mathsize', '25px' if source.startswith('operators/') else '20px')
            root.set('xmlns', 'http://www.w3.org/1998/Math/MathML')
            return root
        def record(case_id, original, root, **kwargs):
            markup = etree.tostring(root, encoding='unicode', with_tail=False)
            cases.append(dict(id=case_id, source=f'https://github.com/web-platform-tests/wpt/blob/{pins["revision"]}/{path}',
                sourceSHA256=sha(raw), originalMarkup=etree.tostring(original, encoding='unicode', with_tail=False),
                markup=markup, sha256=sha(markup.encode()), tolerance=1, **kwargs))
        if source.startswith('operators/'):
            for tag in ['mrow', 'mstyle', 'mpadded']:
                for embellished in [True, False]:
                    element_id = f'{tag}-' + ('op-1' if embellished else 'nonop-1')
                    original = formula(element_id)
                    root = normalize(original)
                    wrapper = root.xpath('//*[@id=$id]', id=element_id)[0]
                    wrapper.set('mathbackground', 'blue')
                    root[0].set('mathcolor', 'red')
                    root[0].set('mathbackground', 'red')
                    wrapper[0].set('mathcolor', 'lime')
                    record(element_id, original, root, feature='embellished operators', kind='operator',
                        upstreamTest=f'{tag} ({"embellished operator" if embellished else "not embellished operator"})',
                        specification='https://www.w3.org/TR/mathml-core/#embellished-operators',
                        fontSize=25, font='fonts/Ahem.ttf', expectedOuterGap=50 if embellished else 0,
                        expectedInnerGap=0 if embellished else 50,
                        normalization=['CSS font:25px/1 Ahem replaced by fixed mathsize on all nodes',
                            'CSS blue backgrounds and colored glyphs identify wrapper and core operator; DOM positions compared via Ahem ink',
                            'transparent foreground draw exposes measured backgrounds without changing geometry'])
        else:
            original = formula('mtable')
            table = normalize(original)
            for e in table.iter('mspace'):
                e.set('mathbackground', ['red', 'lime', 'blue'][list(table.iter('mspace')).index(e)])
            for element_id, title in [('mtd-reference', '<mtd> relies on mrow algorithm to layout its children'),
                                      ('mtable-reference', '<mtable> layout does not change if children of <mtd> elements are wrapped in an explicit <mrow>')]:
                ref = normalize(formula(element_id))
                for i, e in enumerate(ref.iter('mspace')): e.set('mathbackground', ['red', 'lime', 'blue'][i])
                reference = etree.tostring(ref, encoding='unicode', with_tail=False)
                record(element_id, original, table, feature='tables', kind='table', upstreamTest=title,
                    specification='https://www.w3.org/TR/mathml-core/#table-or-matrix-mtable',
                    fontSize=20, referenceMarkup=reference, referenceSHA256=sha(reference.encode()),
                    normalization=['CSS mtd padding:0 matches native cell layout',
                        'mspace CSS backgrounds replaced by mathbackground',
                        'cell comparison uses colored child geometry relative to the first child, excluding table axis placement'])
    font = args.checkout / 'fonts/Ahem.ttf'
    if sha(font.read_bytes()) != pins['files']['fonts/Ahem.ttf']: raise ValueError('Ahem pin mismatch')
    shutil.copyfile(font, args.destination / 'fonts/Ahem.ttf')
    result = dict(revision=pins['revision'], cases=cases,
        fonts=[dict(path='fonts/Ahem.ttf', postScriptName='Ahem', sha256=sha(font.read_bytes()),
                    license='Public domain / CC0; declaration retained in font name table')])
    (args.destination / 'supplemental.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'Imported {len(cases)} supplemental WPT cases')


if __name__ == '__main__': main()
