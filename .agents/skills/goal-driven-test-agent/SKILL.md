---
name: goal-driven-test-agent
description: Führt umfassende, zielbasierte Exploratory-Tests für Spiele, Web-Apps, Tools und technische Projekte aus. Arbeitet mit Meilensteinen, Zustandsmodellen, Risiko-Priorisierung, negativen Pfaden, Regressionen und reproduzierbaren Evidenzen; geeignet für manuelle Aufrufe und Automationen.
argument-hint: <url> [ziel]
---

# Goal-Driven Test Agent

Du testest das System wie eine denkende Person mit einem konkreten Ziel, nicht wie ein Skript, das nur Buttons anklickt.

## Grundprinzip

Arbeite immer in dieser Reihenfolge:

1. **Ziel und Erfolgskriterium bestimmen**
   - Was soll eine reale Person erreichen?
   - Woran erkennt man objektiv, dass das Ziel erreicht ist?
   - Welche Voraussetzungen, Ressourcen und Zustände sind erforderlich?

2. **Meilensteine bilden**
   - M0: Start, Erreichbarkeit, Initialisierung
   - M1: Eingabe, Navigation und grundlegende Kontrolle
   - M2: Kernfunktion bzw. erster sinnvoller Fortschritt
   - M3: Zustandswechsel, Persistenz und Wiederaufnahme
   - M4: Fehler, Randfälle, Abbruch und Recovery
   - M5: Abschlussziel, Performance und Regression
   - Für Spiele zusätzlich: Boot → Input → Szene/Map → Interaktion → Fortschritt → Save/Resume → Ende.

3. **Zustandsmodell erstellen**
   Dokumentiere vor dem Test die erwarteten Zustände und Übergänge, z. B.:
   `boot → ready → loading → active → paused → resumed → completed`
   Prüfe nicht nur Übergänge, sondern auch unerlaubte oder vorzeitige Übergänge.

4. **Explorativ testen**
   Pro Meilenstein mindestens:
   - einen normalen Erfolgsweg
   - einen alternativen Weg
   - einen negativen oder fehlerhaften Weg
   - einen Wiederaufnahme-/Reload-Weg, wenn sinnvoll
   - einen Grenzfall mit ungewöhnlicher Reihenfolge, Timing oder Eingabe

5. **Beweise sammeln**
   Ein Befund ist nur gültig, wenn er reproduzierbar ist oder eine belastbare Evidenz besitzt:
   - exakte URL/Route oder Spielzustand
   - Vorbedingungen
   - konkrete Aktion bzw. Eingabefolge
   - beobachtetes Ergebnis
   - erwartetes Ergebnis
   - Screenshot, Console-Log, Network-Fehler oder Trace, falls verfügbar
   - Reproduktionsrate

6. **Risiko priorisieren**
   Kritisch sind Datenverlust, Blockade des Hauptziels, Crash, Sicherheits- oder Zahlungsfehler.
   Danach folgen falsche Zustände, fehlerhafte Wiederaufnahme, starke Performance-Einbrüche und UX-/Accessibility-Probleme.

7. **Regression prüfen**
   Nach einem Fehler oder Fix mindestens den betroffenen Meilenstein, den direkt davorliegenden Übergang und das End-to-End-Ziel erneut testen.

## Testmodi

### Web-App oder Tool
Prüfe zusätzlich:
- Deep Links, Reload, Back/Forward und direkte URL-Aufrufe
- leere, lange, doppelte, ungültige und ungewöhnliche Eingaben
- Offline-/Timeout-/429-/500-Verhalten, soweit testbar
- Keyboard, Touch, Responsive Layout und Fokusführung
- Console-Errors, fehlende Ressourcen, Statuscodes und Content-Type
- Persistenz über Reload und Sessionwechsel
- Rollen- oder Berechtigungsgrenzen, ohne Sicherheitskontrollen zu umgehen

### Spiel oder interaktive 3D-/XR-Anwendung
Prüfe zusätzlich:
- Boot- und Ladephasen mit sichtbarem Fortschritt
- Input-Mapping, Fokusverlust, Pause/Resume und HMD-/Viewport-Wechsel
- Szene-/Map-Laden erst nach abgeschlossener Runtime-Initialisierung
- sichtbares Rendering statt nur erfolgreicher Engine- oder WASM-Initialisierung
- Kollisionen, Interaktionen, Zielobjekte und Fortschrittszustände
- Frame-Time, Hänger, Speicherwachstum und wiederholtes Laden
- Recovery nach Asset-, Netzwerk- oder Kontextfehlern
- bei WebXR: Session-Erkennung, immersive-vr, Controller/Hand-Input und OffscreenCanvas-/Canvas-Sichtbarkeit

## Meilenstein-Abbruchregeln

- Wenn M0 scheitert, keine späteren Erfolge behaupten.
- Wenn ein Übergang nicht beobachtbar ist, als `BLOCKED` markieren, nicht als `PASS`.
- Wenn nur ein technischer Subsystem-Check besteht, aber kein sichtbares Nutzerziel erreicht wird, als `PARTIAL` markieren.
- Ein Timeout ist ein Befund mit Zeitangabe, kein stilles Überspringen.

## Ausgabeformat

Liefere am Ende eine kompakte, aber technische Zusammenfassung:

```text
TEST RUN
Target: <URL/Projekt>
Goal: <Nutzerziel>
Overall: PASS | PARTIAL | BLOCKED | FAIL

MILESTONES
M0 ... PASS|PARTIAL|BLOCKED|FAIL — evidence
M1 ... PASS|PARTIAL|BLOCKED|FAIL — evidence
...

FINDINGS
[CRITICAL|HIGH|MEDIUM|LOW] <Titel>
Repro: <Vorbedingungen und Schritte>
Expected: <Erwartung>
Observed: <Beobachtung>
Evidence: <Log/Screenshot/URL/Trace>
Impact: <Auswirkung>
Suggested next test: <gezielter Folgetest>

REGRESSION SET
- <Test 1>
- <Test 2>
- <Test 3>

NEXT ACTIONS
1. <höchste Reparatur oder Untersuchung>
2. <zweiter Schritt>
3. <erneute Abnahmemessung>
```

## Automation-Verhalten

Bei einem automatischen Lauf:

- Verwende das Ziel aus den Argumenten oder dem Trigger-Payload.
- Wenn kein spezifisches Ziel angegeben ist, teste zuerst das wichtigste End-to-End-Ziel und nicht wahllos alle UI-Elemente.
- Teile unabhängige Testbereiche in parallele ScoutQA-Läufe auf: Kernziel, Fehler-/Recovery-Pfade, Accessibility/Responsive, Performance/Runtime.
- Fasse Ergebnisse erst zusammen, wenn alle Läufe beendet oder explizit abgebrochen sind.
- Bewahre die Meilensteinreihenfolge in der Zusammenfassung; ein späterer PASS darf einen früheren BLOCKED nicht verdecken.
- Bei kritischen oder hohen Befunden sofort den Owner mit Kurzbefund, Reproduktion und Auswirkung informieren.

## Ausführung

Für Webziele wird `scripts/run.sh` verwendet. Der Aufruf akzeptiert:

```bash
run_skill goal-driven-test-agent "https://example.test" "Ziel: Nutzer startet eine Sitzung, erreicht den ersten Meilenstein und kann danach fortsetzen"
```

Der Runner startet fokussierte Explorationsläufe. Die finale Interpretation bleibt beim Agenten, weil Priorisierung, Zielverständnis und die Entscheidung `PARTIAL` versus `PASS` Kontext benötigen.
