
# Base44 Auftrag: HL2 WebXR/WebGL2 Portierungsmanager

## Ziel
Baue aus den bereitgestellten Referenzen eine eigenständige Wissensbasis und danach einen Portierungsmanager für ein WebXR/WebGL2-Projekt.

## Eingaben
- README.md
- CHANGELOG.md
- HL2-VR-Mod Referenz
- slqnt Browser-Port Referenz
- Archive.org HL2 Basisquellen

## Schritt 1: Analyse
- Lies README.md und CHANGELOG.md vollständig ein.
- Extrahiere Infrastruktur: Mod Organizer 2, gameinfo.txt, cfg/autoexec.cfg, mods/, savegames, load order, texture packs, campaign compatibility.
- Erstelle eine Liste aller referenzierten Mod- und Asset-Kategorien.

## Schritt 2: Struktur
- Baue einen neuen Zielordnerbaum.
- Trenne strikt zwischen Referenzdaten und neuem Zielsystem.
- Erzeuge ein manifest.json mit Asset-Gruppen, Abhängigkeiten und Lade-Reihenfolge.

## Schritt 3: Portierungsmanager
- Erzeuge einen Manager, der Asset-Import, Pfadauflösung, Cache, Save-State und Build-Steuerung übernimmt.
- Optional: WebXR-Entry für Meta Quest 3.
- Optional: WebGL2-Renderer-Integration.

## Schritt 4: Output
- Verzeichnisbaum
- manifest.json
- TASK.md
- Build-Anleitung
- Deployment-Anleitung
- Liste fehlender Dateien/Artefakte

## Wichtige Regeln
- Keine 1:1-Kopie geschützter Inhalte.
- Keine proprietären Assets ohne Rechte.
- Nur Analyse, Struktur und Neubau.
- Verwende die Referenzen als Architekturvorlage, nicht als Rohkopie.

## Gewünschter Arbeitsstil
- Schritt für Schritt.
- Technisch.
- Klare Unterteilung in Analyse, Struktur und Build.
- Möglichst direkt in ein Upload-/Build-Projekt übertragbar.
