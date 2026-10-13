#!/usr/bin/env python3
"""Regenerate the bundled corpora from hash-pinned sources (requires lxml).

Downloads occur only with --download. Ordinary Swift tests use checked-in resources.
The textbook excerpts retain CC-BY-4.0; the SRE excerpts retain Apache-2.0.
"""
import argparse
import hashlib
import json
import tempfile
import urllib.request
from pathlib import Path

from sample_corpus import sample


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + '\n').encode()


def generate(dataset, cache, download):
    root = cache / dataset['id']
    source_base = f'https://github.com/{dataset["repository"]}/blob/{dataset["revision"]}/'
    raw_base = f'https://raw.githubusercontent.com/{dataset["repository"]}/{dataset["revision"]}/'
    sources = {}
    output = {}
    for entry in dataset['files']:
        path = root / entry['path']
        if download and not path.exists():
            with urllib.request.urlopen(raw_base + entry['path'], timeout=30) as response:
                raw = response.read(32 * 1024 * 1024 + 1)
            if len(raw) > 32 * 1024 * 1024 or digest(raw) != entry['sha256']:
                raise ValueError(f'Pinned source hash mismatch: {entry["path"]}')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
        raw = path.read_bytes()
        if digest(raw) != entry['sha256']:
            raise ValueError(f'Pinned source hash mismatch: {path}')
        sources[entry['path']] = raw
        if 'bundledAs' in entry:
            output[entry['bundledAs']] = raw

    if dataset['id'] == 'openstax-precalculus':
        # Reuse the stratified XML sampler. Only MathML excerpts enter the bundle;
        # original modules can be recovered using their recorded paths and hashes.
        with tempfile.TemporaryDirectory() as directory:
            inputs = Path(directory) / 'inputs'
            inputs.mkdir()
            for entry in dataset['files']:
                if entry['path'].endswith('.cnxml'):
                    (inputs / Path(entry['path']).parent.name).with_suffix('.cnxml').write_bytes(sources[entry['path']])
            sampled = Path(directory) / 'sample'
            sample(inputs, sampled, dataset['count'], dataset['seed'], dataset['revision'],
                   dataset['license'], source_base, 'xml')
            manifest = json.loads((sampled / 'manifest.json').read_text())
        modules = {Path(e['path']).parent.name + '.cnxml': e for e in dataset['files'] if e['path'].endswith('.cnxml')}
        for case in manifest['cases']:
            case['id'] = dataset['id'] + '-' + case['sha256'][:20]
            for occurrence in case['provenance']:
                entry = modules[occurrence['sourceFile']]
                occurrence['sourceFile'] = entry['path']
                occurrence['sourceURL'] = source_base + entry['path']
                occurrence['sourceTitle'] = entry['title']
                occurrence.pop('originalFile')
        if len(manifest['cases']) != dataset['count'] or manifest['exclusions']:
            raise ValueError('Textbook sampling did not produce the complete pinned sample')
    else:
        cases = {}
        for entry in dataset['files']:
            if not entry['path'].endswith('.json'):
                continue
            tests = json.loads(sources[entry['path']])['tests']
            for name, test in sorted(tests.items()):
                if not isinstance(test, dict) or not isinstance(test.get('input'), str):
                    continue
                markup = '<math xmlns="http://www.w3.org/1998/Math/MathML">' + test['input'] + '</math>'
                sha = digest(markup.encode())
                case = cases.setdefault(sha, {'id': dataset['id'] + '-' + sha[:20], 'markup': markup,
                    'sha256': sha, 'fontSize': 20, 'provenance': []})
                case['provenance'].append({'sourceFile': entry['path'], 'sourceSHA256': entry['sha256'],
                                          'sourceURL': source_base + entry['path'], 'test': name})
        manifest = {'schemaVersion': 1, 'datasetRelease': dataset['revision'], 'license': dataset['license'],
                    'sampling': 'All distinct inputs from four pinned Mathspeak files; speech-preference duplicates merged.',
                    'cases': [cases[key] for key in sorted(cases)]}

    if not set(dataset.get('expectedInvalidMarkup', {})).issubset({c['sha256'] for c in manifest['cases']}):
        raise ValueError('Expected rejection refers to an input outside the corpus')
    for case in manifest['cases']:
        if case['sha256'] in dataset.get('expectedInvalidMarkup', {}):
            case['expectedInvalidMarkup'] = dataset['expectedInvalidMarkup'][case['sha256']]
            case['rejectionReason'] = 'An unmatched final prescript lacks its subscript/superscript pair.'

    manifest.update({'dataset': dataset['id'], 'attribution': dataset['attribution'],
                     'licenseURL': dataset['licenseURL'], 'licenseFile': 'LICENSE.txt', 'noticeFile': 'NOTICE.txt',
                     'sourceURL': source_base, 'sourceFiles': dataset['files'],
                     'outcomeMeaning': 'Layout robustness invariants, not an authoritative visual or standards oracle.'})
    changes = ('MathML extracted and normalized; display inferred from CNXML equation wrappers; '
               '100 cases selected by the recorded stratified sampler.' if dataset['id'] == 'openstax-precalculus'
               else 'MathML input fragments wrapped in a standalone math element; exact duplicates merged; speech expectations omitted; three incomplete script pairs recorded as expected invalidMarkup rejections.')
    output['NOTICE.txt'] = (dataset['attribution'] + '\n' + source_base + '\n' + dataset['licenseURL']
        + '\n\nChanges by MathMLLayout: ' + changes + '\n'
        + 'This data retains its source license, separately from MathMLLayout\'s original MIT code.\n').encode()
    output['manifest.json'] = encoded(manifest)
    return output, len(manifest['cases'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', type=Path, required=True, help='Local hash-verified upstream source cache')
    parser.add_argument('--download', action='store_true', help='Download missing pinned files into the cache')
    parser.add_argument('--verify', action='store_true', help='Compare regeneration with the checked-in bundle')
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[2] / 'Tests/MathMLLayoutTests/ExternalFixtures/Corpus')
    args = parser.parse_args()
    pins = json.loads(Path(__file__).with_name('bundled-corpus-pins.json').read_text())
    for dataset in pins['datasets']:
        output, count = generate(dataset, args.cache, args.download)
        folder = args.output / dataset['id']
        for filename, raw in output.items():
            path = folder / filename
            if args.verify:
                if path.read_bytes() != raw:
                    raise ValueError(f'Bundled file differs from pinned regeneration: {path}')
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
        print(f'{dataset["id"]}: {count} cases {"verified" if args.verify else "written"}')


if __name__ == '__main__':
    main()
