# Phase 7: Dashboard und Telemetrie

## Phasenziel

Das sichtbare ArcDash-Cockpit wird unabhaengig von der bisherigen Fork-UI neu
gebaut. Es ist deutsch, AMOLED-optimiert, bei Sonne lesbar, mit Handschuhen
bedienbar und in Hoch- sowie Querformat nutzbar. Der Nutzer bestimmt selbst,
welche Werte angezeigt werden und wie gross und wo sie angeordnet sind. Es
werden ausschliesslich plausible und hinsichtlich ihrer Aktualitaet bewertete
Telemetriewerte dargestellt.

## Verbindliche Dashboard-Entscheidungen

- `lib/screens/dashboard_screen.dart` und die bisherigen Dashboard-Widgets sind
  keine visuelle Grundlage. Sie werden nach Aktivierung des Ersatzes entfernt.
- Wiederverwendet werden duerfen nur Domainmodelle, Provider, BLE-/Protokollcode
  und kleine fachlich neutrale Hilfen. Das neue UI beginnt ohne Uebernahme des
  bisherigen Layouts oder dessen Widget-Hierarchie.
- Ein Dashboard besitzt zwei voneinander unabhaengige Layouts: Hochformat und
  Querformat. Ein Wechsel der Geraeteausrichtung veraendert das jeweils andere
  Layout nicht.
- Platzierung und Groesse werden in einem normalisierten Raster gespeichert,
  nicht in Pixelkoordinaten. Dadurch bleibt ein Layout auf kleinen und grossen
  Android-Geraeten nutzbar.
- V1 speichert genau ein benutzerdefiniertes Dashboard mit beiden Ausrichtungen.
  Das Schema wird so modelliert, dass benannte Layouts spaeter ohne Bruch
  ergaenzt werden koennen.
- Das mitgelieferte Standardlayout bleibt immer als Reset-Ziel verfuegbar. Ein
  defektes oder unbekanntes Layoutschema wird nie teilweise gerendert.

## T054 - App-Shell, Designsystem, Navigation und Lokalisierung neu aufbauen

**Abhaengigkeiten:** T006, T008  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Definiere AMOLED-Farben, Typografie, Abstaende, Touch-Ziele und Safety-Farben
  gemaess `conductor/product-guidelines.md`.
- Bette Fonts lokal ein oder verwende Systemfonts ohne Laufzeit-Netzwerkzugriff.
- Richte Flutter-Lokalisierung mit Deutsch als Standard und Englisch als
  optionaler Sprache ein.
- Baue eine neue App-Shell fuer Dashboard, Profile, Fahrten und Einstellungen,
  die in Hoch- und Querformat keine Inhalte verdeckt.
- Entferne die bisherige Portrait-Sperre auf Android und erhalte den sichtbaren
  Screen- und Sessionzustand bei einem Orientierungswechsel.
- Entferne die Fork-Navigation aus dem Dashboard und halte Verbindungszustand
  und Navigation ausserhalb des konfigurierbaren Inhaltsbereichs.

### Tests und Akzeptanz

- Kein zentraler Nutzertext ist hart im Widget verdrahtet.
- App startet offline ohne Font-Download.
- Touch-Ziele sind mindestens 48 dp und Textskalierung verursacht keinen
  kritischen Overflow.
- Theme-, Orientierungs- und Navigations-Smoke-Tests bestehen.

## T055 - Telemetriequalitaet und Stale-State implementieren

**Abhaengigkeiten:** T014, T018  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Fuehre pro Messwert Quelle, Erfassungszeit, Gueltigkeit und optional geglaetteten
  Anzeigewert.
- Definiere physikalische Plausibilitaetsgrenzen und unterschiedliche
  Stale-Zeitfenster fuer schnelle und langsame Frames.
- Verhindere, dass alte Werte nach Disconnect wie live aussehen.

### Tests und Akzeptanz

- Fake-Clock-Tests decken frisch, stale, ungueltig und reconnect ab.
- Glattung erzeugt keine gefaehrliche lange Verzogerung fuer Fehler oder RPM.
- Rohwerte bleiben fuer Diagnose verfuegbar.

## T056 - GPS-Geschwindigkeit mit Fallback implementieren

**Abhaengigkeiten:** T019, T055; neue Abhaengigkeit vorab im Tech Stack  
**Hardware erforderlich:** Android-Geraet fuer Abnahme

### Arbeitsumfang

- Fuehre Location-Permissions getrennt von BLE-Rechten und erklaere den Nutzen.
- Filtere GPS nach Accuracy, Alter und realistischer Beschleunigung.
- Bevorzuge gueltiges GPS; falle bei schlechter Qualitaet auf Controller-Speed
  zurueck und kennzeichne die Quelle intern.
- Behandle Stillstand stabil, ohne GPS-Drift als Fahrt zu zaehlen.

### Tests und Akzeptanz

- Quellenauswahl, stale GPS, Spruenge, Drift und Permission-Ablehnung sind
  deterministisch getestet.
- Dashboard zeigt auch ohne Standortfreigabe Controller-Speed.
- Hintergrundstandort wird nur angefordert, wenn spaetere Sessionanforderungen
  dies technisch und rechtlich rechtfertigen.

## T057 - Versioniertes Dashboard-Layoutmodell und Persistenz bauen

**Abhaengigkeiten:** T024, T054
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Definiere ein UI-unabhaengiges, schema-versioniertes `DashboardLayout` mit
  getrennten Hoch- und Querformat-Rastern.
- Speichere pro Element eine stabile ID, Messwert-ID, Darstellungsart, Position,
  Breite, Hoehe und nur begrenzte, validierte Anzeigeoptionen.
- Validiere Rastergrenzen, Mindestgroessen, eindeutige IDs, bekannte Messwerte
  und unzulaessige Ueberlappungen vor dem Speichern und Rendern.
- Speichere Aenderungen gedrosselt und atomar ueber den bestehenden versionierten
  Repository-Vertrag. Implementiere Migration, Korruptionserkennung und Reset.
- Liefere ein ausgewogenes, unveraenderliches Standardlayout fuer beide
  Ausrichtungen als Fallback und Reset-Ziel.

### Tests und Akzeptanz

- Roundtrip-, Migrations- und Korruptionstests decken beide Ausrichtungen ab.
- Aenderungen am Hochformatlayout veraendern das Querformatlayout nicht und
  umgekehrt.
- Unbekannte Messwerte, Darstellungsarten und neuere Schemas werden kontrolliert
  abgelehnt und fuehren zum diagnostizierbaren Standardlayout.
- Kein gespeichertes Layout kann Elemente ausserhalb des sichtbaren Rasters oder
  unter ihrer messwertspezifischen Mindestgroesse erzeugen.

## T058 - Dashboard-Renderer und konfigurierbare Werte von Grund auf bauen

**Abhaengigkeiten:** T055, T057; T056 nur fuer die reale GPS-Quelle
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Ersetze den bisherigen `DashboardScreen` und seine visuellen Fork-Widgets
  vollstaendig durch einen Renderer fuer das validierte Rastermodell.
- Fuehre einen typisierten Messwertkatalog ein: Geschwindigkeit, Leistung,
  Spannung, Strom, SOC, Reichweite mit Unsicherheit, Profilstatus, D/N/R bzw.
  Gang, Motor- und Controllertemperatur, Rekuperation, Fehler und Verbindung.
- Biete passende Darstellungsarten wie grosse Zahl, kompakter Wert,
  Statusanzeige und Leistungsbogen an. Nicht jede Darstellungsart ist fuer jeden
  Messwert zulaessig.
- Faerbe positive Leistung gestuft und negative Leistung/Rekuperation gruen.
  Safety-Zustaende bleiben auch ohne Farbe unterscheidbar.
- Zeige fehlende, stale, ungueltige und getrennte Daten als solche; niemals als
  plausible Nullwerte. Rohwerte bleiben ausserhalb der UI diagnostizierbar.
- Rendere das Hoch- oder Querformatlayout allein anhand der aktuellen
  Orientierung und ohne zustandsveraendernde Sonderlogik im Widget.

### Tests und Akzeptanz

- Widget-/Golden-Tests decken beide Ausrichtungen sowie idle, Leistung,
  Rekuperation, stale, ungueltig, getrennt und Fehler ab.
- Jeder Katalogwert kann einzeln gerendert und aus dem Layout entfernt werden.
- Unbekannter Gang, Profil- oder Temperaturwert wird als unbekannt, nicht als
  Null gezeigt. Temperaturfarben basieren nur auf bestaetigten Grenzen.
- Das Standardlayout zeigt Geschwindigkeit, Leistung, Verbindung und kritische
  Fehler ohne Scrollen auf kleinen und grossen Zielgeraeten.
- Kein sichtbares Dashboard-Layout oder Branding aus dem Fork bleibt erhalten.

## T059 - Dashboard-Editor fuer Hoch- und Querformat bauen

**Abhaengigkeiten:** T057, T058
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Ergaenze einen expliziten Bearbeitungsmodus; normale Fahransicht darf kein
  versehentliches Verschieben oder Entfernen ausloesen.
- Der Nutzer kann Werte aus dem Messwertkatalog hinzufuegen, entfernen,
  verschieben und innerhalb zulaessiger Grenzen vergroessern oder verkleinern.
- Der Nutzer kann Hoch- und Querformat getrennt bearbeiten, ein Layout in die
  andere Ausrichtung kopieren, Aenderungen verwerfen und das Standardlayout
  wiederherstellen.
- Zeige Raster, belegte Flaechen, Kollisionen und Mindestgroessen unmittelbar.
  Unzulaessige Aenderungen werden nicht persistiert.
- Erlaube fuer kompatible Werte die Wahl zwischen den freigegebenen
  Darstellungsarten und Einheiten, ohne die interne SI-Berechnung zu veraendern.
- Drossele automatische Speicherung und sichere beim Verlassen des Editors.

### Tests und Akzeptanz

- Widgettests decken Hinzufuegen, Entfernen, Verschieben, Skalieren, Kollision,
  Undo/Verwerfen, Kopieren der Ausrichtung, Speichern und Reset ab.
- Ein Neustart stellt beide Layouts ohne Positions- oder Groessenverlust wieder
  her.
- Hochformatbearbeitung veraendert Querformat nur nach einer ausdruecklichen
  Kopieraktion.
- Der Editor funktioniert auf kleinen und grossen Zielgeraeten und bietet fuer
  alle Aktionen mindestens 48 dp grosse Touch-Ziele.

## T060 - Dashboard-Polish, Accessibility und Verbindungs-UX abschliessen

**Abhaengigkeiten:** T021, T054 bis T059
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Verbinde km/h/mph und km/mi konsistent mit Dashboard, Sessions und Exporten;
  interne Berechnung bleibt SI.
- Ergaenze Semantics, Kontrastpruefung, 200-Prozent-Textskalierung und
  Handschuh-Touchziele. Informationen werden nie ausschliesslich durch Farbe
  vermittelt.
- Entferne doppelte/umgangene Connection-Flows und schaffe einen eindeutigen
  Einstieg fuer Erstverbindung, Reconnect und Geraetewechsel.
- Zeige Adapter, Permission, Scan, Connect, Reconnect und Fehler getrennt.
- Verhindere, dass ein Dashboard mit Defaultnullen wie verbunden wirkt.

### Tests und Akzeptanz

- Widgettests decken Erststart, verweigerte Permission, kein Geraet, Connect,
  Disconnect und Reconnect ab.
- Accessibility-Tests finden Labels fuer zentrale Werte und Editoraktionen;
  200 Prozent Textskalierung bleibt in Fahransicht und Editor nutzbar.
- Umrechnung und Rundung besitzen Unit-Tests und wechseln ohne Datenverlust.
- Navigation verliert den Sessionzustand nicht.
- Manuelles Trennen beendet gewollten Auto-Reconnect.

## Phasen-Gate

Alle in Version 1 geforderten Livewerte sind ueber den Katalog frei waehlbar und
mit Quelle und Aktualitaet dargestellt. Eigene Hoch- und Querformatlayouts
ueberleben einen Neustart. Das Cockpit besteht Layout-, Orientierungs-, Kontrast-
und Handschuhbedienungschecks; von der alten Fork-Dashboard-UI bleibt nichts
sichtbar erhalten.
