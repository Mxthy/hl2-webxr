export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const key = url.pathname.replace(/^\//, '');
    
    if (!key) {
      return new Response('R2 Proxy for hl2-webxr-assets', { status: 200 });
    }
    
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
          'Access-Control-Allow-Headers': 'Range',
          'Access-Control-Max-Age': '86400',
        }
      });
    }
    
    // Handle range requests for large file downloads
    const range = request.headers.get('Range');
    const options = {};
    if (range) {
      const m = range.match(/bytes=(\d+)-(\d*)/);
      if (m) {
        const offset = parseInt(m[1]);
        const length = m[2] ? parseInt(m[2]) - offset + 1 : undefined;
        options.range = { offset, length };
      }
    }
    
    const object = await env.ASSETS_BUCKET.get(key, options);
    
    if (object === null) {
      return new Response('Not Found: ' + key, { status: 404 });
    }
    
    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set('Access-Control-Allow-Origin', '*');
    headers.set('Cross-Origin-Resource-Policy', 'cross-origin');
    headers.set('Cache-Control', 'public, max-age=31536000, immutable');
    headers.set('Accept-Ranges', 'bytes');
    
    // Return 206 for range requests
    if (range) {
      const totalSize = object.size; // R2 returns partial body for range
      const start = options.range ? options.range.offset : 0;
      headers.set('Content-Range', `bytes ${start}-${start + object.size - 1}/*`);
      return new Response(object.body, { status: 206, headers });
    }
    
    return new Response(object.body, { headers });
  }
};
