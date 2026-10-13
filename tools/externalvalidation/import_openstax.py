#!/usr/bin/env python3
"""Sample the pinned, locally supplied OpenStax CNXML modules for #52.

Inputs and resulting MathML retain CC-BY-NC-SA-4.0, not the library's MIT license.
Keep these corpus files outside source/binary distributions of MathMLLayout.
This tool neither downloads sources nor accepts license agreements.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
from sample_corpus import sample


def import_corpus(inputs, output):
    pins = json.loads((Path(__file__).parent / 'openstax-pins.json').read_text())
    sources = {s['file']: s for s in pins['sources']}
    # Match the sampler's recursive XML discovery, so every imported file is pinned.
    actual_files = {str(p.relative_to(inputs)) for p in inputs.rglob('*')
                    if p.suffix.lower() in {'.xml', '.cnxml'}}
    if actual_files != set(sources):
        raise ValueError('Supply exactly the six pinned CNXML modules')
    for filename, expected in [(s['file'], s['sha256']) for s in sources.values()] + [('LICENSE', pins['licenseSHA256'])]:
        if hashlib.sha256((inputs / filename).read_bytes()).hexdigest() != expected:
            raise ValueError(f'Pinned source hash mismatch: {filename}')
    base = f'https://github.com/{pins["repository"]}/blob/{pins["revision"]}/'
    sample(inputs, output, pins['count'], pins['seed'], pins['revision'], pins['license'], base, 'xml')
    path = output / 'manifest.json'
    manifest = json.loads(path.read_text())
    manifest['attribution'] = 'OpenStax, Rice University; Calculus Volumes 1–3; textbook mathematics excerpts.'
    manifest['licenseURL'] = 'https://creativecommons.org/licenses/by-nc-sa/4.0/'
    manifest['licenseFile'] = 'LICENSE'
    manifest['sourceModules'] = pins['sources']
    for case in manifest['cases']:
        for occurrence in case['provenance']:
            source = sources[occurrence['sourceFile']]
            occurrence['sourceURL'] = base + source['path']
            occurrence['sourceTitle'] = source['title']
        case['source'] = case['provenance'][0]['sourceURL']
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
    shutil.copyfile(inputs / 'LICENSE', output / 'LICENSE')
    (output / 'NOTICE.txt').write_text(
        manifest['attribution'] + '\n' + manifest['licenseURL'] + '\n'
        'Original modules preserved byte-for-byte under originals/. On October 12, 2026,\n'
        'MathML was extracted and normalized as recorded for each case in manifest.json.\n'
        'This is an independently sourced input corpus, not an authoritative layout oracle.\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inputs', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    import_corpus(args.inputs, args.output)
