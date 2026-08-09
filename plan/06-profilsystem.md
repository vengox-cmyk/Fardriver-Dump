# Phase 5: Profilsystem

## Phasenziel

Profile sind versionierte, hardwarekompatible Zielkonfigurationen. Sie werden
verwaltet, verglichen, importiert und ausschliesslich ueber die sichere
Schreibengine angewendet.

## T038 - Versioniertes Profilmodell implementieren

**Abhaengigkeiten:** T024, T030, T033  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Definiere ID, Name, Beschreibung, Schema, Zeitstempel, Controllerfamilie,
  Parameterwerte und Herkunft.
- Trenne unveraenderliche integrierte Profile von nutzereigenen Kopien.
- Implementiere validierte Migrationen fuer vorhandene BikeTunes-Profile.

### Tests und Akzeptanz

- JSON-/DB-Roundtrip, Gleichheit und Migration sind getestet.
- Unbekannte Parameter und neuere Schemas werden nicht still verworfen.
- Namen sind nicht die technische Identitaet eines Profils.

## T039 - Integrierte Profile definieren

**Abhaengigkeiten:** T002, T027, T038  
**Hardware erforderlich:** Ja fuer echte Werte

### Arbeitsumfang

- Definiere Stock aus dem echten Stock-Backup und Templates fuer Street Legal,
  Eco, Offroad/Trail und Sport/Race.
- Templates enthalten nur bestaetigte, profilgeeignete Parameter und verlangen
  vor Nutzung fahrzeugspezifische Werte.
- Uebernimm keine aggressiven DOCX-Tuningempfehlungen als Defaults.

### Tests und Akzeptanz

- Ohne bestaetigte Hardwarelimits sind leistungssteigernde Templates nicht
  anwendbar.
- Street Legal ist nicht mit einer universellen Rechtsbehauptung verbunden.
- Stock bleibt unveraenderlich und identitaetsgebunden.

## T040 - Profilverwaltung implementieren

**Abhaengigkeiten:** T038  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Implementiere Liste, Erstellen, Umbenennen, Duplizieren und Loeschen.
- Schuetze Stock und integrierte Templates vor direkter Mutation.
- Verhindere Namensverlust, bestaetige Loeschen und behandle DB-Fehler sichtbar.

### Tests und Akzeptanz

- CRUD, Namensvalidierung, Duplikate und Persistenzfehler sind getestet.
- Duplizieren erzeugt eine neue ID und unabhaengige Parameterdaten.
- UI funktioniert auf kleinen und grossen Android-Displays.

## T041 - Sicheren Profileditor bauen

**Abhaengigkeiten:** T030, T038, T040  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Generiere Eingaben aus dem Parameterkatalog mit Einheit, sicheren Grenzen und
  Risikoklasse.
- Zeige nur fuer V1 freigegebene Parameter; fortgeschrittene unbekannte
  Register bleiben verborgen.
- Validiere bei jeder Eingabe und erneut beim Speichern.

### Tests und Akzeptanz

- UI-Grenzen koennen weder durch Text, JSON noch gespeicherte Altwerte umgangen
  werden.
- Rundung und Einheitenumrechnung veraendern den Zielrohwert nachvollziehbar.
- Ungueltige Profile sind nicht anwendbar.

## T042 - Profil-Diff und Kompatibilitaet anzeigen

**Abhaengigkeiten:** T033, T038  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Vergleiche Profil gegen aktuellen Snapshot oder ein zweites Profil.
- Gruppiere Aenderungen nach Risiko und zeige alt, neu, Einheit und Bedeutung.
- Zeige inkompatible/fehlende Parameter und blockiere ungueltige Anwendung.

### Tests und Akzeptanz

- Leerer, normaler, kritischer und inkompatibler Diff sind getestet.
- Unbekannte Werte erscheinen explizit, nicht als Null.
- Diff entspricht exakt dem spaeteren Write-Plan.

## T043 - JSON-Import und -Export implementieren

**Abhaengigkeiten:** T038, T041  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Dokumentiere kanonisches JSON-Schema mit Version und Kompatibilitaetsdaten.
- Implementiere Dateiauswahl, Export und vollstaendige Vorabvalidierung.
- Importierte Dateien werden zunaechst als Vorschau behandelt und nie direkt
  angewendet.

### Tests und Akzeptanz

- Roundtrip, kaputtes JSON, falsche Typen, unbekannte Parameter, zu hohe Werte
  und neuere Schemas sind getestet.
- Import kann bestehende Profile nicht unbestaetigt ueberschreiben.
- Dateinamen enthalten keine unbereinigten Nutzereingaben.

## T044 - Profile verifiziert anwenden

**Abhaengigkeiten:** T037, T042  
**Hardware erforderlich:** Ja fuer Abnahme

### Arbeitsumfang

- Verbinde Profilauswahl, Diff, Bestaetigung und sichere Schreibengine.
- Markiere das aktive Profil nur, wenn ein frischer Snapshot alle Profilwerte
  nach Read-back bestaetigt.
- Setze den Status bei manueller Controlleraenderung auf `abweichend`.

### Tests und Akzeptanz

- Abbruch, Safety-Block, Teilfehler und externe Abweichung sind getestet.
- Ein Profilname wird nicht allein aufgrund des letzten Klicks als aktiv gezeigt.
- Identische Anwendung ist idempotent und erzeugt keine Writes.

## T045 - Street-Legal-Fast-Path optimieren

**Abhaengigkeiten:** T039, T044  
**Hardware erforderlich:** Ja

### Arbeitsumfang

- Beschraenke Street Legal auf den kleinsten bestaetigten Parameter-Diff fuer das
  konkrete Fahrzeug, typischerweise Speedlimit und moderate Strombegrenzung.
- Lese erforderliche Ausgangsregister vorab in die Session und vermeide
  unnoetige Bloecke, ohne Safety oder Read-back zu kuerzen.
- Messe Verbindung-bereit bis verifizierter Abschluss und dokumentiere Zielwert.

### Tests und Akzeptanz

- Fast Path nutzt dieselbe Safety- und Write Engine wie alle Profile.
- Doppeltrigger ist idempotent.
- Zeitmessung trennt Reconnect, Write, ACK und Read-back.
- Das Profil wird auf realer Hardware nach Power-Cycle verifiziert.

## Phasen-Gate

Street Legal wird schnell und ausschliesslich als minimaler, verifizierter Diff
angewendet. Kein Profil kann Safety- oder Hardwaregrenzen umgehen.
