# PROJECT PLAN
## HL2 WebGL2/WebXR Porting Manager

Generated: 2026-07-10
Stand: Initialer Plan basierend auf Link-Analyse (kein Code, kein lokales Asset)

---

## Projektziel

Einen vollständig im Browser spielbaren Port von Half-Life 2 auf Basis von
WebGL2 (Phase 1) und optional WebXR (Phase 3) erstellen, unter Nutzung des
nillerusr/source-engine Forks mit ToGLES-Rendering-Modus via Emscripten.

Referenz: slqnt.dev/blog/hl2-in-web (CONFIRMED funktionierender Port, Juni 2026)

---

## Phasen-Übersicht

### Phase 1 — WebGL2-Basis (Hauptkampagne)
**Ziel:** HL2-Hauptkampagne vollständig im Browser spielbar
**Zeitrahmen:** 3-6 Wochen (SEHR UNSICHER, INFERRED)

| Schritt | Beschreibung | Status |
|---|---|---|
| 1.0 | Environment Setup | PENDING |
| 1.1 | Engine Build + Emscripten | PENDING |
| 1.2 | Asset Pipeline | PENDING |
| 1.3 | Render Debug | PENDING |
| 1.4 | Gameplay Bug Fixes | PENDING |
| 1.5 | Save System (IDBFS) | PENDING |
| 1.6 | QA & Stabilisierung | PENDING |

**Kritische Abhängigkeit:** DEC-001 (Asset-Quelle) muss in Phase 1.2 entschieden werden

---

### Phase 2 — Extended Features (optional)
**Ziel:** Erweiterte Features, bessere UX
**Zeitrahmen:** 2-4 Wochen (SEHR UNSICHER)

| Feature | Status |
|---|---|
| Cloud Save / Cross-Device Sync | OPTIONAL — DEC-002 |
| Performance-Optimierungen | Abhängig von Phase-1-Ergebnissen |
| Web Dashboard für Build-Status | OPTIONAL |
| Audio-System-Verbesserungen | Abhängig von BLK-007-Auflösung |
| Threading (Pthreads) | OPTIONAL — DEC-003 |

---

### Phase 3 — WebXR + Episodes
**Ziel:** VR-Modus + Episode One & Two
**Zeitrahmen:** 4-8 Wochen (SEHR UNSICHER)

| Feature | Status |
|---|---|
| WebXR Device API Integration | PENDING |
| VR Input (Controller) | PENDING |
| VR Interaction Patterns (aus HL2VRU) | DESIGN-REFERENZ |
| Episode One Port | PENDING — ARC-03 |
| Episode Two Port | PENDING — Quelle UNKNOWN |

**Voraussetzung:** Phase 1 vollständig abgeschlossen

---

## Technologie-Stack

| Schicht | Technologie | Status |
|---|---|---|
| Engine | nillerusr/source-engine (ToGLES) | CONFIRMED |
| Compiler | Emscripten (emcc) | CONFIRMED |
| Rendering | WebGL2 | CONFIRMED |
| Filesystem | MEMFS + IDBFS | CONFIRMED |
| Input | Pointer Lock + Keyboard | CONFIRMED |
| Audio | UNKNOWN | BLK-007 |
| VR (Phase 3) | WebXR Device API | PLANNED |

---

## Risiko-Matrix

| Risiko | Wahrscheinlichkeit | Impact | Mitigation |
|---|---|---|---|
| Build-2153 inkompatibel | HOCH | HOCH | Fallback: steam_legacy |
| weliveinhell Repo nicht auffindbar | MITTEL | HOCH | Eigenentwicklung Packing-Skript |
| slqnt Port bleibt closed-source | HOCH | MITTEL | Patches re-implementieren |
| Audio-System komplex | MITTEL | MITTEL | OpenAL via Emscripten testen |
| WASM-Binary zu groß | MITTEL | MITTEL | Size-Optimierungen, Code-Splitting |
| Browser-Inkompatibilität | NIEDRIG | NIEDRIG | Chrome als Primärziel |
| Archive.org weitere Takedowns | NIEDRIG | NIEDRIG | ARC-01 lokal gesichert |

---

## Ressourcen-Anforderungen

- Linux-Build-Maschine (mind. 16 GB RAM, 100 GB Disk) — INFERRED
- Steam-Account mit HL2 (für steam_legacy, falls BLK-003 zutrifft) — MÖGLICHERWEISE NÖTIG
- Web-Server mit COOP/COEP-Header-Support — NÖTIG für Deployment
- CDN für .data-Files — EMPFOHLEN (große Dateien)

---

## Erfolgskriterien Phase 1

- [ ] Engine kompiliert via Emscripten ohne Fehler
- [ ] HL2 Hauptmenü lädt im Browser
- [ ] Pilot-Map `d1_trainstation_01` spielbar
- [ ] Alle bekannten Bugs aus slqnt-Liste behoben
- [ ] Save/Load über IDBFS funktioniert
- [ ] Vollständige Hauptkampagne durchspielbar
- [ ] Getestet in Chrome, Firefox, Edge

---

## Nächster Schritt

→ Siehe `NEXT_ACTIONS.md`, ACTION-001 (weliveinhell URL finden)
→ Alle Blockers lösen bevor Phase 1.1 beginnt
