# TASK
## HL2 WebGL2/WebXR Porting Manager — Aktuelle Aufgabenliste

Zuletzt aktualisiert: 2026-07-10 18:13 (Europe/Berlin)
Format: Flat-List, nach Priorität sortiert.
Detailbeschreibungen aller Actions → NEXT_ACTIONS.md

---

## KRITISCH — Sofort (Phase 1.0)

- [ ] **ACTION-001** — weliveinhell GitHub-Repo-URL herausfinden [BLK-001]
  - GitHub: Suche nach Username "weliveinhell"
  - Fallback: slqnt kontaktieren (Discord/GitHub)
  - Nach Fund: URL in source_map.json (ENG-02) + BLK-001 schließen

- [ ] **ACTION-002** — nillerusr/source-engine klonen & nativ bauen
  - `git clone https://github.com/nillerusr/source-engine ./engine/source-engine`
  - Build-System identifizieren (waf / cmake / make)
  - ToGLES-Modus verifizieren

- [ ] **ACTION-003** — ARC-01 herunterladen (4.8 GB)
  - URL: archive.org/details/Half-Life-2-Retail-2153
  - Ziel: ./assets/raw/arc-01/
  - 7Z entpacken

- [ ] **ACTION-005** — Emscripten SDK installieren und verifizieren
  - `git clone https://github.com/emscripten-core/emsdk ./tools/emsdk`
  - `./emsdk install latest && ./emsdk activate latest`
  - `emcc --version` muss erfolgreich sein

---

## HOCH — Nächste Woche (Phase 1.1 / 1.2)

- [ ] **ACTION-004** — GCF-Extraktion (alle 5 Dateien) [nach ACTION-003]
  - GCFExplorer aus ARC-01/Misc/ — Keys aus manifest.json/assets.gcf_files
  - Ziel: ./assets/hl2/ und ./assets/shared/

- [ ] **ACTION-006** — Asset-Kompatibilitätstest → **DEC-001 entscheiden** [BLK-003]
  - Vorbedingung: ACTION-002 + ACTION-004
  - ARC-01-Assets in Engine laden → Fehler dokumentieren
  - Ergebnis: DEC-001 A (Build 2153 OK) oder B (steam_legacy nötig)

- [ ] **ACTION-007** — Ersten Emscripten-Build ausführen
  - Vorbedingung: ACTION-002 + ACTION-005
  - Flags aus pipeline.yaml Stage 5 anwenden
  - Fehler in ./docs/build-errors-01.txt dokumentieren

---

## MITTEL — Nächste 2 Wochen (Phase 1.2-1.4)

- [ ] **T-007** — Asset-Logging + Pilot-Map d1_trainstation_01 packen
  - Vorbedingung: ACTION-006 abgeschlossen (DEC-001 entschieden)
  - Print-Statement-Logging aktivieren, Durchlauf machen
  - .data + .js mit file_packager.py erzeugen

- [ ] **ACTION-008** — Alle 8 Patches implementieren [BLK-002 beachten]
  - Vorbedingung: ACTION-007 (erster Build muss laufen)
  - Reihenfolge: PATCH-001 → 002 → 003 → 004 → 005 → 006 → 007 → 008
  - Jeden Patch als .patch-Datei in ./patches/ ablegen
  - manifest.json patches[].applied updaten

---

## NIEDRIG — Phase 1.5-1.6

- [ ] **T-010** — IDBFS Save System integrieren [nach ACTION-008]
  - `-sFETCH_SUPPORT_INDEXEDDB=1` verifizieren
  - FS.syncfs() Aufrufe implementieren
  - Save/Load-Zyklus testen

- [ ] **ACTION-009** — Alle Maps packen [nach T-007 Pilot-Erfolg]
  - BSP-Liste aus ./assets/hl2/maps/ ableiten
  - Für jede der 39 Maps im manifest.json: Log + .data Pack

- [ ] **ACTION-010** — Audio-System debuggen → DEC-002 auslösen [BLK-007]
  - Nach erstem Browser-Build (ACTION-007)
  - OpenAL vs SDL2_mixer vs Web Audio testen

- [ ] **ACTION-011** — Performance-Profiling [Phase 1.6]
  - Browser DevTools Performance Tab
  - WebGL-Draw-Calls < 2000/Frame anstreben
  - WASM-Größe optimieren

- [ ] **T-012** — QA & Cross-Browser-Test [Phase 1.6]
  - Vollständige Kampagne durchspielen
  - Chrome, Firefox, Edge testen
  - manifest.json maps[].tested auf true setzen

---

## PHASE 3 — Langfristig

- [ ] **ACTION-012** — EP1 Port vorbereiten
  - ARC-03 (Episode One RAR) entpacken + Struktur analysieren
  - inventory.md EP1-Sektion befüllen

- [ ] **ACTION-013** — EP2 Asset-Quelle recherchieren [BLK-008]
  - ARC-04 entfernt — neue Quelle finden
  - Archive.org-Suche: "half-life 2 episode two"
  - Alternativ: Steam steam_legacy + Episode Two

- [ ] **DEC-004** — WebXR Runtime entscheiden
  - WebXR Device API (nativ) oder Polyfill
  - Nach Abschluss Phase 1

---

## AUSSTEHENDE ENTSCHEIDUNGEN

- [ ] **DEC-001** — Asset-Quelle (Trigger: ACTION-006)
- [ ] **DEC-002** — Audio-System (Trigger: ACTION-007/010)
- [ ] **DEC-003** — Threading/Pthreads (Trigger: ACTION-011)
- [ ] **DEC-004** — WebXR Runtime (Trigger: Phase 3 Start)

---

## ABGESCHLOSSEN

### Analyse-Phase (2026-07-10)
- [x] Quelle 1 analysiert: slqnt Browser-Port (hl2-in-web)
- [x] Quelle 2 analysiert: HL2VRU (vittorioromeo/HL2VRU)
- [x] Quelle 3a analysiert: Emscripten OpenGL Support
- [x] Quelle 3b analysiert: Emscripten Settings Reference
- [x] Quelle 4a analysiert: ARC-01 (Retail 2153) — VERFÜGBAR
- [x] Quelle 4b analysiert: ARC-02 (Collector's Edition) — ENTFERNT
- [x] Quelle 4c analysiert: ARC-03 (Episode One) — VERFÜGBAR
- [x] Quelle 4d analysiert: ARC-04 (Complete Edition Linux) — ENTFERNT

### Artefakte erstellt (2026-07-10)
- [x] docs/reference_analysis.md
- [x] docs/inventory.md
- [x] docs/architecture.md
- [x] docs/assumptions.md
- [x] docs/blockers.md
- [x] docs/decisions.md
- [x] docs/directory-tree.txt (aktualisiert 2026-07-10T17:53)
- [x] docs/porting_manager_spec.md
- [x] docs/runtime_matrix.md
- [x] docs/save_state_options.md
- [x] docs/PHASE_1_BUILDPLAN.md
- [x] docs/PROJECT_PLAN.md
- [x] docs/TASK.md (dieses Dokument, aktualisiert 2026-07-10T17:53)
- [x] docs/NEXT_ACTIONS.md (aktualisiert 2026-07-10T17:53 — Blocker als TODOs)
- [x] config/source_map.json
- [x] config/asset_taxonomy.json
- [x] config/manifest.schema.json
- [x] config/manifest.json (korrigiert 2026-07-10T17:53 — Emscripten-Basis, 39 Maps, 8 Patches)
- [x] config/pipeline.yaml
- [x] config/task_graph.json (aktualisiert 2026-07-10T17:53 — 4 Decisions, 6 Blocker)
