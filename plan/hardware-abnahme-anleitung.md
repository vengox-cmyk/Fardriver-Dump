# Hardware-Abnahme: Read-only-Daten sammeln

Diese Anleitung sammelt nur Identitaet, Telemetrie und Parameter-Reads. Keine
Parameter schreiben, kein Factory Reset, kein Self-Learn, kein Save/Apply und
keine Systemkommandos ausfuehren.

## Vorbereitung

1. Fahrzeug aufbocken oder sicher abstellen; Hinterrad darf keinen Bodenkontakt
   haben.
2. Ladezustand und Zuendschluesselstellung fotografieren, aber das Fahrzeug
   nicht fahren.
3. Android-Bluetooth einschalten und der FarDriver-App nur die benoetigten
   Bluetooth-Rechte geben.
4. Screenshots und Exporte unter einem neuen Ordner `fardriver-read-YYYYMMDD`
   sammeln.
5. MAC-Adresse, Seriennummer und persoenliche Daten vor dem Teilen markieren;
   die Rohdaten trotzdem lokal unveraendert behalten.

## Originale FarDriver-App

1. App starten und genau ein Zielgeraet verbinden. Wenn mehrere Geraete
   angezeigt werden, nicht raten, sondern Name und MAC mit dem BLE-Scanbeleg
   abgleichen.
2. Screenshots von Modellname, Hardwareversion, Firmwareversion,
   Funktionscode/Extension-Code und Verbindungsseite erstellen.
3. Alle vorhandenen Diagnose-/Read-/Parameterseiten oeffnen und exportieren,
   falls die App einen Export anbietet.
4. Falls kein Export existiert, jede Parameterseite mit sichtbarem Namen,
   Adresse/Index, Wert und Einheit screenshotten.
5. Nur Funktionen mit `Read`, `Refresh`, `Query` oder `Get` verwenden. Jede
   Funktion mit `Write`, `Save`, `Apply`, `Send`, `Set`, `Reset`, `Learn` oder
   `Restore` abbrechen.
6. Die App nach jedem Read mindestens 10 Sekunden verbunden lassen und die
   Live-Telemetrie screenshotten.
7. App trennen und nicht erneut verbinden, bevor die Dateien gesichert sind.

## BLE-Beleg

1. Mit einem BLE-Scanner (z. B. dem bereits verwendeten BLE Scanner) nach dem
   Zielgeraet suchen.
2. Screenshot von Geraetename und Service-Liste erstellen.
3. Service `0000FF00-0000-1000-8000-00805F9B34FB` und Characteristic
   `0000FFEC-0000-1000-8000-00805F9B34FB` oeffnen.
4. Properties dokumentieren: insbesondere `READ`, `NOTIFY` und
   `WRITE WITHOUT RESPONSE`. Nichts auf die Characteristic schreiben.
5. Falls der Scanner einen Export anbietet, nur Advertisement- und
   Service-Metadaten exportieren, keine privaten Adressdaten veroeffentlichen.

## Optionaler Mitschnitt

Ein HCI-BTSnoop-Log darf nur waehrend eines reinen Connect-/Read-Vorgangs
aufgenommen werden. Android: Entwickleroptionen -> Bluetooth HCI snoop log
aktivieren, Bluetooth aus/an, verbinden, einen Read ausfuehren, trennen und
danach das Log sichern. Anschliessend HCI snoop wieder deaktivieren.

## Abgabe an ArcDash

Bitte als ZIP mit diesen Dateien liefern:

- `README.txt` mit Android-Modell, FarDriver-App-Version, Datum und kurzer
  Reihenfolge der ausgefuehrten Read-Schritte
- Screenshots der Identitaet und BLE-Service-Liste
- FarDriver-Export oder Parameter-Screenshots
- optional anonymisiertes HCI-BTSnoop-Log
- `MAC.txt` separat und nur privat, falls die Geraetebindung benoetigt wird

Nicht benoetigt und nicht ausfuehren: Writes, Saves, Factory Reset, Self-Learn,
HEB-Import oder Restore. Falls ein Menue nicht exakt so heisst, Screenshot der
Menueansicht schicken und dort stoppen; keine vergleichbare Funktion erraten.
