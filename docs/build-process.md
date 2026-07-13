# Build-Prozess (HL2 WebXR)

Dieses Dokument beschreibt den vollständigen Build-Prozess für das HL2 WebXR Projekt unter Verwendung von Emscripten und dem waf-Buildsystem.

## 1. Voraussetzungen & Toolchain

Der Build erfordert eine spezifische Version von Emscripten sowie weitere grundlegende Systemwerkzeuge:
- **Emscripten (emsdk):** Version `3.1.72` (Commit: `2d480a1b7c7a34a354188d93f3e89190a44a1d21`), vorinstalliert im CI-System zur Vermeidung von LLVM-Compilierungszeiten.
- **Node.js:** `>=18.0.0` (für Chunks-Verarbeitung, Skripte und Webserver).
- **Python:** `>=3.10` (erforderlich für das waf-Build-System).
- **Waf:** Im Source-Engine Submodule (`engine/portal-port/waf`) eingebettet.

## 2. Vorbereitung & Bereinigung (Waf-Cache-Bug Workaround)

> **MACHINE_COMMENT:** Vor jedem CI/CD- oder lokalen Build-Schritt muss der waf-Cache vollständig gelöscht werden, da verbleibende Artefakte bei inkrementellen Builds zu fehlenden Symbolen in den DLLs/Side-Modules führen können.

```bash
# 1. Repository klonen und Submodule initialisieren
git clone --recursive https://github.com/Mxthy/hl2-webxr.git
cd hl2-webxr

# 2. Waf-Cache und Build-Ordner vor jedem Build radikal entfernen
find build/ -mindepth 1 -delete 2>/dev/null || true
```

## 3. Quellcode-Patches vor dem Build

Folgende Patches müssen vor dem Starten des Build-Prozesses angewendet werden:

1. **alloca.h Guard für Emscripten:**
   - Datei: `engine/portal-port/ivp/ivp_physics/ivp_physics.hxx`
   - Datei: `engine/portal-port/ivp/havana/havok/hk_base/base.h`
   - Modifikation: `#include <alloca.h>` unter `#ifdef __EMSCRIPTEN__` hinzufügen.

2. **vtable-Fix für `IVP_Mindist`:**
   - Datei: `engine/portal-port/ivp/ivp_collision/ivp_mindist_minimize.cxx`
   - Modifikation: Emscripten-spezifische Compiler-Guards einbauen, um einen virtuellen Tabellen-Crash (vtable crash) bei der Optimierung zu umgehen.

3. **GetRam() und futimes() Stubs:**
   - Datei: `engine/portal-port/emscripten/emscripten_stubs.cpp`
   - Modifikation: Stubs für POSIX/Linux-spezifische Aufrufe implementieren, die Emscripten nicht standardmäßig anbietet.

4. **WebGL Patch:**
   - Patch-Datei: `engine/portal-port/emscripten/libwebgl.patch` anwenden, um den `glMapBufferRange` Fehler im Zusammenspiel mit Emscriptens WebGL2-Wrapper zu beheben.

5. **SDL2 Audio Patch:**
   - Deaktivierung der Audioausgabe für den Browser, um asynchrone Audio-Blockaden im Haupt-Thread zu verhindern.

## 4. Konfiguration & Kompilierung mit Waf

```bash
# In den Source-Engine Ordner wechseln
cd engine/portal-port

# 1. Konfiguration für OpenGL ES und Emscripten ausführen
python3 waf configure --togles --emscripten --prefix=build/install

# 2. Kompilierung und lokale Installation starten (Full-Compile dauert ca. 25-30 Min)
python3 waf build install
```

## 5. Link-Schritt (Emscripten Flags & Side-Modules)

Der Linker-Schritt (`emcc`) erzeugt das finale WebAssembly und bindet die Side-Modules ein:
- Output: `hl2_launcher.html`, `hl2_launcher.js`, `hl2_launcher.wasm` sowie 25 Side-Modules (`.so`).
- **Ladereihenfolge der Side-Modules:** `tier0.so` → `vstdlib.so` → `engine.so` (geladen via `dlopen` zur Laufzeit).

### Spezifische Emcc-Linkerflags:
- `-sERROR_ON_UNDEFINED_SYMBOLS=0`: Ermöglicht es, dass Symbole erst zur Laufzeit dynamisch über `dlopen` aufgelöst werden.
- `-sPTHREADS=1`: Aktiviert Multithreading-Unterstützung (erzeugt Web-Worker).
- `-sINITIAL_MEMORY=2147418112`: Reserviert ca. 2047MB Arbeitsspeicher.
- `-sUSE_SDL=2`: Nutzt Emscriptens SDL2-Portierung für Fenster und Input-Handling.
- `--std=c++14`: Setzt den C++ Standard auf Version 14 fest.

## 6. Asset-Vorbereitung & Chunk-Strategie (Multi-Chunk)

Die Spieldaten stammen aus dem HL2 Retail Build 2153 (von Archive.org). Die Verzeichnisstruktur wird ohne Extrahierungs-Tools direkt verwendet. Aufgrund der enormen Größe von Half-Life 2 werden die Assets in drei separate Chunks partitioniert, um die Ladezeiten zu parallelisieren:

1. **`background01.data`** (ca. 25MB):
   - Enthält Maps und Konfigurationen: `cfg/`, `resource/`, `platform/resource/`, `maps/` (BSPs).
2. **`materials.data`** (ca. 498MB):
   - Enthält Texturen: `materials/` (VTF+VMT Dateien).
3. **`models.data`** (Inhalt im Build #40 ausstehend):
   - Enthält 3D-Modelle und Audio: `models/` und `sound/`.

### Parallel-Ladung in post.js:
Die drei Chunks werden parallel über `Promise.all()` geladen. Der Engine-Start via Emscripten (`removeRunDependency`) wird blockiert, bis alle drei Promises erfolgreich aufgelöst wurden.
