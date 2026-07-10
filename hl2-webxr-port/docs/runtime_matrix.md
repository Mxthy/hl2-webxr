# Runtime Matrix
## HL2 WebGL2/WebXR Porting Manager

Generated: 2026-07-10

---

## Rendering Pipeline

| Schicht | Technologie | Status | Flags |
|---|---|---|---|
| Source Engine | ToGLES-Modus | CONFIRMED (nillerusr) | — |
| GLES → WebGL2 | Emscripten GL-Translation | CONFIRMED | `-sMAX_WEBGL_VERSION=2` |
| WebGL2 | Browser-Rendering-API | CONFIRMED | — |
| WebGPU | Zukünftige Option | NOT IN SCOPE Phase 1 | — |

## Emscripten Build-Matrix

### Phase 1 — WebGL2-Basis (Pflicht-Flags)

```bash
emcc \
  -sMAX_WEBGL_VERSION=2 \
  -sMIN_WEBGL_VERSION=2 \
  -sALLOW_MEMORY_GROWTH=1 \
  -sINITIAL_MEMORY=268435456 \  # 256 MB Startwert (INFERRED)
  -sSTACK_SIZE=5242880 \         # 5 MB (INFERRED — erhöht für C++)
  -sFULL_ES2=1 \                 # client-side arrays
  -sCASE_INSENSITIVE_FS=1 \     # Source Engine case-insensitive paths
  -sFETCH_SUPPORT_INDEXEDDB=1 \ # IDBFS für Save States
  -sUSE_SDL=2 \                  # SDL2 (INFERRED)
  -sUSE_ZLIB=1 \                 # VPK/Asset-Kompression
  -sASYNCIFY=1 \                 # Async-Support (INFERRED)
  -sFILESYSTEM=1 \
  -sFORCE_FILESYSTEM=1 \
  -sGL_SUPPORT_AUTOMATIC_ENABLE_EXTENSIONS=1 \
  -sEXIT_RUNTIME=0              # Event Loop nach main() weiter
```

**Status:** INFERRED (abgeleitet aus Emscripten-Docs + slqnt-Architektur, nicht direkt confirmed)

### Phase 2 — Threading (wenn nötig)

```bash
  -sSHARED_MEMORY=1 \
  -sPROXY_TO_PTHREAD=1 \
  -sPTHREAD_POOL_SIZE=4 \
  -sOFFSCREENCNVAS_SUPPORT=1 \
  -sOFFSCREEN_FRAMEBUFFER=1
```

**Voraussetzung:** COOP/COEP Headers auf dem Server (SharedArrayBuffer)

### Phase 3 — WebXR (nach WebGL2-Basis)

- WebXR Device API (Browser-nativ)
- Interaction-Patterns aus HL2VRU adaptieren
- Ersatz für OpenVR/SteamVR: WebXR Gamepad API

---

## Filesystem-Matrix

| System | Zweck | Status |
|---|---|---|
| MEMFS | In-Memory Filesystem (Runtime-Assets) | CONFIRMED (Emscripten-Standard) |
| IDBFS | IndexedDB (Save States, persistent) | CONFIRMED (slqnt-Port) |
| WASMFS | Neues FS-System (Alternative) | INFERRED möglich |
| WORKERFS | Assets aus Worker-Thread | INFERRED optional |
| NODEFS | Node.js only — nicht relevant | N/A |

---

## Audio-Matrix

| Technologie | Wahrscheinlichkeit | Grund |
|---|---|---|
| Web Audio API | HOCH | Browser-Standard |
| AUDIO_WORKLET | MITTEL | Für Low-Latency-Audio |
| OpenAL via Emscripten | MÖGLICH | Source Engine nutzt OpenAL |
| SDL2_mixer | MÖGLICH | Wenn SDL2 als Basis |
| FMOD | UNWAHRSCHEINLICH | Proprietär, kein WASM-Support |

**Status:** UNKNOWN — slqnt-Artikel erwähnt Audio nicht explizit

---

## Browser-Kompatibilitäts-Matrix

| Browser | WebGL2 | WebXR | SharedArrayBuffer | IDBFS |
|---|---|---|---|---|
| Chrome 120+ | ✅ | ✅ | ✅ (mit COOP/COEP) | ✅ |
| Firefox 120+ | ✅ | ✅ | ✅ (mit COOP/COEP) | ✅ |
| Safari 17+ | ✅ | ⚠️ Limited | ⚠️ | ✅ |
| Edge 120+ | ✅ | ✅ | ✅ (mit COOP/COEP) | ✅ |

**Status:** INFERRED (Browser-Support aus allgemeinem Wissen, nicht direkt von Quellen bestätigt)

---

## Input-Matrix

| Input | Phase 1 (WebGL2) | Phase 3 (WebXR) |
|---|---|---|
| Keyboard | ✅ Standard | ✅ |
| Mouse (Pointer Lock) | ✅ Standard | N/A |
| Gamepad API | Optional | ✅ |
| WebXR Gamepad | N/A | ✅ (Controller) |
| WebXR Hand Tracking | N/A | OPTIONAL |
| Crouch-Rebind (C statt Ctrl) | ✅ CONFIRMED (slqnt) | ✅ |

---

## Bekannte Runtime-Probleme (aus slqnt-Port)

| Problem | Ursache | Fix |
|---|---|---|
| Face Morphing Crash | Unbekannt | System vollständig deaktiviert |
| Lightmap Random Colors | Shader/Lightmap-Bug | Gefixt |
| NPC random collapse | Game Logic | Gefixt (Contrib "98") |
| Wasser schwarz | Render-Target | Gefixt |
| Flashlight Null-Texture | Asset-Loading | Gefixt |
| Ctrl-Taste Browser-Konflikt | Browser reserviert Ctrl | Rebind auf C |
