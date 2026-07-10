# Save-State Options
## HL2 WebGL2/WebXR Porting Manager

Generated: 2026-07-10
Regel: Optionen vergleichen, NICHT sofort festlegen (per Projektregeln).

---

## Übersicht der Save-State-Strategien

### Option A: IDBFS (Emscripten IndexedDB Filesystem)
**Status: CONFIRMED — von slqnt implementiert**

**Beschreibung:**
Emscripten mappt ein virtuelles Filesystem auf IndexedDB im Browser. Das Spiel schreibt/liest Saves wie auf einem normalen Dateisystem. Emscripten-IDBFS synchronisiert periodisch oder auf Anforderung.

**Vorteile:**
- Bereits im slqnt-Port implementiert und verifiziert (CONFIRMED)
- Transparent für den Source-Engine-Code (kein Game-Code-Rewrite)
- Unterstützt alle Browser mit IndexedDB-Support
- Persistiert über Sessions hinweg

**Nachteile:**
- Kein Cross-Device-Sync
- Browser kann IDB-Daten löschen (Storage Pressure)
- Quota-Limits je nach Browser (~1-10 GB typisch)
- Synchronisierung muss explizit aufgerufen werden (`FS.syncfs()`)

**Build-Flag:** `-sFETCH_SUPPORT_INDEXEDDB=1`

---

### Option B: WASMFS mit IDBFS-Backend
**Status: INFERRED möglich**

**Beschreibung:**
Emscripten's neueres WASMFS-System mit IDBFS als Persistenz-Backend. Saubere Architektur, bessere Performance.

**Vorteile:**
- Modernere Architektur als klassisches MEMFS+IDBFS
- Bessere Performance-Charakteristik (INFERRED)

**Nachteile:**
- Experimentell / weniger erprobt für große Game-Ports
- Kompatibilität mit nillerusr-Source-Engine unklar
- Weniger Dokumentation für Game-Port-Use-Case

**Build-Flag:** `-sWASMFS=1`

---

### Option C: Fetch API + Remote Storage
**Status: INFERRED — für Cloud-Saves**

**Beschreibung:**
Save-Dateien werden über Fetch API an einen Backend-Server gesendet und dort gespeichert. Ermöglicht Cross-Device-Sync.

**Vorteile:**
- Cross-Device-Sync möglich
- Kein lokaler Storage-Limit-Problem
- Backend-kontrollierte Retention

**Nachteile:**
- Erfordert Backend-Server + Auth-System
- Latenz beim Speichern/Laden
- Datenschutz/Privacy-Fragen
- Komplexität deutlich höher

**Empfehlung:** Erst in Phase 2+ evaluieren, nach stabilem IDBFS-Basis-System

---

### Option D: localStorage (Einfach, limitiert)
**Status: INFERRED — nur für kleine Daten**

**Beschreibung:**
Browser localStorage für minimale Save-Daten (Checkpoint-IDs, Einstellungen).

**Vorteile:**
- Extrem einfach
- Universell unterstützt

**Nachteile:**
- 5-10 MB Limit — zu klein für vollständige HL2-Saves
- Nur synchron, blockiert Main Thread
- Strings only (kein Binary)

**Empfehlung:** Nur für Settings/Config, nicht für Game-Saves

---

### Option E: Origin Private File System (OPFS)
**Status: INFERRED — moderne Alternative**

**Beschreibung:**
Neues Web-Filesystem-API (File System Access API, OPFS). Höhere Performance als IDB, größere Quotas.

**Vorteile:**
- Schneller als IndexedDB für binäre Dateien
- Größere Quotas
- Kann aus Worker-Thread genutzt werden

**Nachteile:**
- Neueres API, ältere Browser-Unterstützung eingeschränkt
- Emscripten-Integration weniger erprobt
- Kein fertiger OPFS-Backend für Emscripten FS (Stand: Juli 2026)

---

## Vergleichsmatrix

| Option | Persistenz | Quota | Cross-Device | Komplexität | Emscripten-Support | Erprobt für HL2 |
|---|---|---|---|---|---|---|
| A: IDBFS | ✅ | Mittel | ❌ | Niedrig | ✅ CONFIRMED | ✅ JA |
| B: WASMFS+IDBFS | ✅ | Mittel | ❌ | Mittel | ⚠️ Experimentell | ❌ NEIN |
| C: Remote Backend | ✅ | Unbegrenzt | ✅ | Hoch | Manuell | ❌ NEIN |
| D: localStorage | ⚠️ | Sehr klein | ❌ | Sehr niedrig | ✅ | ⚠️ Nur Settings |
| E: OPFS | ✅ | Groß | ❌ | Mittel | ⚠️ Eingeschränkt | ❌ NEIN |

---

## Empfehlung (vorläufig, nicht final)

**Phase 1:** Option A (IDBFS) — bereits von slqnt verifiziert, niedrigstes Risiko.
**Phase 2:** Option C (Remote Backend) optional für Cloud-Sync evaluieren.
**Nicht empfohlen:** Option B, D, E für Phase 1.

**Entscheidung: AUSSTEHEND** — muss durch Team/Führungsperson final festgelegt werden.
