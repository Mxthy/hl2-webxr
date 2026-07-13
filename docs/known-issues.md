# Bekannte Probleme & Workarounds (HL2 WebXR)

Dieses Dokument erfasst alle bekannten Laufzeit-, Build- und Asset-Probleme im HL2 WebXR-Projekt sowie deren Lösungen und Workarounds.

---

## 1. Undefined Symbol `_ZTV11IVP_Mindist` beim Linken

- **Symptom:** Beim Linken der Side-Modules oder des Hauptmoduls wird eine Warnung über das fehlende Symbol `_ZTV11IVP_Mindist` ausgegeben.
- **Ursache:** Virtueller Tabellen-Crash (vtable) und Optimierungs-Aggressivität von Emscripten/Clang bei komplexen physikalischen Berechnungen im IVP-Subsystem.
- **Status:** Gelöst (Workaround aktiv).
- **Lösung / Workaround:** 
  - Setzen des Linker-Flags `-sERROR_ON_UNDEFINED_SYMBOLS=0`. Dadurch bricht der Linker nicht ab, sondern verschiebt die Symbolauflösung auf die Laufzeit.
  - Patch in `ivp_mindist_minimize.cxx` mittels `#ifdef __EMSCRIPTEN__` Compiler-Guards, um den vtable-Crash zur Laufzeit zu unterbinden.

---

## 2. Inkrementelle Build-Fehler durch Waf-Cache

- **Symptom:** Nach Quellcodeänderungen fehlen beim inkrementellen Build Symbole in den Side-Modules (`.so`), oder der Compiler linkt veraltete Objektdateien zusammen.
- **Ursache:** Das waf-Buildsystem verwaltet den Cache unter Emscripten unzuverlässig, wenn Header oder Compiler-Flags geändert werden.
- **Status:** Gelöst (CI-Spezifischer Fix).
- **Lösung / Workaround:**
  - Vor jedem CI/CD-Lauf und vor jedem kritischen lokalen Compile-Vorgang muss das gesamte `build/`-Verzeichnis restlos gelöscht werden.
  - CI-Command: `find build/ -mindepth 1 -delete` vor dem Aufruf von `ci-build.sh`.

---

## 3. Map-Name-Inkompatibilität (`background1` vs `background01`)

- **Symptom:** Die Engine versucht beim Start, die Map `background1` zu laden und stürzt ab, da diese in den Original-HL2-Assets nicht existiert.
- **Ursache:** Der zugrunde liegende Engine-Fork stammt von einem Portal-Port, welcher standardmäßig `background1.bsp` erwartet. Der originale HL2 Retail-Build 2153 besitzt jedoch stattdessen `background01.bsp`.
- **Status:** Gelöst (Runtime-JS Patch).
- **Lösung / Workaround:**
  - `post.js` fängt die Dateizugriffe und Startup-Argumente der Engine ab und patcht den Map-Pfad dynamisch zur Laufzeit von `background1` auf `background01`.

---

## 4. Canvas-Größe initial 0x0

- **Symptom:** Die Engine startet, im Log sind keine Fehler sichtbar, aber der Bildschirm bleibt komplett schwarz und das HTML5 Canvas-Element hat eine Dimension von `0x0` Pixeln.
- **Ursache:** Die Source-Engine-Portierung setzt die Fenstergröße im Emscripten-Canvas nicht automatisch über die Web-Oberfläche.
- **Status:** Gelöst (Web-Frontend Workaround).
- **Lösung / Workaround:**
  - Die Canvas-Dimensionen müssen explizit im umschließenden HTML/JS gesetzt werden, bevor die Engine mit der Initialisierung des WebGL-Kontexts beginnt.

---

## 5. Zu große Asset-Dateien (materials.data > 498MB)

- **Symptom:** Der Browser bricht den Download ab oder stürzt aufgrund von Speichermangel ab, wenn die Assets in einer einzigen großen Datei geladen werden.
- **Ursache:** Emscriptens standardmäßiger File-Packer erzeugt monolithische `.data`-Dateien. Ein einzelnes Paket mit allen HL2-Assets würde über 1 GB groß sein.
- **Status:** Gelöst (Multi-Chunk-Strategie).
- **Lösung / Workaround:**
  - Aufteilung der Assets in drei funktionale, parallel geladene Chunks: `background01.data` (~25MB), `materials.data` (~498MB) und `models.data`.
  - Parallel-Download via `Promise.all` in `post.js` und anschließender Aufruf von `removeRunDependency()`.

---

## 6. Unvollständige WebXR-Implementierung

- **Symptom:** WebXR-Modus startet nicht oder verliert den Render-Kontext beim Verlassen der VR-Session.
- **Ursache:** Der WebXR-Session-Lifecycle sowie die Übertragung der Frames über einen Offscreen-Canvas innerhalb des Render-Threads sind noch unvollständig.
- **Status:** Offen (Phase 3).
- **Lösung / Workaround:**
  - Aktuell in Phase 3 der Roadmap. Der Render-Thread muss über eine SharedArrayBuffer-Bridge mit dem Haupt-Thread synchronisiert werden, um die WebXR-Gamepads und Posen-Daten latenzfrei zu übertragen.
