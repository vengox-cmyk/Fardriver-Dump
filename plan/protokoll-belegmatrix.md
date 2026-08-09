# FarDriver Protokoll-Belegmatrix

Stand: `2026-08-02`  
Geltungsbereich: gespeicherte Upstream-Referenz und aktueller ArcDash-Code.
Reale Daten des Zielcontrollers fehlen gemaess `plan/hardwareprofil.md`.

## Statusbegriffe

- **BESTAETIGT-UPSTREAM**: direkt im Upstream-Protokoll oder in der Tabelle belegt.
- **WAHRSCHEINLICH**: im aktuellen Parser konsistent, aber nicht durch Zielhardware-Read-back belegt.
- **UNBEKANNT**: keine ausreichende Evidenz; darf nicht als Safety-Signal oder Write-Freigabe dienen.
- **GESPERRT**: Schreibzugriff bleibt bis zu Capture und Read-back deaktiviert.

## Quellen

| Kürzel | Quelle | Abruf / Stand |
|---|---|---|
| U1 | [`reference/upstream/fardriver-controllers/README.md`](../reference/upstream/fardriver-controllers/README.md), Serial Protocol | lokaler Clone, 2026-08-02 |
| U2 | [`reference/upstream/fardriver-controllers/fardriver_message.hpp`](../reference/upstream/fardriver-controllers/fardriver_message.hpp) | lokaler Clone, 2026-08-02 |
| U3 | [`reference/upstream/fardriver-controllers/fardriver.hpp`](../reference/upstream/fardriver-controllers/fardriver.hpp) | lokaler Clone, 2026-08-02 |
| U4 | [`reference/upstream/fardriver-controllers/HEB.bt`](../reference/upstream/fardriver-controllers/HEB.bt) | lokaler Clone, 2026-08-02 |
| A1 | [`lib/utils/packet_parser.dart`](../lib/utils/packet_parser.dart) | ArcDash HEAD, 2026-08-02 |
| A2 | [`lib/services/protocol_service.dart`](../lib/services/protocol_service.dart) | ArcDash HEAD, 2026-08-02 |
| H1 | [`plan/hardwareprofil.md`](./hardwareprofil.md) | Zielhardwarewerte fehlen |

## Frame- und CRC-Belege

| Bereich | Definition | Status | Schreibbar | Quelle / Abweichung |
|---|---|---|:---:|---|
| Status-Magic | Byte 0 = `0xAA` | BESTAETIGT-UPSTREAM | Nein | U1, U2, A1 |
| Status-ID | Byte 1: 6 Bit ID, 2 Bit Flags | BESTAETIGT-UPSTREAM | Nein | U1, U2 |
| Statusdaten | Bytes 2-13, 12 Bytes | BESTAETIGT-UPSTREAM | Nein | U1, U2 |
| Status-CRC | Bytes 14-15, Start `a=0x3C`, `b=0x7F`, Tabellenfolge | BESTAETIGT-UPSTREAM | Nein | U1, U2, A1 |
| Status-Adressrotation | 55 Eintraege, ID `< 0x37` | BESTAETIGT-UPSTREAM | Nein | U1, U2, A1 |
| ID `0x37` Data Gathering | Format unbekannt | UNBEKANNT | Nein | U1 nennt Format unbekannt; nicht automatisch decodieren |
| Write-Magic | Byte 0 = `0xAA` | BESTAETIGT-UPSTREAM | Nur Fake | U1 |
| Write-Header | Byte 1: Laenge 6, Flags 1 => `0x46` | WAHRSCHEINLICH | GESPERRT | U1/A2; Zielcontroller-ACK fehlt |
| Write-Adresse | Bytes 2 und 3: Adresse und Bestaetigung | WAHRSCHEINLICH | GESPERRT | U1/A2; Echo-/ACK-Nachweis fehlt |
| Write-Daten | Bytes 4-5 little-endian oder explizite Bytes | WAHRSCHEINLICH | GESPERRT | U1/A2; HEB-/Firmwarevariante offen |
| ACK-Bedeutung | Antwort ist ACK, Echo oder Status? | UNBEKANNT | Nein | T016 benoetigt Capture |

## Aktuell decodierte Statusadressen

| Adresse | ArcDash-Feld | Datentyp / Skalierung | Status | Safety-Hinweis |
|---:|---|---|---|---|
| `0xE2` | MeasureSpeed, Forward, Reverse, Gear, Brake, Fehlerbits | u16 und Bitfelder | WAHRSCHEINLICH | Einzelnes Nullfeld beweist keinen Stillstand |
| `0xE8` | Spannung, Linien-Strom | i16 / 10 V, i16 / 4 A | WAHRSCHEINLICH | Vorzeichen muss mit Capture bestätigt werden |
| `0xEE` | Phase A/C Strom | 24-bit big-endian, `1.953125 * sqrt(raw)` | WAHRSCHEINLICH | Upstream struct vorhanden, Zielskalierung offen |
| `0xF4` | Motor-Temperatur, SOC | i16 Grad C, i8 Prozent | WAHRSCHEINLICH | SOC-Grenzen und Rohwertquelle offen |
| `0xD6` | Controller-/MOS-Temperatur | i16 Grad C | WAHRSCHEINLICH | Byteposition gegen Firmware prüfen |
| `0xD0` | Radradius, Breite, Ratio, RateRatio | u8/u16 | WAHRSCHEINLICH | Nur Plausibilitaetswert, keine Write-Freigabe |
| `0x12` | MaxSpeed | u16 raw | WAHRSCHEINLICH | App-Adresse `0x15` widerspricht Statusadresse |
| `0x18` | MaxLineCurr raw | u16 | WAHRSCHEINLICH | App-Write-Adresse `0x19` widerspricht Statusadresse |
| `0x0C` | Batteriekoeffizienten | i16/i16 | WAHRSCHEINLICH | Nur Kalibrierung, kein SOC-Beweis |
| alle übrigen 55 IDs | Rohblock | 12 unbekannte Bytes | BESTAETIGT-UPSTREAM (Position) | nicht optimistisch decodieren |

## Aktuell geschriebene Parameter

| App-Konstante | Adresse | Aktuelle Funktion | Belegstatus | Write-Freigabe |
|---|---:|---|---|---|
| `maxSpeed` | `0x15` | u16 MaxSpeed raw | UNBEKANNT | GESPERRT |
| `maxLineCurr` | `0x19` | A * 4, u16 | UNBEKANNT | GESPERRT |
| `throttleResponse` | `0x1A` | Bits 2-3 | UNBEKANNT | GESPERRT |
| `sysCmd` | `0xA0` | `0x88`, Kommando | WAHRSCHEINLICH-UPSTREAM, Save-Bedeutung offen | GESPERRT |
| `ratedSpeed` | `0x18` | Konstante, aktuell kein Writer | UNBEKANNT | GESPERRT |
| `polePairs` | `0x14` | Konstante, aktuell kein Writer | UNBEKANNT | GESPERRT |
| `ratedPower` | `0x16` | Konstante, aktuell kein Writer | UNBEKANNT | GESPERRT |
| `ratedVoltage` | `0x17` | Konstante, aktuell kein Writer | UNBEKANNT | GESPERRT |

## Widersprüche und Entscheidungen

- **HEB-Groesse:** `HEB.bt` listet 26 12-Byte-Bloecke bis `0xD0` und kommentiert
  zusaetzliche `0x180` CAN-Konfiguration. Eine komplette HEB-Dateigroesse,
  Header- und Checksummspezifikation ist damit nicht bewiesen. T015 darf keinen
  Snapshot als vollstaendiges HEB ausgeben.
- **Speicherkommando:** U1 dokumentiert `0x88 XX` an `0xA0` als
  Systemkommandos, aber keinen Persistenzbeweis. `0xA0 / 0x88 0x01` wird daher
  nicht als Save behandelt; T016 bleibt fuer reale Captures gesperrt.
- **Motionssignale:** U3 beschreibt viele Register und Optionen, aber es gibt
  keinen einzelnen universellen Stillstandsschalter. Safety muss RPM, Gas,
  DNR/Bremse, Frische und Datenquelle gemeinsam bewerten.
- **Throttle-Bitfeld:** Der aktuelle Code nimmt Bits 2-3 in `0x1A` an. Das ist
  ohne konkrete Zielhardware-Capture nur eine Hypothese und bleibt gesperrt.
- **DOCX-Referenzen:** Die DOCX-Dateien gelten gemaess Ausfuehrungsregeln nur
  als Hypothesenquelle. Sie erzeugen keinen BESTAETIGT-Status.

## Sicherheitsregel

Parser und Fake-Tests dürfen alle WAHRSCHEINLICH-Felder anzeigen. Kein
UNBEKANNT- oder GESPERRT-Feld darf einen realen Write freischalten. Für jede
spätere Freigabe sind konkrete Controller-ID/Firmware, anonymisierte Rohbytes,
erwarteter Decode und Read-back-Nachweis in T010/T016 erforderlich.
