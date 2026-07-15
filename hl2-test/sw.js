// sw.js — Service Worker: COOP/COEP-Header-Injection + Caching
const CACHE = 'hl2-xr-v4';

const PRECACHE = [
  './',
  'index.html',
  'hl2_launcher.js',
  'hl2_launcher.wasm',
  'xr_wrapper.js',
  'pre.js',
  'sw.js',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      await Promise.allSettled(PRECACHE.map((url) => cache.add(url)));
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const key of await caches.keys()) {
        if (key !== CACHE) await caches.delete(key);
      }
      await self.clients.claim();
    })(),
  );
});

function withCoiHeaders(resp) {
  if (!resp) return resp;
  const headers = new Headers(resp.headers);
  headers.set('Cross-Origin-Opener-Policy', 'same-origin');
  headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
  headers.set('Cross-Origin-Resource-Policy', 'cross-origin');
  return new Response(resp.body, {
    status: resp.status,
    statusText: resp.statusText,
    headers,
  });
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  const url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== self.location.origin) return;

  const path = url.pathname;

  // Chunks: fetch + COEP, kein Cache (zu groß)
  if (path.includes('/chunks/') && path.endsWith('.data')) {
    event.respondWith(
      fetch(req).then(withCoiHeaders).catch(() => new Response('offline', { status: 503 })),
    );
    return;
  }

  // Manifest: fetch + Cache + COEP
  if (path.endsWith('/chunks/manifest.json')) {
    event.respondWith(
      (async () => {
        try {
          const resp = await fetch(req);
          const cache = await caches.open(CACHE);
          cache.put(req, resp.clone());
          return withCoiHeaders(resp);
        } catch (e) {
          const cached = await caches.match(req);
          return withCoiHeaders(cached || new Response('{}', { headers: { 'content-type': 'application/json' } }));
        }
      })(),
    );
    return;
  }

  // Alle anderen: Cache-First + COEP
  event.respondWith(
    (async () => {
      const cached = await caches.match(req);
      if (cached) return withCoiHeaders(cached);
      try {
        const resp = await fetch(req);
        const cache = await caches.open(CACHE);
        if (resp.ok) cache.put(req, resp.clone());
        return withCoiHeaders(resp);
      } catch (e) {
        return new Response('offline', { status: 503 });
      }
    })(),
  );
});
