# Blockers
## HL2 WebGL2/WebXR Porting Manager

Zuletzt aktualisiert: 2026-07-10 18:13 (Europe/Berlin)

---

## Aktive Blocker

### BLK-001 — weliveinhell GitHub-URL unbekannt
**Schweregrad:** HOCH
**Status:** OFFEN
**Betrifft:** T-002, T-005 (Engine Build), T-009 (Patches), Asset-Packing-Skripte
**Auflösung:** ACTION-001

**Problem:**
slqnt erwähnt "weliveinhell on github" als Autor des Portal-Browser-Ports und der
Asset-Packing-Skripte. Die genaue Repository-URL ist aus allen analysierten Quellen
nicht ableitbar (CONFIRMED — kein direkter Link im Blog-Artikel).

**Impact:**
Ohne das weliveinhell-Repo fehlt der direkte Zugang zu:
- Bewährtem Asset-Packing-Skript (Linux-Version, slqnt-Windows-Mod als Basis)
- Emscripten-Build-Konfiguration für Source Engine
- Möglicherweise bekannten Render-Fixes

**Auflösungsschritte:**
1. GitHub-Profile-Suche: `github.com/weliveinhell` (direkt versuchen)
2. GitHub-Suche: `"portal" "source engine" "emscripten" "browser"`
3. Forks von `nillerusr/source-engine` durchsuchen
4. slqnt kontaktieren (GitHub/Discord): `https://www.slqnt.dev`
5. Nach Fund: URL in `source_map.json` unter `ENG-02.url` eintragen,
   Repo klonen nach `./engine/portal-port/`, diesen Blocker schließen

---

### BLK-002 — slqnt Port-Quellcode nicht öffentlich
**Schweregrad:** MITTEL
**Status:** OFFEN
**Betrifft:** T-009 (Patch-Implementierung)
**Auflösung:** ACTION-008 (Patches unabhängig implementieren)

**Problem:**
Der slqnt HL2-Browser-Port ist live spielbar unter `hl2.slqnt.dev`, aber der
Quellcode ist nach aktuellem Stand nicht öffentlich zugänglich. Die 8 bekannten
Patches sind im Blog-Artikel beschrieben, aber nicht als Code verfügbar.

**Impact:**
Alle 8 Patches müssen unabhängig implementiert werden, basierend auf:
- Blog-Beschreibungen (symptom-orientiert, keine Code-Details)
- Engine-Source-Code-Analyse (nillerusr-Repo)
- Community-Ressourcen (Source-Engine-Modding-Foren)

**Auflösungsschritte:**
1. slqnt kontaktieren und nach Open-Source-Status fragen
2. Falls kein Quellcode: Patches eigenständig implementieren (ACTION-008)
3. Für Lightmap/NPC-Bugs: Valve Developer Community Wiki konsultieren
4. weliveinhell-Repo (BLK-001) enthält möglicherweise Teile der Fixes

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

**Mögliche Lösungen (INFERRED):**
- A: OpenAL via Emscripten (`-lopenal` — Emscripten enthält OpenAL-Port)
- B: SDL2_mixer (`-sUSE_SDL_MIXER`) — einfacher, limitierter
- C: Web Audio API direkt (`-sAUDIO_WORKLET`) — maximale Kontrolle, mehr Arbeit

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
| BLK-001 | weliveinhell URL unbekannt | HOCH | 1.0 | OFFEN | ACTION-001 |
| BLK-002 | slqnt kein Open Source | MITTEL | 1.3/1.4 | OFFEN | ACTION-008 |
| BLK-003 | Build-2153 Kompatibilität ungetestet | HOCH | 1.2 | TEST AUSSTEHEND | ACTION-006 |
| BLK-004 | ARC-02+ARC-04 entfernt | NIEDRIG | 1.2 | PERMANENT | Workaround |
| BLK-005 | Face Morphing Bug-Ursache | LATENT | — | DEFERRED | DEC-FIXED-002 |
| BLK-006 | WebXR Debugging-Komplexität | LATENT | 3 | LATENT | Phase-3-Prep |
| BLK-007 | Audio-System unklar | LATENT | 1.1 | LATENT | ACTION-010 |
| BLK-008 | EP2-Quelle fehlt | LATENT | 3 | LATENT | ACTION-013 |
