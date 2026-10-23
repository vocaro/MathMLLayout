// Pinned native browser references. No arbitrary page scripts or external resources run.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { chromium, firefox, webkit } = require('playwright');

(async () => {
  const [manifestPath, output, engine = 'chromium'] = process.argv.slice(2);
  if (!manifestPath || !output || !['chromium', 'firefox', 'webkit'].includes(engine)) {
    throw new Error('Usage: node references.cjs manifest.json output-directory [chromium|firefox|webkit]');
  }
  const raw = fs.readFileSync(manifestPath);
  const manifest = JSON.parse(raw);
  if (new Set(manifest.cases.map(c => c.id)).size !== manifest.cases.length) throw new Error('Duplicate IDs');
  const root = path.dirname(path.resolve(manifestPath));
  const hash = data => crypto.createHash('sha256').update(data).digest('hex');
  const fonts = new Map();
  for (const font of manifest.fonts || []) {
    if (fonts.has(font.path)) throw new Error(`Duplicate font path: ${font.path}`);
    const data = fs.readFileSync(path.join(root, font.path));
    if (hash(data) !== font.sha256) throw new Error(`Font hash mismatch: ${font.path}`);
    fonts.set(font.path, data.toString('base64'));
  }
  fs.mkdirSync(output, { recursive: true });
  // Hang bounds, not time limits: Playwright's 30 s defaults would fail a launch or a case that a
  // busy host only kept waiting for a core. The launch and six cases take under a second.
  const browser = await ({ chromium, firefox, webkit }[engine]).launch({ timeout: 300_000 });
  const results = [];
  try {
    const context = await browser.newContext({ viewport: { width: 4096, height: 4096 }, deviceScaleFactor: 4 });
    context.setDefaultTimeout(120_000);
    await context.route('**/*', route => route.abort());
    const page = await context.newPage();
    for (const sample of manifest.cases) {
      if (!/^[A-Za-z0-9_-]+$/.test(sample.id)) throw new Error(`Unsafe ID: ${sample.id}`);
      try {
        if (sample.maximumWidth != null) throw new Error('maximumWidth constraints are unsupported by the reference adapter');
        await page.setContent('<html><head></head><body></body></html>');
        const base64 = sample.font ? fonts.get(sample.font) : null;
        if (sample.font && !base64) throw new Error(`Unknown font: ${sample.font}`);
        const geometry = await page.evaluate(async ({ sample, base64 }) => {
          // Parse XML with no entity resolution. Only MathML elements and presentation
          // attributes enter the DOM; corpus scripts, URLs and event handlers cannot run.
          if (/<!DOCTYPE|<!ENTITY/i.test(sample.markup)) throw new Error('DOCTYPE/entities rejected');
          const xml = new DOMParser().parseFromString(sample.markup, 'application/xml');
          if (xml.querySelector('parsererror') || xml.documentElement.localName !== 'math') throw new Error('Invalid MathML');
          const allowed = new Set('math mrow mi mn mo mtext ms mspace mfrac msqrt mroot msub msup msubsup mmultiscripts mprescripts none mover munder munderover mtable mtr mtd mlabeledtr mstyle mpadded mphantom merror semantics annotation annotation-xml mfenced menclose mstack mlongdiv msgroup msrow mscarries mscarry msline maction'.split(' '));
          const attrs = new Set('id display displaystyle scriptlevel mathvariant mathsize mathcolor mathbackground width height depth lspace rspace stretchy symmetric largeop movablelimits accent accentunder form minsize maxsize linethickness bevelled rowalign columnalign rowspacing columnspacing columnwidth frame rowlines columnlines open close separators notation position shift stackalign charalign charspacing decimalpoint location crossout scriptsizemultiplier longdivstyle length lquote rquote encoding selection'.split(' '));
          const copy = node => {
            if (node.nodeType === Node.TEXT_NODE) return document.createTextNode(node.nodeValue);
            if (node.nodeType !== Node.ELEMENT_NODE) return document.createDocumentFragment();
            if (!allowed.has(node.localName) || (node.namespaceURI && node.namespaceURI !== 'http://www.w3.org/1998/Math/MathML')) {
              throw new Error(`Unsupported reference element: ${node.nodeName}`);
            }
            const el = document.createElementNS('http://www.w3.org/1998/Math/MathML', node.localName);
            for (const a of node.attributes) {
              if (a.namespaceURI === 'http://www.w3.org/2000/xmlns/' || ['class', 'alttext'].includes(a.name)) continue;
              if (!attrs.has(a.name) || a.namespaceURI) throw new Error(`Unsupported reference attribute: ${a.name}`);
              el.setAttribute(a.name, a.value);
            }
            for (const child of node.childNodes) el.append(copy(child));
            return el;
          };
          const size = sample.fontSize ?? 20;
          if (!Number.isFinite(size) || size <= 0) throw new Error('fontSize must be finite and positive');
          document.head.innerHTML = '<style>html,body{margin:0;background:transparent}#host{display:inline-block;padding:16px;white-space:nowrap}math{margin:0}#baseline{display:inline-block;width:0;height:0;vertical-align:baseline}</style>';
          const font = new FontFace('ExternalFont', base64 ? `url(data:font/otf;base64,${base64})` : 'local("STIXTwoMath-Regular")');
          await font.load(); document.fonts.add(font);
          const host = document.createElement('div'); host.id = 'host';
          host.style.font = `${size}px ExternalFont`;
          const math = copy(xml.documentElement);
          math.style.fontFamily = 'ExternalFont';
          math.style.fontSize = `${size}px`;
          // Display math is hosted inline to expose its baseline while preserving math-style.
          const display = math.getAttribute('display') === 'block';
          if (display) { math.style.display = 'inline math'; math.style.mathStyle = 'normal'; }
          host.append(math);
          const baseline = document.createElement('span'); baseline.id = 'baseline'; host.append(baseline);
          document.body.append(host);
          // The reviewed WPT subset fixes mspace and mo sizes with CSS. mathsize is the
          // equivalent accepted by MathMLLayout but is not a MathML Core browser attribute.
          for (const el of math.querySelectorAll('[mathsize]')) el.style.fontSize = el.getAttribute('mathsize');
          await document.fonts.ready;
          const origin = baseline.getBoundingClientRect();
          const box = math.getBoundingClientRect();
          const hostBox = host.getBoundingClientRect();
          const rect = r => ({ left: r.left-box.left, right: r.right-box.left,
            top: r.top-origin.top, bottom: r.bottom-origin.top, width: r.width, height: r.height });
          const measured = {};
          for (const color of ['red', 'blue']) {
            const el = math.querySelector(`[mathbackground="${color}"]`);
            if (el) measured[color] = rect(el.getBoundingClientRect());
          }
          return { computedFont: getComputedStyle(math).fontFamily, fontLoaded: document.fonts.check(`${size}px ExternalFont`), width: box.width, ascent: origin.top-box.top, descent: box.bottom-origin.top,
            rectangles: measured,
            imageOrigin: { x: (box.left-hostBox.left)*4, y: (origin.top-hostBox.top)*4 },
            clip: { x: hostBox.left, y: hostBox.top, width: Math.ceil(hostBox.width), height: Math.ceil(hostBox.height) } };
        }, { sample, base64 });
        const image = `${engine}-${sample.id}.png`;
        if (geometry.clip.width <= 0 || geometry.clip.height <= 0 || geometry.clip.width > 4096 || geometry.clip.height > 4096 ||
            geometry.clip.width * geometry.clip.height * 16 > 32_000_000) throw new Error('Reference exceeds raster budget');
        await page.screenshot({ path: path.join(output, image), clip: geometry.clip, omitBackground: true });
        const first = geometry.rectangles.red, second = geometry.rectangles.blue;
        const actual = first && second ? first[sample.firstMetric] - second[sample.secondMetric] : null;
        results.push({ id: sample.id, image, ...geometry, actual,
          meetsAssertion: actual !== null ? Math.abs(actual-sample.expected) <= sample.tolerance : null });
      } catch (error) { results.push({ id: sample.id, error: error.message }); }
    }
    const report = { engine, version: browser.version(), playwright: require('playwright/package.json').version,
      manifestSHA256: hash(raw), scale: 4, margin: 16, coordinates: 'CSS pixels, baseline-relative, y-down',
      boxMeaning: 'DOM MathML rectangles, distinct from ink bounds', cases: results };
    fs.writeFileSync(path.join(output, `${engine}.json`), JSON.stringify(report, null, 2)+'\n');
    console.log(`${engine} ${report.version}: ${results.length} cases, ${results.filter(r => r.error).length} errors`);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
