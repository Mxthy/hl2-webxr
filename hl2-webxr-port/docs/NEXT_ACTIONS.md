# Next Actions
## HL2 WebGL2/WebXR Porting Manager

Zuletzt aktualisiert: 2026-07-10 17:53 (Europe/Berlin)
Status: Analyse abgeschlossen — Projektbasis vollständig dokumentiert

---

## AKTIVE BLOCKER (als TODOs eingetragen)

Diese Blocker müssen aufgelöst werden, bevor Phase 1 beginnt.
Vollständige Beschreibungen: `blockers.md`

| ID | Blocker | Priorität | Lösung |
|---|---|---|---|
| BLK-001 | weliveinhell GitHub-URL unbekannt | KRITISCH | ACTION-001 |
| BLK-002 | slqnt Port-Quellcode nicht öffentlich | MITTEL | ACTION-008 (unabhängig implementieren) |
| BLK-003 | Build-2153 ↔ nillerusr Kompatibilität ungetestet | HOCH | ACTION-006 |
| BLK-004 | ARC-02 + ARC-04 permanent entfernt | NIEDRIG | Workaround: ARC-01 (Phase 1), ARC-03 (Phase 3) |
| BLK-007 | Audio-System-Lösung unklar | LATENT | ACTION-010 |
| BLK-008 | EP2-Asset-Quelle fehlt | LATENT | Phase 3 — neu recherchieren |

---

## Sofortige Aktionen — Diese Woche

### ACTION-001 — weliveinhell GitHub-URL finden (BLK-001)
**Priorität:** KRITISCH — blockiert ACTION-002, ACTION-008
**Aufwand:** 0.5 Tage

```
Schritt 1: GitHub öffnen → Profile-Suche: "weliveinhell"
  URL: https://github.com/weliveinhell

Schritt 2: Falls kein direkter Treffer:
  → GitHub-Suche: "portal source engine emscripten browser"
  → GitHub-Suche: "source-engine wasm webgl portal"
  → Suche in nillerusr/source-engine Issues/Forks

Schritt 3: Falls immer noch kein Treffer:
  → slqnt auf Discord/GitHub kontaktieren:
    Blog: https://www.slqnt.dev/blog/hl2-in-web
    GitHub spekulativ: https://github.com/slqnt (verifizieren)

Schritt 4 (nach Fund):
  → URL in source_map.json unter ENG-02 ("url") eintragen
  → Repo klonen: git clone <URL> ./engine/portal-port/
  → Asset-Packing-Skript sichern: ./tools/asset-packer/
  → BLK-001 in blockers.md als GESCHLOSSEN markieren
```

**Erfolgsmetrik:** Repository-URL bekannt, Repo geklont, Packing-Skript verfügbar

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

# Bei waf-Build:
python3 waf configure
python3 waf build

# Bei cmake:
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)

# ToGLES-Modus prüfen:
grep -r "TOGLES\|ToGLES\|gles" --include="*.cpp" --include="*.h" -l | head -20
```

**Erfolgsmetrik:** Engine kompiliert nativ, ToGLES-Modus-Dateien gefunden

---

### ACTION-003 — ARC-01 herunterladen
**Priorität:** HOCH
**Aufwand:** 0.5 Tage + Download-Zeit (4.8 GB)

```bash
# Zielverzeichnis anlegen
mkdir -p ./assets/raw/arc-01

# Download (Torrent empfohlen für große Dateien):
# URL: https://archive.org/details/Half-Life-2-Retail-2153
# Torrent-Datei herunterladen → in Client einlesen
# Oder: ia download Half-Life-2-Retail-2153 (Internet Archive CLI)

# Nach Download — Integrität prüfen:
ls -la ./assets/raw/arc-01/
# Erwartete Dateien: Half-Life-2.7z, Patches-and-Misc.7z, ISOs

# Entpacken:
7z x ./assets/raw/arc-01/Half-Life-2.7z -o./assets/raw/arc-01/extracted/
```

**Erfolgsmetrik:** 7Z vollständig entpackt, GCF-Dateien sichtbar

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

WICHTIG: Keys müssen manuell eingetippt werden (kein Copy-Paste in GCFExplorer).
         Menü: Tools → Set Encryption Key vor jeder Extraktion.

Nach Extraktion:
→ Verzeichnisstruktur in inventory.md unter "Asset-Verzeichnis (nach Extraktion)" ergänzen
→ Anzahl BSP-Dateien in ./assets/hl2/maps/ zählen und dokumentieren
```

**Erfolgsmetrik:** Alle 5 GCF-Dateien extrahiert, BSP-Dateien in ./assets/hl2/maps/ sichtbar

---

### ACTION-005 — Emscripten SDK installieren und verifizieren
**Priorität:** HOCH
**Aufwand:** 0.5 Tage

```bash
git clone https://github.com/emscripten-core/emsdk.git ./tools/emsdk
cd ./tools/emsdk
./emsdk install latest
./emsdk activate latest
source ./emsdk_env.sh

# Verifizieren:
emcc --version
em++ --version
emcmake --version

# Ergebnis in TASK.md als abgeschlossen markieren
```

**Erfolgsmetrik:** `emcc --version` gibt Versionsnummer aus, kein Fehler

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
**Vorbedingung:** ACTION-002 (Engine-Build), ACTION-005 (Emscripten)

```bash
cd ./engine/source-engine
source ../../tools/emsdk/emsdk_env.sh

# Minimaler erster Build (aus pipeline.yaml Stage 5):
emcc \
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
  -sEXIT_RUNTIME=0 \
  -o ../../dist/hl2.js \
  [source files gemäß Engine-Build-System]

# Alle Compiler-Fehler in separater Datei dokumentieren:
# → ./docs/build-errors-01.txt
```

**Erfolgsmetrik:** hl2.wasm + hl2.js erzeugt, Browser lädt die Seite ohne sofortigen Crash

---

### ACTION-008 — Bekannte Patches implementieren (BLK-002)
**Priorität:** MITTEL
**Vorbedingung:** ACTION-007 (erster Build muss laufen)

Patches in dieser Reihenfolge implementieren:

```
PATCH-001: Face Morphing Disable
  → Flex-System deaktivieren (Search: "flexcontroller", "CFlexAnimatingGameobject")
  → In Engine-Source: #define NO_FACE_MORPHING oder direktes Auskommentieren
  → Referenz: slqnt-Blog ("had to just disable the entire system")

PATCH-002: Lightmap Fix
  → Symptom: Random color flickering auf Maps
  → Mögliche Ursache: Lightmap-Atlas-Koordinaten, WebGL2-Textur-Format
  → Referenz: slqnt-Blog (bestätigt behoben, kein Code verfügbar)

PATCH-003: Flashlight Null-Texture Fix
  → Symptom: Flashlight zeigt Null-Texture
  → Asset-Loading-Pfad für Flashlight-Textur prüfen

PATCH-004: Water Render Fix
  → Symptom: Wasser vollständig schwarz
  → Reflection/Refraction Render-Target in WebGL2

PATCH-005: NPC Stability Fix
  → Symptom: NPCs kollabieren und sterben zufällig
  → Contrib "98" in slqnt-Port (Implementierung unbekannt)

PATCH-006: Medkit/Battery Fix
  → Symptom: Pickup-Items funktionieren nicht
  → Contrib "98" in slqnt-Port

PATCH-007: Gravity Gun Inventory Fix
  → Symptom: Gravity Gun nicht im Inventar nach Vergabe

PATCH-008: Crouch Rebind
  → Ctrl → C
  → Engine-Keybind-Konfigurationsdatei anpassen
  → Oder: JavaScript-Event-Handler im Shell-HTML
```

**Für jeden Patch:** .patch-Datei erzeugen und in ./patches/ ablegen

---

## Langfristige Aktionen — Phase 2+

### ACTION-009 — Alle HL2-Maps packen (nach Pilot d1_trainstation_01)
Map-Liste aus BSP-Dateien in ./assets/hl2/maps/ ableiten.
Logging-Skript für jede Map ausführen.
.data-Dateien nach ./dist/maps/ packen.

### ACTION-010 — Audio-System debuggen → DEC-002 auslösen (BLK-007)
Wenn erster Browser-Build läuft: Audio-Test.
OpenAL-Emulation via Emscripten prüfen (`-lopenal` oder `-sUSE_SDL_MIXER`).
Symptome dokumentieren.

### ACTION-011 — Performance-Profiling (Phase 1.6)
Browser DevTools → Performance Tab
WebGL-Draw-Calls messen (Ziel: <2000/Frame)
WASM-Binary-Größe optimieren (Ziel: <100 MB)

### ACTION-012 — EP1 Port vorbereiten (Phase 3)
ARC-03 (Episode One PROViSiON RAR) entpacken.
Interne Struktur analysieren und in inventory.md dokumentieren.
EP1-Map-Liste erstellen.

### ACTION-013 — EP2 Asset-Quelle recherchieren (Phase 3 / BLK-008)
ARC-04 ist entfernt — neue Quelle finden.
Archive.org-Suche: "half-life 2 episode two"
Alternativ: Steam-Account mit Episode Two (steam_legacy Branch)

---

## Dateipflege-Protokoll

Nach jeder abgeschlossenen Action diese Dateien aktualisieren:

| Datei | Trigger |
|---|---|
| `TASK.md` | Nach jeder Action: Status von `[ ]` auf `[x]` |
| `inventory.md` | Nach ACTION-004 (GCF-Extraktion), ACTION-013 (EP2) |
| `source_map.json` | Nach ACTION-001 (weliveinhell URL), ACTION-006 (DEC-001) |
| `task_graph.json` | Nach jedem Status-Update (node.status ändern) |
| `decisions.md` | Nach ACTION-006 (DEC-001), ACTION-010 (DEC-002) |
| `blockers.md` | BLK-001 nach ACTION-001 schließen, BLK-003 nach ACTION-006 |
| `manifest.json` | Nach erstem Build (ACTION-007): build-Sektion befüllen |
| `NEXT_ACTIONS.md` | Wöchentlich / nach großen Fortschritten |

---

## Übergabe-Checkliste für nächsten Agenten oder Entwickler

Vor dem Start lesen:
- [ ] `reference_analysis.md` — Quelle-für-Quelle-Analyse
- [ ] `blockers.md` — Aktive Blocker verstehen
- [ ] `decisions.md` — Was bereits entschieden ist (DEC-FIXED-*)
- [ ] `architecture.md` — Technischer Stack
- [ ] `task_graph.json` — Dependencies zwischen Tasks

Erster Schritt zwingend:
- [ ] **ACTION-001** ausführen (weliveinhell URL finden) — löst BLK-001

Regeln:
- [ ] Kein Sub-Agent ohne explizite Erlaubnis des Owners
- [ ] Jede neue Annahme in `assumptions.md` eintragen
- [ ] Jeden neuen Blocker sofort in `blockers.md` eintragen
- [ ] Keine WebXR-Implementierung vor stabiler WebGL2-Basis (DEC-FIXED-001)
- [ ] Keine Face-Morphing-Reaktivierung (DEC-FIXED-002)
- [ ] Unsicherheiten immer mit CONFIRMED / INFERRED / UNKNOWN markieren
