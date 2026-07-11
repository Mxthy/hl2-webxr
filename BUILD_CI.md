# HL2 WebXR — CI Build Guide

## Übersicht

Der Build läuft vollständig in GitHub Actions auf einem `ubuntu-22.04`-Runner.  
Kein lokaler Emscripten-Toolchain nötig — alles wird in CI heruntergeladen, gepinnt und gecached.

---

## Voraussetzungen

| Was | Details |
|---|---|
| GitHub-Repo | Dieses Verzeichnis (`hl2-webxr-port/`) als Root eines eigenen Repos |
| HL2-Assets | gepackt als `assets.tar.zst` oder `assets.tar.gz`, downloadbar via URL |
| GitHub Secret | `ASSETS_ARCHIVE_URL` → direkter Download-Link zum Asset-Archiv |

### Asset-Archiv vorbereiten

Das Archiv muss die Verzeichnisstruktur `game/Half-Life 2/hl2/` und optional `game/Half-Life 2/platform/` enthalten:

```
assets.tar.zst
└── game/
    └── Half-Life 2/
        ├── hl2/
        │   ├── maps/          ← .bsp Dateien
        │   ├── materials/
        │   ├── models/
        │   └── ...
        └── platform/
            └── resource/
```

Erstellen (lokal, vom `hl2-webxr-port/assets/` Verzeichnis):
```bash
cd hl2-webxr-port/
tar --zstd -cf assets.tar.zst assets/
# oder ohne zstd:
tar -czf assets.tar.gz assets/
```

Hochladen z.B. auf einen S3-Bucket, Backblaze B2, oder als GitHub Release Asset.

---

## Einmalige Einrichtung

### 1. Repo auf GitHub erstellen und pushen

```bash
# Dieses Verzeichnis als Repo-Root verwenden
cd hl2-webxr-port/

git init
git add .
git commit -m "Initial commit: CI build pipeline"
git remote add origin https://github.com/DEIN_USER/hl2-webxr.git
git push -u origin main
```

### 2. Secret setzen

GitHub → Repository Settings → **Secrets and variables** → **Actions** → **New repository secret**:

| Name | Wert |
|---|---|
| `ASSETS_ARCHIVE_URL` | Direkte Download-URL zu `assets.tar.zst` oder `assets.tar.gz` |

Ohne dieses Secret läuft der Build durch, aber `repackage.js` erzeugt keine `.data`-Chunks (kein Asset-Material vorhanden).

---

## Build auslösen

### Automatisch (bei Push)

Jeder Push auf `main` oder `master` der folgende Dateien ändert löst den Build aus:
- `scripts/ci-build.sh`
- `.github/workflows/build.yml`

### Manuell (workflow_dispatch)

GitHub → Repository → **Actions** → **HL2 WebXR – WASM Build** → **Run workflow**

Optional: Build-Typ `release` (default) oder `debug` wählen.

---

## Build-Schritte (Übersicht)

| Schritt | Dauer (ca.) | gecacht |
|---|---|---|
| apt-Dependencies | 1–2 min | nein (schnell) |
| emsdk clone + install | 4–5 min | ✅ ja (per Commit-Hash) |
| source-engine clone | 2–3 min | ✅ ja |
| Source-Patches | < 1 s | ✅ via Checkpoint-Flag |
| SDL2 Emscripten-Cache | 2–3 min | ✅ via emsdk-Cache |
| libwebgl.patch | < 1 s | — |
| waf configure | 1 min | — |
| **waf build (2224 steps)** | **~16 min** | ✅ Objekte gecacht |
| emcc link | 3–5 min | — |
| Asset-Repackaging | 5–15 min | — |
| Artifact-Upload | 1–3 min | — |
| **Gesamt (erster Run)** | **~40–50 min** | — |
| **Gesamt (Folge-Run)** | **~10–15 min** | — |

Timeout: 90 Minuten (großzügig).

---

## Artefakte im GitHub-UI

Nach erfolgreichem Run erscheinen unter **Actions → Run → Artifacts**:

| Artifact-Name | Inhalt |
|---|---|
| `hl2-webxr-web-<run_id>` | `hl2_launcher.html`, `.js`, `.wasm`, `.so`-Side-Module, `assets/` |
| `hl2-webxr-chunks-<run_id>` | `background01.data`, `d1_trainstation_01.data`, … (eine Datei pro Map) |
| `build-logs-<run_id>` | `waf_configure.log`, `waf_build.log`, `emcc_link.log`, `repackage.log` |

Retention: Logs 14 Tage, Outputs 30 Tage.

---

## Lokal ausführen (auf Debian/Ubuntu x86_64)

```bash
# Aus dem hl2-webxr-port/-Verzeichnis:
export ASSETS_ROOT="/pfad/zu/assets/game/Half-Life 2"
bash scripts/ci-build.sh release
```

Outputs landen in `dist/`.

Checkpoint-Datei `.build_checkpoint` merkt sich abgeschlossene Schritte.  
Zum Reset (alles neu bauen): `rm .build_checkpoint`

---

## Troubleshooting

**"waf install failed"** → `dist/logs/waf_build.log` öffnen, nach `error:` suchen.  
**"emcc link failed"** → `dist/logs/emcc_link.log`, oft fehlt ein `-lXXX` oder Side-Module.  
**Chunks leer** → `ASSETS_ARCHIVE_URL` Secret überprüfen, Asset-Pfadstruktur prüfen.  
**SDL2 audio bug** → SDL2-Patch wurde nicht angewendet; Cache löschen (Actions → Cache → delete `emsdk-*`).

---

## Dateistruktur dieses Repos

```
hl2-webxr-port/
├── .github/
│   └── workflows/
│       └── build.yml          ← GitHub Actions Pipeline
├── scripts/
│   └── ci-build.sh            ← Reproduzierbares Build-Skript
├── BUILD_CI.md                ← Diese Datei
├── .build_checkpoint          ← Laufzeit-Checkpoint (nicht committen!)
└── assets/                    ← HL2-Assets (nicht committen! → .gitignore)
```

**.gitignore ergänzen:**
```
assets/
dist/
logs/
.build_checkpoint
engine/
tools/
```
