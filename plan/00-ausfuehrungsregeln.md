# Ausfuehrungsregeln und Projektsteuerung

## Arbeitsweise pro Task

1. Lies `plan/README.md`, diese Datei, die Phasendatei und alle dort genannten
   Referenzen.
2. Pruefe, dass alle Abhaengigkeiten abgeschlossen sind.
3. Setze genau einen Task in `plan/README.md` auf `[~]`.
4. Arbeite ausschliesslich den beschriebenen Umfang ab.
5. Fuehre TDD gemaess `conductor/workflow.md` durch: zuerst ein fachlich
   aussagekraeftiger fehlschlagender Test, danach die minimale Implementierung.
6. Fuehre mindestens Format-Check, Analyse und alle betroffenen Tests in Docker
   aus. Nutze am Taskende `make check`, sofern der Task nichts anderes festlegt.
7. Dokumentiere Abweichungen, Risiken und manuelle Hardwaretests.
8. Markiere den Task erst nach erfuellter Abnahme als `[x]`.

Tasks aus der zurueckgestellten Phase 1.5 werden im aktuellen Read-only-Durchlauf
nicht aktiviert. Dazu gehoeren auch Write-, ACK-, Read-back-, Rollback- und
hardwareabhaengige Write-Tests; sie werden erst bei ausdruecklicher Aktivierung
dieser Phase ausgefuehrt.

Es wird nie stillschweigend am Controller geschrieben. Ohne bestaetigte reale
Fixtures laufen Protokoll- und Schreibtests nur gegen Fakes oder gespeicherte
Testdaten.

## Evidenzhierarchie fuer Controllerwissen

1. Reproduzierbare Rohdaten des konkreten Controllers und Read-back-Ergebnisse.
2. Quellcode und Binary Templates aus `jackhumbert/fardriver-controllers`
   (als Referenz geklont unter `../reference/upstream/fardriver-controllers/`).
3. Verhalten des bestehenden BikeTunes-Codes und dokumentierte Captures
   (Fork-Basis geklont unter `../reference/upstream/Biketunes/`).
4. Herstellerdokumentation passend zu Hardware- und Firmwareversion.
5. Die DOCX-Dateien unter `reference/` als Hypothesenquelle, nicht als Beweis.

Insbesondere werden Empfehlungen wie 100 Prozent in allen RPM-Stromtabellen,
das Absenken von `LM` oder das Aktivieren von Race-Modi niemals ungeprueft als
Preset umgesetzt. `0xA0 / 0x88 0x01` darf nicht als Speicherbefehl behandelt
werden, solange dies nicht fuer die Zielhardware bewiesen ist.

## Globale Definition of Done

- Alle Akzeptanzkriterien des Tasks sind nachweisbar erfuellt.
- Neue Logik besitzt Erfolgs-, Fehler- und Grenzwerttests.
- Neue Kernlogik erreicht mehr als 80 Prozent Coverage.
- `dart format`, `flutter analyze` und betroffene Tests sind fehlerfrei.
- Keine unbekannten Werte werden optimistisch als sicher interpretiert.
- Neue Abhaengigkeiten wurden zuerst in `conductor/tech-stack.md` dokumentiert.
- Nutzertexte sind standardmaessig deutsch und knapp formuliert.
- Relevante Dokumentation und Roadmapstatus sind aktuell.

## T001 - Anforderungs-Traceability erstellen

**Abhaengigkeiten:** Keine  
**Hardware erforderlich:** Nein

### Ziel

Jede Version-1-Anforderung aus `reference/ziel.md` ist mindestens einem Task und
einem spaeteren Abnahmetest zugeordnet. Version-2-Anforderungen sind eindeutig
abgegrenzt.

### Arbeitsumfang

- Erstelle `plan/anforderungsmatrix.md` mit stabilen Requirement-IDs.
- Ordne jeder Anforderung Task-IDs, geplante Tests und die Zielphase zu.
- Markiere rechtliche, hardwareabhaengige oder noch unklare Anforderungen.
- Dokumentiere Abweichungen zwischen Ziel, Product Guide und aktuellem Code.

### Akzeptanzkriterien

- Keine Version-1-Anforderung ist ohne Taskzuordnung.
- Street Legal, Background-Trigger, Safety, Backup und Reichweite sind als
  kritische Anforderungen markiert.
- Version 2 blockiert keinen Version-1-Task.
- Alle Links in der Matrix sind relativ und gueltig.

### Verifikation

Pruefe die Matrix manuell gegen jede Ueberschrift in `reference/ziel.md` und
fuehre `git diff --check` aus.

## T002 - Hardware- und Produktentscheidungen erfassen

**Abhaengigkeiten:** T001  
**Hardware erforderlich:** Ja, fuer vollstaendige Angaben

### Ziel

Alle sicherheitsrelevanten Annahmen werden durch konkrete Fahrzeugdaten ersetzt
oder explizit als Blocker festgehalten.

### Arbeitsumfang

- Erstelle `plan/hardwareprofil.md` als ausfuellbare, versionierte Spezifikation.
- Erfasse Controller-Modell, Seriennummer, Hardware-/Softwareversion,
  FarDriver-Funktionscode, Motor, Batteriechemie, Nennspannung, Kapazitaet,
  BMS-Lade-/Entladelimits, Phasenstromlimit, Rad und Uebersetzung.
- Erfasse ein originales HEB/Stock-Backup und anonymisierte BLE-Captures, sofern
  verfuegbar; referenziere Dateien, statt binaere Daten in Markdown einzubetten.
- Erfasse gewuenschte Application-ID sowie Zielgeraete und Android-Versionen.
- Definiere Street-Legal-Werte nicht pauschal, sondern anhand der Zulassung und
  lokalen Rechtslage; dokumentiere, wer diese Werte bestaetigt hat.

### Akzeptanzkriterien

- Jede unbekannte sicherheitskritische Angabe ist mit `BLOCKIERT` markiert.
- Fehlende Stromlimits verhindern spaeter nur reale Writes, nicht reine UI- oder
  Simulationsarbeit.
- Street Legal wird als nutzerkonfigurierbares Profil mit Disclaimer behandelt.
- Keine Seriennummer, Adresse oder andere sensible Hardwarekennung wird
  ungefragt in oeffentliche Fixtures uebernommen.

### Verifikation

Manuelle Freigabe des Hardwareprofils durch den Fahrzeugeigentuemer.

## T003 - Reproduzierbaren Ist-Zustand dokumentieren

**Abhaengigkeiten:** T001  
**Hardware erforderlich:** Nein

### Ziel

Vor funktionalen Aenderungen existiert ein ehrlicher Baseline-Bericht ueber
Build, Tests, Architektur und bekannte Defekte.

### Arbeitsumfang

- Fuehre Docker-Build, Dependency-Aufloesung, Format-Check, Analyse, Tests und
  Android-Debug-Build einzeln aus.
- Erstelle `plan/baseline.md` mit Datum, Toolversionen, exakten Kommandos,
  Ergebnissen und reproduzierbaren Fehlermeldungen.
- Dokumentiere vorhandene Funktionen und bekannte Risiken mit Dateiverweisen.
- Veraendere in diesem Task keinen Anwendungscode; Baseline-Fehler werden nur
  erfasst und nachfolgenden Tasks zugeordnet.

### Akzeptanzkriterien

- Jeder Standardbefehl hat einen dokumentierten Exit-Status.
- Gradle-Duplikate, fehlende Tests, unsichere Writes, unvollstaendiges Backup,
  fehlender Background-Service und fehlendes GPS sind erfasst.
- Der Bericht unterscheidet beobachtete Fakten von Vermutungen.

### Verifikation

Wiederhole mindestens einen erfolgreichen und einen gegebenenfalls
fehlschlagenden Baseline-Befehl anhand der Dokumentation.
