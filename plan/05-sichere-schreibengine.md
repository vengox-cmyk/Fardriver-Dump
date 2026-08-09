# Phase 1.5: Sichere Schreibengine (zurueckgestellt)

Diese Phase ist bis zum Abschluss der Read-only-Version deaktiviert. Ihre
Implementierung, Write-Abnahme und hardwareabhängigen Tests werden aktuell
nicht ausgeführt.

## Phasenziel

Jede Parameterveraenderung laeuft durch dieselbe fail-closed Safety- und
Transaktionsschicht. UI, Restore und spaeterer Background-Service besitzen
keinen direkten BLE-Schreibzugriff.

## T030 - Parameterkatalog und Hardwaregrenzen erstellen

**Abhaengigkeiten:** T009, T013, T016, T025  
**Hardware erforderlich:** Ja fuer finale Grenzwerte

### Arbeitsumfang

- Definiere fuer jeden freigegebenen Parameter Adresse, Typ, Skalierung,
  Bitmaske, Risiko, Lesbarkeit, Schreibbarkeit und Verifikationsregel.
- Leite absolute Obergrenzen aus Controller, Motor, Batterie und BMS ab; der
  kleinste bestaetigte Grenzwert gewinnt.
- Trenne unveraenderliche Werksgrenzen von nutzerdefinierten Komfortgrenzen.
- Unbekannte Grenzen sperren den Parameter fuer reale Writes.

### Tests und Akzeptanz

- Unter-/Obergrenze, NaN, Rundung und Rohwertueberlauf sind getestet.
- Importierte Profile und Restore koennen die Grenzen nicht umgehen.
- Schutz-, Sensor-, Pin- und Motorbasisparameter sind standardmaessig nicht im
  normalen Profileditor schreibbar.

## T031 - Fail-closed Safety-Evaluator bauen

**Abhaengigkeiten:** T014, T018, T030  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Bewerte Verbindung, Controller-Identitaet, Telemetriefrische, RPM,
  Motorlaufbits, DNR/Park, Bremse und Schreib-Backup.
- Verlange mehrere aufeinanderfolgende frische Stillstandssamples innerhalb
  enger Zeitgrenzen.
- Liefere typisierte Ablehnungsgruende fuer UI und Audit-Log.

### Tests und Akzeptanz

- Disconnected, stale, unbekannt, RPM ungleich null, MotorRun und wechselnde
  Samples sperren Writes.
- Defaultwerte direkt nach App-Start gelten nie als Stillstandsnachweis.
- Nur der vollstaendig bestaetigte Zustand kann freigeben.
- Grenz- und Race-Condition-Tests verwenden eine Fake Clock.

## T032 - Optionales Schreiben beim Ausrollen modellieren

**Abhaengigkeiten:** T031, bestaetigte Gas-/Motorfelder aus T014  
**Hardware erforderlich:** Ja fuer Aktivierungsfreigabe

### Arbeitsumfang

- Fuehre eine standardmaessig deaktivierte Safety-Option ein.
- Definiere erforderliche Signale: Gas sicher null, keine Beschleunigungsanforderung,
  keine Fehler, bestaetigte Richtung und zulaessiger enger RPM-Bereich.
- Beschraenke die Option auf explizit als ausrollsicher klassifizierte Parameter.

### Tests und Akzeptanz

- Fehlende oder veraltete Gasdaten sperren den Vorgang.
- Kritische Parameter bleiben auch bei aktivierter Option auf Stillstand
  beschraenkt.
- Aktivierung erfordert Warnung und bestaetigte Hardwareunterstuetzung.

## T033 - Diff und Read-modify-write implementieren

**Abhaengigkeiten:** T013, T015, T030  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Vergleiche Zielwerte gegen einen frischen aktuellen Snapshot und erzeuge nur
  notwendige Aenderungen.
- Baue Bitfeld-Updates aus dem aktuellen Registerwort auf und erhalte alle
  unbekannten/Nachbarbits.
- Sortiere Aenderungen deterministisch und markiere Abhaengigkeiten.

### Tests und Akzeptanz

- Identische Profile erzeugen null Writes.
- Throttle-, Follow-, Weak- und RXD-Bits beeinflussen einander nicht.
- Ohne aktuellen Rohwert ist Read-modify-write nicht planbar.
- Diff enthaelt alten/neuen physischen und rohen Wert.

## T034 - Transaktionales Schreiben mit Read-back bauen

**Abhaengigkeiten:** T022, T031, T033  
**Hardware erforderlich:** Fuer finale Abnahme

### Arbeitsumfang

- Fuehre vor jedem Write unmittelbar eine erneute Safety-Pruefung durch.
- Sende genau eine Aenderung, korreliere ACK und lese den Wert anschliessend
  erneut aus.
- Vergleiche Rohwert unter Beruecksichtigung dokumentierter Quantisierung.
- Melde Erfolg erst, wenn alle geplanten Aenderungen bestaetigt sind.

### Tests und Akzeptanz

- Transporterfolg ohne ACK oder Read-back ist kein Erfolg.
- Falsche Adresse, falscher Wert, Timeout und Safety-Aenderung waehrend der
  Transaktion brechen ab.
- Ein Ergebnis enthaelt Status je Parameter und Gesamtstatus.

## T035 - Teilfehler und Rollback behandeln

**Abhaengigkeiten:** T034  
**Hardware erforderlich:** Fuer finale Abnahme

### Arbeitsumfang

- Definiere Retry nur fuer sicher wiederholbare Fehler und mit begrenzter Zahl.
- Erzeuge vor dem ersten Write einen frischen Ausgangssnapshot.
- Rolle bereits bestaetigte Aenderungen kontrolliert zurueck, wenn dies fuer den
  Parameter sicher und verifiziert moeglich ist.
- Wenn Rollback nicht sicher ist, stoppe und zeige einen klaren Teilzustand.

### Tests und Akzeptanz

- Fehler beim ersten, mittleren und letzten Parameter sind getestet.
- Ein fehlgeschlagener Rollback wird nie als restauriert gemeldet.
- Retry schreibt keine bereits verifizierten Werte unnoetig erneut.

## T036 - Write-Lock, Idempotenz und Audit-Log ergaenzen

**Abhaengigkeiten:** T035  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Stelle sicher, dass UI, Restore und Hintergrund niemals parallel schreiben.
- Dedupliziere identische laufende Anforderungen und definiere Busy-Verhalten.
- Protokolliere Initiator, Controller, Safety-Entscheidung, Diff, Ergebnisse und
  Rollback ohne sensible Vollidentitaeten.

### Tests und Akzeptanz

- Parallel-, Doppeltrigger- und Cancel-Szenarien sind deterministisch getestet.
- Audit-Eintrag entsteht auch fuer abgelehnte und teilweise fehlgeschlagene
  Vorgange.
- Audit-Historie ist begrenzt und exportierbar.

## T037 - Safety-UX und Hardware-Testplan fertigstellen

**Abhaengigkeiten:** T030 bis T036  
**Hardware erforderlich:** Ja

### Arbeitsumfang

- Baue deutsche Bestatigungs-, Fortschritts-, Fehler- und Teilzustandsanzeigen.
- Zeige kritische Differenzen und harte Limits ohne Tuning zu verharmlosen.
- Erstelle einen stufenweisen Hardware-Testplan: Rad frei, niedrige Limits,
  Einzelparameter, Read-back, Power-Cycle, kontrollierte Probefahrt.

### Tests und Akzeptanz

- Widgettests decken blockiert, schreibt, verifiziert, Teilfehler und Rollback ab.
- Hardwaretests bestaetigen, dass Bewegung und stale Telemetrie sperren.
- Kein UI-Button kann die Write Engine umgehen.

## Phasen-Gate

Kein Write ist bei unbekanntem, veraltetem oder bewegtem Zustand moeglich.
Teilvorgaenge erscheinen nie als Erfolg, und jeder Erfolg besitzt Read-back.
