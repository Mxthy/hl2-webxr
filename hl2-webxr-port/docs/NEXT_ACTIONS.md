# Next Actions
## HL2 WebGL2/WebXR Porting Manager

Generated: 2026-07-10
Status: Bereit für Übergabe an nächsten Agenten oder Entwickler

---

## Sofortige Aktionen (Diese Woche)

### ACTION-001 — weliveinhell Repository finden
**Priorität:** KRITISCH
**Aufwand:** 0.5 Tage
**Verantwortlich:** TBD

```
1. GitHub öffnen
2. Suche: "weliveinhell" (Username)
3. Suche: "portal source engine browser emscripten"
4. Alternativ: slqnt auf GitHub kontaktieren
   → https://github.com/slqnt (spekulativ — verifizieren)
5. URL in source_map.json unter ENG-02 eintragen
6. Repo klonen unter ./engine/portal-port/
```

**Erfolgsmetrik:** Repository-URL bekannt, Repo geklont

---

### ACTION-002 — nillerusr/source-engine klonen & nativ bauen
**Priorität:** KRITISCH
**Aufwand:** 1-2 Tage
**Verantwortlich:** TBD
**Vorbedingung:** Linux-Build-System verfügbar

```bash
git clone https://github.com/nillerusr/source-engine
cd source-engine
# Build-System analysieren (CMake / Makefile / waf)
# Native Linux Build ausführen
# ToGLES-Modus testen
```

**Erfolgsmetrik:** Engine kompiliert, ToGLES-Modus verfügbar

---

### ACTION-003 — ARC-01 herunterladen
**Priorität:** HOCH
**Aufwand:** 0.5 Tage (+ Download-Zeit für 4.8 GB)

```
URL: https://archive.org/details/Half-Life-2-Retail-2153
Format: 7Z (bevorzugt) oder Torrent
Ziel: ./assets/raw/arc-01/
Integrität: Dateigröße und Struktur prüfen
```

**Erfolgsmetrik:** 7Z-Archiv vollständig heruntergeladen

---

### ACTION-004 — GCF-Extraktion testen
**Priorität:** HOCH
**Aufwand:** 1 Tag
**Vorbedingung:** ACTION-003 abgeschlossen

```
1. GCFExplorer aus ARC-01/Misc/ extrahieren
2. halflife 2 base content.gcf öffnen
3. Key eingeben: 187D516D65C617EB6FE90FB20211DEC6
4. Alle Dateien extrahieren
5. Verzeichnisstruktur dokumentieren
6. Gleiche Schritte für shared materials, models, sounds
```

**Erfolgsmetrik:** Alle Assets extrahiert, Verzeichnisstruktur in inventory.md ergänzt

---

### ACTION-005 — Emscripten SDK installieren
**Priorität:** HOCH
**Aufwand:** 0.5 Tage

```bash
git clone https://github.com/emscripten-core/emsdk
cd emsdk
./emsdk install latest
./emsdk activate latest
source ./emsdk_env.sh
emcc --version  # verifizieren
```

**Erfolgsmetrik:** `emcc --version` gibt stabile Version aus

---

## Mittelfristige Aktionen (Nächste 2 Wochen)

### ACTION-006 — Asset-Kompatibilitätstest (DEC-001 auslösen)
**Priorität:** HOCH
**Vorbedingung:** ACTION-002, ACTION-004

```
1. Extrahierte ARC-01-Assets in nillerusr-Engine-Verzeichnis kopieren
2. Engine starten
3. HL2-Main-Menü laden versuchen
4. Fehlertypen dokumentieren
5. Wenn Fehler: steam_legacy-Assets beschaffen (Steam-Account nötig)
6. Ergebnis → DEC-001 entscheiden → source_map.json aktualisieren
```

---

### ACTION-007 — Ersten Emscripten-Build ausführen
**Priorität:** HOCH
**Vorbedingung:** ACTION-002, ACTION-005

```bash
cd source-engine
emcc [FLAGS aus pipeline.yaml Stage 5] \
  -o ./dist/hl2.js \
  [source files]
# Fehler dokumentieren, iterativ beheben
```

---

### ACTION-008 — Bekannte Patches implementieren
**Priorität:** MITTEL
**Vorbedingung:** ACTION-007 (erster Build muss existieren)

Reihenfolge:
1. PATCH-001: Face Morphing Disable (als erstes — Stabilität)
2. PATCH-002: Lightmap Fix
3. PATCH-003: Flashlight Fix
4. PATCH-004: Water Render Fix
5. PATCH-005+006: NPC + Medkit Fixes
6. PATCH-007: Gravity Gun Fix
7. PATCH-008: Crouch Rebind

**Ressource:** slqnt-Blog als Beschreibungsbasis, weliveinhell-Repo für Code-Referenz

---

## Langfristige Aktionen (Phase 2+)

### ACTION-009 — Alle Maps packen (nach Pilot-Erfolg)
Wenn d1_trainstation_01 erfolgreich gepackt und geladen → alle HL2-Maps

### ACTION-010 — Audio-System debuggen (DEC-002 auslösen)
Wenn Engine im Browser läuft → Audio-Test

### ACTION-011 — Performance-Profiling
Phase 1.6 — Browser DevTools + WebGL Inspector

### ACTION-012 — EP1 Port vorbereiten (Phase 3)
Nach vollständiger Phase 1 — ARC-03 analysieren, EP1-Asset-Pipeline

---

## Dateien die noch gepflegt werden müssen

Nach jeder Aktion diese Dateien aktualisieren:

| Datei | Wann aktualisieren |
|---|---|
| `inventory.md` | Nach jeder Asset-Entdeckung |
| `source_map.json` | Nach URL-Funden (weliveinhell) |
| `task_graph.json` | Nach jedem Aufgaben-Status-Update |
| `decisions.md` | Nach jeder Entscheidung |
| `blockers.md` | Wenn Blocker geöffnet/geschlossen |
| `manifest.json` | Nach jedem Build |
| `NEXT_ACTIONS.md` | Wöchentlich |

---

## Übergabe-Checkliste für nächsten Agenten

- [ ] Reference Analysis gelesen (`reference_analysis.md`)
- [ ] Blockers verstanden (`blockers.md`)
- [ ] Decisions gelesen (`decisions.md`)
- [ ] Task Graph geladen (`task_graph.json`)
- [ ] ACTION-001 (weliveinhell URL) als erstes ausgeführt
- [ ] Kein Sub-Agent ohne explizite Erlaubnis starten
