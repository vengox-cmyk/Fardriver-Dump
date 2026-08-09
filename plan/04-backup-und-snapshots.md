# Phase 4: Backup und Snapshots

## Phasenziel

ArcDash kann den bestaetigten Konfigurationszustand eines konkreten Controllers
vollstaendig und nachvollziehbar sichern. Das bisherige Zwei-Werte-Backup wird
nicht als Stock-Backup weiterverwendet.

## T024 - Versionierte Persistenzarchitektur festlegen

**Abhaengigkeiten:** T008, T015  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Vergleiche lokale Datenbankoptionen fuer Profile, Snapshots, Sessions und
  Lernzustand anhand Transaktionen, Migrationen, Android-Support und Wartung.
- Dokumentiere die Entscheidung vor dem Hinzufuegen einer Abhaengigkeit in
  `conductor/tech-stack.md`.
- Trenne Settings in `SharedPreferences` von strukturierten, wachsenden Daten.

### Tests und Akzeptanz

- Die Entscheidung enthaelt Alternativen, Konsequenzen, Backup-Verhalten und
  Migrationsstrategie.
- Ein minimaler Repository-Integrationstest beweist atomare Schreibvorgaenge.
- Datenbankschema und App-Modell besitzen explizite Versionsnummern.

## T025 - Controller-Identitaet und Kompatibilitaet erfassen

**Abhaengigkeiten:** T013, T024  
**Hardware erforderlich:** Fuer reale Validierung

### Arbeitsumfang

- Leite eine Controller-Identitaet aus Modellname, Hardware-/Softwareversion,
  Funktions-/Extension-Code und einer lokal gespeicherten Geraetebindung ab.
- Definiere strikte und tolerierte Kompatibilitaetsregeln fuer Snapshots.
- Behandle fehlende Identitaetsfelder als unbekannt, nicht als kompatibel.

### Tests und Akzeptanz

- Gleicher, kompatibler und fremder Controller sind getestet.
- Bluetooth-Adresse ist nicht die einzige fachliche Identitaet.
- UI kann einen Identitaetskonflikt erklaeren, ohne Restore anzubieten.

## T026 - Vollstaendige Parametersnapshots atomar speichern

**Abhaengigkeiten:** T015, T024, T025  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Speichere Rohbloecke, decodierte Metadaten, Vollstaendigkeit, Quelle,
  Zeitstempel, Schema und Controller-Identitaet in einer Transaktion.
- Berechne eine Integritaetspruefsumme ueber kanonisch serialisierte Rohdaten.
- Speichere unvollstaendige Zwischenstaende getrennt und nie als verwendbaren
  Snapshot.

### Tests und Akzeptanz

- App-Abbruch oder Storage-Fehler erzeugt keinen scheinbar kompletten Snapshot.
- Integritaetsfehler und unbekannte Schema-Versionen werden erkannt.
- Laden und erneutes Serialisieren veraendert Rohbytes nicht.

## T027 - Verlaessliches Stock-Backup erzeugen

**Abhaengigkeiten:** T026  
**Hardware erforderlich:** Ja fuer Abnahme

### Arbeitsumfang

- Erzeuge beim ersten vollstaendigen Read eines Controllers genau ein
  unveraenderliches Stock-Backup.
- Migriere das alte Zwei-Werte-Backup nicht automatisch zu einem gueltigen
  Stock-Backup; kennzeichne es als Legacy und fordere einen neuen Read an.
- Erlaube bewusstes Ersetzen nur ueber einen separaten, bestaetigten Ablauf mit
  Historie.

### Tests und Akzeptanz

- Teilreads, Default-Nullen und Controllerwechsel erzeugen kein Stock-Backup.
- Das Stock-Backup bleibt bei spaeteren Profilwechseln unveraendert.
- UI zeigt Datum, Controller, Vollstaendigkeit und Integritaetsstatus.

## T028 - Backup-Import und -Export implementieren

**Abhaengigkeiten:** T026, T027  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Definiere ein dokumentiertes ArcDash-JSON-Backupformat mit Schema,
  Controller-Metadaten, Rohbloecken und Checksumme.
- Implementiere Android Storage Access Framework bzw. eine begruendete
  plattformgerechte Alternative.
- Validiere Import vollstaendig, bevor Daten persistent oder anwendbar werden.
- HEB-Import bleibt deaktiviert, solange T016 das Format nicht belegt hat.

### Tests und Akzeptanz

- Export/Import-Roundtrip ist bytegenau.
- Kaputtes JSON, falsche Typen, manipulierte Checksummen, fremder Controller und
  unbekannte Version sind getestet.
- Import schreibt niemals direkt an den Controller.

## T029 - Sicheren Restore-Ablauf vorbereiten

**Abhaengigkeiten:** T028, T030 bis T036 fuer reale Ausfuehrung  
**Hardware erforderlich:** Spaeter fuer Abnahme

### Arbeitsumfang

- Implementiere Restore zunaechst als Planer: Backup laden, Kompatibilitaet
  pruefen, aktuellen Snapshot lesen und geplante Differenzen anzeigen.
- Leite die spaetere Ausfuehrung ausschliesslich an die sichere Schreibengine
  weiter; kein direkter BLE-Zugriff aus Storage oder UI.
- Fordere bei kritischen Parametern eine explizite Bestaetigung.

### Tests und Akzeptanz

- Fremde, kaputte oder unvollstaendige Backups erzeugen keinen Write-Plan.
- Ein identischer Snapshot erzeugt einen leeren Plan.
- Vor Aktivierung von Phase 1.5 existiert keine Umgehung zur realen Ausfuehrung.

## Phasen-Gate

Nur vollstaendige, identitaetsgebundene und integritaetsgepruefte Snapshots duerfen
als Stock-Backup oder Restore-Quelle angezeigt werden.
