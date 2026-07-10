# Phase 1 Build Plan
## HL2 WebGL2 Browser Port — Porting Manager

Generated: 2026-07-10
Scope: Nur WebGL2-Basis. Kein WebXR in Phase 1.

---

## Ziele Phase 1

1. Funktionierender WebGL2-Render-Pfad (GLES via ToGLES → Emscripten → WebGL2)
2. Asset-Pipeline: GCF-Extraktion → VPK-Unpacking → .data-Packing pro Map
3. Stabiles Gameplay ohne Face-Morphing
4. Save/Load über IDBFS
5. Korrekte Input-Bindings (inkl. Crouch auf C)

---

## Phasen-Übersicht

### Phase 1.0 — Environment Setup
**Ziel:** Reproduzierbares Build-Environment

- [ ] Emscripten SDK installieren (emsdk, aktuelle stabile Version)
- [ ] nillerusr/source-engine klonen
- [ ] weliveinhell Portal-Port als Referenz klonen
- [ ] Asset-Packing-Skripte sichern (weliveinhell + slqnt Windows-Version)
- [ ] GCFExplorer bereitstellen

**Blocker:** weliveinhell GitHub-URL unbekannt → muss recherchiert werden
**Status:** PENDING

---

### Phase 1.1 — Engine-Basis verifizieren
**Ziel:** Kompilierbare Engine-Basis

- [ ] nillerusr/source-engine bauen (nativ, Linux)
- [ ] ToGLES-Modus aktivieren und testen
- [ ] Emscripten-Build-Pipeline konfigurieren
- [ ] Erste WASM-Kompilation (ohne Assets)

**Build-Flags (minimal):**
```bash
-sMAX_WEBGL_VERSION=2
-sMIN_WEBGL_VERSION=2
-sALLOW_MEMORY_GROWTH=1
-sCASE_INSENSITIVE_FS=1
-sFULL_ES2=1
-sEXIT_RUNTIME=0
-sFILESYSTEM=1
```

**Status:** PENDING

---

### Phase 1.2 — Asset-Pipeline
**Ziel:** Assets für eine Map extrahiert und gepackt

- [ ] ARC-01 (Retail 2153) herunterladen und entpacken
- [ ] GCF-Dateien mit GCFExplorer extrahieren (Keys aus ARC-01 README)
- [ ] VPK-Tool konfigurieren (falls Assets in VPK-Format vorliegen)
- [ ] Asset-Logging-Modus aktivieren (Print-Statement in Engine)
- [ ] Erste Map: `d1_trainstation_01` als Pilot-Map
- [ ] .data-File für Pilot-Map erzeugen

**Kompatibilitäts-Check:** Build-2153-Assets gegen nillerusr-Engine testen
**Fallback:** steam_legacy-Branch-Assets beschaffen (Steam-Account erforderlich)
**Status:** PENDING — Kompatibilität UNBEKANNT

---

### Phase 1.3 — Render-Debug
**Ziel:** Sauberer WebGL2-Render ohne offensichtliche Artefakte

- [ ] Lightmap-Bug untersuchen und fixen (slqnt-Fix als Referenz)
- [ ] Flashlight Null-Texture fixen
- [ ] Wasser-Rendering fixen
- [ ] Face-Morphing-System deaktivieren (CONFIRMED-Schritt)
- [ ] Basis-Shader-Validierung

**Status:** PENDING

---

### Phase 1.4 — Gameplay-Bugs
**Ziel:** Grundlegendes Gameplay funktioniert

- [ ] Medkits/Batterien-Bug fixen (Referenz: Contrib "98" in slqnt-Port)
- [ ] Gravity Gun Inventory-Bug fixen
- [ ] NPC random collapse fixen
- [ ] Headcrab/Zombie Schaden-Bug fixen
- [ ] Crouch auf C rebinden

**Status:** PENDING

---

### Phase 1.5 — Save System
**Ziel:** Funktionierendes Save/Load

- [ ] IDBFS in Build integrieren (`-sFETCH_SUPPORT_INDEXEDDB=1`)
- [ ] `FS.syncfs()` an richtigen Stellen im Engine-Code aufrufen
- [ ] Save/Load testen (inkl. Browser-Reload-Persistenz)

**Status:** PENDING

---

### Phase 1.6 — Stabilisierung & QA
**Ziel:** Vollständige Hauptkampagne spielbar

- [ ] Alle Maps durchspielen (automatisiert oder manuell)
- [ ] Performance-Profiling (WebGL Inspector, Browser DevTools)
- [ ] Memory-Leak-Check
- [ ] Cross-Browser-Test (Chrome, Firefox, Edge)

**Status:** PENDING

---

## Nicht in Phase 1

- WebXR / VR-Modus → Phase 3
- Episode One/Two → Phase 3
- Cloud-Saves → Phase 2
- Face Morphing → Indefinitely deferred

---

## Kritischer Pfad

```
1.0 Environment Setup
    → 1.1 Engine Build
        → 1.2 Asset Pipeline
            → 1.3 Render Debug
                → 1.4 Gameplay Bugs
                    → 1.5 Save System
                        → 1.6 QA
```

---

## Ressourcen-Schätzung

**INFERRED — keine gesicherte Basis:**
- 1.0: 1-2 Tage
- 1.1: 3-5 Tage
- 1.2: 3-7 Tage (abhängig von Asset-Kompatibilität)
- 1.3: 5-10 Tage
- 1.4: 3-5 Tage
- 1.5: 1-2 Tage
- 1.6: 5-10 Tage

**Gesamt-Schätzung Phase 1:** 3-6 Wochen (1 Entwickler, Vollzeit) — SEHR UNSICHER
