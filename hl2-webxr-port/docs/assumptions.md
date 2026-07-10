# Assumptions
## HL2 WebGL2/WebXR Porting Manager

Generated: 2026-07-10

Alle Annahmen sind mit Status markiert:
- CONFIRMED — direkt aus Quellen belegbar
- INFERRED — logisch ableitbar, nicht direkt belegt
- UNKNOWN — keine Basis vorhanden, Annahme trotzdem getroffen

---

## Engine & Rendering

### ASM-001
**Annahme:** nillerusr/source-engine ist weiterhin öffentlich auf GitHub verfügbar.
**Status:** INFERRED (war verfügbar zum Zeitpunkt der slqnt-Analyse, kein direkter Check erfolgt)
**Risiko:** MITTEL — Repo könnte privat/entfernt werden
**Fallback:** Fork oder Mirror beschaffen

### ASM-002
**Annahme:** Der ToGLES-Rendering-Modus ist im nillerusr-Repo vorhanden und funktionsfähig.
**Status:** CONFIRMED (direkt aus slqnt-Blog: "nillerusrs repo had implemented a ToGLES rendering mode")

### ASM-003
**Annahme:** Emscripten kann GLES-Calls des ToGLES-Modus vollständig nach WebGL2 übersetzen.
**Status:** CONFIRMED (aus Emscripten-Doku: GLES → WebGL2 ist der primäre unterstützte Pfad)

### ASM-004
**Annahme:** `-sMAX_WEBGL_VERSION=2` ist der zentrale Build-Flag für diesen Rendering-Pfad.
**Status:** CONFIRMED (aus Emscripten-Doku)

### ASM-005
**Annahme:** Source Engine nutzt keine OpenGL 1.x Fixed-Function-Pipeline-Features,
die `-sLEGACY_GL_EMULATION` erfordern würden.
**Status:** INFERRED (Source Engine 2004 ist bereits Shader-basiert, nicht GL1.x)

---

## Asset-System

### ASM-006
**Annahme:** GCFExplorer kann alle relevanten GCF-Dateien aus ARC-01 korrekt extrahieren.
**Status:** CONFIRMED (GCFExplorer im Archiv enthalten, Keys in README angegeben)

### ASM-007
**Annahme:** Die per-Map .data-Packing-Methode (Logging → Pack) ist auf alle HL2-Maps anwendbar.
**Status:** CONFIRMED (slqnt beschreibt generisches Verfahren, nicht map-spezifisch)

### ASM-008
**Annahme:** Die Asset-Requests sind deterministisch — gleicher Lauf ergibt gleiche Log-Datei.
**Status:** INFERRED (normalerweise deterministisch in Source Engine, aber proc-gen Content könnte abweichen)

### ASM-009
**Annahme:** Build-2153-Assets (Pre-Anniversary) sind NICHT direkt mit nillerusr-Engine kompatibel.
**Status:** INFERRED (aus slqnt-Blog impliziert durch explizite Nutzung von steam_legacy)
**Kritikalität:** HOCH — muss in T-006 validiert werden

### ASM-010
**Annahme:** steam_legacy-Branch-Assets sind im VPK-Format (nicht GCF).
**Status:** INFERRED (Valve wechselte von GCF zu VPK ca. 2010, steam_legacy ist post-2010)

---

## Save System

### ASM-011
**Annahme:** IDBFS ist in allen Ziel-Browsern (Chrome, Firefox, Edge) stabil verfügbar.
**Status:** INFERRED (IndexedDB ist breiter Standard seit 2015+)

### ASM-012
**Annahme:** Die Source-Engine-Speicherpfade können transparent auf IDBFS gemappt werden
ohne Engine-Code-Rewrite.
**Status:** INFERRED (Emscripten-Filesystem-Abstraktion soll dies ermöglichen)

---

## Input

### ASM-013
**Annahme:** Pointer Lock API ist in allen Ziel-Browsern für First-Person-Controls verfügbar.
**Status:** INFERRED (Pointer Lock ist breiter Standard)

### ASM-014
**Annahme:** Ctrl-Taste als Crouch ist der einzige Browser-Konflikt.
**Status:** CONFIRMED für Ctrl (slqnt), aber weitere Konflikte möglich (F-Tasten, Alt+F4 etc.)
**Risiko:** NIEDRIG — weitere Rebinds bei Bedarf möglich

---

## Build-System

### ASM-015
**Annahme:** Das Projekt kann auf Linux gebaut werden (Emscripten ist Linux-first).
**Status:** INFERRED (Emscripten primär Linux, macOS auch unterstützt)

### ASM-016
**Annahme:** SDL2 wird als Eingabe-/Fenster-System genutzt (nicht SDL1 oder rein natives).
**Status:** INFERRED (SDL2 ist de-facto Standard für Emscripten-Game-Ports)

### ASM-017
**Annahme:** `-sUSE_VORBIS=1` und `-sUSE_OGG=1` decken die Audio-Codec-Anforderungen der Source Engine.
**Status:** INFERRED (Source Engine nutzt OGG/Vorbis für Musik, WAV für SFX)

---

## Deployment

### ASM-018
**Annahme:** Der Ziel-Server kann COOP/COEP-Header setzen (für SharedArrayBuffer, falls Threading).
**Status:** INFERRED — noch nicht entschieden ob Threading aktiviert wird (DEC-003)

### ASM-019
**Annahme:** .data-Dateien pro Map sind groß genug, um CDN-Hosting zu rechtfertigen.
**Status:** INFERRED (HL2-Maps sind typisch 50-200 MB an Assets)

---

## Scope

### ASM-020
**Annahme:** Episode One und Episode Two sind separate Porting-Aufgaben (Phase 3).
**Status:** CONFIRMED (slqnt bestätigt: "im planning to do both hl2 episodes 1 and 2")

### ASM-021
**Annahme:** Counter-Strike: Source-Assets aus ARC-01 werden nicht für den HL2-Port benötigt.
**Status:** INFERRED (CS:S ist separates Spiel, kein HL2-Dependency)
