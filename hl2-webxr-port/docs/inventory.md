# Inventory
## HL2 WebGL2/WebXR Porting Manager — Asset & Source Inventory

Generated: 2026-07-10

---

## Verfügbare Quellen

### Engine-Quellen (Code)

| ID | Name | URL | Status | Priorität |
|---|---|---|---|---|
| ENG-01 | nillerusr/source-engine | https://github.com/nillerusr/source-engine | INFERRED verfügbar | P1 |
| ENG-02 | weliveinhell Portal-Port | GitHub (username: weliveinhell) | INFERRED verfügbar | P1 |
| ENG-03 | slqnt HL2-Port | hl2.slqnt.dev | CONFIRMED live | P1 (Referenz) |
| ENG-04 | HL2VRU | https://github.com/vittorioromeo/HL2VRU | CONFIRMED | P3 (VR-Phase) |

### Asset-Quellen (Archive.org)

| ID | Name | URL | Status | Größe |
|---|---|---|---|---|
| ARC-01 | Retail 2153 | archive.org/details/Half-Life-2-Retail-2153 | ✅ VERFÜGBAR | 4.8 GB |
| ARC-02 | Collector's Edition | archive.org/details/HalfLife2CollectorsEdition2153 | ❌ ENTFERNT | — |
| ARC-03 | Episode One PROViSiON | archive.org/details/half-life-2-episode-one_202402 | ✅ VERFÜGBAR | 1.4 GB |
| ARC-04 | Complete Edition Linux | archive.org/details/half-life-2-complete-edition-... | ❌ ENTFERNT | — |

### Technische Dokumentation

| ID | Name | URL | Status |
|---|---|---|---|
| DOC-01 | Emscripten OpenGL Support | emscripten.org/docs/.../OpenGL-support.html | CONFIRMED |
| DOC-02 | Emscripten Settings Reference | emscripten.org/docs/tools_reference/settings_reference.html | CONFIRMED |

---

## Asset-Kategorien (aus GCF-Struktur)

### Shared Base Assets
- `base source shared materials` → Texturen (VTF, VMT)
- `base source shared models` → 3D-Modelle (MDL, VVD, VTX)
- `base source shared sounds` → Audio (WAV, MP3)

### HL2-spezifische Assets
- `halflife 2 base content` → Maps (BSP), Skripte, Konfigurationen
- Face Morphing Data (VFE/Flex-System) → **deaktiviert im Port**

### Episode Assets (geplant, Phase 3)
- Episode One: ep1_c17_*, d1_* Maps
- Episode Two: ep2_* Maps

---

## Tool-Inventory

| Tool | Zweck | Status |
|---|---|---|
| GCFExplorer | GCF-Extraktion | CONFIRMED verfügbar (im ARC-01 Archiv) |
| Emscripten (emcc) | C++ → WASM/JS Compiler | CONFIRMED Dokumentation verfügbar |
| Asset-Packing-Skript | Logs → .data Files | CONFIRMED existiert (slqnt, Linux+Windows) |
| VPK-Tool | VPK Pack/Unpack | INFERRED existiert (Valve SDK) |

---

## Verfügbarkeits-Risiken

1. **ARC-02 und ARC-04 entfernt** — 50% der Archive.org-Quellen nicht verfügbar
2. **slqnt-Port-Quellcode** — nicht öffentlich (UNKNOWN)
3. **Build-2153 ↔ steam_legacy Kompatibilität** — nicht gesichert (INFERRED-negativ)
4. **weliveinhell Portal-Port** — URL unbekannt (nur Name bekannt)
