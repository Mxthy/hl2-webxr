# HL2 WebXR — Lokaler Test-Server

## Schritt 1: Artifacts runterladen

Von GitHub Actions Run #26:
- **Web-Bundle** (42.5 MB): https://github.com/Mxthy/hl2-webxr/actions/runs/29152707526/artifacts/8248771013
- **Asset-Chunks** (13.2 MB): https://github.com/Mxthy/hl2-webxr/actions/runs/29152707526/artifacts/8248771190

## Schritt 2: Entpacken in einen Ordner

```
mkdir hl2-test && cd hl2-test

# Web-Bundle entpacken (enthält: hl2_launcher.html/js/wasm + *.so)
unzip hl2-webxr-web-*.zip

# Chunks entpacken (enthält: background01.data)
# chunks/ Ordner muss NEBEN hl2_launcher.html liegen
unzip hl2-webxr-chunks-*.zip
```

Ergebnis-Struktur:
```
hl2-test/
  hl2_launcher.html
  hl2_launcher.js
  hl2_launcher.wasm
  lib*.so  (25 Dateien)
  chunks/
    background01.data
```

## Schritt 3: Server starten

**Option A — Node.js (empfohlen, im Repo enthalten):**
```bash
node serve.js 8080 /pfad/zu/hl2-test
```

**Option B — Python:**
```bash
# Python hat kein COOP/COEP eingebaut — dieses Skript hier nutzen:
python3 -c "
import http.server, socketserver

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        super().end_headers()

with socketserver.TCPServer(('', 8080), Handler) as httpd:
    print('Server: http://localhost:8080/hl2_launcher.html')
    httpd.serve_forever()
" 
```

**Option C — npx (kein Install nötig):**
```bash
npx --yes serve -p 8080 \
  --config '{"headers":[{"source":"**","headers":[{"key":"Cross-Origin-Opener-Policy","value":"same-origin"},{"key":"Cross-Origin-Embedder-Policy","value":"require-corp"}]}]}'
```

## Schritt 4: Browser öffnen

```
http://localhost:8080/hl2_launcher.html
```

### Wichtig: Browser-Anforderungen
- **Chrome/Chromium 113+** oder **Firefox 119+**
- SharedArrayBuffer muss aktiviert sein (wird durch COOP/COEP freigeschaltet)
- WebGL2 muss verfügbar sein (`chrome://gpu` → "WebGL2: Hardware accelerated")
- Für WebXR (später): Chrome mit VR-Headset oder `--enable-features=WebXR`

## Was du sehen solltest

1. Schwarzer Bildschirm → Engine lädt
2. HL2-Hauptmenü oder Fehlermeldung in der Browser-Konsole (F12)
3. Bei Fehler: Konsolen-Output hierhin kopieren

## Bekannte erste Fehler (normal)

- `filesystem_stdio: ...` → Asset-Pfade noch nicht korrekt gemappt
- `Steam: ... not found` → Normal, Steam-Backend ist im WASM-Port gepatcht
- `GL_ERROR` → WebGL2-Kontext-Problem, GPU-Flags prüfen
