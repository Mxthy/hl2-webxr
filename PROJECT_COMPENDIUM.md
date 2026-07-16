# HL2 WebXR — Project Compendium (Machine-Readable)
**Version:** 1.0.0  
**Date:** 2026-07-16  
**Repository:** https://github.com/Mxthy/hl2-webxr  
**Deployment:** https://hl2-webxr.pages.dev  

---

## META

```yaml
project_name: "HL2 WebXR"
goal: "Port Half-Life 2 to WebGL2 (browser) and WebXR (Meta Quest 3) via Emscripten compilation of the Source Engine"
status: "Phase 1 — 2D Browser Rendering (in progress)"
last_stable_build: 71
current_build: 82 (in_progress, commit d80d8af9)
engine_fork: "weliveinhell/source-engine"
emsdk_version: "3.1.72 (pinned commit 2d480a1b7c7a34a354188d93f3e89190a44a1d21)"
asset_source: "HL2 Retail 2153 (Archive.org)"
ci_platform: "GitHub Actions"
hosting: "Cloudflare Pages + R2 + Workers"
language: "en/de mixed"
```

---

## 1. PROJECT SCOPE

### Endziel
Half-Life 2 läuft im Browser (WebGL2) und auf Meta Quest 3 (WebXR), kompiliert aus der Source Engine via Emscripten. Die Engine wird aus dem weliveinhell/source-engine Fork gebaut, Assets aus dem HL2 Retail 2153 Archiv (Archive.org).

### Phasen
| Phase | Ziel | Status |
|-------|------|--------|
| Phase 1 | 2D Browser Rendering (Desktop-Browser, analog slqnt.dev) | IN PROGRESS |
| Phase 2 | WebXR / Meta Quest 3 (Stereo Rendering, VR Input) | NOT STARTED |
| Phase 3 | Polish (Multi-Map-Streaming, Save States, Performance) | NOT STARTED |

---

## 2. CURRENT STATUS (2026-07-16)

### Working
| Component | Details |
|-----------|---------|
| CI Build Pipeline | GitHub Actions, emsdk 3.1.72, waf + emcc, ~25 min build time |
| Engine Compilation | WASM 3.8MB + 25 .so Side-Modules (dlopen-based) |
| Vtable Fix (_ZTV11IVP_Mindist) | Out-of-line destructor + -O0 compilation, auto-export via MAIN_MODULE=1 |
| GL Stubs (187 functions) | dlsym intercept + __glStubs table with WASM signatures |
| GL Version Spoof | glGetString returns "3.3.0 (WebGL 2.0 ...)" instead of "OpenGL ES 3.0" |
| Asset Pipeline | R2 upload: shaders.data(22MB) + background01/1(804MB x2) + materials(981MB) + models(1329MB) + shader-manifest |
| R2 Proxy Worker | https://hl2-assets-proxy.hl2-webxr.workers.dev, CORS + range requests |
| Cloudflare Pages | https://hl2-webxr.pages.dev, COOP/COEP headers, SharedArrayBuffer works |
| Bootstrap VTFs | 4 critical VTFs (identitylightwarp, flashlight_border, etc.) |
| Engine Init | callMain() returns 0, all 25 .so load, GL context created (720x450), IDirect3DDevice9::Create succeeds |

### In Progress / Unconfirmed
| Component | Details |
|-----------|---------|
| Chunk Loading in Browser | R2 proxy URL patched but not yet verified in browser |
| Game Mode Mismatch | CI pre.js: -game portal, source post.js: -game hl2 |
| Canvas Rendering | Engine starts but canvas shows only "Preparing..." |
| MOD Write Path | "Requested non-existent write path MOD!" — IDBFS mount issue |
| CI Cache Architecture | Fixed (source/waf cache separation) but build #82 still running |

### Not Started
| Component | Details |
|-----------|---------|
| 2D Rendering Loop | Engine runs but does not render visibly |
| WebXR Session | Only architecture defined in xr_wrapper.js |
| VR Input (Controller) | SAB layout defined but not implemented |
| Quest 3 Optimization | PTHREAD_POOL_SIZE, OVR_multiview2, etc. |
| OPFS Caching | slqnt uses OPFS, we use XHR (deferred to Phase 3) |
| Save States | IDBFS planned for Phase 1.5 |

---

## 3. ARCHITECTURE

### 3.1 Build Pipeline
```
GitHub Actions CI (Mxthy/hl2-webxr)
+-- emsdk 3.1.72 (prebuilt, pinned commit)
+-- weliveinhell/source-engine (ToGLES mode, waf build system)
+-- waf configure --togles --emscripten + waf build
+-- emcc link (MAIN_MODULE=1, PROXY_TO_PTHREAD, SharedMemory)
+-- repackage.js (asset chunking via Node.js)
+-- GL version spoof patch (gl_stubs_patch.py)
+-- Bootstrap VTFs generation (create_dummy_vtfs.py)
+-- R2 upload (chunks/*.data via boto3)
```

### 3.2 Runtime Architecture
```
Browser Main Thread
+-- hl2_launcher.html -> loads hl2_launcher.js
+-- hl2_launcher.js (Emscripten-generated, ~1.3MB)
|   +-- pre.js (globals, GL stubs, SAB constants, chunk URL, locateFile)
|   +-- WASM Main Module (hl2_launcher.wasm, 3.8MB)
|   +-- 25 .so Side-Modules (dlopen, dynamic loading)
|   +-- post.js (canvas setup, dynamicLibraries, engine args)
+-- SharedArrayBuffer (requires COOP/COEP)
+-- PThreads (PROXY_TO_PTHREAD, 4 workers)
+-- WebGL2 Canvas (720x450 initial)

Cloudflare R2 (hl2-webxr-assets bucket)
+-- chunks/shaders.data (22MB)
+-- chunks/background01.data (804MB)
+-- chunks/background1.data (804MB)
+-- chunks/materials.data (981MB)
+-- chunks/models.data (1329MB)
+-- chunks/shader-manifest.json

Cloudflare Worker (hl2-assets-proxy)
+-- R2 -> Public URL with CORS headers

Cloudflare Pages (hl2-webxr.pages.dev)
+-- hl2_launcher.html/js/wasm
+-- 25 .so files
+-- _headers (COOP/COEP)
+-- Service Worker (sw.js, COOP/COEP fallback)
```

### 3.3 Module Loading Order
Side-Modules load via dlopen in dependency order:
```
tier0.so -> vstdlib.so -> engine.so -> filesystem.so -> inputsystem.so ->
materialsystem.so -> datacache.so -> studiorender.so -> vphysics.so ->
video_services.so -> vguimatsurface.so -> ... (25 total)
```

### 3.4 Key Emscripten Build Flags
```bash
-sMAIN_MODULE=1              # Auto-exports all symbols (disables dead-code elimination)
-sSIDE_MODULE=1              # For .so files
-sPROXY_TO_PTHREAD=1         # Main thread runs in worker
-sPTHREAD_POOL_SIZE=4        # Worker count
-sINITIAL_MEMORY=2047MB      # Initial WASM memory
-sALLOW_MEMORY_GROWTH=1      # Dynamic memory expansion
-sMAX_WEBGL_VERSION=2         # Force WebGL2
-sMIN_WEBGL_VERSION=2
-sSHARED_MEMORY=1            # SharedArrayBuffer support
-sERROR_ON_UNDEFINED_SYMBOLS=0  # Symbols resolved at runtime via dlopen
-sCASE_INSENSITIVE_FS=1       # Windows-style filesystem (HL2 expects this)
-msimd128                     # SIMD for physics performance
```

---

## 4. KEY DECISIONS AND RATIONALE

### DEC-FIXED-001: WebGL2 before WebXR
No WebXR implementation until stable WebGL2 rendering. Parallel development would make error sources unclear.

### DEC-FIXED-002: Face Morphing Disabled
slqnt disabled the flex/face-morphing system due to stability issues. We follow this — too risky, unknown bug cause.

### DEC-FIXED-003: IDBFS for Phase 1 Save States
Emscripten IndexedDB filesystem — lowest risk, transparent to engine code, verified by slqnt.

### DEC-FIXED-004: Crouch rebound to C (not Ctrl)
Browser reserves Ctrl combinations (Ctrl+W closes tab). slqnt implemented this fix.

### DEC-FIXED-005: nillerusr/source-engine as engine base
Contains ToGLES mode, basis of all known Source Engine browser ports.

### DEC-FIXED-006: weliveinhell/source-engine as build reference
Complete emscripten/ build infrastructure, pinned emsdk commit, SDL2 audio patch, libwebgl.patch.

### DEC-IMPLICIT-001: MAIN_MODULE=1 (not =2)
MAIN_MODULE=1 auto-exports ALL symbols (disables dead-code elimination). Necessary because vtable _ZTV11IVP_Mindist was being stripped. MAIN_MODULE=2 would require explicit symbol keep-alive lists. Trade-off: larger WASM but simpler symbol management.

### DEC-IMPLICIT-002: dlsym intercept for GL functions
Source Engine ToGL library resolves GL function pointers via dlsym(), NOT SDL_GL_GetProcAddress. Previous _emscripten_GetProcAddress override was never called. Fix: intercept __dlsym_js and check __glStubs table before native lookup.

### DEC-IMPLICIT-003: GL version spoof to 3.3.0
Source Engine requires GL >= 3.2. WebGL2 reports OpenGL ES 3.0. Spoofing to "3.3.0 (WebGL 2.0 ...)" satisfies the version check.

### DEC-IMPLICIT-004: Game mode is portal not hl2
weliveinhell fork is a Portal port. Using -game portal matches the demo at yikes.pw/portal. HL2 assets are compatible but map names differ (background01 vs background1).

---

## 5. ALL FIXES AND BUG HISTORY (Chronological)

### Build Fixes

#### FIX-001: IVP vtable crash (Build #41 era)
- Problem: _ZTV11IVP_Mindist vtable undefined — assertion failure after loadDylibs
- Root Cause: #ifndef __EMSCRIPTEN__ guard in ivp_mindist_minimize.cxx prevented compilation for WASM. Out-of-line destructor missing (no key function, vtable not emitted)
- Fix: Remove EMSCRIPTEN guard, add out-of-line ~IVP_Mindist() destructor, compile at -O0 to prevent dead-code elimination. MAIN_MODULE=1 auto-exports the vtable
- Files: emscripten_stubs.cpp (in ci-build.sh heredoc), ivp_mindist_minimize.cxx

#### FIX-002: Canvas element not defined
- Problem: ReferenceError: canvasElement is not defined in hl2_launcher.js
- Root Cause: Canvas object not passed to engine initialization
- Fix: Define canvasElement and statusElement as global variables in pre.js

#### FIX-003: OpenGL version mismatch
- Problem: Engine sees OpenGL ES 3.0 (WebGL2) but expects desktop GL 3.2
- Fix: Intercept glGetString(GL_VERSION) to return "3.3.0 (WebGL 2.0 ...)"

#### FIX-004: Missing GL functions (187 stubs)
- Problem: Desktop GL functions not available in WebGL (glAlphaFunc, glColor4f, glClientActiveTexture, glGetTexLevelParameteriv, glDrawRangeElementsBaseVertex, etc.)
- Fix: 187 GL stubs with WASM function signatures in __glStubs table. dlsym intercept returns addFunction(stub.fn, stub.sig)

#### FIX-005: dlsym/dlopen intercept
- Problem: ToGL resolves GL functions via dlsym(), not SDL_GL_GetProcAddress. Previous _emscripten_GetProcAddress override was dead code
- Fix: Intercept __dlopen_js (return fake handle 999 for GL libs) and __dlsym_js (check __glStubs before native lookup)

#### FIX-006: libGLESv3.so missing dependency
- Problem: liblauncher.so depends on libGLESv3.so which does not exist
- Fix: Create 24-byte empty WASM stub side-module

#### FIX-007: CI source-engine cache conflict (Builds #72-75)
- Problem: Source-engine cache (entire ENGINE_DIR) and waf build cache (ENGINE_DIR/build) shared path space. On source cache MISS + waf cache HIT, build/ dir existed but no source code. clone_engine() saw non-empty dir and failed
- Fix: Remove source-engine cache entirely. Only cache ENGINE_DIR/build. clone_engine() checks .git/HEAD validity. Stale dirs cleared via find -exec rm -rf

#### FIX-008: Wrong CI file paths (Build #76-78)
- Problem: All edits went to hl2-webxr-port/ subdirectory but CI runs root paths (.github/workflows/build.yml, scripts/ci-build.sh)
- Fix: Copy files to both root and subdirectory paths

#### FIX-009: MANIFEST_EOF heredoc swallowed main() (Build #80)
- Problem: Heredoc closing delimiter MANIFEST_EOF was placed AFTER the main() function, so the entire main() body was treated as heredoc content
- Fix: Close heredoc immediately after JSON block, then define main()

#### FIX-010: write_build_manifest undefined (Build #78)
- Problem: Function defined after main "$@" call — bash never parsed it
- Fix: Move function definition before main() call

### Runtime Fixes

#### FIX-RT-001: Map name background1 vs background01
- Problem: Portal port expects background1.bsp, HL2 Retail 2153 has background01.bsp
- Fix: post.js patches map path dynamically

#### FIX-RT-002: Canvas 0x0 pixels
- Problem: Engine does not set canvas dimensions
- Fix: Set canvas width/height in HTML before engine init

#### FIX-RT-003: XHR handler for missing chunks
- Problem: Engine requests chunks that do not exist yet
- Fix: XHR handler gracefully skips 404s

---

## 6. INFRASTRUCTURE

### Cloudflare
```yaml
pages:
  url: "https://hl2-webxr.pages.dev"
  project: "hl2-webxr"
  headers: "COOP/COEP via _headers file"

r2:
  bucket: "hl2-webxr-assets"
  endpoint: "https://bdeeeb229289da950d71472c4c4bab76.r2.cloudflarestorage.com"
  chunks:
    - shaders.data (22MB)
    - background01.data (804MB)
    - background1.data (804MB)
    - materials.data (981MB)
    - models.data (1329MB)
    - shader-manifest.json (1MB)
  total_size: "~4.1GB"

worker:
  name: "hl2-assets-proxy"
  url: "https://hl2-assets-proxy.hl2-webxr.workers.dev"
  function: "R2 proxy with CORS headers + range request support"
  file: "r2-proxy-worker-v2.js"
```

### GitHub
```yaml
repo: "Mxthy/hl2-webxr"
secrets:
  - R2_ACCESS_KEY_ID
  - R2_SECRET_ACCESS_KEY
  - ASSETS_ARCHIVE_URL (archive.org HL2 Retail 2153)
workflow: ".github/workflows/build.yml"
build_script: "scripts/ci-build.sh"
build_time: "~25 minutes"
caches:
  - emsdk (pinned commit)
  - waf build objects (build/ only)
  - HL2 assets (extracted)
```

### Key URLs
| Service | URL |
|---------|-----|
| Live Demo | https://hl2-webxr.pages.dev/hl2_launcher.html |
| R2 Proxy | https://hl2-assets-proxy.hl2-webxr.workers.dev |
| GitHub Repo | https://github.com/Mxthy/hl2-webxr |
| Archive.org Assets | https://archive.org/download/Half-Life-2-Retail-2153/Half-Life%202.7z |
| slqnt Reference | https://hl2.slqnt.dev |
| weliveinhell Demo | https://yikes.pw/portal |

---

## 7. REFERENCE PROJECTS

### slqnt.dev (Closed Source, Live Demo)
- URL: https://hl2.slqnt.dev
- Status: Fully functional 2D browser port, loads maps on-demand
- Key Learnings:
  - dynamicLibraries = [] (empty — Emscripten reads neededDynlibs from WASM binary)
  - PROXY_TO_PTHREAD, pthreadPoolSize=6
  - OPFS for chunk caching (hl2_chunks/ directory)
  - Binary packing format: [pathLen int32][dataLen int32][path UTF-8][data bytes]
  - Service Worker for COOP/COEP headers
  - Module.__gameChoice Promise pattern (waits for user game selection)
  - Engine args: -game hl2 -windowed -w 1280 -h 800 -novid -noip +mat_hdr_level 0
  - Facial animations: disabled (stability)

### weliveinhell/source-engine (Our Engine Base)
- URL: https://github.com/weliveinhell/source-engine
- Demo: https://yikes.pw/portal
- Key Features:
  - ToGLES build mode
  - waf build system
  - emscripten/build.sh — main build script
  - emscripten/repackage.js — asset packing
  - emscripten/libwebgl.patch — glMapBufferRange fix
  - SDL2 audio patch
  - Pthreads + SharedMemory (NOT asyncify)

### nillerusr/source-engine (Original Fork, 2171 Stars)
- URL: https://github.com/nillerusr/source-engine
- Note: Basis of all known ports, but we use weliveinhell for better Emscripten integration

### vittorioromeo/HL2VRU (VR Mod, 189 Stars)
- URL: https://github.com/vittorioromeo/HL2VRU
- Note: Phase 2 reference — VR-specific Source Engine modifications (native, non-Web)

---

## 8. KEY FILES

| File | Purpose | Status |
|------|---------|--------|
| scripts/ci-build.sh | CI Build Pipeline (~960 lines) | Stable |
| scripts/gl_stubs_patch.py | GL stubs + ASSET_ORIGIN + telemetry injection | Latest: d80d8af9 |
| scripts/create_dummy_vtfs.py | Bootstrap VTF generation | Works |
| scripts/upload_chunks_r2.py | R2 chunk upload | Works |
| .github/workflows/build.yml | GitHub Actions workflow | Stable |
| hl2-webxr-port/emscripten/pre.js | DataLoader, GL stubs, SAB, game args | Needs ASSET_BASE fix |
| hl2-webxr-port/emscripten/post.js | Canvas, dynamicLibraries, engine args | Redundant with pre.js |
| hl2-webxr-port/emscripten/xr_wrapper.js | WebXR session, SAB bridge | Phase 2 |
| hl2-webxr-port/emscripten/sw.js | Service Worker (COOP/COEP) | Defined |
| hl2-webxr-port/emscripten/index.html | Main HTML | Needs canvas fix |
| r2-proxy-worker-v2.js | Cloudflare R2 proxy worker | Deployed |
| serve.js | Local dev server with COOP/COEP | Works |
| hl2-webxr-port/docs/MASTER_SCOPE.md | Master scope and project plan | Current |
| hl2-webxr-port/docs/PHASE_1_BUILDPLAN.md | Phase 1 detailed plan | Current |
| hl2-webxr-port/docs/decisions.md | Decision log | Current |

---

## 9. OPEN ISSUES AND NEXT STEPS

### Current Blockers (Phase 1)
1. Canvas not rendering — Engine starts but canvas shows "Preparing..." — GL heartbeat telemetry added but not yet verified in browser
2. Chunk loading unverified — R2 URL patched but browser download not confirmed
3. Game mode mismatch — CI uses -game portal, post.js says -game hl2
4. CI build #82 running — Cache fix + heredoc fix verification pending

### Phase 1 Steps (Remaining)
1. CI: Fix ASSET_ORIGIN in pre.js (centralized chunk URL) — gl_stubs_patch.py does this
2. Browser: Verify chunk requests with status/bytes logging
3. Browser: Verify GL heartbeat (G1-G4 gates)
4. Runtime: Confirm draw calls in browser console
5. Engine: Debug material/shader issues after confirmed draw call
6. Game mode: Consolidate to -game portal (matches weliveinhell)

### Phase 2 (WebXR — NOT STARTED)
1. WebXR session lifecycle (XRSession, requestAnimationFrame)
2. Stereo rendering (OVR_multiview2, single-pass)
3. SAB bridge: Main thread (XR poses) to Worker (engine rendering)
4. VR input (controller mapping)
5. Quest 3 optimization (PTHREAD_POOL_SIZE=4, memory limits)

### Phase 3 (Polish — NOT STARTED)
1. OPFS chunk caching
2. Multi-map streaming
3. Save states (IDBFS)
4. Performance tuning
5. Cross-browser testing

---

## 10. ANTI-CIRCLE RULES

1. No manual patches in deployed hl2_launcher.js — always fix in CI source
2. No WebXR until Phase 1 (2D rendering) works
3. Read browser console first, then decide
4. One problem per iteration — not 5 things at once
5. Commit message documents what the fix should achieve

---

## 11. GLOSSARY

| Term | Meaning |
|------|---------|
| ToGLES | Source Engine mode translating DirectX calls to OpenGL ES |
| Side-Module (.so) | Emscripten dynamic library loaded via dlopen |
| MAIN_MODULE=1 | Emscripten flag: auto-exports all symbols |
| PROXY_TO_PTHREAD | Main thread logic runs in a Web Worker |
| SAB | SharedArrayBuffer — shared memory between threads |
| COOP/COEP | Cross-Origin headers required for SharedArrayBuffer |
| OPFS | Origin Private File System — browser-internal storage |
| VPK | Valve Pack format — HL2 asset container |
| VTF | Valve Texture Format |
| waf | Python-based build system used by Source Engine |
| emcc | Emscripten compiler (C/C++ to WASM) |
| dlsym | Dynamic symbol lookup (intercepted for GL stubs) |
| R2 | Cloudflare S3-compatible object storage |
| Pages | Cloudflare static site hosting |
| Worker | Cloudflare serverless edge functions |
