# Decisions
## HL2 WebGL2/WebXR Porting Manager

Generated: 2026-07-10
Zuletzt aktualisiert: 2026-07-17 (Europe/Berlin)

---

## Getroffene Entscheidungen

### DEC-FIXED-001 — WebGL2 vor WebXR
**Status:** FESTGELEGT (Projektregel)
**Datum:** 2026-07-10

**Entscheidung:**
Keine WebXR-Implementierung vor stabiler WebGL2-Basis.

**Begründung:**
WebXR ist auf funktionierendem WebGL2-Rendering aufgebaut.
Parallelentwicklung würde Fehlerquellen unklar machen.

**Impact:** Phase-Struktur: Phase 1 (WebGL2) → Phase 2 → Phase 3 (WebXR)

---

### DEC-FIXED-002 — Face Morphing: Deaktiviert
**Status:** FESTGELEGT
**Datum:** 2026-07-10

**Entscheidung:**
Das Face-Morphing/Flex-System wird für den Browser-Port deaktiviert.

**Begründung:**
slqnt hat das System wegen Stabilitätsproblemen vollständig deaktiviert (CONFIRMED).
Bug-Ursache unbekannt. Reaktivierung würde erheblichen unbekannten Aufwand bedeuten.

**Impact:** PATCH-001 ist Pflicht-Patch. Keine Facial Animations im Port.

---

### DEC-FIXED-003 — Save System: IDBFS für Phase 1
**Status:** FESTGELEGT für Phase 1
**Datum:** 2026-07-10

**Entscheidung:**
Phase 1 nutzt IDBFS (Emscripten IndexedDB Filesystem) für Save States.

**Begründung:**
- Von slqnt bereits implementiert und verifiziert (CONFIRMED)
- Niedrigstes Risiko / niedrigste Komplexität
- Transparent für Engine-Code

**Einschränkung:** Gilt nur für Phase 1. Cloud-Saves für Phase 2 evaluieren.

---

### DEC-FIXED-004 — Crouch-Rebind: C statt Ctrl
**Status:** FESTGELEGT
**Datum:** 2026-07-10

**Entscheidung:**
Crouch wird auf Taste `C` gebunden, nicht auf `Ctrl`.

**Begründung:**
Browser reserviert `Ctrl`-Kombinationen für native Funktionen (Ctrl+W, Ctrl+T etc.).
slqnt hat diesen Fix implementiert (CONFIRMED).

---

### DEC-FIXED-005 — Engine-Basis: nillerusr/source-engine
**Status:** FESTGELEGT
**Datum:** 2026-07-10

**Entscheidung:**
nillerusr/source-engine (2020 TF2 Leak-Fork) als Engine-Basis.

**Begründung:**
- Enthält ToGLES-Modus (CONFIRMED)
- Basis aller bekannten Source-Engine-Browser-Ports
- Bewährt durch weliveinhell (Portal) und slqnt (HL2)

---

### DEC-FIXED-006 — Emscripten-Build-Referenz: weliveinhell/source-engine
**Status:** FESTGELEGT
**Datum:** 2026-07-10 (BLK-001-Auflösung)

**Entscheidung:**
Als primäre Emscripten-Build-Referenz wird `github.com/weliveinhell/source-engine` genutzt,
nicht ein hypothetisch rekonstruierter Build-Prozess.

**Begründung:**
- Repo öffentlich verfügbar und verifiziert (BLK-001 geschlossen)
- Enthält vollständige `emscripten/`-Build-Infrastruktur:
  - `build_emscripten.sh` — direkter Build-Einstiegspunkt
  - `emscripten/repackage.js` — Asset-Packing
  - `emscripten/get_logs.sh` — Asset-Logging
  - `emscripten/libwebgl.patch` — notwendiger WebGL-Fix
- Pinned emsdk-Commit: `2d480a1b7c7a34a354188d93f3e89190a44a1d21`
  (verhindert Inkompatibilitäten durch neue emsdk-Versionen)
- SDL2-Patch dokumentiert (MAIN_THREAD_EM_ASM_INT-Fix)

**Impact:**
- ACTION-007 (Emscripten-Build) folgt direkt weliveinhell's README-Anleitung
- T-007 (Asset-Logging) nutzt `emscripten/get_logs.sh` + printf-Patch aus weliveinhell-Repo
- Emscripten-Flags aus weliveinhell's `build_emscripten.sh` verifizieren (ggf. pipeline.yaml aktualisieren)

---

### DEC-FIXED-007 — CI Sparse-Checkout muss alle benötigten Verzeichnisse enthalten
**Status:** FESTGELEGT
**Datum:** 2026-07-17

**Entscheidung:**
Die `sparse-checkout` in `.github/workflows/build.yml` MUSS alle Verzeichnisse enthalten,
deren Dateien im `ci-build.sh` referenziert werden. Aktuell: `scripts/`, `emscripten/`, `.github/`.

**Begründung:**
Build #87 (commit 7e8b2b52) war "successful" aber `webxr_bridge.cpp` und `webxr_hooks.cpp`
wurden als "not found, skipping" übersprungen — obwohl die Dateien im GitHub Repo existierten.
Root cause: `sparse-checkout` enthielt nur `scripts/` und `.github/`, nicht `emscripten/`.
Der CI-Runner hatte die Dateien schlicht nicht heruntergeladen. Die Builds liefen "erfolgreich"
durch, weil alle Checks optional waren (`if [ -f ... ]` → "not found, skipping").

**Symptom:**
```
[ci-build]   webxr_bridge.cpp not found, skipping (Phase 2 bridge)
[ci-build]   webxr_hooks.cpp not found, skipping (Phase 2 engine hooks)
```

**Fix:**
```yaml
sparse-checkout: |
  scripts/
  emscripten/
  .github/
```

Außerdem wurden `emscripten/webxr_bridge.cpp`, `emscripten/webxr_hooks.cpp`,
`emscripten/pre.js`, `emscripten/post.js`, `emscripten/index.html` und
`scripts/webxr_glmain_patch.py` zu den `paths:`-Triggern hinzugefügt.

**Impact:** Jede neue Datei, die von `ci-build.sh` referenziert wird, MUSS in einem
Verzeichnis stehen, das in der `sparse-checkout` aufgeführt ist. Bei neuen Verzeichnissen
diese Liste zwingend erweitern.

---

### DEC-FIXED-008 — WebXR Phase 2: Engine Hooks via global state + ComputeViewMatrix override
**Status:** FESTGELEGT
**Datum:** 2026-07-17

**Entscheidung:**
WebXR Camera-Override erfolgt über globale Variablen in `webxr_hooks.cpp`
(`g_WebXRViewMatrix[16]`, `g_bWebXRMatrixActive`) und einen Patch in
`ComputeViewMatrix()` (gl_rmain.cpp), der bei aktivem Override die Matrix
aus dem globalen State kopiert statt aus Origin+Angles zu berechnen.

**Begründung:**
- Minimal-invasiv: Nur eine Funktion (`ComputeViewMatrix`) wird gepatched
- Keine Änderung an `CViewSetup` oder der View-Pipeline nötig
- Die globale State-Variable kann von JS via `Module._Engine_SetCameraMatrix(ptr)` gesetzt werden
- Column-major (WebXR) → Row-major (VMatrix m[row][col]) Konvertierung: `m[r][c] = src[c*4+r]`
- Für die Projektionsmatrix existiert bereits `m_bViewToProjectionOverride` in `CViewSetup`
- `em_loop_iteration()` (sys_dll2.cpp:1502) wird für manuelle Frame-Rendering verwendet

**Architektur:**
```
JS (xr_wrapper.js)
  → Module._malloc(64) → HEAPF32.set(matrix) → Module._SetCameraMatrices(viewPtr, projPtr)
  → Module._RenderXRFrame() (pro Auge)

C++ (webxr_bridge.cpp — KEEPALIVE exports)
  → DisableAutoRenderLoop() → Engine_DisableAutoRender()
  → SetCameraMatrices(view, proj) → Engine_SetCameraMatrix(view) + Engine_SetProjectionMatrix(proj)
  → RenderXRFrame() → Engine_RenderSingleFrame()

C++ (webxr_hooks.cpp — engine integration)
  → Engine_DisableAutoRender() → emscripten_cancel_main_loop()
  → Engine_RenderSingleFrame() → em_loop_iteration()
  → Engine_SetCameraMatrix(float*) → memcpy to g_WebXRViewMatrix[16], set g_bWebXRMatrixActive=true

C++ (gl_rmain.cpp — patched by webxr_glmain_patch.py)
  → ComputeViewMatrix() checks g_bWebXRMatrixActive first
  → If active: copy g_WebXRViewMatrix (column-major) into VMatrix (row-major)
  → If inactive: original angle-based computation
```

**Impact:** Build #88 (commit 59a8fc14) — erstmals beide Hooks + Bridge kompiliert und gelinkt.

---

## Ausstehende Entscheidungen

### DEC-001 — Asset-Quelle: Build 2153 vs steam_legacy
**Status:** GELÖST — Build 2153 als primäre Quelle bestätigt (CI Build #65+)
**Datum:** 2026-07-15

**Entscheidung:**
Build 2153 (Retail) wird als primäre Asset-Quelle verwendet. Direkt extrahierbar,
kein HLExtract/Wine nötig. CI-Pipeline lädt von Archive.org und cacht extrahierte Assets.

---

### DEC-002 — Audio-System
**Status:** AUSSTEHEND
**Entscheider:** Entwickler

**Optionen:**
- OpenAL via Emscripten (Source Engine Standard)
- SDL2_mixer (bevorzugt nach weliveinhell-SDL2-Patch-Hinweis)
- Web Audio API direkt
- AUDIO_WORKLET

**Hinweis:** weliveinhell-Repo enthält SDL2-Audio-Patch → bevorzugt SDL2-basierte Option.

**Trigger:** Wenn Engine erstmals im Browser läuft und Audio-System sichtbar wird

---

### DEC-003 — Threading: Pthreads aktivieren?
**Status:** GELÖST — Pthreads + SHARED_MEMORY aktiviert
**Datum:** 2026-07-11

**Entscheidung:**
Multi-threaded (SHARED_MEMORY + Pthreads) mit PROXY_TO_PTHREAD und OffscreenCanvas.
COOP/COEP-Header sind Pflicht für alle Deployments.

---

### DEC-004 — WebXR Runtime (Phase 3)
**Status:** GELÖST — WebXR Device API (Browser-nativ)
**Datum:** 2026-07-15

**Entscheidung:**
Direkte WebXR Device API ohne Framework-Overhead. SharedArrayBuffer-Bridge zwischen
Main-Thread (XRSession) und Engine-Worker (OffscreenCanvas).

---

## Entscheidungs-Log

| ID | Titel | Status | Datum |
|---|---|---|---|
| DEC-FIXED-001 | WebGL2 vor WebXR | FESTGELEGT | 2026-07-10 |
| DEC-FIXED-002 | Face Morphing deaktiviert | FESTGELEGT | 2026-07-10 |
| DEC-FIXED-003 | IDBFS für Phase 1 | FESTGELEGT | 2026-07-10 |
| DEC-FIXED-004 | Crouch auf C | FESTGELEGT | 2026-07-10 |
| DEC-FIXED-005 | nillerusr als Engine-Basis | FESTGELEGT | 2026-07-10 |
| DEC-FIXED-006 | weliveinhell als Build-Referenz | FESTGELEGT | 2026-07-10 |
| DEC-FIXED-007 | CI Sparse-Checkout completeness | FESTGELEGT | 2026-07-17 |
| DEC-FIXED-008 | WebXR Phase 2 Engine Hooks Architecture | FESTGELEGT | 2026-07-17 |
| DEC-001 | Asset-Quelle | GELÖST (Build 2153) | 2026-07-15 |
| DEC-002 | Audio-System | AUSSTEHEND | — |
| DEC-003 | Threading | GELÖST (Pthreads) | 2026-07-11 |
| DEC-004 | WebXR Runtime | GELÖST (WebXR Device API) | 2026-07-15 |
