# Reference Analysis
## HL2 WebGL2/WebXR Porting Manager — Source Analysis

Generated: 2026-07-10
Agent: Sequential Analysis Mode (no sub-agents)

---

## Quelle 1: slqnt Browser-Port Blog
**URL:** https://www.slqnt.dev/blog/hl2-in-web
**Datum:** 24. Juni 2026

### Architektur-Stack (CONFIRMED)
- Engine-Basis: `nillerusr/source-engine` (2020 TF2 Leak-Fork)
- Portal-Port-Vorläufer: `weliveinhell` (GitHub) — direkte Vorgänger-Codebasis
- Rendering: ToGLES-Modus → Emscripten → WebGL2
- Asset-Basis: Steam `steam_legacy`-Branch (nicht Anniversary-Release!)
- Save-State: IDBFS (Emscripten IndexedDB Filesystem)

### Asset-Loading-Pipeline (CONFIRMED)
1. Print-Statement-Logging aller Asset-Requests
2. Logs werden in Datei gespeichert
3. Skript extrahiert referenzierte Assets
4. Assets werden in `.data`-Dateien gepackt (eine pro Map)
5. VPK-Unpacking: Skript ursprünglich Linux, auf Windows portiert

### Bekannte Bugs und Fixes (CONFIRMED)
- Face Morphing: vollständig deaktiviert (Stabilitätsprobleme)
- Batterien/Medkits: gefixt (Contributor "98")
- Gravity Gun Inventory: gefixt
- Lightmap-Farbfehler: gefixt
- Flashlight Null-Texture: gefixt
- NPC random collapse: gefixt (Contributor "98")
- Headcrab/Zombie Schaden: gefixt
- Wasser schwarz: gefixt
- Crouch: auf `C` rebindet (Ctrl = Browser-Konflikt)

### Offene Punkte
- Genaue Build-Flags: UNKNOWN
- Quellcode des HL2-Ports öffentlich?: UNKNOWN
- Audio-Lösung: UNKNOWN
- WebXR-Integration: UNKNOWN (nicht erwähnt)

---

## Quelle 2: HL2VRU (vittorioromeo)
**URL:** https://github.com/vittorioromeo/HL2VRU

### Typ (CONFIRMED)
Desktop-VR-Mod (SteamVR/OpenVR), kein Browser-Port
Fork von "Half-Life 2: VR Mod" (SourceVR-Team)

### VR-Features (CONFIRMED)
- Universal Melee, Physical Jumping, Dual Wielding
- Virtual Stock, Grip-Holster Mode, Weapon Weight Simulation
- Difficulty Tweaks via CVar-System

### Relevanz für WebXR-Phase (INFERRED)
- Interaction-Patterns als Design-Referenz
- CVar-Konfigurationssystem als Architektur-Vorbild
- Direkte technische Übertragbarkeit: GERING (Desktop-VR ≠ WebXR)

### Offene Punkte
- HL2VR Quellcode öffentlich?: UNKNOWN
- WebXR-API als Ersatz für OpenVR: UNKNOWN (Implementierungsarbeit nötig)

---

## Quelle 3a: Emscripten OpenGL Support
**URL:** https://emscripten.org/docs/porting/multimedia_and_graphics/OpenGL-support.html

### Drei Modi (CONFIRMED)
1. WebGL-friendly subset (Default) — empfohlen
2. OpenGL ES 2.0/3.0 Emulation (`-sFULL_ES2`, `-sFULL_ES3`)
3. Legacy Desktop GL (`-sLEGACY_GL_EMULATION`)

### Kritische Flags (CONFIRMED)
- `-sMAX_WEBGL_VERSION=2` — WebGL2 aktivieren (PFLICHT)
- `-sMIN_WEBGL_VERSION=2` — nur WebGL2 (optional, kleinerer Output)
- `-sFULL_ES2` — client-side arrays (möglicherweise nötig)
- Extensions: über SDL/EGL automatisch, sonst `emscripten_webgl_enable_extension()`

---

## Quelle 3b: Emscripten Settings Reference
**URL:** https://emscripten.org/docs/tools_reference/settings_reference.html

### Key Settings für HL2-Port (CONFIRMED)
**Memory:** INITIAL_MEMORY, MAXIMUM_MEMORY, ALLOW_MEMORY_GROWTH, STACK_SIZE (erhöhen)
**WebGL:** MAX_WEBGL_VERSION=2, FULL_ES2, GL_SUPPORT_AUTOMATIC_ENABLE_EXTENSIONS
**Threading:** SHARED_MEMORY, PTHREAD_POOL_SIZE, PROXY_TO_PTHREAD
**Filesystem:** FILESYSTEM, FETCH_SUPPORT_INDEXEDDB, CASE_INSENSITIVE_FS, FETCH
**Async:** ASYNCIFY oder JSPI
**Libs:** USE_SDL, USE_VORBIS, USE_OGG, USE_ZLIB

---

## Quelle 4a: Archive.org — Retail 2153
**URL:** https://archive.org/details/Half-Life-2-Retail-2153

### Status: VERFÜGBAR (CONFIRMED)
- Build: 2153 (16. November 2004)
- Größe: 4.8 GB, Format: 7Z + ISO

### GCF-Struktur (CONFIRMED)
| Datei | Key |
|---|---|
| base source shared.gcf | C596D1BA1FEAD9A40DD0058118F58975 |
| base source shared materials.gcf | 33648B73E732E0734E34FE3CDA09AB74 |
| base source shared models.gcf | D147FC333F1B2B18A8E0B9354B94AFF6 |
| base source shared sounds.gcf | 9DC57C809A92196E2674ADA87AEA0FCE |
| halflife 2 base content.gcf | 187D516D65C617EB6FE90FB20211DEC6 |

### Wichtig: Kompatibilitätswarnung (INFERRED)
slqnt benötigt `steam_legacy`-Branch (Post-Anniversary). Build 2153 ist Pre-Anniversary.
Direkte Kompatibilität mit nillerusr-Engine NICHT gesichert.

---

## Quelle 4b: Collector's Edition
**URL:** https://archive.org/details/HalfLife2CollectorsEdition2153
**Status: NICHT VERFÜGBAR** — Item removed

---

## Quelle 4c: Episode One PROViSiON
**URL:** https://archive.org/details/half-life-2-episode-one_202402

### Status: VERFÜGBAR (CONFIRMED)
- Größe: 1.4 GB, Format: RAR + Torrent
- Scene-Release (PROViSiON-Gruppe)
- Interne Struktur: UNKNOWN

---

## Quelle 4d: Complete Edition (Linux Steam Rip)
**URL:** https://archive.org/details/half-life-2-complete-edition-...
**Status: NICHT VERFÜGBAR** — Item removed

---

## Archiv-Verfügbarkeits-Summary

| Quelle | Status |
|---|---|
| Retail 2153 | ✅ VERFÜGBAR |
| Collector's Edition | ❌ ENTFERNT |
| Episode One PROViSiON | ✅ VERFÜGBAR |
| Complete Edition Linux | ❌ ENTFERNT |
