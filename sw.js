// Service worker de "Mi material": deja la app y sus librerías guardadas para poder
// abrirla sin conexión (por ejemplo, en un almacén sin cobertura).
const C = 'mi-material-v7';
const SHELL = ['./', 'index.html', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png'];
const CDN = [
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js',
  'https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.js',
  'https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.js',
  'https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js'
];

self.addEventListener('install', e => {
  e.waitUntil((async () => {
    const c = await caches.open(C);
    try { await c.addAll(SHELL); } catch (err) {}
    // Las librerías externas se guardan sin leer su contenido (no-cors), una a una
    await Promise.all(CDN.map(u => fetch(new Request(u, {mode: 'no-cors'})).then(r => c.put(u, r)).catch(() => {})));
  })());
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== C).map(k => caches.delete(k)))));
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const u = new URL(e.request.url);
  // Librerías y tipografías: primero lo guardado, y si no está, de internet
  if (u.hostname === 'cdn.jsdelivr.net' || u.hostname === 'fonts.googleapis.com' || u.hostname === 'fonts.gstatic.com'){
    e.respondWith(caches.match(e.request).then(hit => hit || fetch(e.request).then(r => {
      const cp = r.clone(); caches.open(C).then(c => c.put(e.request, cp)); return r;
    })));
    return;
  }
  if (u.origin !== location.origin) return;   // los datos de Supabase nunca se guardan aquí
  // La app: primero internet (para recibir las actualizaciones) y, sin conexión, lo guardado
  e.respondWith(
    fetch(e.request).then(r => { const cp = r.clone(); caches.open(C).then(c => c.put(e.request, cp)); return r; })
      .catch(() => caches.match(e.request).then(r => r || caches.match('index.html')))
  );
});
