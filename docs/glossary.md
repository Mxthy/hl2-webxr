# Glossar (HL2 WebXR)

Dieses Dokument definiert die im HL2 WebXR-Projekt verwendeten Fachbegriffe, Dateiformate und Toolchain-Komponenten.

---

## Dateiformate & Engine-Strukturen

### BSP (.bsp)
- **Binary Space Partitioning:** Das compiled Map-Format der Source-Engine. Enthält die Geometrie der Map, Lichtdaten (Lightmaps), Entity-Platzierungen und Sichtbarkeitslisten (PVS).

### VTF (.vtf)
- **Valve Texture Format:** Das proprietäre Texturformat der Source-Engine. Es enthält Bilddaten, Mipmaps und kann plattformspezifisch komprimiert sein. Wird zur Laufzeit in WebGL-Texturen konvertiert.

### VMT (.vmt)
- **Valve Material Type:** Eine Textdatei, die die Eigenschaften eines Materials beschreibt (z.B. welche `.vtf`-Textur geladen werden soll, Shader-Typen wie `LightmappedGeneric` oder `VertexLitGeneric`, Transparenz und Reflexionen).

### MDL (.mdl)
- **Model File:** Das Hauptformat für dreidimensionale Modelle in der Source-Engine. Enthält Skelett-Animationen, Kollisionsmodelle und Verweise auf Texturen.

### VVD (.vvd)
- **Valve Vertex Data:** Enthält die Vertex-Buffer-Daten (Positionen, Normalen, Tangenten, UV-Koordinaten) für ein entsprechendes `.mdl`-Modell.

### VPK / GCF (.vpk / .gcf)
- **Valve Pack File / Game Cache File:** Archivformate von Valve zur Paketierung von Spieldaten. 
- *Hinweis im Projekt:* Der HL2 Retail Build 2153 liegt bereits in einer entpackten Ordnerstruktur vor, weshalb kein Laufzeit-Entpacker oder Wine/HLExtract für den Build-Prozess benötigt wird.

---

## WebAssembly & Runtime-Architektur

### post.js
- Eine JavaScript-Datei, die von Emscripten am Ende des generierten Codes eingefügt wird. Sie wird genutzt, um das Verhalten der Laufzeitumgebung anzupassen, Dateizugriffe abzufangen und in unserem Fall den parallelen Multi-Chunk-Ladevorgang zu orchestrieren.

### Chunk
- Ein segmentierter Satz verpackter Spieldaten (z.B. `materials.data`). Chunks werden parallel über das Netzwerk übertragen, um die Bandbreite optimal zu nutzen und den Ladebalken präzise zu steuern.

### Side-Module (.so)
- Dynamisch ladbare Bibliotheken (Shared Objects) im WebAssembly-Kontext. Emscripten erlaubt es, mithilfe des Compilerflags `SIDE_MODULE=1` Module zu erstellen, die zur Laufzeit mittels `dlopen` vom Hauptmodul geladen werden.

### COOP/COEP
- **Cross-Origin-Opener-Policy (COOP)** und **Cross-Origin-Embedder-Policy (COEP):** Sicherheitsfeatures moderner Browser. Sie müssen serverseitig über HTTP-Header erzwungen werden, damit die Webseite Zugriff auf den `SharedArrayBuffer` erhält.

### SharedArrayBuffer
- Ein Web-Sicherheits-relevantes JavaScript-Objekt, das es mehreren Web Workern (Threads) erlaubt, direkt auf denselben Speicherbereich im RAM zuzugreifen. Essentiell für das Multithreading (`-sPTHREADS=1`) der Source-Engine.

---

## Toolchain & Build-System

### waf
- Ein Python-basiertes Build-System, das im Source-Engine-Submodule verwendet wird, um Compiler-Aufrufe, Include-Pfade und Linker-Argumente plattformunabhängig zu verwalten.

### emsdk / Emscripten
- Die Toolchain zur Kompilierung von C/C++ Code in hochperformantes WebAssembly (WASM). Bietet Kompatibilitätsschichten für POSIX-APIs, OpenGL (toGLES) und SDL2.

### toGLES
- Ein Konfigurationsflag im waf-Buildsystem, das anweist, die OpenGL-Aufrufe der Source-Engine für OpenGL ES (bzw. WebGL im Browser) anzupassen.
