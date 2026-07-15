# WebXR + WebAssembly-Architektur: Half-Life 2 (Source Engine) auf Meta Quest 3

Dieses Dokument beschreibt das technische Architektur- und Implementierungsdesign für die Portierung der Source Engine (`nillerusr/source-engine` im ToGLES/WebGL2-Modus) auf die **Meta Quest 3** als performante, native **Standalone-WebXR-Anwendung** (72Hz, 6DoF, duale Motion-Controller).

---

## 1. Fundamental-Unterschiede: Browser-2D vs. Quest-3-WebXR

Die Portierung eines hochgradig synchronen und sequenziellen Spiels wie Half-Life 2 (welches ursprünglich für Desktop-2D mit festen Framebuffer-Pipelines und synchronem Input geschrieben wurde) auf ein immersives VR-Headset erfordert grundlegende Änderungen in der Art und Weise, wie Frames berechnet, dargestellt und kontrolliert werden.

### A) Render-Loop-Mechanik
*   **Browser-2D (slqnt.dev):** Nutzt standardmäßig den klassischen `requestAnimationFrame` (rAF) des Fensters. Dieser läuft direkt auf dem UI/Main-Thread oder wird im Worker über `OffscreenCanvas` via `setTimeout`/`requestAnimationFrame` gesteuert.
*   **WebXR (Quest 3):** Die Darstellung *muss* zwingend über den WebXR-spezifischen Renderloop `XRSession.requestAnimationFrame` laufen. Dieser Loop wird von der VR-Runtime (Oculus/Meta-Browser-Composer) gesteuert, um eine exakte Synchronisation mit die Display-Wiederholrate des Headsets (hier standardmäßig **72Hz** für Quest 3, hochskalierbar auf 90Hz/120Hz) und den asynchronen Reprojection-Mechanismen (SpaceWarp / Late Latching) zu gewährleisten.

### B) Stereo-Rendering & Framebuffer-Besitz
*   **Browser-2D:** Die App besitzt das `<canvas>`-Element und erstellt darin einen eigenen Framebuffer. Am Ende des Frames wird dieser über den Browser-Compositor auf den Bildschirm kopiert.
*   **WebXR:** Das klassische `<canvas>` dient nur als Fallback oder Spiegel-Monitor. Der tatsächliche Framebuffer wird von der WebXR-Sitzung bereitgestellt (`XRWebGLLayer.framebuffer`). Die Engine *muss* direkt in diesen zugewiesenen Framebuffer rendern.
*   **Stereo-Pipeline:** Quest 3 erfordert stereoskopisches Rendern (ein Bild pro Auge). 
    *   **Traditioneller Ansatz (Multi-Pass):** Szene zweimal hintereinander rendern mit unterschiedlichen Viewport-Offsets und Matrizen für das linke und rechte Auge. Dies verdoppelt den CPU-Draw-Call-Overhead drastisch, was bei der ohnehin CPU-limitierten Source-Engine auf mobilen Chipsätzen (Snapdragon XR2 Gen 2 der Quest 3) zu extremen Framedrops führt.
    *   **Optimierter WebXR-Ansatz (OVR_multiview2):** Verwendung des WebGL-Extensions-Standards `OCULUS_multiview` bzw. `OVR_multiview2`. Hierbei rendert die Engine die Szene in einem einzigen Durchlauf (Single-Pass Instanced Rendering) in ein 2D-Texture-Array. Der Grafiktreiber dupliziert die Draw Calls auf GPU-Ebene und verschiebt die Vertices basierend auf der `gl_ViewID_OVR` für das jeweilige Auge. Dies reduziert den CPU-Overhead um nahezu 50%.

### C) GPU- & Browser-Einschränkungen (Quest 3 / Meta Horizon Browser)
*   Der Meta Horizon Browser basiert auf Chromium (Blink/V8) und teilt dessen Sicherheits- und Leistungsmerkmale.
*   **Memory Quotas:** Obwohl die Quest 3 über **8 GB RAM** verfügt, teilt der Meta Browser den Tabs strenge Limits zu. Ein einzelner Tab darf selten mehr als **2 bis 3 GB** Speicher belegen, bevor die Sandbox abstürzt. Eine strikte Speicherverwaltung des WASM-Heaps ist zwingend erforderlich.
*   **Sicherheitsauflagen für Multithreading:** Damit `SharedArrayBuffer` und Atomics für performantes Multithreading genutzt werden können, müssen die HTTP-Header zwingend Cross-Origin Isolation erzwingen:
    ```http
    Cross-Origin-Opener-Policy: same-origin
    Cross-Origin-Embedder-Policy: require-corp
    ```
    Ohne diese Header verweigert der Quest-Browser die Instanziierung von Web Workers mit geteiltem Speicher.

---

## 2. Render-Thread-Architektur

Die Source Engine ist architektonisch stark auf Threads ausgelegt (Material-System, Physics-Engine, Client/Server-Splitting). In `slqnt.dev` wird dies typischerweise über Emscriptens `PROXY_TO_PTHREAD` abgebildet, wodurch die gesamte C++ Engine in einem Web Worker läuft und der Main-Thread entlastet wird.

### Das WebXR-Dilemma
Die **WebXR-Spezifikation schreibt vor**, dass die Interaktion mit die `XRSession` (Erstellung, Frame-Abfrage über `session.requestAnimationFrame` und Input-Abfrage) **ausschließlich im Main-Thread (UI-Thread)** stattfinden darf. Web Workers haben keinen direkten Zugriff auf das `XRSession`-Objekt.

### Die Lösung: Shared Memory Bridge & Synchronisations-Architektur
Um dieses Problem zu lösen, implementieren wir eine asynchrone **Shared Memory Bridge** unter Nutzung von `SharedArrayBuffer`, Atomics und einem dualen Render-Loop:

```
[ Main-Thread (JS / WebXR) ]
        |
        |  1. XRSession.requestAnimationFrame() triggert Frame-Event.
        |  2. Liest HMD-Poses & Controller-Eingaben aus der WebXR-API.
        |  3. Schreibt Poses & Inputs in Shared Memory (HEAP32 / SharedArrayBuffer).
        |  4. Signalisiert dem Engine-Thread via Atomics.store / wait.
        v
[ Shared Memory Bridge (SharedArrayBuffer) ] <---> [ Engine-Worker (WASM / Pthread) ]
                                                            |
                                                            | 5. Engine-Thread erwacht (Atomics.wait).
                                                            | 6. Führt Simulationsschritt mit neuen Poses aus.
                                                            | 7. Führt C++ Rendering aus.
                                                            | 8. Rendert direkt über OffscreenCanvas
                                                            |    (mittels WebGL-Context-Proxying)
                                                            |    in den zugewiesenen WebXR-Framebuffer.
                                                            v
                                                    [ GPU / Compositor (Quest 3) ]
```

#### Synchronisations-Protokoll:
1. **Main-Thread (WebXR Loop):**
   * Ruft `session.requestAnimationFrame(onXRFrame)` auf.
   * Holt die aktuellen Kopfmatrizen (`XRFrame.getViewerPose(referenceSpace)`) und Controller-Posen.
   * Schreibt diese Daten in ein vordefiniertes Segment des `SharedArrayBuffer` (Struktur: `XRSharedState`).
   * Setzt ein Atom-Flag (`Atomics.store(state, FRAME_READY, 1)`) und weckt den C++ Thread mittels `Atomics.notify(state, FRAME_READY)`.
   * Wartet asynchron oder limitiert die Blockierung, um den UI-Thread nicht aufzuhängen (Frame-Shedding bei Ausreißern).

2. **Engine-Thread (C++ Event-Loop):**
   * Wartet in seiner Hauptschleife über einen blockierenden oder semi-blockierenden Aufruf (`emscripten_futex_wait` oder `Atomics.wait`) auf das `FRAME_READY`-Signal.
   * Liest die neuen Head- und Hand-Posen direkt aus dem geteilten Speicher.
   * Aktualisiert das interne Kamera- und Physiksystem von HL2.
   * Rendert den Stereo-Frame. Da der WebGL-Context mit `OffscreenCanvas` im Worker erstellt und an die WebXR-Session des Main-Threads gekoppelt ist, kann der C++ Thread direkt in das Render-Target zeichnen.
   * Quittiert den Frame (`Atomics.store(state, FRAME_DONE, 1)`) und geht in den Wartezustand für den nächsten Frame.

### Erforderliche Emscripten-Flags für dieses Modell:
*   `-sPROXY_TO_PTHREAD=1`: Verlagert das C++ Main-System komplett in den Worker.
*   `-sOFFSCREEN_CANVAS=1`: Ermöglicht es dem WebGL2-Context, direkt im Worker gerendert und manipuliert zu werden.
*   `-sUSE_PTHREADS=1`: Aktiviert Pthreads-Unterstützung via Web Workers und `SharedArrayBuffer`.

---

## 3. Controller-Input-Mapping

Die Steuerung in HL2 basiert historisch auf Keyboard/Maus oder standardmäßigen Gamepad-Achsen. In VR auf der Quest 3 müssen wir die komplexen räumlichen 6DoF-Posen und Tasten der Meta Quest Touch Controller abbilden.

```
[ WebXR Input Sources ] -> [ Main-Thread JavaScript ] -> [ SharedArrayBuffer (Input-Block) ] -> [ HL2 C++ IInputSystem ]
```

### Implementierungsschritte:
1. **Erfassung im Main-Thread:**
   * Während des `onXRFrame`-Callbacks iteriert der JS-Code über `session.inputSources`.
   * Für jeden Controller (Hand: `left`/`right`) extrahiert er:
     * Die räumliche Pose (`frame.getPose(inputSource.targetRaySpace, referenceSpace)`).
     * Die analogen Werte und Buttons über das `Gamepad`-API-Interface (`inputSource.gamepad`).

2. **Übertragung in den C++ Heap:**
   * Die Input-Struktur wird direkt in ein definiertes C-Struct im Shared Memory serialisiert:
     ```cpp
     struct XRControllerData_t {
         bool bActive;
         float vecPosition[3];
         float qRotation[4];
         float flTrigger;
         float flGrip;
         float vecJoystick[2];
         uint32_t nButtons; // Bitmaske für A, B, X, Y, Thumbstick-Klick, Menu
     };
     ```

3. **Engine-Integration (C++ Seite):**
   * Wir patchen die Klasse `IInputSystem` (bzw. implementieren einen dedizierten VR-Input-Treiber in `inputsystem/key_translation.cpp` oder im Client-Modul):
     * **Bewegung (Locomotion):** Der linke Daumenstick (`vecJoystick`) wird direkt auf die Vorwärts-/Seitwärtsgeschwindigkeit (`cl.sidemove`, `cl.forwardmove`) gemappt.
     * **Drehung (Snap/Smooth Turn):** Der rechte Daumenstick steuert die Rotation um die Y-Achse (Yaw). Wir implementieren standardmäßig *Snap-Turning* (z. B. 45-Grad-Schritte), um VR-Übelkeit (Motion Sickness) zu minimieren.
     * **Waffen-Interaktion:**
       * Rechter Trigger -> `IN_ATTACK` (Primärer Feuermodus).
       * Rechter Grip -> `IN_ATTACK2` (Sekundärer Feuermodus / z.B. Zoom oder Gravity Gun Objekt anziehen).
       * Linker Trigger -> Springen (`IN_JUMP`) oder Ducken (`IN_DUCK`).
     * **Waffenwechsel:** Über ein virtuelles radiales VR-Menü oder Mapping der analogen X/Y-Tasten.

---

## 4. Audio-Architektur

Der Sound in HL2 ist ein wesentlicher Teil der Atmosphäre (räumliche Ortung von Headcrabs, Echos im Abwasserkanal). Die native Engine nutzt ein eigenes DSP/Software-Mischpult.

### WebAudio auf Meta Quest 3:
*   **Performance-Einschränkung:** Jedes Dekodieren und Mischen im Main-Thread führt zu Rucklern im VR-Rendering. Das gesamte Audiosystem sollte asynchron laufen.
*   **Lösungsansatz (WebAudio + OpenAL-Emscripten-Bridge):**
    *   Emscripten bietet eine standardmäßige OpenAL-Implementierung, die intern auf der **Web Audio API** aufbaut.
    *   Da die Source Engine über eine offene Audioschnittstelle verfügt (in Linux-Ports oft SDL2 Audio oder OpenAL), patchen wir das Sound-System der Engine, um direkt die Emscripten-OpenAL-Bibliothek anzusprechen (`-lopenal`).
    *   **Spatial Audio (3D HRTF):** Wir nutzen das native 3D-Panner-System der Web Audio API (`PannerNode` mit `HRTF`-Panner-Modell). Jedes Mal, wenn die Source Engine eine 3D-Schallquelle instanziiert, wird die Position relativ zum Spieler aktualisiert. Da Web Audio HRTF nativ im Browser-Prozess optimiert in C++ ausgeführt wird, entlastet dies den WASM-CPU-Thread massiv gegenüber dem klassischen HL2-Software-DSP.

---

## 5. Lösung des Vtable / Side-Module-Problems

### Das Problem: `_ZTV11IVP_Mindist` vtable-Fehler
Die Source Engine lädt physikalische Berechnungen dynamisch zur Laufzeit aus dem Side-Module `vphysics.so` (bzw. `vphysics.wasm`). Beim Laden des Moduls schlägt die WASM-Instanziierung mit dem Fehler fehl, dass das Symbol `_ZTV11IVP_Mindist` (die Virtual Table für die Klasse `IVP_Mindist` der Physik-Engine Ipion Virtual Physics) als **GOT.mem Import** deklariert ist, aber vom Hauptmodul (`engine.wasm`) nicht exportiert oder aufgelöst werden kann.

#### Warum passiert das?
In C++ GCC/Clang Compilaten gehört die vtable zu einer Klasse dem Modul an, in dem die erste nicht-inline, nicht-rein-virtuelle Methode definiert ist. Wenn die Deklarationen unsauber sind (z. B. weil die IPion-Physik-Header in `vphysics` und der `engine` unterschiedlich eingebunden sind oder Symbole nicht korrekt exportiert werden), geht der Compiler fälschlicherweise davon aus, dass die vtable extern gelagert ist. Bei dynamischen WASM-Modulen führt das dazu, dass ein Side-Module eine vtable aus dem Hauptmodul importieren möchte, dieses das Symbol aber wegoptimiert hat oder gar nicht kennt.

### Lösungsstrategie:

```
[ C++ Quellcode: ivp_mindist.hxx ]
              |
              | 1. Header patchen mit __attribute__((visibility("default")))
              v
     [ Compiler (emcc) ]
              |
              | 2. Linker-Flags: -sMAIN_MODULE=1 (Hauptmodul) & -sSIDE_MODULE=1 (Side-Modul)
              v
[ Generierte WASM-Module ] -> Exportiert & importiert vtable korrekt über GOT.mem / GOT.func
```

#### Empfohlene Lösung (Option C & A kombiniert):
1.  **C++ Patch (Expliziter Export der Klasse):**
    Wir müssen sicherstellen, dass die Symbole von `IVP_Mindist` im Hauptmodul sichtbar sind und nicht als ungelöste Referenz enden. Dazu patchen wir die Klassendefinition in `ivp_mindist.hxx` (oder der entsprechenden Implementierungsdatei `ivp_mindist.cxx`):
    ```cpp
    #if defined(__EMSCRIPTEN__)
      #define DLL_EXPORT __attribute__((visibility("default")))
    #else
      #define DLL_EXPORT
    #endif

    class DLL_EXPORT IVP_Mindist {
        // ... Klassen-Definition ...
    };
    ```
    Dies zwingt den Compiler, die vtable im Hauptmodul bzw. in dem Modul, das sie definiert, explizit zu exportieren.

2.  **Emscripten Linker-Anpassungen (Option A):**
    Wir kompilieren das Hauptmodul mit `-sMAIN_MODULE=1` (oder `2`, um ungenutzten Code zu strippen) und das Side-Module mit `-sSIDE_MODULE=1`.
    *   Wir fügen das vtable-Symbol explizit zu den exportierten Funktionen des Hauptmoduls hinzu, um ein Wegoptimieren durch den LLVM Optimizer zu verhindern:
        ```bash
        emcc ... -sMAIN_MODULE=1 -sEXPORTED_FUNCTIONS="['_ZTV11IVP_Mindist', '_main']"
        ```
    *   *Alternativer Weg (Option B - Monolithischer Build):*
        Da dlsym/dynamisches Laden in WASM einen signifikanten Performance- und Speicher-Overhead hat, ist es für die Quest 3 am stabilsten, die Engine **statisch zu linken**. Wir deaktivieren das dynamische Laden (`dynamicLibraries=[]` wie bei `slqnt`) und linken `vphysics`, `soundemittersystem`, `materialsystem` etc. statisch in ein einziges, monolithisches WASM-Modul (`hl2.wasm`). Dies löst sämtliche Vtable- und GOT.mem-Import-Probleme zur Compile-Zeit auf und verbessert die Ausführungsgeschwindigkeit auf dem VR-Headset drastisch.

---

## 6. Konkrete Emscripten-Flags für Quest 3 WebXR

Um maximale Performance und Stabilität auf dem Snapdragon XR2 Gen 2 Chipsatz der Quest 3 zu erreichen, wird folgende emcc-Konfiguration für das Build-System definiert:

| Flag | Wert | Erklärung / Begründung für Quest 3 |
| :--- | :--- | :--- |
| `-O3` | - | Maximale Performance-Optimierung (Inlining, Loop Vectorization). |
| `-msimd128` | - | Nutzt WASM SIMD-Instruktionen. Kritisch für Physik- und Partikelberechnungen der Source Engine. |
| `-sUSE_PTHREADS=1` | - | Aktiviert Multithreading. Quest 3 hat einen Octa-Core-Prozessor; wir nutzen Threads intensiv. |
| `-sPTHREAD_POOL_SIZE=4` | `4` | Reserviert 4 Web Workers im Voraus. Optimal für Quest 3 (1 Main-Thread, 1 Render/Simulation-Thread, 2 Helfer-Threads für Audio/Netzwerk). Höhere Werte können das RAM-Limit des Browsers sprengen. |
| `-sINITIAL_MEMORY` | `2147483648` | **2 GB** Startspeicher. Source-Engine-Assets (VVD, VTX, BSP) sind speicherintensiv. |
| `-sMAXIMUM_MEMORY` | `3221225472` | **3 GB** absolutes Limit. Höhere Werte führen auf der Quest 3 zum Out-Of-Memory Absturz des Tabs. |
| `-sALLOW_MEMORY_GROWTH=1` | - | Erlaubt dynamische Heap-Vergrößerung bei Bedarf (mit Performance-Warnung, daher hohes Initial-Memory setzen). |
| `-sOFFSCREEN_CANVAS=1` | - | Erlaubt WebGL2-Rendering direkt aus dem WASM-Worker. |
| `-sMIN_WEBGL_VERSION=2` | - | Erzwingt ausschließlich WebGL2 (äquivalent zu OpenGL ES 3.0, passend zum ToGLES-Modus). |
| `-sMAX_WEBGL_VERSION=2` | - | Verhindert unnötigen Fallback-Code für WebGL1 in der JS-Glue-Schicht. |
| `-sENVIRONMENT` | `"web,worker"` | Beschränkt die Laufzeitumgebung, um Node.js-spezifischen Glue-Code einzusparen. |

### C++ Compiler-Defines für die Engine:
*   `-D_GLIBCXX_USE_CXX11_ABI=1` (Moderne C++ ABI)
*   `-DSOURCE_ENGINE_PORT`
*   `-DWEBXR` (Unser Custom-Define für VR-spezifischen Code)

---

## 7. Asset-Loading & Speicher-Optimierung auf der Quest 3

Half-Life 2 umfasst mehrere Gigabyte an Texturen, Sounds und Geometriedaten. Der RAM-limitierten Quest-3-Browserumgebung muss hier Rechnung getragen werden.

```
[ Cloud (CDN) ] -> Download in Chunks -> [ Service Worker / Cache API ] -> [ Origin Private File System (OPFS) ] -> WASM VFS (C++ fopen)
```

### A) Speicherort: Origin Private File System (OPFS)
*   **Status auf Quest 3:** Vollständig unterstützt im Meta Horizon Browser.
*   **Vorteil:** Bietet ein hochperformantes, sandboxed Dateisystem mit direktem, blockierendem Lese-/Schreibzugriff aus dem Web Worker heraus (`FileSystemSyncAccessHandle`).
*   **Implementierung:** Die Spieldateien (VPK-Archive wie `hl2_textures.vpk`, `hl2_sound_misc.vpk` und die BSP-Maps) werden beim ersten Start vom WebServer gestreamt und im OPFS abgelegt. Das WASM-Virtual-File-System (VFS) mountet das OPFS direkt, sodass C++ Standard-IO-Operationen (`fopen`, `fread`) ohne RAM-Zwischenspeicherung direkt auf den Flash-Speicher der Quest 3 zugreifen.

### B) Chunk-Größe & VPK-Streaming
*   **Problem:** Ein 1-GB-Paket im RAM zu entpacken führt zum sofortigen Absturz des Browsers.
*   **Lösung:**
    *   Aufteilen der `.vpk`-Dateien in kleinere Chunks (z.B. **64 MB**-Segmente).
    *   Nutzung eines **Service Workers**, der Anfragen nach bestimmten Offsets abfängt und inkrementell via `Range`-Requests nachlädt.
    *   **On-Demand Loading:** Texturen und Sounds werden erst geladen, wenn die Map sie anfordert (klassisches Source-Engine-Verhalten über das VPK-Verzeichnis).

---

## 8. Konkreter Build- & Implementierungsplan (Delta zu slqnt)

Dieser Schritt-für-Schritt-Plan zeigt die notwendigen Modifikationen gegenüber dem bestehenden 2D-Desktop-Port auf.

### Phase 1: Source-Code-Patches (C++)

1.  **Vtable / Symbolexport fixen:**
    *   Datei `ivp_collision/ivp_mindist.hxx` öffnen.
    *   Klasse `IVP_Mindist` mit Export-Makro versehen (wie in Sektion 5 beschrieben).
2.  **Stereo-Kamera integrieren:**
    *   In `view_render.cpp` (bzw. dem Render-Modul der Engine) den klassischen Single-Camera-Render-Aufruf modifizieren.
    *   Wenn im `WEBXR`-Modus:
        *   Nicht `RenderView()` einmal aufrufen, sondern Matrizen für das linke und rechte Auge aus unserem `XRSharedState` abfragen.
        *   Zwei Render-Pässe ausführen (oder optimalerweise die Shader auf `OVR_multiview2` umstellen).
3.  **Controller-Input einspeisen:**
    *   In `inputsystem/inputsystem.cpp` eine Update-Schleife einbauen, welche die Daten aus dem `XRControllerData_t`-Struct ausliest und in das HL2-Event-Queue-System einspeist.

### Phase 2: JavaScript WebXR Frontend (Wrapper)

Wir erstellen ein robustes JS-Frontend (`index.html` und `xr_wrapper.js`), welches die WebGL2-Instanziierung und die WebXR-Session verwaltet.

```javascript
// xr_wrapper.js
let xrSession = null;
let xrRefSpace = null;
let glCtx = null;

async function initWebXR() {
    const enterVRBtn = document.getElementById('enter-vr-btn');
    const supportsVR = await navigator.xr.isSessionSupported('immersive-vr');
    
    if (supportsVR) {
        enterVRBtn.disabled = false;
        enterVRBtn.addEventListener('click', onEnterVR);
    }
}

async function onEnterVR() {
    xrSession = await navigator.xr.requestSession('immersive-vr', {
        requiredFeatures: ['local-floor'],
        optionalFeatures: ['hand-tracking']
    });
    
    // WebGL2 Context erstellen und an WebXR binden
    const canvas = document.createElement('canvas');
    glCtx = canvas.getContext('webgl2', { xrCompatible: true });
    
    xrSession.updateRenderState({
        baseLayer: new XRWebGLLayer(xrSession, glCtx)
    });
    
    xrRefSpace = await xrSession.requestReferenceSpace('local-floor');
    
    // Startet den WebXR-Renderloop
    xrSession.requestAnimationFrame(onXRFrame);
    
    // WASM-Engine starten (falls noch nicht geladen) und Context übergeben
    startSourceEngineWasm(canvas);
}

function onXRFrame(time, frame) {
    const session = frame.session;
    session.requestAnimationFrame(onXRFrame);
    
    const pose = frame.getViewerPose(xrRefSpace);
    if (pose) {
        // 1. Posen für linkes/rechtes Auge extrahieren und in Shared Array Buffer schreiben
        writePoseToSharedMemory(pose);
        
        // 2. Controller-Input extrahieren und schreiben
        writeInputToSharedMemory(session.inputSources, frame);
        
        // 3. Dem Engine-Worker signalisieren, dass neue Daten bereitstehen
        signalEngineToRender();
    }
}
```

### Phase 3: Build & Deployment

1.  **Modifiziertes Makefile / CMakeLists.txt erstellen:**
    *   Statischen Link-Modus erzwingen, um Side-Module-Probleme vollständig zu eliminieren:
        ```cmake
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -sUSE_PTHREADS=1 -sOFFSCREEN_CANVAS=1 -msimd128")
        # Alle Sub-Bibliotheken (vphysics, materialsystem, etc.) statisch linken
        ```
2.  **Asset-Präparation:**
    *   HL2-Dateien (`.vpk`-Archive) packen, komprimieren und in 64-MB-Chunks auf dem Webserver ablegen.
3.  **Deployment:**
    *   Hoster mit Support für COOP/COEP-Header konfigurieren (z. B. GitHub Pages mit einem dedizierten Service Worker, der diese Header lokal über HTTP-Interzeption simuliert, oder ein Vercel/Render-Backend mit echtem Header-Support).

---

## Zusammenfassung & Risikobewertung

| Risiko | Schweregrad | Gegenmaßnahme |
| :--- | :--- | :--- |
| **Out of Memory (OOM)** | **Hoch** | Aggressives Asset-Streaming; Heap-Limit strikt auf maximal 3 GB im WASM-Compiler begrenzen; Texturauflösungen im Spiel standardmäßig auf "Medium" drosseln. |
| **Motion Sickness** | **Mittel** | Implementierung von Snap-Turning (45°), künstlichem Tunnelblick (Vignette) bei schneller Fortbewegung und Option für Teleportation. |
| **Performance-Drops (< 72Hz)** | **Hoch** | Implementierung von `OVR_multiview2` (Single-Pass Instanced Rendering), um die CPU-Draw-Call-Last zu halbieren. |
| **Sicherheits-Header fehlen** | **Mittel** | Service Worker Proxy nutzen (z.B. `coi-serviceworker.js`), um COOP/COEP-Header clientseitig zu injizieren, falls kein Server-Zugriff besteht. |

Mit dieser Architektur wird die CPU-Last minimiert, der Quest-3-Prozessor über Multithreading optimal ausgelastet und das vtable-Problem durch die Umstellung auf einen performanteren, statisch gelinkten Monolithen elegant umgangen.
