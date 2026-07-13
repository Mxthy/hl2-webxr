# Deployment-Prozess (HL2 WebXR)

Dieses Dokument beschreibt die automatisierte CI/CD-Pipeline in GitHub Actions sowie die Deployment-Schritte für den lokalen Test und das Hosting.

## 1. GitHub Actions Pipeline (.github/workflows/build.yml)

Die Pipeline automatisiert den gesamten Kompilierungs- und Paketierungsprozess.

### Workflow-Definition:
- **Trigger:** Push auf `main` oder manuelle Auslösung (`workflow_dispatch`).
- **Secrets:**
  - `ASSETS_ARCHIVE_URL`: URL zum HL2 Retail Build 2153 Archiv auf Archive.org.
  - `GITHUB_TOKEN`: Automatischer GitHub-Token für Datei-Operationen und Paketierung.

### Schritte der CI-Pipeline:
1. **Checkout:** Repository inklusive aller Submodule klonen (`submodules: recursive`).
2. **Setup Emscripten:** Aktivieren der prebuilt `emsdk` Version `3.1.72` aus dem Cache/System, um LLVM-Compile-Zeiten einzusparen.
3. **Asset-Download & Extraktion:** Herunterladen der HL2 Assets über das Secret `ASSETS_ARCHIVE_URL` und Platzierung in der vorgesehenen Verzeichnisstruktur.
4. **Waf-Cache-Bereinigung:** Löschen des existierenden `build/` Verzeichnisses.
5. **Kompilierung:** Ausführen von `scripts/ci-build.sh`, welches das waf-Buildsystem konfiguriert, die Source-Engine sowie alle 25 Side-Modules baut.
6. **Chunk-Generierung:** Partitionierung der Assets in `background01.data`, `materials.data` und `models.data` mittels des emscripten-Dateipackers.
7. **Artefakte hochladen:**
   - `hl2-webxr-web-{run_id}`: Enthält die JS, WASM und Side-Module (`.so`).
   - `hl2-webxr-chunks-{run_id}`: Enthält die gepackten `.data` und `.js` Chunk-Dateien.

## 2. Lokales Hosting & Test-Server (serve.js)

Da SharedArrayBuffer für das Multithreading (`-sPTHREADS=1`) verwendet wird, müssen im Webbrowser zwingend COOP/COEP-Sicherheitsheader gesetzt werden. Ein gewöhnlicher HTTP-Server reicht nicht aus.

### Lokaler Server-Start:
Das Projekt beinhaltet ein Skript `serve.js`, welches die benötigten Header sendet:
- **Cross-Origin-Opener-Policy:** `same-origin`
- **Cross-Origin-Embedder-Policy:** `require-corp`

```bash
# 1. Abhängigkeiten installieren (falls nötig)
npm install

# 2. Server starten (Port 8080)
node serve.js 8080 /path/to/hl2-build
```

## 3. WebXR-Test mittels Cloudflare-Tunnel & Browserbase

Um WebXR-Anwendungen auf echten Headsets (wie der Meta Quest oder HoloLens 2) zu testen, wird eine sichere HTTPS-Verbindung benötigt. Dies lässt sich unkompliziert mit Cloudflare Tunnel realisieren:

```bash
# 1. Cloudflare Tunnel starten, um den lokalen Port 8080 freizugeben
cloudflared tunnel --url http://localhost:8080
```
Die generierte HTTPS-URL kann direkt im VR-Headset oder in virtuellen Browsern aufgerufen werden.

## 4. Rollback-Strategie

Sollte ein Build fehlerhaft sein, kann ein Rollback auf einen früheren stabilen Zustand über die GitHub-Artifact-IDs vorgenommen werden:
1. Identifiziere den letzten erfolgreichen GitHub Action Run (z.B. Build #39).
2. Lade die entsprechenden Artefakte (`hl2-webxr-web-{run_id}` und `hl2-webxr-chunks-{run_id}`) herunter.
3. Ersetze die Dateien auf dem Zielserver/Testverzeichnis mit diesen Versionen.
