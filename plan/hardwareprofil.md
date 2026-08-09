# ArcDash Hardwareprofil

Version: `0.1.0`  
Stand: `2026-08-02`  
Freigabestatus: **BLOCKIERT bis manueller Freigabe durch den Fahrzeugeigentuemer**

Dieses Dokument ist die versionierte Quelle fuer fahrzeug- und controllergebundene
Sicherheitsentscheidungen. Unbekannte Werte werden nicht geschaetzt. Solange
Pflichtfelder blockiert sind, duerfen App, UI, Simulation und Fake-Tests weiter
entwickelt werden; reale Parameter-Schreibvorgaenge bleiben deaktiviert.

## Fahrzeug und Controller

| Feld | Wert | Nachweis / Quelle | Status |
|---|---|---|---|
| Fahrzeug | Arctic Leopard Xe Pro S | Produktanforderung | bestaetigt als Zielmodell |
| Controller-Modell | `BLOCKIERT` | Typenschild / BLE-Identitaet | Eigentuemernachweis erforderlich |
| Controller-Seriennummer | `BLOCKIERT`, nicht oeffentlich dokumentieren | Typenschild | vertraulich |
| Controller-Hardwareversion | `BLOCKIERT` | Controller-Read-back | erforderlich |
| Controller-Firmwareversion | `BLOCKIERT` | Controller-Read-back | erforderlich |
| FarDriver-Funktionscode | `BLOCKIERT` | bestaetigtes HEB/Read-back | erforderlich |
| Protokoll-/Registerprofil | `BLOCKIERT` | konkrete Captures und Read-back | T009-T016 |
| BLE-Geraetename | `BLOCKIERT` | Scan auf Zielgeraet | darf anonymisiert werden |
| BLE-MAC-Adresse | `BLOCKIERT`, niemals in Fixtures | Scan | vertraulich |

## Motor, Batterie und Antrieb

| Feld | Wert | Nachweis / Quelle | Status |
|---|---|---|---|
| Motorhersteller und Modell | `BLOCKIERT` | Typenschild / Datenblatt | erforderlich |
| Motor-Nennleistung | `BLOCKIERT` | Datenblatt | erforderlich |
| Batteriechemie | `BLOCKIERT` | Batterie-/BMS-Datenblatt | sicherheitskritisch |
| Batterie-Nennspannung | `BLOCKIERT` | Batterie-/BMS-Datenblatt | sicherheitskritisch |
| Batterie-Kapazitaet | `BLOCKIERT` | Batterie-/BMS-Datenblatt | sicherheitskritisch |
| BMS-Ladelimit | `BLOCKIERT` | BMS-Read-back / Datenblatt | sicherheitskritisch |
| BMS-Entladelimit | `BLOCKIERT` | BMS-Read-back / Datenblatt | sicherheitskritisch |
| Controller MaxLineCurr | `BLOCKIERT` | bestaetigtes Register + BMS | reale Writes gesperrt |
| Controller MaxPhaseCurr | `BLOCKIERT` | bestaetigtes Register + Motor | reale Writes gesperrt |
| Radumfang / Reifengroesse | `BLOCKIERT` | Messung / Typenschild | fuer RPM-GPS-Fallback |
| Uebersetzung | `BLOCKIERT` | Fahrzeugdaten | fuer RPM-GPS-Fallback |

## Originaldaten und Fixtures

| Artefakt | Referenzpfad | Status / Datenschutz |
|---|---|---|
| Originales HEB-/Stock-Backup | `reference/fixtures/stock/` | `BLOCKIERT`, erst nach Hardware-Read-back erstellen |
| Anonymisierte BLE-Captures | `reference/fixtures/ble/` | `BLOCKIERT`, Adressen und Seriennummern entfernen |
| Rohdaten-Manifest | `reference/fixtures/manifest.json` | `BLOCKIERT`, Hashes und Herkunft dokumentieren |
| Oeffentliche Test-Fixtures | `test/fixtures/` | Nur synthetisch oder anonymisiert; keine privaten Kennungen |

Ein Backup darf erst als Stock-Backup angeboten werden, wenn Identitaet,
Vollstaendigkeit, CRC und Read-back-Referenz gespeichert sind. Ein Capture ohne
Metadaten zu Controller/Firmware und Testbedingungen ist kein Beleg.

## Street-Legal-Entscheidung

| Feld | Wert | Status |
|---|---|---|
| Zulaessige Hoechstgeschwindigkeit | `BLOCKIERT` | lokale Rechtslage und Zulassung pruefen |
| Moderates Linien-/Phasenstromlimit | `BLOCKIERT` | Fahrzeug-/BMS-Freigabe erforderlich |
| Throttle-Response | `BLOCKIERT` | nur nach Zulassungspruefung |
| Rechtsraum | `BLOCKIERT` | Nutzer muss Land/Region angeben |
| Bestaetigt durch | `BLOCKIERT` | Fahrzeugeigentuemer / fachkundige Stelle |
| Bestaetigungsdatum | `BLOCKIERT` | nach manueller Freigabe eintragen |

Street Legal ist ein nutzerkonfigurierbares Profil mit sichtbarem Disclaimer,
kein pauschales Preset. Ohne bestaetigte Werte wird es nicht geschrieben und
nicht als rechtssicher bezeichnet.

## Produkt- und Zielgeraetentscheidungen

| Feld | Entscheidung | Status |
|---|---|---|
| Application-ID | `BLOCKIERT`, finale ArcDash-ID in T006 festlegen | offen |
| Primarplattform | Android | bestaetigt |
| Android-Zielversionen | `BLOCKIERT` | Zielgeraeteinventar erforderlich |
| Mindest-Android-Version | `BLOCKIERT` | BLE-/Foreground-Service-Matrix erforderlich |
| iOS | Nice-to-have, kein V1-Release-Gate | bestaetigt |
| Hintergrundbetrieb | Android Foreground Service | Architekturentscheidung |
| Reale Writes | deaktiviert bis Profilfreigabe und Fixtures | Sicherheitsentscheidung |

## Freigabecheckliste

- [ ] Controller-Modell, Hardware- und Firmwareversion ausgelesen
- [ ] Seriennummer vertraulich erfasst und aus oeffentlichen Fixtures entfernt
- [ ] Motor-, Batterie- und BMS-Daten mit Quelle belegt
- [ ] MaxLineCurr und MaxPhaseCurr bestaetigt
- [ ] Originales HEB-/Stock-Backup atomar gesichert und geprueft
- [ ] BLE-Captures anonymisiert und mit Hash/Metadaten abgelegt
- [ ] Street-Legal-Werte fuer Rechtsraum bestaetigt
- [ ] Zielgeraete und Android-Versionen festgelegt
- [ ] Fahrzeugeigentuemer hat dieses Profil manuell freigegeben

Bis alle sicherheitskritischen Punkte abgehakt sind, bleibt der Freigabestatus
`BLOCKIERT`. Die Freigabe darf nicht durch einen automatisierten Test ersetzt
werden.
