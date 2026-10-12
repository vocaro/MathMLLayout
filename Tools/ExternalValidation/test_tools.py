import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from lxml import etree
from sample_corpus import sample
from import_wpt import number


class ExternalToolTests(unittest.TestCase):
    def testArithmeticCannotExecuteCode(self):
        self.assertEqual(number('v * 234 / 100', {'v': 100}), 234)
        for expression in ['__import__("os").system("false")', 'v.__class__', '[v]', 'True']:
            with self.assertRaises(ValueError): number(expression, {'v': 1})

    def testCorpusSamplingIsDeterministicAndKeepsProvenance(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); inputs = root/'inputs'; inputs.mkdir()
            # Named entities, annotation, duplicate in a different source, rare root,
            # inline/display forms, and a reference to an external entity.
            (inputs/'a.html').write_text('''<!doctype html><html><body>
              <math id="first"><mi>&alpha;</mi></math>
              <math display="block"><semantics><mfrac><mi>x</mi><mi>y</mi></mfrac>
                <annotation encoding="application/x-tex">x/y</annotation></semantics></math>
              <math><mroot><mi>x</mi><mn>3</mn></mroot></math></body></html>''')
            (inputs/'b.html').write_text('<html><math class="duplicate"><mi>α</mi></math></html>')
            results = []
            for name in ['one', 'two']:
                output = root/name
                with contextlib.redirect_stdout(io.StringIO()):
                    sample(inputs, output, 1000, 52, 'test', 'test-only', 'https://example.invalid/corpus')
                results.append((output/'manifest.json').read_bytes())
            self.assertEqual(results[0], results[1])
            manifest = json.loads(results[0])
            self.assertEqual(manifest['population']['equations'], 4)
            self.assertEqual(len(manifest['cases']), 3)
            alpha = next(c for c in manifest['cases'] if 'α' in c['markup'])
            self.assertEqual(len(alpha['provenance']), 2)
            self.assertEqual(etree.QName(etree.fromstring(alpha['markup'].encode())).namespace, 'http://www.w3.org/1998/Math/MathML')
            self.assertNotIn('&alpha;', alpha['markup'])
            for case in manifest['cases']:
                self.assertIn(case['classification'], ['unreviewed'])
                self.assertTrue((root/'one'/case['provenance'][0]['originalFile']).exists())
            self.assertTrue(any('annotation' in c['features'] for c in manifest['cases']))

    def testCorpusDoesNotResolveExternalEntities(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); inputs = root/'inputs'; inputs.mkdir()
            secret = root/'secret'; secret.write_text('EXTERNAL_ENTITY_SHOULD_NOT_LOAD')
            (inputs/'a.html').write_text(f'<!DOCTYPE html [<!ENTITY external SYSTEM "{secret.as_uri()}">]><html><math><mtext>&external;</mtext></math></html>')
            with contextlib.redirect_stdout(io.StringIO()):
                sample(inputs, root/'out', 1000, 52, 'test', 'test', 'https://example.invalid/')
            manifest = (root/'out'/'manifest.json').read_text()
            self.assertNotIn('EXTERNAL_ENTITY_SHOULD_NOT_LOAD', manifest)
            self.assertNotIn('<!DOCTYPE', manifest)

if __name__ == '__main__': unittest.main()
