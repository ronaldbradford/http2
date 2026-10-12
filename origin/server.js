// HTTPS origin supporting ALPN h2 + http/1.1 (no npm deps).
// Serves a test page that loads N_JS scripts, N_IMG images and N_API fetch() calls,
// each with an artificial server delay between DELAY_MIN..DELAY_MAX ms.
const http2 = require('http2');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PORT = +process.env.PORT || 8443;
const N_JS = +process.env.N_JS || 50;
const N_IMG = +process.env.N_IMG || 60;
const N_API = +process.env.N_API || 60;
const DMIN = +process.env.DELAY_MIN || 100;
const DMAX = +process.env.DELAY_MAX || 400;
const certDir = path.join(__dirname, '..', 'certs');

// deterministic delay per path so every mode sees the same server latency
function delayFor(p) {
  const h = crypto.createHash('md5').update(p).digest().readUInt32BE(0);
  return DMIN + (h % (DMAX - DMIN + 1));
}

function page() {
  const js = [], img = [];
  for (let i = 0; i < N_JS; i++) js.push(`<script async src="/static/js/mod${i}.js"></script>`);
  for (let i = 0; i < N_IMG; i++) img.push(`<img width="32" height="32" src="/static/img/i${i}.svg">`);
  return `<!doctype html><html><head><meta charset="utf-8"><title>h2 downgrade demo</title>
<link rel="icon" href="data:,">
${js.join('\n')}
</head><body>
<h1>h2 downgrade demo</h1>
<p>${N_JS} scripts, ${N_IMG} images, ${N_API} fetch() calls; server delay ${DMIN}-${DMAX} ms each.</p>
<p id="status">loading…</p>
<div>${img.join('')}</div>
<script>
window.__jsLoaded = 0;
const imgsDone = Promise.all([...document.images].map(i => i.complete ? 1 :
  new Promise(r => { i.onload = i.onerror = r; })));
const apis = [];
for (let i = 0; i < ${N_API}; i++) apis.push(fetch('/api/item/' + i + '?t=' + Date.now()).then(r => r.json()));
const loaded = new Promise(r => addEventListener('load', r));
Promise.all([loaded, imgsDone, Promise.all(apis)]).then(() => {
  window.__doneMs = performance.now();
  const proto = performance.getEntriesByType('navigation')[0].nextHopProtocol;
  document.getElementById('status').textContent =
    'done in ' + Math.round(window.__doneMs) + ' ms, page protocol: ' + proto + ', scripts run: ' + window.__jsLoaded;
});
</script>
</body></html>`;
}

function svg(i) {
  const hue = (i * 37) % 360;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32" fill="hsl(${hue},70%,50%)"/><text x="4" y="21" font-size="12">${i}</text></svg>`;
}

function handler(req, res) {
  const url = new URL(req.url, 'https://x');
  const p = url.pathname;
  let body, type;
  if (p === '/' || p === '/index.html') { body = page(); type = 'text/html; charset=utf-8'; }
  else if (/^\/static\/js\/mod\d+\.js$/.test(p)) { body = `window.__jsLoaded++; /* ${p} ${'x'.repeat(2000)} */`; type = 'application/javascript'; }
  else if (/^\/static\/img\/i\d+\.svg$/.test(p)) { body = svg(+p.match(/\d+/)[0]); type = 'image/svg+xml'; }
  else if (/^\/api\/item\/\d+$/.test(p)) { body = JSON.stringify({ id: +p.split('/').pop(), proto: req.httpVersion }); type = 'application/json'; }
  else { res.writeHead(404); return res.end('not found'); }
  const d = p === '/' ? 0 : delayFor(p);
  setTimeout(() => {
    res.writeHead(200, { 'content-type': type, 'cache-control': 'no-store', 'x-server-delay-ms': String(d) });
    res.end(body);
  }, d);
}

const server = http2.createSecureServer({
  key: fs.readFileSync(path.join(certDir, 'origin.key')),
  cert: fs.readFileSync(path.join(certDir, 'origin.pem')),
  allowHTTP1: true,               // ALPN offers h2 and http/1.1
  settings: { maxConcurrentStreams: 256 },
}, handler);
server.on('secureConnection', s => { if (process.env.VERBOSE) console.log('TLS conn', s.remoteAddress, s.remotePort, 'alpn=', s.alpnProtocol); });
server.listen(PORT, () => console.log(`origin listening https://localhost:${PORT}/ (ALPN h2,http/1.1) N_JS=${N_JS} N_IMG=${N_IMG} N_API=${N_API} delay=${DMIN}-${DMAX}ms`));
