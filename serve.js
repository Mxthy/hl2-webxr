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
  if (urlPath === '/') urlPath = '/hl2_launcher.html'

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
  console.log(`   URL:  http://localhost:${PORT}/hl2_launcher.html`)
  console.log(`   Root: ${ROOT}`)
  console.log(`   COOP/COEP: ✓ (SharedArrayBuffer enabled)`)
  console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`)
  console.log(`\n  Ctrl+C zum Beenden\n`)
})
