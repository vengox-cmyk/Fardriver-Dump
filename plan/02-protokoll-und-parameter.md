# Phase 2: Protokoll und Parameter

## Phasenziel

Das FarDriver-Protokoll wird nicht aus Vermutungen implementiert. Paketformat,
Register, Skalierungen und Safety-Signale sind durch Upstream-Quellen und reale
Fixtures nachvollziehbar abgesichert.

Die Upstream-Referenzprojekte liegen geklont unter
`../reference/upstream/fardriver-controllers/` und
`../reference/upstream/Biketunes/`. Daraus stammen `fardriver.hpp`,
`fardriver_message.hpp` und `fardriver.bt`.

## T009 - Protokoll-Belegmatrix erstellen

**Abhaengigkeiten:** T008  
**Hardware erforderlich:** Teilweise

### Arbeitsumfang

- Erstelle eine versionierte Tabelle fuer Frame-Typen, Adressen, Felder,
  Datentypen, Skalierungen, Schreibbarkeit und Quellen.
- Vergleiche aktuellen Parser, beide DOCX-Dateien, `fardriver.hpp`,
  `fardriver_message.hpp`, `fardriver.bt` und reale Daten aus T002.
- Markiere jede Definition als bestaetigt, wahrscheinlich oder unbekannt.
- Dokumentiere bekannte Widersprueche, insbesondere HEB-Groesse,
  Speicherkommando, Motionsignale und Throttle-Bitfeld.

### Tests und Akzeptanz

- Jede aktuell geparste und geschriebene Adresse besitzt einen Belegstatus.
- Unbestaetigte schreibbare Parameter sind standardmaessig deaktiviert.
- Quellen enthalten URL/Commit oder lokalen Dateipfad und Abrufdatum.

## T010 - BLE-Captures und Paket-Fixtures definieren

**Abhaengigkeiten:** T009, Hardwareprofil aus T002  
**Hardware erforderlich:** Ja fuer reale Fixtures

### Arbeitsumfang

- Definiere ein textbasiertes Fixture-Format mit Bytes, Richtung, Zeitstempel,
  Controller-Metadaten und erwartetem Decode-Ergebnis.
- Erfasse sichere Read-only-Szenarien: Start, Stillstand, Radbewegung,
  Vorwaerts/Neutral/Rueckwaerts, Bremse, positiver und negativer Strom.
- Definiere getrennte, manuell freizugebende Capture-Ablaufe fuer Writes/ACKs.
- Entferne Bluetooth-Adressen, Seriennummern und Passwoerter aus oeffentlichen
  Fixtures.

### Tests und Akzeptanz

- Fixture-Loader validiert fehlerhafte Hexdaten und fehlende Metadaten.
- Mindestens die vorhandenen Beispielpakete koennen ohne Hardware geladen
  werden; reale Fixtures bleiben bei fehlender Hardware als Blocker markiert.

## T011 - CRC durch Golden-Tests absichern

**Abhaengigkeiten:** T010  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Schreibe Tests fuer bekannte 8- und 16-Byte-Pakete, Initialwerte, CRC-Bytefolge
  und mutierte Nutzdaten.
- Pruefe Berechnung und Verifikation gegen Upstream-Vektoren.
- Aendere den CRC-Code nur, wenn ein fehlschlagender Golden-Test den Fehler
  reproduziert.

### Tests und Akzeptanz

- Gueltige Upstream- und Capture-Pakete werden akzeptiert.
- Jede Ein-Bit-Mutation in den getesteten Bereichen wird verworfen.
- Zu kurze und ungueltige Eingaben fuehren zu definiertem Verhalten statt
  Indexfehlern.

## T012 - Fragmentierungsfesten Paket-Framer bauen

**Abhaengigkeiten:** T011  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Ersetze das zustandslose Extrahieren durch einen inkrementellen Byte-Puffer.
- Unterstuetze 8-Byte-Antworten und 16-Byte-Statusframes, mehrere Frames pro
  Notification, Fragmentierung, Datenmuell und erneute Synchronisierung auf
  `0xAA`.
- Begrenze den Puffer gegen unkontrolliertes Wachstum.

### Tests und Akzeptanz

- Ein isoliertes 8-Byte-Paket wird erkannt.
- Alle moeglichen Teilungspositionen eines 16-Byte-Pakets funktionieren.
- Gemischte ACK-/Statusfolgen, kaputte CRC und Prefix-Muell sind getestet.
- Jeder Bytewert wird hoechstens kontrolliert oft verarbeitet; kein Busy Loop.

## T013 - FarDriver-Speichermodell abbilden

**Abhaengigkeiten:** T009, T012  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Bilde die fuer Version 1 benoetigten 12-Byte-Adressbloecke typisiert ab.
- Trenne rohen Speicher, decodierte Werte und editierbare Parameter.
- Implementiere little-endian, signed/unsigned und Bitfeldzugriffe ohne das
  Ueberschreiben benachbarter Bits.
- Halte unbekannte Bytes unveraendert und kennzeichne sie explizit.

### Tests und Akzeptanz

- Roundtrip Raw -> Modell -> Raw ist fuer unveraenderte Fixtures bytegenau.
- Feldtests decken Grenzen, negative Werte und Bitnachbarn ab.
- `ThrottleResponse` kann geaendert werden, ohne `FollowConfig`, `WeakA` oder
  `RXD` zu veraendern.

## T014 - Telemetrie-, Fehler- und Safety-Register decodieren

**Abhaengigkeiten:** T013  
**Hardware erforderlich:** Fuer abschliessende Bestaetigung

### Arbeitsumfang

- Decodiere Geschwindigkeit/RPM, DNR/Gang, Bremse, Motorlaufzustand,
  Gasgriffspannung/-tiefe, Spannung, Strom, SOC, Temperaturen und alle fuer V1
  benoetigten Fehlerflags.
- Ergaenze Plausibilitaetsgrenzen und behalte Rohwert sowie Belegstatus.
- Verwende `0xFA` und weitere Signale defensiv; kein einzelnes Nullfeld darf
  Stillstand beweisen.

### Tests und Akzeptanz

- Jede decodierte Groesse besitzt Golden-Tests mit bekannten Rohbytes.
- Unbekannte Enumwerte gehen nicht verloren und verursachen keinen Crash.
- Stromvorzeichen und Rekuperation sind eindeutig getestet.
- Safety-relevante Felder enthalten Erfassungszeit und Datenquelle.

## T015 - Parameter-Snapshots aus dem Datenstrom aufbauen

**Abhaengigkeiten:** T014  
**Hardware erforderlich:** Fuer Vollstaendigkeitsmessung

### Arbeitsumfang

- Sammle den rotierenden Datenstrom in einem Snapshot-Builder.
- Definiere erwartete Bloecke je Hardware-/Firmwarefamilie und einen
  Vollstaendigkeitsstatus mit fehlenden Adressen.
- Trenne fluechtige Telemetrie von persistierbaren Konfigurationsbloecken.
- Implementiere Timeout, Fortschritt und Neustart bei Controllerwechsel.

### Tests und Akzeptanz

- Unvollstaendige, doppelte und ungeordnet eintreffende Bloecke sind getestet.
- Ein Snapshot wird erst komplett, wenn alle erforderlichen Bloecke frisch sind.
- Daten zweier Controller koennen niemals in einen Snapshot gemischt werden.

## T016 - Schreibprotokoll, ACK und HEB validieren

**Abhaengigkeiten:** T010, T013, T015  
**Hardware erforderlich:** Ja; ohne Hardware bleibt der Task `[!]`

### Arbeitsumfang

- Ermittle anhand sicherer, einzeln freigegebener Testaenderungen das exakte
  Write-/ACK-Verhalten inklusive Adresse, Wert, CRC und Persistenz.
- Pruefe, ob eine Transportantwort ein ACK, Echo oder nur ein Statusframe ist.
- Vergleiche Stock-HEB vor/nach einer harmlosen Aenderung und dokumentiere
  Layout, Blockauswahl, Metadaten und Checksumme.
- Beweise den echten Persistenz-/Save-Ablauf; teste niemals vermutete
  Systemkommandos.

### Tests und Akzeptanz

- Jede freigegebene Write-Adresse besitzt Capture, erwartete Antwort und
  Read-back-Nachweis.
- ACK-Pruefung korreliert mindestens Adresse und erwarteten Rohwert.
- HEB-Erkenntnisse sind reproduzierbar; unbekannte Bereiche bleiben unangetastet.
- Der konkrete Controller ist nach jedem Test wieder im bestaetigten
  Ausgangszustand.

## Phasen-Gate

Reale Writes bleiben gesperrt, bis T016 abgeschlossen ist. Parser- und
Speichermodelle muessen komplett mit gespeicherten Fixtures testbar sein.
