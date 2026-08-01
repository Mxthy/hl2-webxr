---
name: security-red-team-two-phase
description: Führt autorisierte, defensive Sicherheitstests mit strikt getrennter Analyse- und Fix-Phase durch. Dokumentiert Schwachstellen reproduzierbar und wendet Patches erst nach abgeschlossenem Analyse-Report und expliziter Fix-Freigabe an.
argument-hint: <target> [scope-or-goal]
---

# Security Red-Team — Two-Phase Defensive Testing

Arbeite wie ein potenzieller Angreifer, aber ausschließlich auf ausdrücklich autorisierten Zielen und mit defensiver Absicht. Die zentrale Sicherheitsregel ist die harte Trennung:

- **Phase A — ANALYZE:** beobachten, modellieren, testen, reproduzieren und notieren; keine Projektdateien verändern.
- **Phase B — FIX:** den eingefrorenen Report prüfen, minimal patchen, Tests ausführen und Regressionen dokumentieren.

Nie Analyse und Fix in einem unkontrollierten Schritt vermischen.

## Autorisierungs- und Sicherheitsgrenzen

Vor Phase A klären oder als Annahme dokumentieren:

- Zielsystem, Repository oder URL
- erlaubter Testumfang und ausgeschlossene Bereiche
- Testfenster, Rate-Limits und maximale Last
- ob Testdaten oder produktive Daten vorkommen
- verantwortliche Person und Rollback-Möglichkeit

Nicht durchführen:

- Credential-Diebstahl, Phishing, Social Engineering oder reale Kontoübernahme
- Persistenz, Malware, Backdoors, Privilege Escalation über das notwendige Proof-of-Concept hinaus
- destruktive Aktionen, Datenlöschung, unkontrollierte Lasttests oder exfiltrierte Geheimnisse
- Exploit-Ketten gegen fremde oder nicht freigegebene Systeme

Verwende stattdessen minimal-invasive, synthetische Testdaten und beende einen Test, sobald die Schwachstelle ausreichend belegt ist.

## Phase A — ANALYZE

### 1. Scope und Systemmodell

Erfasse evidenzbasiert:

- Entry Points: HTTP-Routen, Webhooks, Uploads, Parser, CLI, Worker, Adminpfade
- Trust Boundaries: Browser/Server, Service/Service, User/Admin, Build/Deploy, Drittanbieter
- Assets: Tokens, Sessions, PII, Dateien, Konfiguration, Build-Artefakte, Integrität und Verfügbarkeit
- Authentisierung, Autorisierung, Validierung, Rate-Limits, Logging und Fehlergrenzen
- Runtime gegenüber CI/Build/Dev-Tooling getrennt

Keine Architekturannahme als Tatsache darstellen, wenn sie nicht im Code, in Konfiguration oder im beobachteten Verhalten belegt ist.

### 2. Angreifermodell

Formuliere realistische Fähigkeiten:

- unauthentifizierter Internetnutzer
- authentifizierter Nutzer mit eigener Rolle
- kompromittierter Account mit begrenzten Rechten
- bösartiger oder manipulierter Input in Upload, Parser, URL, Header oder Message
- Supply-Chain- oder CI-Angreifer nur, wenn der Scope das einschließt

Nicht automatisch annehmen, dass ein Angreifer Serverzugriff, gültige Secrets oder Administratorrechte besitzt.

### 3. Zielbasierte Testpfade

Für jedes priorisierte Asset mindestens prüfen:

- normaler Zugriff und erwartete Autorisierung
- Boundary-/Rollenwechsel
- ungültige, leere, zu große, doppelte und typverfälschte Eingaben
- Session-, Token-, Origin-, CSRF- und Replay-Verhalten, sofern relevant
- Fehler-, Timeout-, Reload- und Recovery-Pfad
- Rate-Limit- und Ressourcenverhalten mit sicherer, niedriger Last
- Logging und Fehlermeldungen auf Secret-/PII-Leaks

Bei Web-, Spiel- oder XR-Projekten zusätzlich Runtime- und Asset-Grenzen prüfen: untrusted URLs, Binary-/Chunk-Parser, WebAssembly/Worker-Grenzen, Cross-Origin-Policies, dynamische Module und Dateipfade.

### 4. Befundstandard

Jeder Befund braucht:

```text
ID: SEC-YYYY-NNN
Severity: CRITICAL | HIGH | MEDIUM | LOW | INFO
Status: CONFIRMED | SUSPECTED | BLOCKED | NOT_REPRODUCIBLE
Asset/Boundary: ...
Location: Datei:Zeile, Route oder reproduzierbare URL
Preconditions: ...
Reproduction: nummerierte, sichere Schritte
Expected: ...
Observed: ...
Impact: Vertraulichkeit / Integrität / Verfügbarkeit / AuthZ
Evidence: Log, Response-Metadaten, Screenshot, Testoutput oder Hash
Likelihood: LOW | MEDIUM | HIGH — Begründung
Recommended patch: minimaler Gegenentwurf, noch nicht angewendet
Regression tests: konkrete Abnahmetests
```

Keine Secrets in Reports schreiben. Tokens, Cookies, private Schlüssel und personenbezogene Daten redigieren.

### 5. Analyse-Report einfrieren

Schreibe den Report nach `security-reports/security-analysis-<timestamp>.md` und zusätzlich eine maschinenlesbare Zusammenfassung nach `security-reports/security-analysis-<timestamp>.json`.

Der Report muss enthalten:

- Scope, Autorisierungsannahmen und Testzeitraum
- Systemmodell, Assets und Trust Boundaries
- getestete Meilensteine und nicht getestete Bereiche
- Befunde nach Priorität
- sichere Reproduktion und Evidenz
- empfohlene Fixes, aber keine bereits behaupteten Fixes
- offene Fragen und Restrisiken

Nach Phase A darf der Agent keine Dateien patchen, auch nicht „nebenbei“ zur Verifikation.

## Übergang A → B

Phase B ist nur erlaubt, wenn:

1. ein Analyse-Report existiert und lesbar ist;
2. jeder Befund `CONFIRMED` oder ausdrücklich als zu verifizierender `SUSPECTED` markiert ist;
3. Scope und Autorisierung weiter gelten;
4. der Nutzer oder eine konfigurierte Automation die Fix-Phase ausdrücklich freigibt;
5. ein sauberer Git-/Dateistand oder ein Rollback-Punkt bekannt ist.

Wenn eine Bedingung fehlt: stoppen und `BLOCKED` melden.

## Phase B — FIX

Für jeden freigegebenen Befund in Prioritätsreihenfolge:

1. Report und betroffene Datei/Route erneut lesen.
2. Ursache vom Symptom trennen.
3. Minimalen Patch mit kleinstem Berechtigungs- und Verhaltensumfang entwerfen.
4. Patch anwenden — keine unnötigen Refactorings.
5. Statische Checks, Unit-/Integrationstests und den ursprünglichen Reproduktionstest ausführen.
6. Negativtest bestätigen: der alte Angriffspfad scheitert.
7. Positivtest bestätigen: das legitime Ziel funktioniert weiter.
8. Regressionen in direkt angrenzenden Vertrauensgrenzen prüfen.
9. Report um `FIXED`, `PARTIAL`, `WONT_FIX` oder `BLOCKED` ergänzen.

Ein Patch gilt erst als `FIXED`, wenn der ursprüngliche Befund nicht mehr reproduzierbar ist und der Regressionstest bestanden wurde. Bei fehlgeschlagenem Test Patch nicht als erledigt markieren.

## Fix-Protokoll

Für jeden angewendeten Patch dokumentieren:

```text
Finding: SEC-...
Changed: Datei:Zeile oder Komponente
Root cause: ...
Patch summary: ...
Tests before: ...
Tests after: ...
Negative test: BLOCKED/PASS
Positive regression: PASS/FAIL
Rollback: Commit, Patch oder Wiederherstellungspfad
Residual risk: ...
```

## Automationsmodus

Nutze `scripts/run.sh` als Phasenwächter:

```bash
# Nur Analyse; schreibt Report, verändert keine Projektdateien
run_skill security-red-team-two-phase "analyze" "https://target.example" "primary user/API scope"

# Fix nur nach konkretem Analyse-Report und expliziter Freigabe
run_skill security-red-team-two-phase "fix" "security-reports/security-analysis-20260801T120000Z.md" "--approve"
```

Der Runner prüft Phase, Reportpfad und Freigabe. Die eigentliche technische Bewertung und das Anwenden eines minimalen Patches übernimmt der Agent mit den verfügbaren Datei- und Testwerkzeugen; ein Script darf nicht eigenmächtig beliebige Sicherheitsänderungen an unbekanntem Code vornehmen.

## Abschlussausgabe

```text
SECURITY RUN
Phase: ANALYZE | FIX
Target/scope: ...
Authorization: ...
Overall: PASS | FINDINGS | BLOCKED

Findings:
- SEC-... [severity/status] — one-line impact

Phase A evidence: report path + hash
Phase B changes: files/commits or NONE
Tests: passed / failed / blocked
Residual risk: ...
Next action: ...
```
