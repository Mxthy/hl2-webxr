# Runtime-Architektur (HL2 WebXR)

Dieses Dokument beschreibt die Interaktion der verschiedenen Komponenten zur Laufzeit, vom parallelen Laden der Assets bis zur WebXR-Render-Loop.

## 1. Übersicht & Initialisierung

Das HL2 WebXR-Projekt baut auf einer hochgradig modularisierten WebAssembly-Architektur auf. Der Haupt-Thread initialisiert die Laufzeitumgebung, startet parallele Web Worker für die PThreads-Implementierung und stößt den asynchronen Ladevorgang der Spielressourcen (Chunks) an.

## 2. Mermaid-Architektur-Diagramm

```mermaid
graph TD
    subgraph Browser-Thread (Haupt-Thread)
        HTML[hl2_launcher.html] -->|lädt| JS[hl2_launcher.js]
        JS -->|lädt parallel via Promise.all| PL[post.js Chunk Loader]
        
        subgraph Parallel Asset Loading
            PL -->|Chunk 1| CH1[background01.data - 25MB]
            PL -->|Chunk 2| CH2[materials.data - 498MB]
            PL -->|Chunk 3| CH3[models.data - Pending]
        end
        
        PL -->|removeRunDependency nach Promise.all| WASM_Init[WASM Runtime Start]
    end

    subgraph WebAssembly & Worker-Threads (SharedArrayBuffer)
        WASM_Init -->|instanziiert| Core[WASM Main Module]
        Core -->|dynamisches Laden via dlopen| T0[tier0.so]
        T0 -->|lädt| VS[vstdlib.so]
        VS -->|lädt| ENG[engine.so]
        ENG -->|lädt restliche 22 Module| SideM[22x Side-Modules .so]
    end

    subgraph Render & WebXR Bridge
        ENG -->|rendert| Canvas[HTML5 Canvas]
        Canvas -->|Größenanpassung via JS| Display[Screen]
        ENG -->|XR Session / Offscreen Canvas| WebXR[WebXR Device API]
        WebXR -->|Controller Input| Gamepad[WebXR Gamepads]
    end
```

## 3. Dynamisches Modul-Laden (Side-Modules)

Emscripten kompiliert die Source-Engine als Hauptmodul (`hl2_launcher.wasm`) mit `MAIN_MODULE=1`. Die restlichen Komponenten werden als Side-Modules (`.so` Dateien) mit `SIDE_MODULE=1` kompiliert.

1. **Haupt-Module (`hl2_launcher.wasm`):** Enthält das minimale Emscripten-Bootstrap-System und grundlegende Symbole.
2. **Dynamic Linking:** Beim Start der Engine wird über das POSIX-Kompatibilitäts-Interface `dlopen` gearbeitet.
3. **Ladereihenfolge:**
   - **`tier0.so`:** Beherbergt grundlegende Debugging- und Memory-Management-Funktionen.
   - **`vstdlib.so`:** Enthält Hilfs- und Utility-Klassen.
   - **`engine.so`:** Die eigentliche Engine-Logik, die wiederum das Rendering, die Physik und den Game-State steuert.
   - **Restliche 22 Module:** Werden bedarfsweise oder direkt im Anschluss dynamisch nachgeladen.

## 4. Chunk-Lade-Prozess (post.js)

Da die Gesamtgröße der Assets Hunderte von Megabytes überschreitet, blockiert ein sequenzieller Download den Engine-Start massiv.
- **post.js** fängt die Emscripten-Standard-Laderoutine ab.
- Es führt ein paralleles Fetching von `background01.data`, `materials.data` und `models.data` durch.
- Jede Datei wird im virtuellen Emscripten-Dateisystem (FS) abgelegt.
- Erst wenn alle Chunks vollständig geladen wurden, wird `Module.removeRunDependency()` aufgerufen, was der WASM-Laufzeitumgebung signalisiert, dass der Einstiegspunkt (`main()`) sicher ausgeführt werden kann.
