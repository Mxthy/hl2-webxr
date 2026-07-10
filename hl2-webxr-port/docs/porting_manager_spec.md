# Porting Manager Specification
## HL2 WebGL2/WebXR Porting Manager

Generated: 2026-07-10

---

## Zweck

Der Porting Manager ist ein Automatisierungs- und Koordinationswerkzeug, das den gesamten
Prozess von der Asset-Extraktion bis zum deployten WebGL2-Build orchestriert.

---

## Komponenten

### 1. Asset Pipeline Manager

**Eingabe:** GCF-Dateien (ARC-01) / VPK-Dateien (steam_legacy)
**Ausgabe:** `.data`-Dateien pro Map, Manifest-JSON

**Pipeline-Schritte:**
```
GCF/VPK Input
    → GCF-Extraktor (GCFExplorer oder CLI-Tool)
    → Asset-Verzeichnis (flache Struktur)
    → Engine Start (Logging-Modus)
    → Asset-Request-Log Parser
    → Per-Map Asset-Set Builder
    → Emscripten File-Packer (file_packager.py)
    → .data + .js Loader Files
    → CDN/Server Upload
```

**Konfiguration:**
- Map-Liste: konfigurierbar (Pilot: `d1_trainstation_01`)
- Logging-Modus: Engine-interne Print-Statements
- Output-Verzeichnis: konfigurierbar

### 2. Build System

**Eingabe:** nillerusr/source-engine Quellcode + Patches
**Ausgabe:** WASM-Binary + JS-Loader

**Build-Konfiguration (template):**
```makefile
EMCC_FLAGS = \
    -sMAX_WEBGL_VERSION=2 \
    -sMIN_WEBGL_VERSION=2 \
    -sALLOW_MEMORY_GROWTH=1 \
    -sINITIAL_MEMORY=268435456 \
    -sSTACK_SIZE=5242880 \
    -sFULL_ES2=1 \
    -sCASE_INSENSITIVE_FS=1 \
    -sFETCH_SUPPORT_INDEXEDDB=1 \
    -sUSE_SDL=2 \
    -sUSE_ZLIB=1 \
    -sASYNCIFY=1 \
    -sFILESYSTEM=1 \
    -sFORCE_FILESYSTEM=1 \
    -sGL_SUPPORT_AUTOMATIC_ENABLE_EXTENSIONS=1 \
    -sEXIT_RUNTIME=0
```

### 3. Patch Manager

**Zweck:** Verwaltet Engine-Patches für Browser-Kompatibilität

**Bekannte Patches (aus slqnt-Analyse):**
- Face Morphing Disable Patch (CONFIRMED)
- Lightmap Fix Patch (CONFIRMED)
- Flashlight Null-Texture Patch (CONFIRMED)
- Water Render Fix (CONFIRMED)
- NPC Stability Patch (CONFIRMED)
- Medkit/Battery Fix (CONFIRMED)
- Gravity Gun Inventory Fix (CONFIRMED)
- Crouch Rebind Patch (CONFIRMED)

**Format:** Git Patches (.patch-Dateien)

### 4. Manifest Generator

**Zweck:** Erzeugt Deployment-Manifeste pro Build

**Ausgabe-Felder:**
- Build-Timestamp
- Engine-Commit-Hash
- Asset-Checksums
- Map-Liste + .data-Größen
- Emscripten-Version
- Flag-Set

### 5. QA-Modul (Phase 1.6)

**Zweck:** Automatisiertes Durchlaufen der Maps im Headless-Browser

**Tools:** Playwright / Puppeteer (INFERRED)
**Checks:** Render-Output nicht schwarz, keine Crashes, Performance-Metriken

---

## Deployment-Architektur

```
Build Server (Linux)
    ├── Emscripten SDK
    ├── nillerusr/source-engine
    ├── Asset Pipeline
    └── Output:
        ├── hl2.wasm
        ├── hl2.js
        ├── maps/
        │   ├── d1_trainstation_01.data
        │   ├── d1_trainstation_01.js
        │   └── ... (alle Maps)
        └── manifest.json

CDN / Web Server
    ├── index.html (Shell)
    ├── hl2.wasm + hl2.js
    ├── maps/*.data
    └── Headers: COOP/COEP (für SharedArrayBuffer)
```

---

## HTTP-Header-Anforderungen

Für SharedArrayBuffer (Threading-Support):
```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

**Status:** INFERRED — nötig wenn SHARED_MEMORY aktiviert wird

---

## Interfaces

### CLI Interface (Phase 1)
```bash
# Asset Pipeline
./porting-manager assets extract --source ARC-01 --output ./assets
./porting-manager assets pack --map d1_trainstation_01 --log ./asset.log

# Build
./porting-manager build --config build.json --output ./dist

# Patch
./porting-manager patch apply --engine ./source-engine --patches ./patches/
```

### Web Dashboard (Phase 2, optional)
- Build-Status-Übersicht
- Asset-Inventar-Viewer
- Map-Completion-Matrix
- Performance-Metriken

---

## Abhängigkeiten

| Abhängigkeit | Version | Status |
|---|---|---|
| Emscripten SDK | Aktuell stabil | CONFIRMED verfügbar |
| Python 3 | 3.10+ | INFERRED (für Skripte) |
| Node.js | 18+ | INFERRED (für Tools) |
| GCFExplorer | Enthalten in ARC-01 | CONFIRMED |
| nillerusr/source-engine | Main branch | INFERRED |
| SDL2 (Emscripten port) | Via `-sUSE_SDL=2` | CONFIRMED |
