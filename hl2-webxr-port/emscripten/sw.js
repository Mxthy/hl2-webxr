const CACHE_NAME = 'hl2-xr-v1';

// Pre-Caching von Kerndateien für das HL2 WebXR-Erlebnis
const PRECACHE_ASSETS = [
  'index.html',
  'hl2_launcher.js',
  'hl2_launcher.wasm',
  'xr_wrapper.js',
  'pre.js',
  'post.js'
];

// Hilfsfunktion zur Injektion von COOP-, COEP- und CORP-Sicherheitsheadern.
// Diese sind zwingend erforderlich, damit der Browser SharedArrayBuffer erlaubt.
function withCoiHeaders(response) {
  if (!response) return response;
  
  // Neue Header definieren
  const newHeaders = new Headers(response.headers);
  newHeaders.set('Cross-Origin-Opener-Policy', 'same-origin');
  newHeaders.set('Cross-Origin-Embedder-Policy', 'require-corp');
  newHeaders.set('Cross-Origin-Resource-Policy', 'cross-origin');
  newHeaders.set('Access-Control-Allow-Origin', '*');

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: newHeaders
  });
}

// Service Worker Installation
self.addEventListener('install', (event) => {
  console.log('[Service Worker] Installiere und cache Core-Assets...');
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(PRECACHE_ASSETS))
      .then(() => self.skipWaiting())
  );
});

// Service Worker Aktivierung
self.addEventListener('activate', (event) => {
  console.log('[Service Worker] Aktiviert. Lösche alte Caches...');
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cache) => {
          if (cache !== CACHE_NAME) {
            console.log('[Service Worker] Lösche alten Cache:', cache);
            return caches.delete(cache);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

// Fetch-Event-Handler zur Header-Injektion und Caching-Strategie
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Fall 1: Große Asset-Chunks (*.data) werden NICHT gecacht (zu groß für Cache API),
  // aber erhalten zwingend die COI-Header und unterstützen ggf. Range-Requests.
  if (url.pathname.includes('/chunks/') && url.pathname.endsWith('.data')) {
    event.respondWith(
      fetch(event.request)
        .then((response) => withCoiHeaders(response))
        .catch((err) => {
          console.error('[Service Worker] Fehler beim Fetchen von Chunk-Daten:', err);
          return new Response('Fehler beim Laden der Chunk-Daten', { status: 500 });
        })
    );
    return;
  }

  // Fall 2: Manifest-Dateien der Chunks: Fetch, Caching und COI-Header
  if (url.pathname.includes('/chunks/') && url.pathname.endsWith('manifest.json')) {
    event.respondWith(
      caches.match(event.request).then((cachedResponse) => {
        if (cachedResponse) {
          return withCoiHeaders(cachedResponse);
        }
        return fetch(event.request).then((networkResponse) => {
          return caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, networkResponse.clone());
            return withCoiHeaders(networkResponse);
          });
        });
      })
    );
    return;
  }

  // Fall 3: Alle anderen Anfragen (Index, JS, WASM, CSS, etc.) -> Cache-First mit Network-Fallback + COI-Header
  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      if (cachedResponse) {
        return withCoiHeaders(cachedResponse);
      }
      return fetch(event.request)
        .then((networkResponse) => {
          // Nur erfolgreiche GET-Anfragen cachen
          if (networkResponse.ok && event.request.method === 'GET') {
            const responseToCache = networkResponse.clone();
            caches.open(CACHE_NAME).then((cache) => {
              cache.put(event.request, responseToCache);
            });
          }
          return withCoiHeaders(networkResponse);
        })
        .catch((error) => {
          console.error('[Service Worker] Netzwerkfehler bei:', event.request.url, error);
          // Fallback für HTML-Seiten im Offline-Modus
          if (event.request.headers.get('accept').includes('text/html')) {
            return caches.match('index.html').then((r) => withCoiHeaders(r));
          }
        });
    })
  );
});
