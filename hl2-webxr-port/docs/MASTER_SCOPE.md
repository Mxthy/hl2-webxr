# HL2 WebXR — Master Scope & Project Plan
**Stand:** 2026-07-16  
**Repository:** https://github.com/Mxthy/hl2-webxr

---

## 1. PROJEKT-SCOPE

### Endziel
Half-Life 2 läuft im Browser (WebGL2) und auf Meta Quest 3 (WebXR), kompiliert aus der Source Engine via Emscripten. Die Engine wird aus dem weliveinhell/source-engine Fork gebaut, Assets aus dem HL2 Retail 2153 Archiv (Archive.org).

### Phasen
- **Phase 1 — 2D Browser Rendering** (FOUNDATION): HL2 rendert in einem Desktop-Browser, analog zu slqnt.dev und yikes.pw/portal
- **Phase 2 — WebXR / Quest 3**: Stereo Rendering via WebXR API, VR-Input, Quest 3 Optimierung
- **Phase 3 — Polish**: Multi-Map-Streaming, Save States, Performance-Tuning

---

## 2. AKTUELLER STATUS (2026-07-16)

### ✅ Was funktioniert
| Komponente | Status | Details |
|---|---|---|
| CI Build Pipeline | ✅ Stabil | Build #71, GitHub Actions, emsdk 3.1.72, waf + emcc |
| Engine Kompilierung | ✅ Done | WASM 3.8MB + 25 .so Side-Modules |
| Vtable Fix (_ZTV11IVP_Mindist) | ✅ Gelöst | Out-of-line destructor + -O0, auto-export via MAIN_MODULE=1 |
| GL Stubs (187 Funktionen) | ✅ Done | dlsym intercept + __glStubs table mit WASM signatures |
| GL Version Spoof | ✅ Done | glGetString → "3.3.0 (WebGL 2.0 ...)" |
| Asset Pipeline | ✅ Done | R2 upload: shaders.data(22MB) + background01/1(804MB) + materials(981MB) + models(1329MB) + shader-manifest |
| R2 Proxy Worker | ✅ Done | https://hl2-assets-proxy.hl2-webxr.workers.dev, CORS + COOP/COEP |
| Cloudflare Pages | ✅ Done | https://hl2-webxr.pages.dev, COOP/COEP headers, SharedArrayBuffer works |
| Bootstrap VTFs | ✅ Done | 4 kritische VTFs (identitylightwarp, flashlight_border, etc.) in chunks |
| Engine Init | ✅ Teilweise | callMain() returns 0, alle 25 .so laden, GL Context erstellt (720x450) |

### ⚠️ In Progress / Unconfirmed
| Komponente | Status | Details |
|---|---|---|
| Chunk Loading im Browser | ⚠️ Unconfirmed | R2 proxy URL gepatched, aber noch nicht im Browser verifiziert |
| Game Mode | ⚠️ Mismatch | CI pre.js: `-game portal`, source post.js: `-game hl2` — muss vereinheitlicht werden |
| Canvas Rendering | ⚠️ Nicht sichtbar | Engine startet aber Canvas zeigt nur "Preparing..." |
| MOD Write Path | ⚠️ Cosmetic | "Requested non-existent write path MOD!" — IDBFS mount |

### ❌ Nicht begonnen
| Komponente | Status | Details |
|---|---|---|
| 2D Rendering Loop | ❌ | Engine läuft aber rendert nicht sichtbar |
| WebXR Session | ❌ | Nur Architektur in xr_wrapper.js definiert |
| VR Input (Controller) | ❌ | SAB Layout definiert aber nicht implementiert |
| Quest 3 Optimierung | ❌ | PTHREAD_POOL_SIZE, OVR_multiview2, etc. |

---

## 3. WO WIR UNS IM KREIS GEDREHT HABEN

1. **Bug-für-Bug Fixing** statt holistischer Betrachtung — jeder Fix (vtable → GL stubs → chunk loading → R2 upload) offenbarte das nächste Problem, aber wir zoomten nie aus
2. **2D vs WebXR Vermischung** — wir haben WebXR-Architektur (xr_wrapper.js, SAB Layout) definiert bevor die Basis-Engine überhaupt rendert
3. **Game Mode Verwirrung** — CI inlined weliveinhell's pre.js mit `-game portal`, aber unsere post.js sagt `-game hl2`. Nie konsolidiert.
4. **Chunk URL Patching** — wir patchten die URL im deployten hl2_launcher.js manuell statt im CI-Build zu fixen. Jeder neuer Build überschreibt den Patch.
5. **Deployment-Cycling** — wir deployen manuell, testen mit Browserbase, finden einen Bug, pushen einen Fix, warten auf CI, deployen wieder, etc.

---

## 4. REFERENZPROJEKTE & ERKENNTNISSE

### slqnt.dev (https://hl2.slqnt.dev) — Closed Source, Live Demo
- **Was wir gelernt haben:** dynamicLibraries=[], OPFS für Chunk-Caching, Binary-Packing Format `[pathLen][dataLen][path][blob]`, Service Worker für COOP/COEP, Module.__gameChoice Promise-Pattern
- **Status:** Voll funktionsfähiger 2D Browser-Port, lädt Maps on-demand, nutzt IDBFS für Persistenz
- **Relevanz für uns:** Goldstandard für Phase 1

### weliveinhell/source-engine — Unsere Engine-Basis (67 Stars)
- **Was wir gelernt haben:** ToGLES Build-Modus, waf build system, emscripten/build.sh, repackage.js Asset-Packing, libwebgl.patch für glMapBufferRange
- **Demo:** yikes.pw/portal (live, beweist dass der Browser-Port funktioniert)
- **Relevanz:** Direkt unser Code-Fork — CI nutzt diesen Repo

### nillerusr/source-engine — Original Fork (2171 Stars)
- **Relevanz:** Referenz für Build-Prozess, aber wir nutzen weliveinhell (bessere Emscripten-Integration)

### vittoriorameo/HL2VRU — VR Mod (189 Stars)
- **Relevanz:** Phase 2 Referenz — VR-spezifische Source Engine Modifikationen, aber native (non-Web)

---

## 5. PHASE 1 PLAN — 2D BROWSER RENDERING

**Ziel:** HL2 rendert sichtbar in einem Desktop-Browser (wie slqnt.dev / yikes.pw)

### Step 1.1: CI-Build Fix — Game Mode & Chunk URL (1-2 Builds)
**Problem:** CI inlined weliveinhell's pre.js mit `-game portal`. Unsere post.js sagt `-game hl2`. Chunk URL wird manuell gepatcht, bei jedem Build überschrieben.
**Lösung:**
- pre.js im Repo: `-game portal` beibehalten (weliveinhell verwendet portal, nicht hl2)
- post.js: Argumente entfernen (werden von pre.js gesetzt)
- Chunk URL: `const ASSET_BASE = "https://hl2-assets-proxy.hl2-webxr.workers.dev/chunks/"` in pre.js
- DataLoader: `xhr.open("GET", ASSET_BASE + mapName + ".data", true)`
**Dateien:** `hl2-webxr-port/emscripten/pre.js`, `hl2-webxr-port/emscripten/post.js`
**CI-Änderung:** ci-build.sh — pre.js patchen um ASSET_BASE Variable einzufügen

### Step 1.2: Browser-Verifikation — Chunk Loading (1 Test-Cycle)
**Ziel:** In Browserbase: Konsole zeigt "shaders.data loaded", "Shader preflight OK", "All chunks loaded"
**Test:** Navigate to hl2-webxr.pages.dev, warte 5min (804MB download), screenshot
**Erfolg:** Console logs zeigen alle 3 chunks geladen (shaders, background1, materials)

### Step 1.3: Canvas Rendering Fix (1-2 Builds)
**Problem:** Engine startet (callMain=0) aber Canvas ist leer/schwarz
**Mögliche Ursachen:**
  - Canvas Größe nicht gesetzt (0x0)
  - Module.canvas nicht korrekt zugewiesen
  - Engine-Render-Loop nicht gestartet
  - D3D→WebGL Translation Problem
**Lösungsansatz:**
  - `Module.canvas` explizit setzen in pre.js (nicht post.js)
  - Canvas Größe in HTML fixieren (width/height attributes)
  - Browserbase console: nach "CreateDevice", "SwapBuffers", "glDraw" logs suchen
  - gles2 SDL2 nutzt canvas — sicherstellen dass SDL2 den Canvas korrekt referenziert

### Step 1.4: Map Rendering Verifikation (1 Test-Cycle)
**Ziel:** Hintergrund-Map (background1) wird gerendert, nicht nur schwarzer Bildschirm
**Test:** Screenshot nach 5min Loading
**Erfolg:** Portal/Half-Life 2 Hintergrund sichtbar (nicht nur "Preparing...")

---

## 6. PHASE 2 PLAN — WEBXR / QUEST 3 (nach Phase 1)

### Step 2.1: WebXR Session Setup
- XRSession request (immersive-vr)
- WebGL context für XR (XRWebGLLayer)
- Enter VR Button in UI

### Step 2.2: Stereo Rendering
- OVR_multiview2 für Single-Pass Stereo
- View/Projection Matrices aus XRFrame
- SAB Bridge: Main-Thread (XR poses) → Worker (Engine rendering)

### Step 2.3: VR Input
- Controller Pose-Daten via SAB
- Source Engine Input Mapping (movement, use, weapon)
- HMD Pose → Engine Camera

### Step 2.4: Quest 3 Optimierung
- PTHREAD_POOL_SIZE=4 (RAM-Limit)
- INITIAL_MEMORY=2GB, MAXIMUM_MEMORY=3GB
- -msimd128 für Physik-Performance
- Texture streaming / LOD bias

---

## 7. INFRASTRUKTUR ÜBERSICHT

```
┌─────────────────────────────────────────────────┐
│  GitHub Actions CI (Mxthy/hl2-webxr)             │
│  ├── emsdk 3.1.72 (prebuilt)                     │
│  ├── weliveinhell/source-engine (ToGLES)         │
│  ├── waf build + emcc link                       │
│  ├── repackage.js (asset chunking)               │
│  ├── GL version spoof patch                      │
│  ├── Bootstrap VTFs                               │
│  └── R2 upload (chunks/*.data)                   │
├─────────────────────────────────────────────────┤
│  Cloudflare R2 (hl2-webxr-assets)                │
│  ├── chunks/shaders.data (22MB)                  │
│  ├── chunks/background01.data (804MB)            │
│  ├── chunks/background1.data (804MB)             │
│  ├── chunks/materials.data (981MB)               │
│  ├── chunks/models.data (1329MB)                 │
│  └── chunks/shader-manifest.json                 │
├─────────────────────────────────────────────────┤
│  Cloudflare Worker (hl2-assets-proxy)            │
│  └── R2 → Public URL with CORS                   │
├─────────────────────────────────────────────────┤
│  Cloudflare Pages (hl2-webxr.pages.dev)          │
│  ├── hl2_launcher.html/js/wasm                   │
│  ├── 25 .so Side-Modules                          │
│  ├── _headers (COOP/COEP)                         │
│  └── DataLoader → R2 Worker → R2 chunks          │
└─────────────────────────────────────────────────┘
```

---

## 8. WORKFLOW — Wie wir weiter vorgehen

### Iterations-Zyklus
1. **CI-Build-Änderung** → Commit & Push zu GitHub (Mxthy/hl2-webxr)
2. **CI läuft** (~25 min) → Download Web-Artifact
3. **Deploy** → `wrangler pages deploy` (web artifact) + verify R2 chunks
4. **Test** → Browserbase: navigate, wait, screenshot, console
5. **Diagnose** → Console logs, errors, canvas state
6. **Fix** → Code-Änderung, zurück zu Step 1

### Anti-Circle Regeln
- **Keine manuellen Patches** im deployten hl2_launcher.js — immer im CI-Source fixen
- **Kein WebXR** bis Phase 1 (2D Rendering) vollständig funktioniert
- **Kein "vielleicht"** — erst Browser-Konsole lesen, dann entscheiden
- **Ein Problem pro Iteration** — nicht 5 Dinge gleichzeitig patchen
- **Commit-Message** dokumentiert was der Fix bewirken soll

---

## 9. OFFENE FRAGEN / ENTSCHEIDUNGEN

1. **-game portal vs -game hl2**: weliveinhell nutzt "portal" — das bedeutet Portal-Maps, nicht HL2-Maps. Ist das gewollt? (Portal ist im Half-Life 2 Universum, nutzt aber eigene Maps/Assets)
   - **Empfehlung:** `-game portal` beibehalten (entspricht weliveinhell's Setup und yikes.pw/portal)
   
2. **models.data (1.3GB)**: Wird aktuell NICHT vom DataLoader geladen — nur shaders, background1, materials. Models werden für NPC/Prop rendering benötigt, aber nicht für Background-Map.
   - **Empfehlung:** In Phase 1 weglassen, in Phase 3 als on-demand Stream hinzufügen

3. **background01 vs background1**: Zwei fast identische 804MB chunks. background01 ist das Start-Hintergrundbild, background1 ist die erste Map.
   - **Empfehlung:** Prüfen ob beide benötigt werden oder einer ausreicht

4. **OPFS vs XHR Chunk Loading**: slqnt nutzt OPFS für Caching, wir nutzen XHR direkt. OPFS würde wiederholte Besuche beschleunigen.
   - **Empfehlung:** Phase 3 — in Phase 1 XHR direkt nutzen

---

## 10. KEY FILES

| Datei | Zweck | Status |
|---|---|---|
| `hl2-webxr-port/scripts/ci-build.sh` | CI Build Pipeline | ✅ Stabil (Build #71) |
| `hl2-webxr-port/emscripten/pre.js` | DataLoader, GL stubs, SAB Layout, game args | ⚠️ Braucht ASSET_BASE fix |
| `hl2-webxr-port/emscripten/post.js` | Module.canvas, dynamicLibraries, engine args | ⚠️ Redundant mit pre.js |
| `hl2-webxr-port/emscripten/xr_wrapper.js` | WebXR Session, SAB Bridge | Phase 2 |
| `hl2-webxr-port/emscripten/sw.js` | Service Worker (COOP/COEP) | ✅ Defined |
| `hl2-webxr-port/emscripten/index.html` | Haupt-HTML | ⚠️ Braucht Canvas Fix |
| `.github/workflows/build.yml` | GitHub Actions Workflow | ✅ Stabil |
| `scripts/upload_chunks_r2.py` | R2 Upload Script | ✅ Works |
