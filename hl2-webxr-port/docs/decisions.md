# Decisions
## HL2 WebGL2/WebXR Porting Manager

Generated: 2026-07-10
Zuletzt aktualisiert: 2026-07-10 19:00 (Europe/Berlin)

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

## Ausstehende Entscheidungen

### DEC-001 — Asset-Quelle: Build 2153 vs steam_legacy
**Status:** AUSSTEHEND — abhängig von T-006 (Compatibility Test)
**Entscheider:** Projekt-Lead
**Deadline:** Nach Abschluss T-006

**Option A:** Build 2153 (ARC-01)
- Pro: Sofort verfügbar, kein Steam-Account nötig
- Contra: Kompatibilität mit nillerusr UNSICHER
- Risiko erhöht: weliveinhell nutzt VPK-Format (Steam-Rip), nicht GCF

**Option B:** Steam legacy-Branch
- Pro: Kompatibilität gesichert (slqnt nutzt dies)
- Contra: Steam-Account + HL2-Kauf erforderlich

**Trigger:** T-006 Compatibility Test Ergebnis

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
**Status:** AUSSTEHEND
**Entscheider:** Entwickler

**Kontext:**
Pthreads (SHARED_MEMORY) erfordert COOP/COEP HTTP-Header auf dem Server.
Erhöht Komplexität des Deployments erheblich.

**Optionen:**
- A: Single-threaded (kein SHARED_MEMORY) — einfacher, möglicherweise langsamer
- B: Multi-threaded (SHARED_MEMORY + Pthreads) — komplexer, bessere Performance

**Trigger:** Performance-Profiling in Phase 1.6

---

### DEC-004 — WebXR Runtime (Phase 3)
**Status:** AUSSTEHEND — Phase 3
**Optionen:**
- WebXR Device API (Browser-nativ)
- Polyfill für ältere Browser
- OpenVR-to-WebXR-Bridge

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
| DEC-001 | Asset-Quelle | AUSSTEHEND | — |
| DEC-002 | Audio-System | AUSSTEHEND (SDL2-Hinweis) | — |
| DEC-003 | Threading | AUSSTEHEND | — |
| DEC-004 | WebXR Runtime | AUSSTEHEND (Phase 3) | — |
