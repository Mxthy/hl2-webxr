# HL2 WebXR — Process Documentation

> **Hinweis:** Diese Dokumentation ist primär für Maschinen/Automation konzipiert.
> Sie ermöglicht KI-Agenten und automatisierten Tools, den Projektstand zu verstehen
> und Prozesse reproduzierbar auszuführen.

## Dateien

| Datei | Zweck |
|---|---|
| `build-process.md` | Vollständiger Build-Prozess (Emscripten, Flags, Chunks) |
| `deploy-process.md` | Deployment via GitHub Actions + lokaler Server |
| `runtime-architecture.md` | WASM, WebXR, Chunk-Loading, Architektur-Diagramm |
| `checkpoints.json` | **Maschinenlesbarer Fortschritt** — hier immer starten |
| `environment-spec.yaml` | Exakte Toolchain-Versionen, Flags, Umgebungsvariablen |
| `known-issues.md` | Bekannte Probleme & Workarounds |
| `glossary.md` | Begriffe, Abkürzungen, Referenzen |

## Schnellstart für KI-Agenten

1. Lies `checkpoints.json` → Feld `nextAction` zeigt die nächste Aufgabe
2. Lies `environment-spec.yaml` → exakte Toolchain
3. Führe `build-process.md` Schritt für Schritt aus
4. Nach jeder Änderung: `checkpoints.json` aktualisieren
