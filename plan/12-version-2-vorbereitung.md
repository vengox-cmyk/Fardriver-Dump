# Phase 11: Version 2 vorbereiten

## Phasenziel

Navigation und Hoehenmodelle werden fuer Version 2 geplant, ohne Version 1 durch
vorzeitige Karten-, Routing- oder Netzwerkkomplexitaet zu belasten.

## T084 - Navigation hinter stabilen Schnittstellen vorbereiten

**Abhaengigkeiten:** T083  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Definiere Domain-Schnittstellen fuer Route, Streckensegment, Hoehe,
  Energiebedarf und End-SOC, ohne einen Anbieter in Kernlogik einzubauen.
- Erstelle eine ADR fuer `flutter_map` und kostenfreie/self-hostbare
  GraphHopper-, Valhalla- oder OSRM-Optionen inklusive Offline-/Kostenfolgen.
- Implementiere hoechstens testbare Interfaces und Fakes, keine Navigation UI.

### Tests und Akzeptanz

- Version-1-Reichweitenlogik bleibt ohne Routingabhaengigkeit verwendbar.
- Keine bezahlte API oder API-Key-Pflicht wird eingefuehrt.
- Architektur erlaubt spaeter Hoehendaten und mehrere Routingpraeferenzen.

## T085 - Version-2-Backlog konkretisieren

**Abhaengigkeiten:** T084  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Erstelle einen getrennten, priorisierten Backlog fuer Karte, schnellste Route,
  Trailpraeferenz, grosse Strassen meiden, Hoehenverbrauch und End-SOC.
- Definiere Forschungs-, Datenschutz-, Kartenlizenz-, Offline- und
  Betriebsaufwandsfragen als eigene Tasks.
- Verknuepfe Anforderungen aus `reference/ziel.md`, ohne sie als Version 1
  abgeschlossen zu markieren.

### Tests und Akzeptanz

- Jeder Backlogpunkt besitzt Ziel, Abhaengigkeit und messbares Akzeptanzkriterium.
- Laufende Kosten und Lizenzpflichten sind sichtbar.
- Kein Version-2-Punkt veraendert rueckwirkend den Version-1-Abnahmestatus.

## Abschluss

Nach T085 kann fuer Version 2 ein eigener Conductor-Track erstellt werden. Diese
Roadmap bleibt bis dahin die Source of Truth fuer ArcDash Version 1.
