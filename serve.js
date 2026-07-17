#!/usr/bin/env node
// HL2 WebXR Local Test Server
// Startet einen HTTP-Server mit COOP/COEP-Headers für SharedArrayBuffer/Pthreads
// Usage: node serve.js [port] [dir]

const http = require('http')
const fs   = require('fs')
const path = require('path')

const PORT = parseInt(process.argv[2] || '8080')
const ROOT = path.resolve(process.argv[3] || '.')

const MIME = {
  '.html': 'text/html',
  '.js':   'application/javascript',
  '.wasm': 'application/wasm',
  '.so':   'application/wasm',
  '.data': 'application/octet-stream',
  '.css':  'text/css',
  '.png':  'image/png',
  '.ico':  'image/x-icon',
  '.txt':  'text/plain',
  '.json': 'application/json',
}

const server = http.createServer((req, res) => {
  // COOP/COEP — required for SharedArrayBuffer + Pthreads
  res.setHeader('Cross-Origin-Opener-Policy',   'same-origin')
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp')
  res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin')

  let urlPath = req.url.split('?')[0]
  console.log(`[REQ] ${urlPath}`)

  // TESTMODUS: Chunks durch Stub ersetzen für schnelles Testing
  const STUB_CHUNKS = process.env.STUB_CHUNKS === '1';
  if (STUB_CHUNKS && urlPath.startsWith('/chunks/') && urlPath.endsWith('.data')) {
    const mapName = urlPath.split('/').pop().replace('.data', '');
    const pathStr = `/hl2/maps/${mapName}.bsp`;
    const pathBuf = Buffer.from(pathStr, 'utf8');
    const dataBuf = Buffer.alloc(64);
    const header = Buffer.alloc(8);
    header.writeInt32LE(pathBuf.length, 0);
    header.writeInt32LE(dataBuf.length, 4);
    const stub = Buffer.concat([header, pathBuf, dataBuf]);
    res.writeHead(200, {
      'Content-Type': 'application/octet-stream',
      'Content-Length': stub.length,
      'Cache-Control': 'no-cache',
    });
    res.end(stub);
    console.log('[STUB] ' + urlPath + ' -> ' + stub.length + ' bytes');
    return;
  }

  if (urlPath === '/') urlPath = '/index.html'

  const filePath = path.join(ROOT, urlPath)

  // Security: stay inside ROOT
  if (!filePath.startsWith(ROOT)) {
    res.writeHead(403); res.end('Forbidden'); return
  }

  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) {
      res.writeHead(404, {'Content-Type': 'text/plain'})
      res.end(`404: ${urlPath}\n\nFiles in root:\n` +
        fs.readdirSync(ROOT).join('\n'))
      return
    }

    const ext  = path.extname(filePath).toLowerCase()
    const mime = MIME[ext] || 'application/octet-stream'

    res.writeHead(200, {
      'Content-Type':   mime,
      'Content-Length': stat.size,
      'Cache-Control':  'no-cache',
    })

    fs.createReadStream(filePath).pipe(res)
  })
})

server.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🎮 HL2 WebXR Test Server`)
  console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`)
  console.log(`   URL:  http://localhost:${PORT}/`)
  console.log(`   Root: ${ROOT}`)
  console.log(`   COOP/COEP: ✓ (SharedArrayBuffer enabled)`)
  console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`)
  console.log(`\n  Ctrl+C zum Beenden\n`)
})
