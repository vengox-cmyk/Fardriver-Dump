# Phase 9: Sessions, Fehler und Einstellungen

## Phasenziel

Fahrten werden unabhaengig von sichtbaren Screens aufgezeichnet. Statistiken,
Fehler und Einstellungen verwenden dieselben validierten Daten wie Dashboard und
Background-Service.

## T070 - Serviceweiten Session-Lifecycle implementieren

**Abhaengigkeiten:** T048, T055, T062  
**Hardware erforderlich:** Nein fuer Simulation

### Arbeitsumfang

- Starte/beende Sessions anhand Verbindung, Bewegung und konfigurierter
  Ruhezeiten im langlebigen Service-Layer.
- Verhindere, dass das Oeffnen des Statistik-Screens Voraussetzung ist.
- Behandle kurze Disconnects, App-Neustart und aktive Sessionwiederaufnahme.

### Tests und Akzeptanz

- Spaete UI-Consumer beeinflussen Aufzeichnung nicht.
- Kurze Unterbrechung erzeugt nicht automatisch mehrere Fahrten.
- Timer und Subscriptions werden nach Sessionende freigegeben.

## T071 - Sessionmetriken aggregieren

**Abhaengigkeiten:** T063, T070  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Erfasse GPS-Distanz, Dauer, Durchschnitt/Maximum Geschwindigkeit, entnommene,
  rekuperierte und netto Energie, Wh/km, Maximalleistung sowie Durchschnitt und
  Maximum der Temperaturen.
- Gewichte zeitbasierte Mittelwerte nach Sampleintervall.
- Kennzeichne unvollstaendige Metriken bei Datenluecken.

### Tests und Akzeptanz

- Synthetische Sessions besitzen analytisch pruefbare Ergebnisse.
- Rekuperation macht entnommene Energie nicht negativ.
- Stale und ungueltige Samples gehen nicht in Aggregate ein.

## T072 - Sessionhistorie persistieren

**Abhaengigkeiten:** T024, T071  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Speichere Summary und optional begrenzte Track-/Zeitreihendaten transaktional.
- Implementiere Liste, Detailansicht, Loeschen und Aufbewahrungsregeln.
- Migriere brauchbare alte Session-Summaries defensiv.

### Tests und Akzeptanz

- App-Abbruch waehrend Speichern korrumpiert keine Historie.
- Leere, lange und unvollstaendige Sessions sind getestet.
- Speicherwachstum ist dokumentiert und begrenzt.

## T073 - Sessionexport und Sharing implementieren

**Abhaengigkeiten:** T072  
**Hardware erforderlich:** Android-Geraet fuer Sharing-Abnahme

### Arbeitsumfang

- Exportiere ausgewaehlte vergangene Sessions als dokumentiertes CSV und JSON.
- Nutze aktuelle Einheiteneinstellung nur fuer Darstellung; JSON behaelt klare
  SI-Felder und Schema-Version.
- Integriere Android Share Sheet/Storage Access Framework.

### Tests und Akzeptanz

- Sonderzeichen, deutsche Locale, leere optionale Felder und grosse Session sind
  getestet.
- CSV-Spalten, Einheiten und Dezimalformat sind eindeutig.
- Exportdateien verwenden ArcDash-Namen und sichere Dateinamen.

## T074 - Fehlerkatalog und Fehlerhistorie bauen

**Abhaengigkeiten:** T014, T023, T072  
**Hardware erforderlich:** Fixtures oder Hardware

### Arbeitsumfang

- Ordne bestaetigte Controller-Flags deutschen Titeln, Erklaerungen, Schweregrad
  und empfohlenem sicheren Verhalten zu.
- Erfasse Auftreten/Ende in einer begrenzten Historie mit Rohflags.
- Zeige unbekannte Flags als Diagnosecode statt sie zu ignorieren.

### Tests und Akzeptanz

- Gleichzeitige, wiederkehrende und unbekannte Fehler sind getestet.
- App gibt keine gefaehrliche Reparatur- oder Weiterfahranweisung.
- Kritische Fehler sind in Dashboard und Sessiondetail nachvollziehbar.

## T075 - Einstellungen und Datenverwaltung konsolidieren

**Abhaengigkeiten:** T032, T052, T059, T068, T072  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Konsolidiere Sprache, Einheiten, Feedback, Reconnect, Safety-Ausrolloption und
  Datenschutz in typisierten Settings.
- Dark Mode bleibt fuer Version 1 AMOLED; entferne wirkungslose Schalter.
- Implementiere getrenntes Zuruecksetzen von Dashboard-Layouts, Lernwerten,
  Sessions, Profilen und allen App-Daten mit klarer Bestaetigung.

### Tests und Akzeptanz

- Defaults, Persistenz, Migration und Resetbereiche sind getestet.
- Stock-Backup kann nicht versehentlich durch allgemeinen Profilreset geloescht
  werden; kompletter Datenreset warnt ausdruecklich.
- Einstellungen wirken sofort und konsistent in allen Screens.

## Phasen-Gate

Eine komplette simulierte Fahrt erzeugt ohne geoeffneten Statistik-Screen eine
korrekte, persistierte, exportierbare Session mit nachvollziehbaren Fehlern.
