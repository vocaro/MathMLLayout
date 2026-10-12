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
  const root = path.dirname(path.resolve(manifestPath));
  const hash = data => crypto.createHash('sha256').update(data).digest('hex');
  const fonts = new Map((manifest.fonts || []).map(font => {
    const data = fs.readFileSync(path.join(root, font.path));
    if (hash(data) !== font.sha256) throw new Error(`Font hash mismatch: ${font.path}`);
    return [font.path, data.toString('base64')];
  }));
  fs.mkdirSync(output, { recursive: true });
  const browser = await ({ chromium, firefox, webkit }[engine]).launch();
  const results = [];
  try {
    const context = await browser.newContext({ viewport: { width: 4096, height: 4096 }, deviceScaleFactor: 4 });
    await context.route('**/*', route => route.abort());
    const page = await context.newPage();
    for (const sample of manifest.cases) {
      if (!/^[A-Za-z0-9_-]+$/.test(sample.id)) throw new Error(`Unsafe ID: ${sample.id}`);
      try {
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
            if (node.nodeType !== Node.ELEMENT_NODE || !allowed.has(node.localName)) return document.createDocumentFragment();
            const el = document.createElementNS('http://www.w3.org/1998/Math/MathML', node.localName);
            for (const a of node.attributes) if (attrs.has(a.name)) el.setAttribute(a.name, a.value);
            for (const child of node.childNodes) el.append(copy(child));
            return el;
          };
          const size = sample.fontSize || 20;
          document.head.innerHTML = '<style>html,body{margin:0;background:transparent}#host{display:inline-block;padding:16px;white-space:nowrap}math{margin:0}#baseline{display:inline-block;width:0;height:0;vertical-align:baseline}</style>';
          if (base64) {
            const font = new FontFace('ExternalFont', `url(data:font/otf;base64,${base64})`);
            await font.load(); document.fonts.add(font);
          }
          const host = document.createElement('div'); host.id = 'host';
          host.style.font = `${size}px ${base64 ? 'ExternalFont' : '"STIX Two Math"'}`;
          const math = copy(xml.documentElement);
          math.style.fontFamily = base64 ? 'ExternalFont' : '"STIX Two Math"';
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
          const rect = r => ({ left: r.left-box.left, right: r.right-box.left,
            top: r.top-origin.top, bottom: r.bottom-origin.top, width: r.width, height: r.height });
          const measured = {};
          for (const color of ['red', 'blue']) {
            const el = math.querySelector(`[mathbackground="${color}"]`);
            if (el) measured[color] = rect(el.getBoundingClientRect());
          }
          return { computedFont: getComputedStyle(math).fontFamily, fontLoaded: document.fonts.check(`${size}px ExternalFont`), width: box.width, ascent: origin.top-box.top, descent: box.bottom-origin.top,
            rectangles: measured, clip: { x: 0, y: 0, width: Math.ceil(host.getBoundingClientRect().width), height: Math.ceil(host.getBoundingClientRect().height) } };
        }, { sample, base64 });
        const image = `${engine}-${sample.id}.png`;
        if (geometry.clip.width > 4096 || geometry.clip.height > 4096) throw new Error('Reference exceeds raster budget');
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
