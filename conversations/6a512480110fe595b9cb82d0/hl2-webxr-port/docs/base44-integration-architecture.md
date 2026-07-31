# HL2 WebXR ↔ Base44 App Integration — Architektur-Dokument

## 1. Übersicht

Das HL2-WebXR-Projekt läuft als eigenständige WebAssembly-Anwendung (WASM) 
in einem Browser. Die Integration in eine Base44-App erfolgt über einen 
**Embed-Layer**: die App liefert die UI-Shell (Session-Management, Settings, 
Multiplayer-Lobby), während das HL2-WASM-Modul in einem iframe oder 
WebGL-Canvas eingebettet läuft.

```
┌─────────────────────────────────────────────────┐
│              Base44 App (React Frontend)          │
│  ┌───────────┐  ┌──────────┐  ┌───────────────┐  │
│  │  Session   │  │  Settings │  │  Multiplayer  │  │
│  │  Manager   │  │  Panel    │  │  Lobby        │  │
│  └─────┬─────┘  └────┬─────┘  └──────┬────────┘  │
│        │              │                │           │
│        └──────────────┼────────────────┘           │
│                       ▼                             │
│  ┌─────────────────────────────────────────────┐  │
│  │         HL2 WebXR Bridge Layer                │  │
│  │  (postMessage API ↔ WASM Module)              │  │
│  └────────────────────┬────────────────────────┘  │
│                       │                             │
└───────────────────────┼─────────────────────────────┘
                        ▼
┌───────────────────────────────────────────────────┐
│              HL2 WASM Engine                        │
│  (hl2_launcher.wasm + 25 .so Side-Modules)         │
│  ┌─────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ Renderer │  │ Audio     │  │  Physics (IVP)    │  │
│  │ (WebGL2) │  │ (SDL2)    │  │  + Game Logic    │  │
│  └─────────┘  └──────────┘  └──────────────────┘  │
└───────────────────────────────────────────────────┘
```

---

## 2. Datei-Struktur des Integration-Projekts

### 2.1 Base44 App — Entities (Datenmodell)

```
Base44 App
├── entities/
│   ├── GameSession.json          # Aktive Spiele-Sessions
│   ├── PlayerProfile.json        # Spieler-Profile (Name, Settings, Stats)
│   ├── MultiplayerRoom.json      # Multiplayer-Räume (Lobby-System)
│   ├── GameEvent.json            # Event-Log (Kill, Death, Map-Wechsel)
│   └── AssetCache.json           # Asset-Metadaten (Chunks, Versionen)
```

#### Entity-Schemata

**GameSession:**
```json
{
  "properties": {
    "sessionId": { "type": "string" },
    "playerId": { "type": "string" },
    "mapName": { "type": "string" },
    "status": { "type": "string", "enum": ["loading", "playing", "paused", "ended"] },
    "fps": { "type": "number" },
    "renderQuality": { "type": "string", "enum": ["low", "medium", "high"] },
    "webxrEnabled": { "type": "boolean" },
    "startedAt": { "type": "string" },
    "endedAt": { "type": "string" }
  }
}
```

**PlayerProfile:**
```json
{
  "properties": {
    "displayName": { "type": "string" },
    "avatarUrl": { "type": "string" },
    "totalPlayTime": { "type": "number" },
    "preferredControls": { "type": "string", "enum": ["keyboard", "touch", "webxr"] },
    "settings": { "type": "object" }
  }
}
```

**MultiplayerRoom:**
```json
{
  "properties": {
    "roomId": { "type": "string" },
    "hostPlayerId": { "type": "string" },
    "mapName": { "type": "string" },
    "maxPlayers": { "type": "number" },
    "currentPlayers": { "type": "array" },
    "status": { "type": "string", "enum": ["lobby", "loading", "active", "finished"] }
  }
}
```

### 2.2 Backend Functions (Server-Logik)

```
functions/
├── createGameSession.ts      # Neue Session erstellen
├── loadMap.ts                 # Map laden (übersetzt zu WASM-Kommando)
├── getPlayerStats.ts          # Spieler-Statistiken abrufen
├── syncMultiplayerState.ts    # Multiplayer-State synchronisieren
└── reportGameEvent.ts         # Event-Log schreiben
```

#### Beispiel: loadMap.ts
```typescript
export default async function(req: Request): Promise<Response> {
  const { mapName, sessionId } = await req.body.json();
  
  // Session validieren
  const session = await base44.entities.GameSession.get(sessionId);
  if (!session) return Response.json({ error: "Session not found" }, { status: 404 });
  
  // Map-Namen validieren (nur erlaubte Maps)
  const allowedMaps = ["background01", "d1_trainstation_01", "d1_canals_01"];
  if (!allowedMaps.includes(mapName)) {
    return Response.json({ error: "Map not allowed" }, { status: 400 });
  }
  
  // Session aktualisieren
  await base44.entities.GameSession.update(sessionId, {
    mapName,
    status: "loading"
  });
  
  return Response.json({ 
    command: `map_background ${mapName}`,
    sessionId 
  });
}
```

### 2.3 Frontend — Bridge Layer

```
frontend/
├── components/
│   ├── HL2Canvas.tsx           # WASM-Canvas Wrapper (iframe/embed)
│   ├── GameHUD.tsx             # In-Game Overlay (FPS, Health, Ammo)
│   ├── SettingsPanel.tsx       # Engine-Settings (Quality, Controls)
│   └── MultiplayerLobby.tsx    # Lobby-UI
├── lib/
│   ├── hl2-bridge.ts           # postMessage Bridge ↔ WASM Engine
│   ├── engine-api.ts           # Engine_Init, Engine_LoadMap, Engine_RunFrame
│   └── asset-loader.ts         # Asset-Chunk Loader (MEMFS preload)
└── pages/
    ├── play.tsx                # Haupt-Spiel-Seite
    ├── lobby.tsx               # Multiplayer-Lobby
    └── settings.tsx            # Einstellungen
```

#### hl2-bridge.ts — Kern der Integration
```typescript
/**
 * Bridge zwischen Base44 App und HL2 WASM Engine.
 * Kommunikation via postMessage (iframe) oder direkter WASM-Export-Aufrufe.
 */

export class HL2Bridge {
  private wasmModule: any;
  private canvas: HTMLCanvasElement;
  
  async init(canvas: HTMLCanvasElement): Promise<void> {
    this.canvas = canvas;
    
    // WASM Modul laden (via Emscripten Module)
    this.wasmModule = await (window as any).HL2Module({
      canvas: this.canvas,
      noInitialRun: true,    // Engine nicht automatisch starten
      onStatus: (msg: string) => this.handleStatus(msg),
      onFrame: () => this.handleFrame(),
    });
    
    // Engine initialisieren (Host_Init)
    this.wasmModule._Engine_Init();
  }
  
  // Map laden
  loadMap(mapName: string): void {
    this.wasmModule._Engine_LoadMap(mapName);
  }
  
  // Einen Frame rendern
  renderFrame(): void {
    this.wasmModule._Engine_RenderSingleFrame();
  }
  
  // Kommando an Engine senden
  sendCommand(cmd: string): void {
    this.wasmModule._Engine_QueueCommand(cmd);
  }
  
  // WebXR Kamera-Matrix setzen
  setCameraMatrix(matrix: Float32Array): void {
    this.wasmModule._Engine_SetCameraMatrix(matrix);
  }
  
  // Auto-Render Loop deaktivieren (für WebXR manuellen Render)
  disableAutoRender(): void {
    this.wasmModule._Engine_DisableAutoRender();
  }
}
```

---

## 3. Engine API — Verfügbare Hooks

Diese C++ Hooks sind in `webxr_hooks.cpp` definiert und über WASM-Exports 
aus dem Main-Module verfügbar:

| Hook | C++ Signatur | Zweck |
|------|-------------|-------|
| `Engine_Init` | `int Engine_Init()` | Ruft `Host_Init(false)` — Engine-Initialisierung |
| `Engine_LoadMap` | `int Engine_LoadMap(const char* mapName)` | Lädt eine BSP-Map via `Cbuf_AddText("map_background X")` |
| `Engine_RunFrame` | `int Engine_RunFrame()` | Ruft `em_loop_iteration()` mit Exception-Handling |
| `Engine_RenderSingleFrame` | `void Engine_RenderSingleFrame()` | Alias für `em_loop_iteration()` |
| `Engine_QueueCommand` | `int Engine_QueueCommand(const char* cmd)` | Sendet Konsolen-Kommando an Engine |
| `Engine_DisableAutoRender` | `void Engine_DisableAutoRender()` | Stopt Emscripten Main-Loop, manuelle Render-Kontrolle |
| `Engine_SetCameraMatrix` | `void Engine_SetCameraMatrix(float* mat)` | Setzt WebXR View-Matrix |
| `Engine_SetProjectionMatrix` | `void Engine_SetProjectionMatrix(float* mat)` | Setzt WebXR Projektions-Matrix |
| `Engine_ResetCameraMatrix` | `void Engine_ResetCameraMatrix()` | Reset auf Default-Kamera |

### Side-Module Exports (libengine.so, via KEEPALIVE)

| Funktion | Mangled Name | C++ Signatur |
|----------|-------------|-------------|
| `Host_Init` | `_Z9Host_Initb` | `void Host_Init(bool bDedicated)` |
| `Host_RunFrame` | `_Z13Host_RunFramef` | `void Host_RunFrame(float time)` |
| `Cbuf_AddText` | `_Z12Cbuf_AddTextPKc` | `void Cbuf_AddText(const char* pText)` |
| `Cbuf_Execute` | `_Z12Cbuf_Executev` | `void Cbuf_Execute()` |
| `em_loop_iteration` | `_Z17em_loop_iterationv` | `void em_loop_iteration()` |

---

## 4. Asset-Pipeline

```
CI Build (GitHub Actions)
├── Source Engine Compile (waf + emcc)
│   └── hl2_launcher.wasm + 25 .so Side-Modules
├── Asset Extraction (HL2 Retail 2153)
│   └── Chunking: background1.data (843MB), materials.data (1GB), 
│       shaders.data, models.data, sounds.data, preload.data (3.3MB)
└── Deployment
    ├── WASM/JS/HTML → Web Host (Cloudflare)
    ├── .so Modules → CDN (gleicher Host, CORS-enabled)
    └── Asset Chunks → Cloudflare R2 (mit COOP/COEP)
```

### Asset-Loading im Browser
```typescript
// 1. MEMFS mit Config-Dateien füllen (preRun)
Module.preRun = () => {
  FS.mkdirTree('/hl2/');
  FS.writeFile('/hl2/gameinfo.txt', gameinfoContent);
  FS.writeFile('/hl2/steam.inf', '2153');
};

// 2. Asset-Chunks als preloadData laden
Module.preloadData = [
  { path: '/hl2/maps/background01.bsp', url: chunkBaseUrl + 'preload.data' },
  // ...weitere Chunks
];

// 3. Nach Init: Map laden
Module.onRuntimeInitialized = () => {
  Module._Engine_Init();
  Module._Engine_LoadMap('background01');
};
```

---

## 5. Integrations-Punkte (Einstiegspunkte)

### 5.1 minimal — Nur Engine einbetten
```
Base44 Page: /play
  └── <iframe src="https://hl2-webxr.workers.dev" />
```
→ Engine läuft isoliert, keine App-Integration.

### 5.2 basic — Settings + Session-Tracking
```
Base44 App
  ├── GameSession Entity (Session-Tracking)
  ├── Settings Page → Engine_QueueCommand("mat_picmip 2")
  └── /play Page → embedded WASM Canvas
```

### 5.3 full — Multiplayer + Events + WebXR
```
Base44 App
  ├── GameSession + PlayerProfile + MultiplayerRoom Entities
  ├── Backend Functions (createSession, loadMap, syncState)
  ├── Frontend: HL2Canvas, GameHUD, MultiplayerLobby
  ├── WebXR API → Engine_SetCameraMatrix / Engine_SetProjectionMatrix
  ├── Event-Log via GameEvent Entity
  └── Automations (scheduled cleanup, stats aggregation)
```

---

## 6. Build & Deploy

### CI Pipeline (bestehend)
```yaml
# .github/workflows/build.yml
- Clone source-engine + repo
- Apply patches (KEEPALIVE, ivp, SDL2, WebGL)
- waf configure + build (25 .so Side-Modules)
- emcc link (hl2_launcher.wasm + .js + .html)
- runtime_patches.py (14 Patches auf hl2_launcher.js)
- Asset-Chunks → Cloudflare R2
- Web-Bundle → Cloudflare Worker
```

### Deploy in Base44 App
```
1. Web-Bundle URL in App-Konfiguration hinterlegen
2. Frontend-Komponente (HL2Canvas.tsx) lädt WASM via Module()
3. Asset-Base-URL konfigurierbar (CDN oder lokaler Server)
4. COOP/COEP Headers müssen vom Host gesetzt werden
```

---

## 7. Nächste Schritte

1. ✅ Build #108: KEEPALIVE-Exports für alle Engine-Funktionen
2. ⬜ Engine_Init() erfolgreich aufrufen (Host_Init ohne Crash)
3. ⬜ Engine_LoadMap("background01") → sichtbare 3D-Szene
4. ⬜ WebXR API: Engine_SetCameraMatrix / Engine_SetProjectionMatrix
5. ⬜ Base44 App: Entities + Backend Functions erstellen
6. ⬜ Frontend: HL2Canvas + Bridge-Layer implementieren
7. ⬜ Multiplayer: WebRTC oder WebSocket-Relay
