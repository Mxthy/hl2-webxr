# Architecture
## HL2 WebGL2/WebXR Porting Manager — Technische Architektur

Generated: 2026-07-10

---

## Gesamt-Stack (Phase 1)

```
┌─────────────────────────────────────────────────────────┐
│                    Browser (Chrome/Firefox/Edge)        │
├─────────────────────────────────────────────────────────┤
│  WebGL2 API                │  IndexedDB (IDBFS)         │
│  Web Audio API             │  Fetch API (.data files)   │
│  Pointer Lock API          │  Gamepad API (optional)    │
├─────────────────────────────────────────────────────────┤
│              Emscripten Runtime (JS + WASM)             │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐ │
│  │ WASM Binary  │  │ JS Glue Code │  │ .data Assets  │ │
│  │ (hl2.wasm)   │  │ (hl2.js)     │  │ (per Map)     │ │
│  └──────────────┘  └──────────────┘  └───────────────┘ │
├─────────────────────────────────────────────────────────┤
│        Source Engine (nillerusr fork, ToGLES mode)      │
│  ┌────────────┐  ┌────────────┐  ┌──────────────────┐  │
│  │ Render     │  │ Game Logic │  │ Asset System     │  │
│  │ (ToGLES)   │  │ (C++)      │  │ (VPK/GCF reader) │  │
│  └────────────┘  └────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## Rendering-Datenpfad

```
Source Engine → ToGLES Mode
    → GLES API Calls
        → Emscripten GL Translation Layer
            → WebGL2 Context
                → Browser GPU
```

**Status:** CONFIRMED (aus slqnt-Blog + Emscripten-Doku)

---

## Asset-Loading-Datenpfad (Runtime)

```
Browser Fetch API
    → CDN / Web Server
        → Map-spezifische .data Datei
            → Emscripten MEMFS (In-Memory)
                → Source Engine Asset-System
                    → Geladene Map + Assets
```

**Status:** CONFIRMED (aus slqnt-Blog)

---

## Asset-Pipeline (Build-Zeit)

```
ARC-01 (GCF)
    → GCFExplorer Extraktion
        → Flache Asset-Verzeichnisstruktur
            → Engine (Logging-Modus)
                → Asset-Request-Log
                    → Log-Parser-Skript
                        → Asset-Set pro Map
                            → file_packager.py (Emscripten)
                                → map_name.data + map_name.js
                                    → CDN Upload
```

**Status:** CONFIRMED Methode (slqnt), INFERRED Toolchain-Details

---

## Save-State-Architektur

```
Source Engine save/load calls
    → Emscripten Filesystem API
        → IDBFS (IndexedDB)
            → Browser IndexedDB Storage
                (persistent, survives page reload)

Sync: FS.syncfs(false, callback) — Write to IDB
      FS.syncfs(true, callback)  — Read from IDB
```

**Status:** CONFIRMED (slqnt + Emscripten-Doku)

---

## Build-System-Architektur

```
nillerusr/source-engine (C++ Quellcode)
    + Patches (PATCH-001 bis PATCH-008)
        → emcc (Emscripten C++ Compiler)
            + Flags (aus pipeline.yaml)
                → hl2.wasm (WASM Binary)
                + hl2.js  (JS Glue + Runtime)
                    → dist/ (Deployment-Paket)
```

---

## Deployment-Architektur

```
Web Server / CDN
├── index.html          (Shell-HTML, COOP/COEP Headers)
├── hl2.wasm            (Engine-Binary, ~50-200MB INFERRED)
├── hl2.js              (JS Glue, ~1-5MB INFERRED)
└── maps/
    ├── d1_trainstation_01.data   (~50-150MB INFERRED)
    ├── d1_trainstation_01.js     (Loader)
    └── ... (alle anderen Maps)
```

**Wichtig:** COOP/COEP HTTP-Headers auf Server setzen:
```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```
(Pflicht wenn SharedArrayBuffer/Pthreads, optional sonst)

---

## Phase-3-Erweiterung (WebXR — NICHT Phase 1)

```
WebXR Device API
    → XRSession (immersive-vr)
        → XRFrame
            → XRView (Left/Right Eye)
                → WebGL2 Layer
                    + XRInputSource (Controller)
                        → Interaction Logic
                            (Basis: HL2VRU Patterns)
```

**Status:** GEPLANT — nach stabiler WebGL2-Basis
