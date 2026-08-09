# Safety- und Hardware-Testplan

Dieser Plan darf erst nach dokumentierter Controller-, Motor-, Batterie- und
BMS-Freigabe ausgefuehrt werden. Bis dahin bleiben reale Writes deaktiviert.

## Stufe 0: Identitaet und Backup

- Controller-Modell, Hardware-/Firmwareversion und lokale Bindung erfassen.
- Vollstaendigen Read durchfuehren und Rohbytes, CRC, Quelle und Zeitstempel
  sichern.
- Vollstaendigkeit und Integritaetspruefung bestaetigen.
- Stock-Backup als unveraenderlich markieren.

## Stufe 1: Stillstand

- Fahrzeug sichern, Hinterrad frei oder Fahrzeug sicher abgestellt.
- BLE verbunden, drei frische Stillstandssamples empfangen.
- Gas null, Bremse/DNR/Parkzustand bekannt, RPM null, keine Fehler.
- Safety-Evaluator muss freigeben; bei stale oder wechselnden Samples abbrechen.

## Stufe 2: Einzelparameter

- Genau einen freigegebenen Komfortparameter waehlen.
- Aktuellen Rohwert lesen, Diff anzeigen und explizit bestaetigen.
- Genau einen Write senden, ACK korrelieren und Read-back pruefen.
- Bei jedem Fehler stoppen; keinen Folgeparameter automatisch senden.

## Stufe 3: Persistenz

- Controller trennen und neu verbinden.
- Read-back erneut aufnehmen und Wert vergleichen.
- Power-Cycle durchfuehren, erneut lesen und Abweichung dokumentieren.

## Stufe 4: Rollback

- Nur einen verifizierten, vorher gesicherten Parameter zuruecksetzen.
- ACK und Read-back pruefen.
- Fehlgeschlagenes Rollback niemals als erfolgreich melden.

## Ergebnisprotokoll

Für jeden Test: Datum, Controllerbindung, App-Version, Firmware, Parameter,
alter/neuer Rohwert, ACK, Read-back, Safety-Samples, Ergebnis und Abbruchgrund.
