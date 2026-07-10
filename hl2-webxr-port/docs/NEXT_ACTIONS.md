# Next Actions
## HL2 WebGL2/WebXR Porting Manager

Zuletzt aktualisiert: 2026-07-10 19:38 (Europe/Berlin)
Status: ERSTER BUILD ERFOLGREICH — portal target. wasm VALID 4.18 MB. ACTION-007 ✅ DONE.

---

## GELÖSTE BLOCKER

| ID | Blocker | Status |
|---|---|---|
| ~~BLK-001~~ | weliveinhell GitHub-URL unbekannt | ✅ **GESCHLOSSEN** — `github.com/weliveinhell/source-engine` |

---

## AKTIVE BLOCKER (als TODOs eingetragen)

| ID | Blocker | Priorität | Lösung |
|---|---|---|---|
| BLK-002 | slqnt Port-Quellcode nicht öffentlich | MITTEL | ACTION-008 (unabhängig implementieren) |
| BLK-003 | Build-2153 ↔ nillerusr Kompatibilität ungetestet | HOCH | ACTION-006 |
| BLK-004 | ARC-02 + ARC-04 permanent entfernt | NIEDRIG | Workaround: ARC-01 (Phase 1), ARC-03 (Phase 3) |
| BLK-007 | Audio-System-Lösung unklar | LATENT | ACTION-010 (SDL2-Hinweis aus weliveinhell-Repo) |
| BLK-008 | EP2-Asset-Quelle fehlt | LATENT | Phase 3 — neu recherchieren |

---

## Sofortige Aktionen — Diese Woche

### ~~ACTION-001~~ — weliveinhell GitHub-URL finden ✅ ERLEDIGT
**Status:** DONE — 2026-07-10 19:00
**URL:** https://github.com/weliveinhell/source-engine

**Gefundenes Build-System im weliveinhell-Repo:**
```
emscripten/
  repackage.js          — Asset-Packing (Node.js, konfigurierbar)
  get_logs.sh           — Asset-Logging-Skript
  libwebgl.patch        — glMapBufferRange-Fix für WebGL
build_emscripten.sh     — vollständiger Emscripten-Build-Einstiegspunkt
```

**emsdk-Pinning (wichtig!):**
```bash
git checkout 2d480a1b7c7a34a354188d93f3e89190a44a1d21
```

**SDL2-Audio-Patch (aus README):**
```bash
sed -Ei 's/freq = EM_ASM_INT/freq = MAIN_THREAD_EM_ASM_INT/' \
  /emsdk/upstream/emscripten/cache/ports/sdl2/SDL-release-2.32.0/src/audio/emscripten/SDL_emscriptenaudio.c
```

**Asset-Logging printf-Patch (in filesystem/basefilesystem.cpp):**
```cpp
FileHandle_t CBaseFileSystem::OpenForRead(...) {
    printf("OpenForRead %s %s\n", pFileNameT, pathID);
    ...
}
```

**Nächster Schritt jetzt fällig:**
```bash
git clone https://github.com/weliveinhell/source-engine ./engine/portal-port/
```

---

### ACTION-002 — nillerusr/source-engine klonen & Build-System analysieren
**Priorität:** KRITISCH
**Aufwand:** 1 Tag
**Vorbedingung:** Linux-Build-System verfügbar (mind. 16 GB RAM, 50 GB freier Speicher)

```bash
git clone https://github.com/nillerusr/source-engine ./engine/source-engine
cd ./engine/source-engine

# Build-System identifizieren
ls CMakeLists.txt wscript GNUmakefile 2>/dev/null

# Bei waf-Build (nillerusr nutzt waf):
python3 waf configure
python3 waf build

# ToGLES-Modus prüfen:
grep -r "TOGLES\|ToGLES\|gles" --include="*.cpp" --include="*.h" -l | head -20
```

**Erfolgsmetrik:** Engine kompiliert nativ, ToGLES-Modus-Dateien gefunden

---

### ACTION-003 — ARC-01 herunterladen
**Priorität:** HOCH
**Aufwand:** 0.5 Tage + Download-Zeit (4.8 GB)

```bash
mkdir -p ./assets/raw/arc-01

# Download (Torrent empfohlen):
# URL: https://archive.org/details/Half-Life-2-Retail-2153
# Oder: ia download Half-Life-2-Retail-2153

# Entpacken:
7z x ./assets/raw/arc-01/Half-Life-2.7z -o./assets/raw/arc-01/extracted/
```

**Erfolgsmetrik:** 7Z vollständig entpackt, GCF-Dateien sichtbar

---

### ACTION-003b — weliveinhell-Repo klonen (NEU — nach BLK-001-Auflösung)
**Priorität:** HOCH (war bisher blockiert)
**Aufwand:** 0.1 Tage
**Vorbedingung:** keine

```bash
git clone https://github.com/weliveinhell/source-engine ./engine/portal-port/

# Build-Skripte sichern:
ls ./engine/portal-port/emscripten/
cp -r ./engine/portal-port/emscripten/ ./tools/asset-packer/

# Verfügbare Skripte prüfen:
cat ./engine/portal-port/README.md
cat ./engine/portal-port/build_emscripten.sh
```

**Erfolgsmetrik:** Repo geklont, `emscripten/repackage.js` und `build_emscripten.sh` verfügbar

---

### ACTION-004 — GCF-Extraktion (alle 5 relevanten Dateien)
**Priorität:** HOCH
**Aufwand:** 1 Tag (Windows erforderlich für GCFExplorer)
**Vorbedingung:** ACTION-003 abgeschlossen

```
GCFExplorer aus: ARC-01/Misc/GCFExplorer.exe

Reihenfolge der Extraktion:

1. halflife 2 base content.gcf
   Key: 187D516D65C617EB6FE90FB20211DEC6
   Output: ./assets/hl2/

2. base source shared materials.gcf
   Key: 33648B73E732E0734E34FE3CDA09AB74
   Output: ./assets/shared/materials/

3. base source shared models.gcf
   Key: D147FC333F1B2B18A8E0B9354B94AFF6
   Output: ./assets/shared/models/

4. base source shared sounds.gcf
   Key: 9DC57C809A92196E2674ADA87AEA0FCE
   Output: ./assets/shared/sounds/

5. base source shared.gcf
   Key: C596D1BA1FEAD9A40DD0058118F58975
   Output: ./assets/shared/
```

**Erfolgsmetrik:** Alle 5 GCF-Dateien extrahiert, BSP-Dateien in ./assets/hl2/maps/ sichtbar

---

### ACTION-005 — Emscripten SDK installieren und verifizieren
**Priorität:** HOCH
**Aufwand:** 0.5 Tage
**Quelle:** `emscripten/get_emscripten.sh` aus weliveinhell-Repo (CONFIRMED)

```bash
git clone https://github.com/emscripten-core/emsdk.git ./tools/emsdk
cd ./tools/emsdk

# PINNED COMMIT (CONFIRMED aus emscripten/get_emscripten.sh):
git checkout 2d480a1b7c7a34a354188d93f3e89190a44a1d21

./emsdk install latest
./emsdk activate latest
source ./emsdk_env.sh

# SDL2 erst bauen, dann patchen, dann neu bauen (Reihenfolge wichtig!):
embuilder --pic build sdl2 sdl2-mt
sed -Ei 's/freq = EM_ASM_INT/freq = MAIN_THREAD_EM_ASM_INT/' \
  $(dirname $(which emcc))/cache/ports/sdl2/SDL-release-2.32.0/src/audio/emscripten/SDL_emscriptenaudio.c
embuilder --force --pic build sdl2 sdl2-mt

# WebGL-Patch:
patch $(dirname $(which emcc))/src/lib/libwebgl.js \
  /app/hl2-webxr-port/engine/portal-port/emscripten/libwebgl.patch

# Verifizieren:
emcc --version
```

**Erfolgsmetrik:** `emcc --version` gibt Versionsnummer aus, SDL2-Patch angewendet, libwebgl.patch angewendet

---

## Mittelfristige Aktionen — Nächste 2 Wochen

### ACTION-006 — Asset-Kompatibilitätstest → DEC-001 auslösen (BLK-003)
**Priorität:** HOCH
**Vorbedingung:** ACTION-002 (Engine nativ gebaut), ACTION-004 (Assets extrahiert)

```
Schritte:
1. Extrahierte ARC-01-Assets in Engine-Verzeichnis kopieren/verlinken
2. Engine-Kommandozeile: ./hl2_linux -game hl2 -novid
3. Beobachten:
   a. Lädt Hauptmenü? → Kompatibel (DEC-001 → Option A)
   b. Fehler "unknown asset format" / crash? → Inkompatibel (DEC-001 → Option B)
   c. Fehler-Typ dokumentieren → in decisions.md und blockers.md eintragen

Wenn inkompatibel:
4. Steam-Account mit HL2 erforderlich
5. Steam → Bibliothek → HL2 → Eigenschaften → Betas → steam_legacy
6. Assets aus Steam-Verzeichnis kopieren (VPK-Format erwartet)
7. DEC-001 final entscheiden und eintragen
```

**Erfolgsmetrik:** DEC-001 entschieden, asset_source in source_map.json und manifest.json aktualisiert

---

### ACTION-007 — Ersten Emscripten-Build ausführen
**Priorität:** HOCH
**Vorbedingung:** ACTION-002 (Engine nativ gebaut), ACTION-005 (Emscripten + patches), ACTION-003b (weliveinhell-Repo geklont)
**Quelle:** `emscripten/build.sh` aus weliveinhell/source-engine (CONFIRMED)
**WICHTIG:** Build nutzt Pthreads+SharedMemory — NICHT ASYNCIFY. Server braucht COOP/COEP-Header.

```bash
# Aus weliveinhell-Repo bauen (Portal als Referenz, danach auf hl2 umstellen):
cd ./engine/portal-port
source ../../tools/emsdk/emsdk_env.sh

# (libwebgl.patch wurde bereits in ACTION-005 angewendet)

# waf konfigurieren:
python3 waf configure -T release --notests -4 --togles --emscripten \
  --disable-warns --build-games=portal --prefix=build/install

# Bauen:
python3 waf install

# Linken (emcc mit Pthreads, SharedMemory, PROXY_TO_PTHREAD — aus build.sh):
bash emscripten/build.sh release

# Output: ./build/install/ + ./build/launcher_main/hl2_launcher.{html,wasm,js}
# Compiler-Fehler dokumentieren: → ./docs/build-errors-01.txt
```

**Emscripten-Flags (CONFIRMED aus build.sh):**
```
-sFULL_ES3 -sINITIAL_MEMORY=2047mb -sSHARED_MEMORY=1
-sUSE_PTHREADS=1 -sPTHREAD_POOL_SIZE=8 -sPTHREAD_POOL_SIZE_STRICT=2
-sPROXY_TO_PTHREAD=1 -sOFFSCREENCANVAS_SUPPORT=1
-sUSE_SDL=2 -sUSE_BZIP2=1 -sUSE_FREETYPE=1 -sUSE_LIBJPEG=1 -sUSE_LIBPNG=1
-sMALLOC=mimalloc -sMAIN_MODULE=1
```

**Erfolgsmetrik:** hl2_launcher.wasm + hl2_launcher.js erzeugt, Browser lädt ohne sofortigen Crash

✅ **ERLEDIGT 2026-07-10:**
- waf configure: OK (26s)
- waf install: OK (2317/2317 targets, 5m12s)
- emcc link: OK (EXIT:0)
- hl2_launcher.wasm: 4.18 MB, WASM magic b'\x00asm' VALID
- hl2_launcher.js: 1.1 MB
- hl2_launcher.html: 6.5 KB
- 25 shared libraries in build/install/

---

### ACTION-008 — Bekannte Patches implementieren (BLK-002)
**Priorität:** MITTEL
**Vorbedingung:** ACTION-007 (erster Build muss laufen)

Patches in dieser Reihenfolge implementieren:

```
PATCH-001: Face Morphing Disable
  → Flex-System deaktivieren (Search: "flexcontroller", "CFlexAnimatingGameobject")
  → Referenz: slqnt-Blog ("had to just disable the entire system")

PATCH-002: Lightmap Fix
  → Hinweis: weliveinhell-libwebgl.patch (glMapBufferRange) könnte bereits helfen
  → Symptom: Random color flickering auf Maps
  → Mögliche Ursache: Lightmap-Atlas-Koordinaten, WebGL2-Textur-Format

PATCH-003: Flashlight Null-Texture Fix
  → weliveinhell-Repo auf ähnliche Patches prüfen

PATCH-004: Water Render Fix
  → Symptom: Wasser vollständig schwarz
  → Reflection/Refraction Render-Target in WebGL2

PATCH-005: NPC Stability Fix
PATCH-006: Medkit/Battery Fix
PATCH-007: Gravity Gun Inventory Fix
PATCH-008: Crouch Rebind (Ctrl → C)
```

**Für jeden Patch:** .patch-Datei erzeugen und in ./patches/ ablegen

---

## Langfristige Aktionen — Phase 2+

### ACTION-009 — Alle HL2-Maps packen (nach Pilot d1_trainstation_01)
Nutze `emscripten/repackage.js` aus weliveinhell-Repo (knownMaps, baseGamePath konfigurieren).
.data-Dateien nach ./dist/maps/ packen.

### ACTION-010 — Audio-System debuggen → DEC-002 auslösen (BLK-007)
SDL2-Audio-Patch aus weliveinhell-Repo ist bereits eingebaut (ACTION-005).
Beim ersten Browser-Build Audio-Test: SDL2_mixer prüfen.
Symptome dokumentieren → DEC-002 entscheiden.

### ACTION-011 — Performance-Profiling (Phase 1.6)
Browser DevTools → Performance Tab.
WebGL-Draw-Calls messen (Ziel: <2000/Frame).
WASM-Binary-Größe optimieren (Ziel: <100 MB).

### ACTION-012 — EP1 Port vorbereiten (Phase 3)
ARC-03 (Episode One PROViSiON RAR) entpacken.
Interne Struktur analysieren und in inventory.md dokumentieren.

### ACTION-013 — EP2 Asset-Quelle recherchieren (Phase 3 / BLK-008)
ARC-04 ist entfernt — neue Quelle finden.

---

## Dateipflege-Protokoll

Nach jeder abgeschlossenen Action diese Dateien aktualisieren:

| Datei | Trigger |
|---|---|
| `TASK.md` | Nach jeder Action: Status von `[ ]` auf `[x]` |
| `inventory.md` | Nach ACTION-004 (GCF-Extraktion), ACTION-013 (EP2) |
| `source_map.json` | ~~ACTION-001~~ ✅ DONE, noch: ACTION-006 (DEC-001) |
| `task_graph.json` | Nach jedem Status-Update (node.status ändern) |
| `decisions.md` | Nach ACTION-006 (DEC-001), ACTION-010 (DEC-002) |
| `blockers.md` | ~~BLK-001~~ ✅ DONE, noch: BLK-003 nach ACTION-006 |
| `manifest.json` | Nach erstem Build (ACTION-007): build-Sektion befüllen |

---

## NÄCHSTE PHASE nach erstem Build (Stand: 2026-07-10 19:38)

### ACTION-009 — HL2-Assets beschaffen (ARC-01 downloaden)
**Priorität:** HOCH
**Status:** OFFEN
Ohne Game-Assets kann kein Browserlauf stattfinden. 
Benötigt: ARC-01 von archive.org (Half-Life-2-Retail-2153, ~4.8 GB)

```bash
cd /app/hl2-webxr-port/
wget -c "https://archive.org/download/Half-Life-2-Retail-2153/Half-Life-2-Retail-2153.7z" \
  -O assets/source/Half-Life-2-Retail-2153.7z
```

### ACTION-010 — Assets extrahieren und per-map .data Packs erzeugen
**Priorität:** HOCH (nach ACTION-009)
Nutze `emscripten/get_logs.sh` + `emscripten/repackage.js` aus portal-port.
Pilot: `d1_trainstation_01` (HL2) oder `testchmb_a_00` (Portal).

### ACTION-011 — Ersten Browser-Launch testen
**Priorität:** HOCH (nach ACTION-010)
Server mit COOP/COEP-Headern starten, .data Chunks laden, Browser-Konsole prüfen.

```bash
python3 -m http.server --bind 0.0.0.0 8080 &
# oder: npx serve -p 8080 --cors
```
Server muss senden:
- Cross-Origin-Opener-Policy: same-origin
- Cross-Origin-Embedder-Policy: require-corp

### BLK-003 — Build-2153 Asset-Kompatibilität
**Status:** OFFEN — erst testbar nach ACTION-009+010+011
