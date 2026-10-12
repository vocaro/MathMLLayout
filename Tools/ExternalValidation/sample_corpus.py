#!/usr/bin/env python3
"""Stratify local HTML+MathML data; source access/license acceptance is the caller's responsibility.
No downloads or external entity loading. Requires lxml; preserves source files byte-for-byte.
"""
import argparse
import copy
import hashlib
import json
import math
from collections import Counter, defaultdict
from pathlib import Path
from lxml import etree, html

NS = 'http://www.w3.org/1998/Math/MathML'

def sha(data):
    return hashlib.sha256(data).hexdigest()


def sample(inputs, output, count, seed, release, license_name, source_url, input_format='html'):
    if count < 1: raise ValueError('count must be positive')
    if not inputs.is_dir(): raise ValueError('inputs must be an existing directory')
    if output.resolve().is_relative_to(inputs.resolve()): raise ValueError('output must be outside inputs')
    candidates, errors = {}, []
    originals = output / 'originals'
    originals.mkdir(parents=True, exist_ok=True)
    file_count, equations = 0, 0
    if input_format not in {'html', 'xml'}: raise ValueError('Unknown input format')
    extensions = {'.html', '.xhtml', '.htm'} if input_format == 'html' else {'.xml', '.cnxml'}
    paths = sorted(p for p in inputs.rglob('*') if p.suffix.lower() in extensions)
    for path in paths:
        file_count += 1
        with path.open('rb') as source:
            raw = source.read(32 * 1024 * 1024 + 1)
        if len(raw) > 32 * 1024 * 1024:
            errors.append({'source': str(path.relative_to(inputs)), 'classification': 'invalid/out-of-bounds input',
                           'reason': 'Source exceeds importer 32 MiB budget'}); continue
        try:
            # HTML parser resolves only built-in named character references, not XML external entities.
            raw.decode('utf-8')  # Reject other encodings explicitly.
            if input_format == 'xml':
                # CNXML textbook sources contain namespace-qualified presentation MathML.
                # Reject declarations rather than retaining unresolved entity nodes.
                if b'<!DOCTYPE' in raw.upper() or b'<!ENTITY' in raw.upper():
                    raise ValueError('XML DOCTYPE/entity declarations are not accepted')
                doc = etree.fromstring(raw, parser=etree.XMLParser(resolve_entities=False, no_network=True))
            else:
                doc = html.fromstring(raw, parser=html.HTMLParser(encoding='utf-8', no_network=True, recover=False))
        except (ValueError, etree.ParserError, etree.XMLSyntaxError) as error:
            errors.append({'source': str(path.relative_to(inputs)), 'classification': 'invalid/out-of-bounds input',
                           'reason': str(error)}); continue
        raw_hash = sha(raw)
        sources = doc.xpath('//*[local-name()="math"]')
        if input_format == 'xml':
            sources = [e for e in sources if etree.QName(e).namespace == NS]
        if sources:
            (originals / (raw_hash + path.suffix.lower())).write_bytes(raw)
        for index, element in enumerate(sources):
            equations += 1
            root = copy.deepcopy(element)
            features = Counter(etree.QName(e).localname for e in root.iter() if isinstance(e.tag, str))
            attrs = sorted({etree.QName(e).localname + '@' + a for e in root.iter() if isinstance(e.tag, str) for a in e.attrib})
            # Build namespace-correct standalone XML from the parsed HTML; remove DOM IDs/classes
            # for deduplication, preserving every mathematical attribute and annotations.
            for e in root.iter():
                if not isinstance(e.tag, str): continue
                if not any(etree.QName(parent).localname == 'annotation-xml' for parent in e.iterancestors()):
                    e.tag = '{' + NS + '}' + etree.QName(e).localname
                for a in ['id', 'class']: e.attrib.pop(a, None)
            etree.cleanup_namespaces(root, top_nsmap={None: NS})
            # Whitespace within tokens, annotations, foreign payloads, and xml:space
            # regions is content. Only strip indentation in mathematical containers.
            def preserves_text(e):
                return any(isinstance(p.tag, str) and (
                    etree.QName(p).localname in {'mi', 'mn', 'mo', 'mtext', 'ms', 'annotation', 'annotation-xml'}
                    or p.get('xml:space') == 'preserve'
                    or p.get('{http://www.w3.org/XML/1998/namespace}space') == 'preserve')
                    for p in [e, *e.iterancestors()])
            for e in root.iter():
                if not isinstance(e.tag, str): continue
                if not preserves_text(e) and len(e) and e.text and e.text.isspace(): e.text = None
                parent = e.getparent()
                if parent is not None and not preserves_text(parent) and e.tail and e.tail.isspace(): e.tail = None
            original_display = root.get('display')
            # CNXML equation wrappers distinguish display equations from inline math.
            inferred_display = input_format == 'xml' and any(
                etree.QName(p).localname == 'equation' for p in element.iterancestors())
            if original_display is None and inferred_display: root.set('display', 'block')
            normalized = etree.tostring(root, encoding='unicode', with_tail=False)
            digest = sha(normalized.encode())
            provenance = {'sourceFile': str(path.relative_to(inputs)), 'sourceSHA256': raw_hash,
                'originalFile': 'originals/' + raw_hash + path.suffix.lower(), 'equationIndex': index,
                'sourceElementID': element.get('id'), 'sourceURL': source_url}
            if digest in candidates:
                candidates[digest]['provenance'].append(provenance); continue
            nodes = sum(features.values())
            depth = max((len(list(e.iterancestors())) for e in root.iter()), default=0)
            if len(normalized.encode()) > 4*1024*1024 or nodes > 20_000 or depth > 64:
                errors.append({'source': provenance, 'sha256': digest,
                    'classification': 'invalid/out-of-bounds input', 'reason': 'Exceeds documented parser/layout bounds'}); continue
            display = root.get('display', 'inline')
            candidates[digest] = {'id': 'corpus-' + digest[:20], 'markup': normalized, 'sha256': digest,
                'feature': 'corpus', 'features': dict(features), 'attributes': attrs, 'provenance': [provenance],
                'nodeCount': nodes, 'depth': depth, 'display': display, 'fontSize': 20,
                'normalization': [('UTF-8 XML; declarations rejected; external access disabled' if input_format == 'xml'
                    else 'UTF-8 HTML; named entities decoded to Unicode by lxml; external access disabled'),
                    'standalone MathML namespace outside annotation-xml payloads', 'DOM id/class removed for deduplication',
                    'inter-element indentation removed; token text and annotations preserved'] +
                    (['display=block inferred from CNXML equation wrapper'] if inferred_display and original_display is None else []),
                'classification': 'unreviewed', 'stratum': display + ':' + str(int(math.log2(max(1, nodes))))}
    frequencies = Counter()
    for c in candidates.values(): frequencies.update(c['features'].keys())
    buckets = defaultdict(list)
    for digest, c in candidates.items():
        rarest = min(c['features'], key=lambda f: (frequencies[f], f))
        c['stratum'] += ':' + rarest
        buckets[c['stratum']].append((sha((str(seed)+digest).encode()), c))
    for bucket in buckets.values(): bucket.sort(key=lambda entry: entry[0])
    chosen = []
    # Round-robin strata guarantee rare element and display/complexity combinations participate.
    while buckets and len(chosen) < count:
        for name in sorted(list(buckets)):
            chosen.append(buckets[name].pop(0)[1])
            if not buckets[name]: del buckets[name]
            if len(chosen) == count: break
    manifest = {'schemaVersion': 1, 'datasetRelease': release, 'license': license_name,
        'sourceURL': source_url, 'seed': seed, 'requestedCount': count, 'cases': chosen, 'fonts': [],
        'population': {'files': file_count, 'equations': equations, 'uniqueEquations': len(candidates)},
        'sampling': 'SHA256(seed+fixture hash) order within display/log2(node count)/rarest element strata; round-robin strata',
        'exclusions': errors, 'outcomeMeaning': 'Inputs for invariant checks and review; no authoritative expected layout.'}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False)+'\n')
    print(f'{len(chosen)} sampled of {len(candidates)} unique equations ({equations} before deduplication)')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inputs', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--count', type=int, default=1000)
    parser.add_argument('--seed', type=int, default=52)
    parser.add_argument('--release', required=True)
    parser.add_argument('--license', required=True, dest='license_name')
    parser.add_argument('--source-url', required=True)
    parser.add_argument('--input-format', choices=['html', 'xml'], default='html')
    args = parser.parse_args()
    if args.count < 1: parser.error('count must be positive')
    if args.output.resolve().is_relative_to(args.inputs.resolve()): parser.error('output must be outside inputs')
    sample(args.inputs, args.output, args.count, args.seed, args.release, args.license_name, args.source_url, args.input_format)
