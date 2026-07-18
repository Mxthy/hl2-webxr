const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, 'hl2-test');
const PORT = 8087;

const MIME = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.wasm': 'application/wasm',
  '.data': 'application/octet-stream',
  '.so': 'application/octet-stream',
  '.json': 'application/json',
  '.css': 'text/css',
  '.png': 'image/png',
  '.vtf': 'application/octet-stream',
};

const server = http.createServer((req, res) => {
  let urlPath = req.url.split('?')[0];
  if (urlPath === '/') urlPath = '/index.html';

  // COOP/COEP headers for SharedArrayBuffer
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');

  const filePath = path.join(ROOT, urlPath);

  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      console.error(`[404] ${urlPath}`);
      res.writeHead(404);
      res.end('Not found');
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    const mime = MIME[ext] || 'application/octet-stream';
    res.writeHead(200, {
      'Content-Type': mime,
      'Content-Length': stats.size,
      'Access-Control-Allow-Origin': '*',
    });

    // For large files, pipe instead of readFileSync
    if (stats.size > 10 * 1024 * 1024) {
      console.log(`[200] ${urlPath} (${(stats.size / 1024 / 1024).toFixed(1)} MB) - streaming`);
      fs.createReadStream(filePath).pipe(res);
    } else {
      fs.readFile(filePath, (err, data) => {
        if (err) {
          res.writeHead(500);
          res.end('Internal error');
          return;
        }
        console.log(`[200] ${urlPath} (${stats.size} bytes)`);
        res.end(data);
      });
    }
  });
});

server.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT} (COOP/COEP enabled)`);
  console.log(`Serving from: ${ROOT}`);
});
