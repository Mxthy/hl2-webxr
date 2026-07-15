#!/usr/bin/env node
// Static file server with COOP/COEP + Range-Request support
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = parseInt(process.argv[2]) || 8080;
const ROOT = process.argv[3] || '.';

const MIME = {
  '.html': 'text/html',
  '.js':   'application/javascript',
  '.wasm': 'application/wasm',
  '.data': 'application/octet-stream',
  '.so':   'application/octet-stream',
  '.svg':  'image/svg+xml',
  '.css':  'text/css',
  '.json': 'application/json',
};

const COOP_HEADERS = {
  'Cross-Origin-Opener-Policy':   'same-origin',
  'Cross-Origin-Embedder-Policy': 'require-corp',
  'Cross-Origin-Resource-Policy': 'cross-origin',
};

const server = http.createServer((req, res) => {
  Object.entries(COOP_HEADERS).forEach(([k,v]) => res.setHeader(k, v));

  let filePath = path.join(ROOT, req.url.split('?')[0]);
  if (req.url === '/' || req.url === '') filePath = path.join(ROOT, 'hl2_launcher.html');

  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) {
      res.writeHead(404); res.end('Not found: ' + req.url); return;
    }

    const ext = path.extname(filePath).toLowerCase();
    const mime = MIME[ext] || 'application/octet-stream';
    const total = stat.size;

    // Handle Range requests (needed for large .data files over Cloudflare)
    const rangeHeader = req.headers['range'];
    if (rangeHeader) {
      const match = rangeHeader.match(/bytes=(\d+)-(\d*)/);
      if (match) {
        const start = parseInt(match[1], 10);
        const end   = match[2] ? parseInt(match[2], 10) : total - 1;
        if (start >= total || end >= total || start > end) {
          res.writeHead(416, { 'Content-Range': `bytes */${total}` });
          res.end(); return;
        }
        const chunkSize = end - start + 1;
        res.writeHead(206, {
          'Content-Type':   mime,
          'Content-Range':  `bytes ${start}-${end}/${total}`,
          'Content-Length': chunkSize,
          'Accept-Ranges':  'bytes',
        });
        fs.createReadStream(filePath, { start, end }).pipe(res);
        return;
      }
    }

    res.writeHead(200, {
      'Content-Type':   mime,
      'Content-Length': total,
      'Accept-Ranges':  'bytes',
    });
    fs.createReadStream(filePath).pipe(res);
  });
});

server.listen(PORT, () => {
  console.log(`Serving ${ROOT} on http://localhost:${PORT}`);
  console.log('COOP/COEP headers: enabled (SharedArrayBuffer support)');
  console.log('Range requests: enabled (large .data file support)');
});
