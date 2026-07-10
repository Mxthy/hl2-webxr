# Blockers
## HL2 WebGL2/WebXR Porting Manager

Zuletzt aktualisiert: 2026-07-10 19:00 (Europe/Berlin)

---

## Gelöste Blocker

### ~~BLK-001~~ — weliveinhell GitHub-URL ✅ GESCHLOSSEN
**Schweregrad:** HOCH → GELÖST
**Status:** GESCHLOSSEN — 2026-07-10 19:00
**Betrifft:** T-002, T-005 (Engine Build), T-009 (Patches), Asset-Packing-Skripte

**Lösung:**
Repository gefunden: **https://github.com/weliveinhell/source-engine**

Repo-Details:
- Public Fork von `nillerusr/source-engine` (61 Stars, 16 Forks)
- Live-Demo des Portal-Ports: `https://yikes.pw/portal/`
- Vollständiges `emscripten/`-Unterverzeichnis vorhanden:
  - `emscripten/repackage.js` — Asset-Packing-Skript (Node.js, konfigurierbar via `knownMaps`/`baseGamePath`)
  - `emscripten/get_logs.sh` — Asset-Logging-Skript (führt Engine aus, fängt printf-Output ab)
  - `emscripten/libwebgl.patch` — glMapBufferRange-Fix für Emscripten WebGL
  - `build_emscripten.sh` — vollständiger Emscripten-Build-Skript
- emsdk-Pinning: Commit `2d480a1b7c7a34a354188d93f3e89190a44a1d21`
- SDL2-Audio-Patch dokumentiert: `sed -Ei 's/freq = EM_ASM_INT/freq = MAIN_THREAD_EM_ASM_INT/'`
- Asset-Logging via printf-Patch in `filesystem/basefilesystem.cpp`:
  ```cpp
  FileHandle_t CBaseFileSystem::OpenForRead(...) {
      printf("OpenForRead %s %s\n", pFileNameT, pathID);
      ...
  }
  ```
- Per-Map `.data`-Chunk-System (Ziel: `./build/install/chunks/<mapName>.data`)

**Impact aufgehoben:**
- ✅ Asset-Packing-Skript verfügbar (Linux + Windows-Variante über slqnt)
- ✅ Emscripten-Build-Konfiguration für Source Engine verfügbar
- ✅ Bekannte Render-Fixes (libwebgl.patch) verfügbar
- ✅ Genaue emsdk-Version bekannt (kein Versionsraten mehr nötig)

**Nächster Schritt:**
```bash
git clone https://github.com/weliveinhell/source-engine ./engine/portal-port/
```
T-002 kann auf `done` gesetzt werden sobald geklont.

---

## Aktive Blocker

### BLK-002 — slqnt Port-Quellcode nicht öffentlich
**Schweregrad:** MITTEL (reduziert — weliveinhell-Basis jetzt verfügbar)
**Status:** OFFEN
**Betrifft:** T-009 (Patch-Implementierung)
**Auflösung:** ACTION-008 (Patches unabhängig implementieren)

**Problem:**
Der slqnt HL2-Browser-Port ist live spielbar unter `hl2.slqnt.dev`, aber der
Quellcode ist nach aktuellem Stand nicht öffentlich zugänglich. Die 8 bekannten
Patches sind im Blog-Artikel beschrieben, aber nicht als Code verfügbar.

**Update nach BLK-001-Auflösung:**
Das weliveinhell-Repo enthält einen Teil der Fixes (insbesondere `libwebgl.patch`
für den Lightmap-ähnlichen glMapBufferRange-Bug). Die slqnt-spezifischen
Gameplay-Patches (PATCH-002 bis PATCH-008) müssen weiterhin eigenständig
implementiert werden.

**Auflösungsschritte:**
1. weliveinhell-Repo auf vorhandene Patches durchsuchen (PATCH-003 Flashlight, PATCH-004 Wasser)
2. slqnt kontaktieren und nach Open-Source-Status fragen
3. Falls kein Quellcode: Patches eigenständig implementieren (ACTION-008)
4. Für Lightmap/NPC-Bugs: Valve Developer Community Wiki konsultieren

---

### BLK-003 — Build-2153-Kompatibilität mit nillerusr ungetestet
**Schweregrad:** HOCH
**Status:** OFFEN — Test erforderlich (ACTION-006)
**Betrifft:** T-006 (Asset Compatibility Test), T-007 (Map Packing)
**Auflösung:** ACTION-006 ausführen → DEC-001 entscheiden

**Problem:**
slqnt verwendet explizit den `steam_legacy`-Branch, weil die Post-Anniversary-Assets
nicht mit der nillerusr-Engine-Basis kompatibel sind. Build 2153 ist Pre-Anniversary.
Die genaue Art der Inkompatibilität ist nicht bekannt.

**Hinweis aus weliveinhell-Repo:**
weliveinhell nutzt für Portal ebenfalls VPK-Format (Steam-Rip), nicht GCF.
Dies erhöht das Risiko, dass ARC-01 (GCF-Format, 2004) Kompatibilitätsprobleme hat.

**Mögliche Inkompatibilitätstypen (INFERRED):**
- Asset-Format-Versionierung (GCF vs VPK)
- Unterschiedliche BSP-Version oder lightmap-Format
- Material-Shader-Unterschiede (Pre- vs Post-Anniversary)

**Impact:**
- Wenn inkompatibel: ARC-01 (einzige verfügbare Asset-Quelle) kann nicht direkt genutzt werden
- Fallback: Steam-Account + HL2-Kauf + steam_legacy Branch

**Auflösungsschritte:**
1. ARC-01-Assets in nillerusr-Engine-Verzeichnis kopieren (nach T-004)
2. Engine starten: Typ der Fehler dokumentieren
3. DEC-001 entscheiden (A: Build 2153 kompatibel / B: steam_legacy nötig)
4. source_map.json, manifest.json/assets.source aktualisieren
5. Diesen Blocker als GESCHLOSSEN oder ESKALIERT markieren

---

### BLK-004 — Archive.org-Quellen permanent entfernt (50%)
**Schweregrad:** NIEDRIG
**Status:** PERMANENT — kein Fix möglich
**Betrifft:** ARC-02, ARC-04

**Problem:**
- ARC-02 (Collector's Edition Build 2153) — von Archive.org entfernt
- ARC-04 (Complete Edition Linux Steam Rip) — von Archive.org entfernt

**Impact:**
- Phase 1: Kein direkter Impact (ARC-01 ist ausreichend)
- Phase 3: ARC-04 wäre ideal für EP1/EP2 + Linux-Build gewesen

**Workaround:**
- Phase 1: ARC-01 als primäre Quelle (ausreichend für HL2-Hauptkampagne)
- Phase 3 EP1: ARC-03 (Episode One PROViSiON, 1.4 GB — noch verfügbar)
- Phase 3 EP2: Neue Quelle suchen (ACTION-013)

---

## Latente Blocker (werden aktiv in späteren Phasen)

### BLK-005 — Face-Morphing-Bug-Ursache unbekannt
**Schweregrad:** LATENT
**Status:** LATENT — indefinitely deferred
**Phase:** Keine geplante Reaktivierung

**Problem:**
slqnt hat das Face-Morphing-System vollständig deaktiviert wegen Stabilitätsproblemen.
Die genaue Bug-Ursache ist unbekannt (CONFIRMED — Blog erwähnt nur "instability").

**Auswirkung wenn reaktiviert:** Unbekannt — möglicherweise Crash oder Korrumpierung
**Entscheidung:** DEC-FIXED-002 — System bleibt deaktiviert

---

### BLK-006 — WebXR API: Debugging-Komplexität
**Schweregrad:** LATENT
**Status:** LATENT — Phase 3
**Phase:** Phase 3 (WebXR-Integration)

**Problem:**
WebXR erfordert HTTPS, aktives VR-Headset oder Emulator, und Nutzergeste.
Browser-Debugging für WebXR ist komplexer als Desktop-VR-Debugging.

**Vorbereitungsmaßnahmen (wenn Phase 3 beginnt):**
- Chrome WebXR DevTools Extension installieren
- WebXR Emulator (Chrome Extension) für Desktop-Tests nutzen
- HTTPS-Deployment von Anfang an konfigurieren

---

### BLK-007 — Audio-System-Lösung unklar
**Schweregrad:** LATENT
**Status:** LATENT — wird aktiv bei erstem Browser-Build (T-008)
**Betrifft:** DEC-002 (Audio-System-Entscheidung)
**Auflösung:** ACTION-010

**Problem:**
slqnt's Blog-Artikel erwähnt das Audio-System nicht. Es ist unklar, welche
Audio-Bibliothek der Port nutzt. Die Source Engine verwendet OpenAL nativ,
aber Emscripten's OpenAL-Unterstützung ist begrenzt.

**Update nach BLK-001-Auflösung:**
Das weliveinhell-Repo enthält einen SDL2-Audio-Patch (MAIN_THREAD_EM_ASM_INT-Fix),
was darauf hindeutet, dass SDL2 für Audio genutzt wird. Dies bevorzugt DEC-002 Option A
(SDL2/OpenAL via Emscripten) oder Option C (SDL2_mixer). Kein direkter Web-Audio-API-Ansatz.

**Wird aktiv:** Sobald erster Browser-Build (T-008) läuft und Audio-Fehler sichtbar werden

---

### BLK-008 — EP2-Asset-Quelle fehlt
**Schweregrad:** LATENT
**Status:** LATENT — Phase 3
**Phase:** Phase 3 (Episode Two Port)
**Auflösung:** ACTION-013

**Problem:**
ARC-04 (Complete Edition Linux Steam Rip — enthielt EP2) wurde von Archive.org entfernt.
Keine alternative Archive.org-Quelle für Episode Two bekannt.

**Auflösungsoptionen für Phase 3:**
1. Neue Archive.org-Quelle suchen (ACTION-013)
2. Steam-Account + Episode Two + steam_legacy-Branch
3. Community-Kontakte im Source-Engine-Porting-Bereich

---

## Blocker-Zusammenfassung

| ID | Titel | Schweregrad | Phase | Status | Auflösung |
|---|---|---|---|---|---|
| ~~BLK-001~~ | weliveinhell URL unbekannt | ~~HOCH~~ | 1.0 | **GESCHLOSSEN 2026-07-10** | ✅ URL: github.com/weliveinhell/source-engine |
| BLK-002 | slqnt kein Open Source | MITTEL | 1.3/1.4 | OFFEN | ACTION-008 |
| BLK-003 | Build-2153 Kompatibilität ungetestet | HOCH | 1.2 | TEST AUSSTEHEND | ACTION-006 |
| BLK-004 | ARC-02+ARC-04 entfernt | NIEDRIG | 1.2 | PERMANENT | Workaround |
| BLK-005 | Face Morphing Bug-Ursache | LATENT | — | DEFERRED | DEC-FIXED-002 |
| BLK-006 | WebXR Debugging-Komplexität | LATENT | 3 | LATENT | Phase-3-Prep |
| BLK-007 | Audio-System unklar | LATENT | 1.1 | LATENT (SDL2-Hinweis) | ACTION-010 |
| BLK-008 | EP2-Quelle fehlt | LATENT | 3 | LATENT | ACTION-013 |


---

## Build-Status (2026-07-10 19:38)

Erster Emscripten-Build erfolgreich abgeschlossen.

| Artefakt | Größe | Status |
|---|---|---|
| hl2_launcher.wasm | 4.18 MB | ✅ VALID (magic b'\x00asm') |
| hl2_launcher.js | 1.1 MB | ✅ erzeugt |
| hl2_launcher.html | 6.5 KB | ✅ erzeugt |
| 25x *.so | ~46 MB total | ✅ in build/install/ |

**Build-Pfad:** `engine/portal-port/` (weliveinhell/source-engine, Commit 63f8364)
**Emscripten:** 4.0.9 (emsdk 2d480a1b)
**Flags:** Pthreads+SharedMemory, INITIAL_MEMORY=2047mb, FULL_ES3, PROXY_TO_PTHREAD

**Nächster Blocker:** BLK-003 (Asset-Kompatibilität) — erst testbar nach ARC-01-Download + Asset-Packing
