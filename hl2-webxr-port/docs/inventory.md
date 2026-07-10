# Inventory
## HL2 WebGL2/WebXR Porting Manager — Asset & Source Inventory

Zuletzt aktualisiert: 2026-07-10 18:13 (Europe/Berlin)

---

## Engine-Quellen (Code)

| ID | Name | URL | Status | Priorität |
|---|---|---|---|---|
| ENG-01 | nillerusr/source-engine | https://github.com/nillerusr/source-engine | INFERRED verfügbar | P1 |
| ENG-02 | weliveinhell Portal-Port | GitHub — URL UNKNOWN (BLK-001) | INFERRED verfügbar | P1 |
| ENG-03 | slqnt HL2-Port (live) | https://hl2.slqnt.dev | CONFIRMED live | P1 (Referenz) |
| ENG-04 | HL2VRU (VR-Mod) | https://github.com/vittorioromeo/HL2VRU | CONFIRMED | P3 (VR-Phase) |

## Asset-Quellen (Archive.org)

| ID | Name | URL | Status | Größe | Priorität |
|---|---|---|---|---|---|
| ARC-01 | Retail Build 2153 | https://archive.org/details/Half-Life-2-Retail-2153 | ✅ VERFÜGBAR | 4.8 GB | P1 |
| ARC-02 | Collector's Edition 2153 | https://archive.org/details/HalfLife2CollectorsEdition2153 | ❌ ENTFERNT | — | — |
| ARC-03 | Episode One PROViSiON | https://archive.org/details/half-life-2-episode-one_202402 | ✅ VERFÜGBAR | 1.4 GB | P3 |
| ARC-04 | Complete Edition Linux | https://archive.org/details/half-life-2-complete-edition-... | ❌ ENTFERNT | — | — |

## Technische Dokumentation

| ID | Name | URL | Status |
|---|---|---|---|
| DOC-01 | Emscripten OpenGL Support | https://emscripten.org/docs/porting/multimedia_and_graphics/OpenGL-support.html | CONFIRMED |
| DOC-02 | Emscripten Settings Reference | https://emscripten.org/docs/tools_reference/settings_reference.html | CONFIRMED |

---

## GCF-Datei-Inventar (ARC-01 — Retail Build 2153)

Vollständige Liste aus ARC-01. Für HL2-Port werden nur die 5 markierten Dateien benötigt.
CS:S-Dateien sind im Archiv enthalten, aber nicht relevant für dieses Projekt.

| Datei | Key (MD5) | Für HL2-Port | Status |
|---|---|---|---|
| `halflife 2 base content.gcf` | `187D516D65C617EB6FE90FB20211DEC6` | ✅ BENÖTIGT | nicht extrahiert |
| `base source shared materials.gcf` | `33648B73E732E0734E34FE3CDA09AB74` | ✅ BENÖTIGT | nicht extrahiert |
| `base source shared models.gcf` | `D147FC333F1B2B18A8E0B9354B94AFF6` | ✅ BENÖTIGT | nicht extrahiert |
| `base source shared sounds.gcf` | `9DC57C809A92196E2674ADA87AEA0FCE` | ✅ BENÖTIGT | nicht extrahiert |
| `base source shared.gcf` | `C596D1BA1FEAD9A40DD0058118F58975` | ✅ BENÖTIGT | nicht extrahiert |
| `counterstrike source base content.gcf` | `null` (kein Key im README) | ❌ nicht benötigt | — |
| `counterstrike source shared content.gcf` | `D1C6EA82416EF4053E0B7E4C242D770F` | ❌ nicht benötigt | — |

**Extraktion:** GCFExplorer (im ARC-01/Misc/ enthalten) — ACTION-004

---

## Asset-Kategorien (nach GCF-Extraktion erwartet)

| Kategorie | Quell-GCF | Zielverzeichnis | Formate | Status |
|---|---|---|---|---|
| Maps (BSP) | halflife 2 base content | `./assets/hl2/maps/` | BSP | nicht extrahiert |
| Skripte/Config | halflife 2 base content | `./assets/hl2/scripts/` | TXT, CFG, VDF | nicht extrahiert |
| Texturen | base source shared materials | `./assets/shared/materials/` | VTF, VMT | nicht extrahiert |
| 3D-Modelle | base source shared models | `./assets/shared/models/` | MDL, VVD, VTX | nicht extrahiert |
| Audio | base source shared sounds | `./assets/shared/sounds/` | WAV, MP3 | nicht extrahiert |
| Face Morphing | halflife 2 base content | — | VFE (in MDL) | **DEAKTIVIERT (DEC-FIXED-002)** |

---

## Tool-Inventar

| Tool | Zweck | Quelle | Status |
|---|---|---|---|
| GCFExplorer | GCF-Dateien extrahieren | ARC-01/Misc/ | CONFIRMED vorhanden, noch nicht extrahiert |
| Emscripten (emcc) | C++ → WASM/JS Compiler | emsdk (ACTION-005) | noch nicht installiert |
| Asset-Packing-Skript (Linux) | Logs → .data Dateien | weliveinhell-Repo (BLK-001) | URL UNKNOWN |
| Asset-Packing-Skript (Windows) | Logs → .data Dateien (Windows-Port) | slqnt-Mod | Quellcode nicht öffentlich (BLK-002) |
| file_packager.py | Emscripten Asset-Packer | Emscripten SDK (inkl.) | nach ACTION-005 verfügbar |
| VPK-Tool | VPK Pack/Unpack (für steam_legacy) | Valve Source SDK | INFERRED verfügbar (DEC-001 ausstehend) |

---

## Verfügbarkeits-Risiken

| Risiko | Schweregrad | Blocker-Ref |
|---|---|---|
| weliveinhell-Repo URL unbekannt | HOCH | BLK-001 |
| slqnt Port-Quellcode nicht öffentlich | MITTEL | BLK-002 |
| Build-2153 ↔ nillerusr Kompatibilität ungetestet | HOCH | BLK-003 |
| ARC-02 + ARC-04 von Archive.org entfernt | NIEDRIG | BLK-004 |
| EP2-Asset-Quelle fehlt | LATENT (Phase 3) | BLK-008 |

---

## Was noch fehlt (nach Extraktion auszufüllen)

- [ ] Anzahl BSP-Dateien in `./assets/hl2/maps/` (nach ACTION-004)
- [ ] Verzeichnisstruktur nach GCF-Extraktion (nach ACTION-004)
- [ ] ARC-03-Inhaltsstruktur (RAR → entpacken → analysieren, Phase 3)
- [ ] steam_legacy-Asset-Verzeichnisstruktur (wenn DEC-001 → Option B)
