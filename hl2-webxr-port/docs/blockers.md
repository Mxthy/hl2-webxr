# Blockers
## HL2 WebGL2/WebXR Porting Manager

Generated: 2026-07-10

---

## Aktive Blocker

### BLK-001 — weliveinhell GitHub URL unbekannt
**Schweregrad:** HOCH
**Status:** OFFEN
**Betrifft:** T-002, T-005 (Engine Build), Asset-Packing-Skripte

**Problem:**
slqnt erwähnt "weliveinhell on github" als Autor des Portal-Browser-Ports und des Asset-Packing-Skripts.
Die genaue Repository-URL ist aus den analysierten Quellen nicht ableitbar.

**Impact:**
Ohne das weliveinhell-Repo fehlt der direkte Zugang zu:
- Bewährtem Asset-Packing-Skript (Linux-Version)
- Emscripten-Build-Konfiguration für Source Engine
- Bekannten Fixes für den Browser-Port

**Auflösung:**
1. GitHub-Suche: `site:github.com weliveinhell source-engine`
2. Suche nach "portal browser port emscripten" auf GitHub
3. Kontaktaufnahme mit slqnt (Discord/GitHub) für direkten Link

---

### BLK-002 — slqnt Port-Quellcode nicht öffentlich
**Schweregrad:** MITTEL
**Status:** OFFEN
**Betrifft:** Patch-Implementierung (T-009)

**Problem:**
Der slqnt HL2-Browser-Port ist live auf `hl2.slqnt.dev`, aber der Quellcode
ist nach aktuellem Stand nicht öffentlich zugänglich.
Die Patches (Lightmap-Fix, NPC-Fix etc.) sind im Blogartikel beschrieben
aber nicht als Code verfügbar.

**Impact:**
Alle Patches müssen neu implementiert werden basierend auf:
- Blog-Beschreibungen (CONFIRMED — vorhanden aber undetailliert)
- Reverse Engineering der Live-Version
- Eigenentwicklung

**Auflösung:**
1. slqnt kontaktieren (Discord/GitHub) und nach Open-Source-Status fragen
2. weliveinhell-Repo (BLK-001) löst möglicherweise Teile davon
3. Community: Source Engine Modding-Foren für Lightmap/NPC-Bugs

---

### BLK-003 — Build-2153-Kompatibilität mit nillerusr ungesichert
**Schweregrad:** HOCH
**Status:** OFFEN — Test erforderlich
**Betrifft:** T-006 (Asset Compatibility Test)

**Problem:**
slqnt verwendet explizit den `steam_legacy`-Branch, weil Build 2153
(Pre-Anniversary) nicht mit der nillerusr-Engine-Basis kompatibel ist.
Diese Inkompatibilität wurde nicht im Detail beschrieben.

**Impact:**
- Wenn inkompatibel: ARC-01 kann nicht direkt genutzt werden
- Fallback: Steam-Account mit HL2 erforderlich für `steam_legacy`-Assets
- Beschaffung alternativer Pre-Anniversary-Assets unklar

**Auflösung:**
1. Test: ARC-01-Assets in nillerusr-Engine laden → Fehleranalyse
2. Falls inkompatibel: Steam `steam_legacy`-Branch-Assets beschaffen
3. Alternative: Analyse welche Asset-Formate sich unterscheiden

---

### BLK-004 — Archive.org-Quellen entfernt (50%)
**Schweregrad:** NIEDRIG (Workaround verfügbar)
**Status:** PERMANENT
**Betrifft:** ARC-02, ARC-04

**Problem:**
- ARC-02 (Collector's Edition) — entfernt
- ARC-04 (Complete Edition Linux Steam Rip) — entfernt

**Impact:**
- Collector's Edition: kein direkter Ersatz nötig (ARC-01 deckt Basis ab)
- Complete Edition (Linux): wäre ideal für EP1/EP2 + Linux-Build gewesen

**Auflösung:**
- ARC-01 als primäre Quelle bestätigt (ausreichend für Phase 1)
- ARC-03 (EP1 PROViSiON) für Phase 3 EP1-Port
- EP2-Quelle: UNKNOWN — muss für Phase 3 neu recherchiert werden

---

## Latente Blocker (zukünftige Phasen)

| ID | Beschreibung | Phase |
|---|---|---|
| BLK-005 | Face-Morphing-Fix — Bug-Ursache unbekannt | Indefinitely deferred |
| BLK-006 | WebXR API: HTTPS-Pflicht, Debugging komplex | Phase 3 |
| BLK-007 | Audio-System unklar (OpenAL vs Web Audio) | Phase 1.1 |
| BLK-008 | EP2-Asset-Quelle fehlt (ARC-04 entfernt) | Phase 3 |

---

## Blocker-Zusammenfassung

| ID | Schweregrad | Phase | Status |
|---|---|---|---|
| BLK-001 | HOCH | 1.0 | OFFEN |
| BLK-002 | MITTEL | 1.3/1.4 | OFFEN |
| BLK-003 | HOCH | 1.2 | TEST ERFORDERLICH |
| BLK-004 | NIEDRIG | 1.2 | PERMANENT (Workaround: ARC-01) |
| BLK-005 | LATENT | Später | — |
| BLK-006 | LATENT | Phase 3 | — |
| BLK-007 | LATENT | Phase 1.1 | — |
| BLK-008 | LATENT | Phase 3 | — |
