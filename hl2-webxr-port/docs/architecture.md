# HL2 WebXR/WebGL2 Port — Zielarchitektur & Infrastruktur-Notizen

> Erstellt: 2026-07-10 | Status: Entwurf v1.0
> Basierend auf Recherche der Source Engine (HL2) Architektur für einen WebGL2/WebXR-Port

---

## 1. Quelle Engine Architektur — Extrahierte Erkenntnisse

### 1.1 gameinfo.txt (Mount-System)
`gameinfo.txt` ist eine KeyValues-Konfigurationsdatei, die ein Source-Mod beschreibt.
Sie enthält:

| Sektion / Schlüssel | Beschreibung |
|---|---|
| `GameInfo` | Root-Block |
| `game` | Interner Name des Mods |
| `title` / `title2` | Anzeige-Name |
| `type` | `singleplayer_only` / `multiplayer_only` / `both` |
| `developer` | Entwickler-Name |
| `GameData` | Pfad zur .fgd (Forge Game Data) Datei |
| `InstancePath` | Pfad für Instanz-Maps |
| `FileSystem` | Dateisystem-Block |
| `SteamAppId` | Steam App-ID für Basis-Content |
| `ToolsAppId` | Steam App-ID für SDK-Tools |
| `SearchPaths` | Geordnete Liste von Mount-Pfaden |

**SearchPaths-Logik (Load-Order):**
- Pfade werden **top-down** evaluiert — der erste Treffer gewinnt
- Präfixe steuern Mount-Typ: `game+mod` (Mod + Basis), `game` (nur Basis), `platform`, `mod`, `gamebin`
- `|gameinfo_path|` = Verzeichnis, in dem die gameinfo.txt liegt
- `|all_source_engine_paths|` = Steam Source Engine Basis-Verzeichnis
- VPKs und Ordner im `custom/`-Verzeichnis werden **alphabetisch** gemountet
- `game+download` = Pfad für heruntergeladene Inhalte
- `mod_write` / `default_write_path` / `game_write` = Schreibpfade

**Beispiel (HL2-ähnlich, aus GMod gameinfo.txt):**
```
"GameInfo"
{
    game  "Half-Life 2"
    type  singleplayer_only
    FileSystem
    {
        SteamAppId  420
        ToolsAppId  211
        SearchPaths
        {
            game+mod     |gameinfo_path|.
            game         |all_source_engine_paths|hl2_textures.vpk
            game         |all_source_engine_paths|hl2_sound_vo_english.vpk
            game         |all_source_engine_paths|hl2_sound_misc.vpk
            game         |all_source_engine_paths|hl2_misc.vpk
            platform     |all_source_engine_paths|platform/platform_misc.vpk
            game+game_write  hl2
            gamebin          hl2/bin
            game             |all_source_engine_paths|hl2
            platform         |all_source_engine_paths|platform
            game+download    hl2/download
        }
    }
}
```

### 1.2 VPK-Format (Valve PacK)
- Unkomprimiertes Archiv-Format für gepackte Assets (Materialien, Modelle, Partikel, Sounds)
- Gelöst als Performance-Lösung für das Lesen tausender kleiner Dateien von Festplatte
- Multi-Chunk-Modus: Chunks sind ~200MB groß; Dateien heißen `pak01_000.vpk`, `pak01_001.vpk`, ... `pak01_dir.vpk` (Index)
- Tool: `vpk.exe` (Windows) / `vpk_linux32` (Linux) im `bin/`-Ordner des Spiels
- VPKs MÜSSEN in `gameinfo.txt` gemountet werden, um vom Spiel erkannt zu werden
- Inhalt folgt der gleichen Ordnerstruktur wie ungeschützte Dateien (materials/, models/, sound/, etc.)
- Signaturen mit public/private Key-Paaren für Integrität

### 1.3 Asset-Pipeline: VBSP → VVIS → VRAD

| Stage | Tool | Funktion |
|---|---|---|
| 1 | **VBSP** | Kompiliert VMF → BSP. Backface Culling, Entity-Setup, Portal-Datei (PRT), Cubemap-Verlinkung, Patch-Materialien. Erzeugt BSP mit 64 Lumps. |
| 2 | **VVIS** | Berechnet Visibility (PVS — Potentially Visible Set). Bestimmt welche Visleaves sich gegenseitig sehen können. Ohne VVIS wird alles gerendert. |
| 3 | **VRAD** | Radiosity-Beleuchtung. Berechnet Lightmap-Bounces, direktes/indirektes Licht, HDR-Lighting. Baked Lightmaps in BSP. |

**BSP-Lump-Struktur (Version 19-21, HL2):**
64 Lumps (0-63), bekannt aus srctools-Doku:

| ID | Lump | Bedeutung |
|---|---|---|
| 0 | ENTITIES | Alle Entities (KeyValues als Text) |
| 1 | PLANES | Ebene (BSP-Baum-Definition) |
| 2 | TEXDATA | Textur-Daten-Referenzen |
| 3 | VERTEXES | Vertex-Koordinaten |
| 4 | VISIBILITY | PVS-Daten (komprimiert) |
| 5 | NODES | BSP-Baum-Knoten |
| 6 | TEXINFO | Textur-Info (Material-Referenz + Textur-Matrix) |
| 7 | FACES | Faces (Dreiecke, Lightmap-Referenzen) |
| 8 | LIGHTING | Baked Lightmaps |
| 10 | LEAFS | BSP-Blätter (Visleaves) |
| 12 | EDGES | Kanten-Definitionen |
| 13 | SURFEDGES | Edge-Indizes für Faces |
| 14 | MODELS | Sub-Modelle (B-Models) |
| 18 | BRUSHES | Original-Brushwork |
| 19 | BRUSHSIDES | Brush-Seiten |
| 26 | DISPINFO | Displacement-Surface-Info |
| 33 | DISP_VERTS | Displacement-Vertices |
| 35 | GAME_LUMP | Game-spezifische Daten (Static Props) |
| 40 | PAKFILE | Eingebettete Assets (ZIP-Format) |
| 42 | CUBEMAPS | Cubemap-Positionen |
| 43-44 | TEXDATA_STRING | Textur-Namen-Strings |
| 53 | LIGHTING_HDR | HDR Lightmaps |
| 58 | FACES_HDR | HDR Faces |

**Wichtige Eigenschaften für WebGL-Port:**
- BSP ≈ "Quake 2++" Format — nicht GPU-freundlich
- Texture-Koordinaten als **Matrix**, nicht direkte UVs → müssen zur Ladezeit berechnet werden
- Lightmaps **per-Face**, nicht vorgepackt → Atlas-Packing nötig zur Ladezeit
- ~200MB pro Level (Texturen, Lightmaps) → Streaming/Compression nötig für Web

### 1.4 Asset-Formate

| Format | Datei(en) | Beschreibung |
|---|---|---|
| BSP | `.bsp` | Kompilierte Map (64 Lumps) |
| VMF | `.vmf` | Source-Map-Datei (Hammer Editor) |
| VTF | `.vtf` | Valve Texture Format (Texturen, DXT-komprimiert) |
| VMT | `.vmt` | Valve Material Type (KeyValues, Shader+Parameter) |
| MDL+VVD+VTX | `.mdl`, `.vvd`, `.vtx` | Studio-Modell: MDL=Struktur/Animation, VVD=Vertices, VTX=Rendering-Indices |
| PHY | `.phy` | Physik-Kollisionsmodell |
| PCF | `.pcf` | Partikel-System |
| VCD | `.vcd` | Choreography-Szene (Face-Posing, Dialog) |
| VPK | `.vpk` | Valve Pak (Asset-Archiv) |
| FGD | `.fgd` | Forge Game Data (Entity-Definitionen für Hammer) |
| NAV | `.nav` | Navigation Mesh (AI) |

### 1.5 Verzeichnisstruktur (Source Engine)

```
<game>/
  gameinfo.txt              # Mount-Konfiguration
  hl2/
    maps/                   # *.bsp + *.nav + *.lst
    materials/
      models/
      nature/
      brick/
      concrete/
      ... (thematisch)
    models/
      props/
      characters/
      weapons/
      vehicles/
    sound/
      ambient/
      npc/
      weapons/
      vo/                   # Voice-Over
    particles/
    scenes/                 # *.vcd
    resource/               # UI-Definitionen, Fonts
    scripts/
    cfg/                    # config.cfg, autoexec.cfg, mount.cfg
    custom/                 # Mod-Overrides (alphabetisch gemountet)
    addons/                 # GMod-spezifisch
    download/
    bin/                    # vbsp.exe, vvis.exe, vrad.exe, vpk.exe, studiomdl.exe
```

### 1.6 Shader-System
Source nutzt **Ubershaders** — wenige Basis-Shader mit vielen Parametern:
- `LightmappedGeneric` — Weltgeometrie mit Lightmaps
- `VertexLitGeneric` — Props/Modelle mit Vertex-Beleuchtung
- `UnlitGeneric` — UI/HUD
- `Water` — Wasser-Oberflächen
- `Refract` — Brechungs-Effekte
- Parameter in VMT: `$basetexture`, `$bumpmap`, `$envmap`, `$surfaceprop`, etc.

---

## 2. Annahmen

1. **Eigene Assets / Fair Use**: Wir portieren die *Engine-Architektur*, nicht automatisch die proprietären HL2-Assets. Der Portierungsmanager konvertiert Original-Assets zu Web-Formaten, aber der Nutzer muss die HL2-Dateien legal besitzen.
2. **WebGL2 als Mindeststandard**: WebGL2 ist in modernen Browsern universell verfügbar; WebXR nutzt WebGL2-Kontexte.
3. **WebAssembly für Performance**: Asset-Parsing (BSP, MDL, VTF) und Pathing/Physics werden in Rust/C → WASM kompiliert.
4. **Kein echtes VBSP/VVIS/VRAD im Browser**: Diese Tools laufen als Build-Step (Offline/Node.js), nicht zur Laufzeit. Der Browser lädt vorverarbeitete Formate.
5. **Progressive Loading**: Maps werden gestreamt — initiales Manifest → low-LOD Geometrie → hochauflösende Texturen nachladen.
6. **VR-First Rendering**: WebXR für immersive VR (Quest, PC-VR), mit Desktop-Fallback (non-VR WebGL2).
7. **Kein Multiplayer**: Fokus auf Singleplayer-Kampagne. Netzwerk-Code später erweiterbar.
8. **BSP wird zur Build-Zeit zu WebGL-freundlichem Format konvertiert**: JSON-Binär-Hybrid (`.geom` + `.lightmap.webp`), nicht als Roh-BSP geliefert.

---

## 3. Abhängigkeits-Liste

### 3.1 Externe JavaScript-Bibliotheken

| Bibliothek | Version | Zweck |
|---|---|---|
| `gl-matrix` | ^4.0 | Vektor/Matrix-Mathematik (glsl-freundlich) |
| `webxr-polyfill` | ^2.0 | WebXR API Polyfill für nicht-VR-Fallback |
| `pako` | ^2.1 | gzip/deflate Dekompression (BSP PAKFILE, VPK) |
| `msgpack-lite` | ^1.0 | Binäre Serialisierung für konvertierte Assets |
| `howler.js` | ^2.2 | WebAudio-Sound-Engine (3D-Audio) |

### 3.2 Rendering / Engine

| Bibliothek | Zweck |
|---|---|
| Custom WebGL2 Renderer | Kein Three.js — direkte WebGL2-Kontrolle für Source-Shader-Port |
| Custom Shader-System | Ubershader-Konzept → GLSL ES 3.00 Shader-Generator |

### 3.3 WebAssembly-Toolchain

| Tool | Version | Zweck |
|---|---|---|
| Rust | 1.75+ | Systemsprache für WASM-Module |
| `wasm-pack` | 0.12+ | Rust → WASM Build + JS-Bindings |
| `wasm-bindgen` | 0.7+ | Rust ↔ JS Interop |
| `wasm-opt` (binaryen) | 116+ | WASM-Optimierung (size + speed) |
| Emscripten | 3.1+ | Fallback für C/C++-Portierung (falls nötig) |

### 3.4 WASM-Module

| Modul | Quelle | Zweck |
|---|---|---|
| `bsp_parser.wasm` | Rust | BSP-Format Parser → Vertices, Faces, Lightmaps, PVS |
| `mdl_parser.wasm` | Rust | MDL+VVD+VTX → WebGL-freundliche Meshes |
| `vtf_decoder.wasm` | Rust/C | VTF → RGBA/BC7 (WebGPU-kompatibel) |
| `vpk_reader.wasm` | Rust | VPK-Archiv-Leser (Streaming) |
| `vmt_parser.wasm` | Rust | VMT KeyValues → Shader-Parameter-JSON |
| `physics.wasm` | Rust | Physik/Kollision (vereinfacht, Convex-Hull) |

### 3.5 Build-Tools (Node.js / Offline)

| Tool | Version | Zweck |
|---|---|---|
| Node.js | 20 LTS | Build-Runner |
| `esbuild` | ^0.20 | JS/TS Bundling + Minification |
| `typescript` | ^5.3 | TypeScript Compiler |
| `vite` | ^5.0 | Dev-Server + HMR + Build |
| `sharp` | ^0.33 | Bild-Konvertierung (VTF → WebP/KTX2) |
| `@webxr-input-profiles` | latest | VR-Controller-Profile |
| `telys/ktx2-encoder` | ^0.4 | KTX2/BasisU Texturen (GPU-komprimiert) |

### 3.6 Asset-Extraktion (Offline, Source-SDK-Tools)

| Tool | Zweck |
|---|---|
| `vpk.exe` / VPKEdit | VPK extrahieren (Source SDK) |
| `Crowbar` | MDL dekompilieren → SMD |
| `VTFEdit` / `vtfcmd` | VTF → PNG/TGA Batch-Konvertierung |
| `BSPSource` | BSP dekompilieren → VMF |
| `GCFScape` | GCF/VPK browsen |
| `Source SDK Base 2013` | VBSP/VVIS/VRAD (falls Neukompilierung nötig) |

---

## 4. Infrastruktur-Notizen

### 4.1 gameinfo.txt → manifest.json Mapping

| Source Engine Konzept | WebXR Port Entsprechung |
|---|---|
| `gameinfo.txt` | `config/manifest.json` |
| `SearchPaths` (geordnete Mount-Liste) | `manifest.assetGroups[].loadOrder` |
| VPK-Mounting (alphabetisch) | `assetGroup.archives[]` (geordnete Liste) |
| `SteamAppId` (Basis-Content) | `manifest.dependencies.baseContent` |
| `ToolsAppId` | `manifest.build.toolchain` |
| `game+mod` Präfix (Mod-Overlay) | `assetGroup.priority` + Overlay-Logik |
| `custom/` Ordner (Mod-Overrides) | `manifest.assetGroups[].type: "override"` |
| `|gameinfo_path|` Makro | `${BASE_PATH}` Template-Variable |
| `|all_source_engine_paths|` | `${ENGINE_PATH}` Template-Variable |
| VMT-Shader-Parameter | `manifest.assetGroups[].materials[].shaderParams` |

### 4.2 Load-Order Logik

Die Load-Order folgt dem Source-Prinzip **"erster Treffer gewinnt"**:

1. **Override-Assets** (höchste Priorität) — Mod-Overrides, benutzerdefiniert
2. **Map-spezifische Assets** — in BSP PAKFILE eingebettet (Lump 40)
3. **Mod-Assets** — eigene VPKs/Ordner des Mods
4. **Basis-Content** — hl2_textures, hl2_misc, hl2_sound (in Reihenfolge)

Bei Konflikten (gleiche Asset-ID): erstes Vorkommen in der Load-Order gewinnt.

### 4.3 Config-System

| Datei | Format | Zweck |
|---|---|---|
| `manifest.json` | JSON | Haupt-Manifest (Asset-Gruppen, Build, Deploy) |
| `engine.json` | JSON | Engine-Konfiguration (Render-Quality, VR-Settings) |
| `controls.json` | JSON | Input-Mapping (Keyboard, Mouse, VR-Controller) |
| `materials.json` | JSON | Shader-Parameter-Overrides (Runtime) |
| `levels.json` | JSON | Level-Liste mit Asset-Referenzen |

### 4.4 Streaming-Strategie

1. **Phase 0 (Boot)**: manifest.json laden (~10KB), WASM-Module initialisieren
2. **Phase 1 (Preload)**: Level-Geometrie (`.geom` binär, ~5-10MB) + Lightmap-Atlas (WebP, ~2-5MB)
3. **Phase 2 (Visible)**: Texturen für sichtbare Visleaves (PVS-gesteuert, KTX2/BC7)
4. **Phase 3 (Background)**: Restliche Texturen, Modelle, Sounds lazily nachladen
5. **VR-spezifisch**: Foveated Loading — hohe Auflösung nur für zentrales Sichtfeld

### 4.5 Build-Pipeline (Offline → Web)

```
HL2 Original Assets
       │
       ▼
[1] VPK Extract     →  Loose Files (BSP, VTF, VMT, MDL, VVD, VTX, WAV)
       │
       ▼
[2] BSP Convert     →  .geom (binär) + .lightmap.webp + .entities.json
    (bsp_parser.wasm via Node.js)
       │
       ▼
[3] Texture Convert →  .ktx2 (BasisU) + .webp (Fallback)
    (sharp + ktx2-encoder)
       │
       ▼
[4] Model Convert   →  .glb (glTF 2.0) + .anim.bin
    (mdl_parser.wasm → glTF-Export)
       │
       ▼
[5] Audio Convert   →  .opus (3D-positional) + .webm
       │
       ▼
[6] Package         →  Web-VPK (.wvpk) — komprimierte Web-Container
       │
       ▼
[7] Bundle          →  esbuild/vite → minified JS + WASM + Assets
       │
       ▼
[8] Deploy          →  Static Hosting (CDN) + Service Worker (Offline-Cache)
```
