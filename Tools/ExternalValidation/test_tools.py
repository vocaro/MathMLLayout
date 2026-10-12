import contextlib
import io
import hashlib
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from lxml import etree
from sample_corpus import sample
from import_openstax import import_corpus
from import_wpt import number, apply_reviewed
from gallery import aligned, outcome, validate_reports
from PIL import Image


class ExternalToolTests(unittest.TestCase):
    def testPinnedOpenStaxImporterRejectsExtraXMLBeforeSampling(self):
        pins = json.loads((Path(__file__).parent / 'openstax-pins.json').read_text())
        for extra in ['extra.xml', 'nested/extra.cnxml', 'nested/extra.XML']:
            with self.subTest(extra=extra), tempfile.TemporaryDirectory() as temp:
                root = Path(temp); inputs = root/'inputs'; inputs.mkdir()
                for source in pins['sources']:
                    (inputs/source['file']).write_text('<document/>')
                unexpected = inputs/extra
                unexpected.parent.mkdir(parents=True, exist_ok=True)
                unexpected.write_text('<document/>')
                with self.assertRaisesRegex(ValueError, 'Supply exactly the six pinned'):
                    import_corpus(inputs, root/'out')
                self.assertFalse((root/'out').exists())

    def testCNXMLPreservesNamespacesAndInfersDisplayWithoutResolvingEntities(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); inputs = root/'inputs'; inputs.mkdir()
            (inputs/'a.cnxml').write_text('<document xmlns="http://cnx.rice.edu/cnxml" '
                'xmlns:m="http://www.w3.org/1998/Math/MathML"><math>foreign</math>'
                '<equation><m:math id="original"><m:mtext> a &amp; b </m:mtext></m:math></equation>'
                '<m:math><m:mi>x</m:mi></m:math></document>')
            (inputs/'b.cnxml').write_text('<!DOCTYPE document [<!ENTITY e SYSTEM "file:///etc/hosts">]>'
                '<document xmlns:m="http://www.w3.org/1998/Math/MathML"><m:math><m:mtext>&e;</m:mtext></m:math></document>')
            with contextlib.redirect_stdout(io.StringIO()):
                sample(inputs, root/'out', 100, 52, 'test', 'test', 'https://example.invalid/', 'xml')
            manifest = json.loads((root/'out'/'manifest.json').read_text())
            self.assertEqual(manifest['population']['equations'], 2)
            self.assertEqual(len(manifest['exclusions']), 1)
            display = next(c for c in manifest['cases'] if c['display'] == 'block')
            doc = etree.fromstring(display['markup'].encode())
            self.assertEqual(etree.QName(doc).namespace, 'http://www.w3.org/1998/Math/MathML')
            self.assertEqual(doc[0].text, ' a & b ')
            self.assertNotIn('id=', display['markup'])
            self.assertEqual(display['provenance'][0]['sourceElementID'], 'original')
            self.assertIn('display=block inferred from CNXML equation wrapper', display['normalization'])

    def testReviewedOutcomesCannotReplaceTheUpstreamExpectation(self):
        case = {'id': 'a', 'expected': 30, 'tolerance': 1, 'classification': 'pass'}
        reviewed = {'classification': 'bug', 'issue': 'https://github.com/vocaro/MathMLLayout/issues/54', 'observed': 35}
        for record in [dict(reviewed, expected=35), dict(reviewed, observed=30), dict(reviewed, observed=float('inf'))]:
            with self.assertRaises(ValueError): apply_reviewed([case.copy()], {'a': record})
        with self.assertRaises(ValueError): apply_reviewed([case.copy()], {'absent': reviewed})
        apply_reviewed([case], {'a': reviewed})
        self.assertEqual(case['expected'], 30)

    def testGalleryRequiresCurrentCompleteReports(self):
        raw = b'{"cases":[{"id":"a"},{"id":"b"}]}'
        manifest = json.loads(raw)
        report = {'manifestSHA256': hashlib.sha256(raw).hexdigest(), 'cases': manifest['cases']}
        validate_reports(raw, manifest, report, report)
        for invalid in [dict(report, manifestSHA256='stale'), dict(report, cases=[{'id':'a'}]),
                        dict(report, cases=[{'id':'a'}, {'id':'a'}])]:
            with self.assertRaises(ValueError): validate_reports(raw, manifest, invalid, report)
        with self.assertRaises(ValueError): validate_reports(raw+b' ', manifest, report, report)

    def testGalleryDoesNotHideChangedBugsOrClipping(self):
        case = {'expected': 30, 'tolerance': 1, 'classification': 'pass', 'firstMetric': 'top', 'secondMetric': 'top'}
        native = {'rectangles': {'red': {'top': 30}, 'blue': {'top': 0}}, 'clipped': False}
        reference = {'meetsAssertion': True}
        self.assertEqual(outcome(case, native, reference), ('pass', 30))
        self.assertEqual(outcome(case, dict(native, clipped=True), reference)[0], 'unreviewed')
        self.assertEqual(outcome(case, native, {'meetsAssertion': False})[0], 'unsuitable reference/test')
        bug = dict(case, classification='bug', observed=35, issue='#54')
        self.assertEqual(outcome(bug, native, reference)[0], 'unreviewed')
        native['rectangles']['red']['top'] = 35
        self.assertEqual(outcome(bug, native, reference)[0], 'bug')
        self.assertEqual(outcome(bug, native, {'meetsAssertion': False})[0], 'unsuitable reference/test')
        native['rectangles']['red']['top'] = 40
        self.assertEqual(outcome(bug, native, reference)[0], 'unreviewed')

    def testGalleryAlignsActualImageOriginsOnBothAxes(self):
        a = Image.new('RGBA', (10, 12)); a.putpixel((2, 7), (255, 0, 0, 255))
        b = Image.new('RGBA', (14, 14)); b.putpixel((5, 9), (255, 0, 0, 255))
        first = {'imageOrigin': {'x': 2, 'y': 7}}
        second = {'imageOrigin': {'x': 5, 'y': 9}}
        left, right = aligned(a, b, first, second, {'scale':4}, {'scale':4})
        self.assertEqual(left.tobytes(), right.tobytes())

    def testCorpusPreservesTokenAndAnnotationWhitespace(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); inputs = root/'inputs'; inputs.mkdir()
            (inputs/'a.html').write_text('<math><mtext> <mi>x</mi> </mtext><semantics><mi>x</mi>'
                '<annotation-xml encoding="application/xhtml+xml"><div> <span>x</span> </div></annotation-xml>'
                '</semantics><mrow xml:space="preserve"> <mi>x</mi> </mrow></math>')
            with contextlib.redirect_stdout(io.StringIO()):
                sample(inputs, root/'out', 1, 52, 'test', 'test', 'https://example.invalid/')
            markup = json.loads((root/'out'/'manifest.json').read_text())['cases'][0]['markup']
            doc = etree.fromstring(markup.encode())
            for name in ('mtext', 'div', 'mrow'):
                element = doc.xpath('//*[local-name()=$name]', name=name)[0]
                self.assertEqual(element.text, ' ')
                self.assertEqual(element[0].tail, ' ')

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

class RendererIntegrationTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get('MATHML_NATIVE_RENDERER'), 'Set MATHML_NATIVE_RENDERER to the built CLI')
    def testNativeErrorsArePerCaseAndOriginAccountsForRounding(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            cases = [dict(id=name, markup='<math><mi>x</mi></math>', fontSize=size)
                     for name, size in [('valid', 17.3), ('zero', 0), ('negative', -1)]]
            cases.append({'id':'budget', 'markup':'<math><mspace width="4000px" height="4000px"/></math>'})
            cases.append({'id':'width', 'markup':'<math><mi>x</mi></math>', 'maximumWidth':0})
            manifest = root/'manifest.json'; manifest.write_text(json.dumps({'cases':cases}))
            subprocess.run([os.environ['MATHML_NATIVE_RENDERER'], str(manifest), str(root)], check=True, capture_output=True)
            report = json.loads((root/'mathmllayout.json').read_text())
            valid, *errors = report['cases']
            self.assertNotIn('error', valid)
            self.assertTrue(all('error' in case for case in errors))
            with Image.open(root/valid['image']) as image:
                self.assertEqual(valid['imageOrigin']['y'], image.height - (report['margin']+valid['descent'])*report['scale'])

    @unittest.skipUnless(os.environ.get('MATHML_BROWSER_NODE'), 'Set MATHML_BROWSER_NODE to run Chromium checks')
    def testBrowserReportsUnsupportedMarkupInsteadOfChangingIt(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            cases = [dict(id=name, markup=markup, fontSize=10) for name, markup in [
                ('valid', '<math><mi>x</mi></math>'),
                ('element', '<math><unknown><mi>x</mi></unknown></math>'),
                ('attribute', '<math><mpadded voffset="2em"><mi>x</mi></mpadded></math>'),
                ('namespace', '<math xmlns="urn:foreign"><mi>x</mi></math>'),
                ('budget', '<math><mspace width="2000px" height="2000px"/></math>')]]
            cases.append({'id':'width', 'markup':'<math><mi>x</mi></math>', 'maximumWidth':20})
            manifest = root/'manifest.json'; manifest.write_text(json.dumps({'cases':cases}))
            subprocess.run([os.environ['MATHML_BROWSER_NODE'], str(Path(__file__).with_name('references.cjs')),
                            str(manifest), str(root), 'chromium'], check=True, capture_output=True)
            valid, *errors = json.loads((root/'chromium.json').read_text())['cases']
            self.assertNotIn('error', valid)
            self.assertTrue(valid['fontLoaded'])
            self.assertTrue(all('error' in case for case in errors))
            self.assertGreater(valid['imageOrigin']['y'], 0)
            self.assertLess(valid['imageOrigin']['y'], valid['clip']['height']*4)

if __name__ == '__main__': unittest.main()
