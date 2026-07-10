# TASK
## HL2 WebGL2/WebXR Porting Manager — Aktuelle Aufgabenliste

Generated: 2026-07-10
Format: Flat-List, nach Priorität sortiert

---

## KRITISCH — Sofort

- [ ] **ACTION-001** — weliveinhell GitHub-Repo-URL herausfinden
  - Suche: github.com/weliveinhell
  - Fallback: slqnt kontaktieren
  - Ziel: URL in source_map.json (ENG-02) eintragen

- [ ] **T-001** — Build-Environment einrichten
  - Emscripten SDK installieren
  - nillerusr/source-engine klonen
  - GCFExplorer bereitstellen

- [ ] **ACTION-003** — ARC-01 herunterladen
  - URL: archive.org/details/Half-Life-2-Retail-2153
  - Format: 7Z (4.8 GB)

---

## HOCH — Diese Woche

- [ ] **T-002** — weliveinhell URL auflösen (= ACTION-001)
- [ ] **T-003** — ARC-01 herunterladen (= ACTION-003)
- [ ] **ACTION-005** — Emscripten SDK installieren und verifizieren

---

## MITTEL — Nächste Woche

- [ ] **T-004** — GCF-Extraktion mit GCFExplorer
  - Alle 5 relevanten GCF-Dateien extrahieren
  - Keys aus ARC-01 README nutzen

- [ ] **T-005** — nillerusr/source-engine nativ bauen (Linux)
  - Build-System identifizieren
  - ToGLES-Modus verifizieren

- [ ] **T-006** — Asset-Kompatibilitätstest (**DEC-001 auslöser**)
  - ARC-01-Assets mit nillerusr-Engine testen
  - Ergebnis dokumentieren

- [ ] **T-007** — Asset-Logging + Pilot-Map packen
  - Map: d1_trainstation_01
  - .data-Datei erzeugen

- [ ] **T-008** — Ersten Emscripten-Build ausführen
  - Flags aus pipeline.yaml nutzen
  - Fehler dokumentieren und beheben

---

## NIEDRIG — Phase 1.3+

- [ ] **T-009** — Alle 8 Patches implementieren
  - PATCH-001: Face Morphing Disable (höchste Priorität)
  - PATCH-002: Lightmap Fix
  - PATCH-003: Flashlight Fix
  - PATCH-004: Water Render Fix
  - PATCH-005: NPC Stability
  - PATCH-006: Medkit/Battery Fix
  - PATCH-007: Gravity Gun Fix
  - PATCH-008: Crouch Rebind (C statt Ctrl)

- [ ] **T-010** — IDBFS Save System integrieren
- [ ] **T-011** — Alle Maps packen (nach Pilot-Erfolg)
- [ ] **T-012** — QA & Cross-Browser-Test

---

## ENTSCHEIDUNGEN AUSSTEHEND

- [ ] **DEC-001** — Asset-Quelle: Build 2153 vs steam_legacy
  → Trigger: T-006 Ergebnis
- [ ] **DEC-002** — Audio-System
  → Trigger: Erster Browser-Build
- [ ] **DEC-003** — Threading (Pthreads) aktivieren?
  → Trigger: Phase-1.6-Performance-Profiling

---

## ABGESCHLOSSEN

- [x] Alle Input-Quellen analysiert (2026-07-10)
- [x] reference_analysis.md erstellt
- [x] inventory.md erstellt
- [x] source_map.json erstellt
- [x] asset_taxonomy.json erstellt
- [x] runtime_matrix.md erstellt
- [x] save_state_options.md erstellt
- [x] PHASE_1_BUILDPLAN.md erstellt
- [x] porting_manager_spec.md erstellt
- [x] manifest.schema.json erstellt
- [x] pipeline.yaml erstellt
- [x] task_graph.json erstellt
- [x] directory-tree.txt erstellt
- [x] architecture.md erstellt
- [x] PROJECT_PLAN.md erstellt
- [x] TASK.md erstellt
- [x] blockers.md erstellt
- [x] decisions.md erstellt
- [x] assumptions.md erstellt
- [x] NEXT_ACTIONS.md erstellt
