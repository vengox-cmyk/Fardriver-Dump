# Phase 3: BLE und Controller-Session

## Phasenziel

BLE-Verbindung und Protokollverarbeitung bilden eine langlebige,
UI-unabhaengige und testbare Session. Spaet abonnierende Komponenten erhalten
sofort den aktuellen Zustand.

## T017 - Testbare Transport-Schnittstelle einfuehren

**Abhaengigkeiten:** T012  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Definiere eine kleine Schnittstelle fuer Scan, Connect, Disconnect, Write,
  Verbindungszustand und eingehende Bytes.
- Kapsle `flutter_blue_plus` hinter einem Android/BLE-Adapter.
- Implementiere einen deterministischen Fake mit steuerbaren Fehlern,
  Fragmenten, Delays und Disconnects.

### Tests und Akzeptanz

- Controller- und Protokolltests importieren `flutter_blue_plus` nicht direkt.
- Fake-Tests koennen Connect-Fehler, Write-Fehler und Datenfolgen simulieren.
- Bestehendes Verhalten bleibt ueber den realen Adapter erreichbar.

## T018 - Zustandsbehaftete Controller-Session bauen

**Abhaengigkeiten:** T017, T015  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Fuehre Adapter-, Verbindungs-, Protokoll-, Snapshot- und Telemetriezustand in
  einer langlebigen Session zusammen.
- Starte Statusstream und Parser unabhaengig davon, wann ein Screen oder Provider
  abonniert.
- Definiere klare Zustandsuebergaenge und Fehlerursachen.

### Tests und Akzeptanz

- Ein nach Connect erzeugter Consumer sieht sofort `connected` und aktuelle
  Telemetrie.
- Doppeltes Connect/Disconnect bleibt idempotent.
- Session-Dispose beendet Subscriptions und Timer ohne spaete Events.

## T019 - Android-Runtime-Permissions implementieren

**Abhaengigkeiten:** T018  
**Hardware erforderlich:** Android-Geraet fuer manuelle Abnahme

### Arbeitsumfang

- Implementiere versionsabhaengige Bluetooth- und Standortfreigaben.
- Fordere nur benoetigte Rechte im passenden Nutzungskontext an.
- Behandle Ablehnung, dauerhaft abgelehnt und deaktiviertes Bluetooth mit klarer
  deutscher UI und Link zu Systemeinstellungen.

### Tests und Akzeptanz

- Permission-Entscheidungslogik ist als reine Logik unit-getestet.
- Android 11 und Android 12+ verwenden die korrekten Rechte.
- Ohne Freigabe startet kein Scan und die App bleibt bedienbar.

## T020 - Scan, Pairing und Service-Erkennung haerten

**Abhaengigkeiten:** T019  
**Hardware erforderlich:** Ja fuer manuelle Abnahme

### Arbeitsumfang

- Leere alte Scanergebnisse und verhindere parallele Scans.
- Unterstuetze Dongles, die ihre UART-Service-UUID nicht im Advertisement
  melden, ueber einen kontrollierten Namens-/Manuell-Auswahl-Fallback.
- Pruefe Characteristic-Properties und waehle Write-Modus passend zur Hardware.
- Speichere das explizit bestaetigte Zielgeraet, nicht irgendeinen Namensmatch.
- Bilde das reale Zielgeraet der Arctic Leopard Xe Pro S ab (BLE-Scan-Beleg in
  `reference/`):
  - Gerätename `CONTROLDMC88`, MAC `C0:07:AD:88:00:6B` (anonymisieren in Fixtures)
  - Service `0000FF00-0000-1000-8000-00805F9B34FB`
  - Characteristic `0000FFEC-0000-1000-8000-00805F9B34FB`
  - Properties `READ`, `NOTIFY`, `WRITE WITHOUT RESPONSE`
  - Die bisherige FFE0/FFE1- und `49535343`-Annahme aus BikeTunes gilt fuer diese
    Hardware nicht; sie ist als Fallback zu erhalten, nicht als Standard.
- Scan ohne ausschliesslichen `withServices`-Filter auf FFE0/`49535343`
  durchfuehren, damit Geräte erkannt werden, die ihre Service-UUID nicht im
  Advertisement melden; anschliessend per Name filtern und Services nach dem
  Verbinden dynamisch aus `discoverServices()` ermitteln.
- Auf der echten Hardware verifizieren, dass das bekannte FarDriver-Protokoll
  (Paketformat, CRC, Adressen) unveraendert ueber `FFEC` laeuft; Abweichungen
  dokumentieren und T009/T010 zurueckmelden.

### Tests und Akzeptanz

- Duplikate, namenlose Geraete, Scanabbruch und fehlender UART-Service sind
  getestet.
- Die App verbindet sich nie automatisch mit einem nur schwach passenden neuen
  Geraet.
- Reale Zielhardware kann reproduzierbar gefunden und verbunden werden.

## T021 - Automatisches Wiederverbinden implementieren

**Abhaengigkeiten:** T020  
**Hardware erforderlich:** Ja fuer manuelle Abnahme

### Arbeitsumfang

- Implementiere Reconnect zum bestaetigten letzten Geraet mit begrenztem
  exponentiellem Backoff und Jitter.
- Reagiere auf Adapter aus/an, GATT-Disconnect, Timeout und App-Lifecycle.
- Biete manuellen Abbruch und sichtbaren Reconnect-Status.

### Tests und Akzeptanz

- Backoff, Maximalintervall, Reset nach Erfolg und Abbruch sind mit Fake Clock
  getestet.
- Mehrere Disconnect-Events starten nur eine Reconnect-Schleife.
- Nach erneutem Connect werden Notifications und Statusstream neu initialisiert.

## T022 - Command-Queue und Protokollzugriff serialisieren

**Abhaengigkeiten:** T018, T021  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Fuehre eine FIFO-Queue fuer Protokollkommandos mit Timeout und Cancellation
  ein.
- Korrelierte Antworten werden genau dem aktiven Kommando zugestellt;
  Telemetrie laeuft parallel weiter.
- Disconnect bricht aktive und wartende Kommandos mit typisiertem Fehler ab.

### Tests und Akzeptanz

- Gleichzeitige Aufrufer erzeugen keine ueberlappenden Writes.
- Timeout, spaete Antwort, falsches ACK, Cancel und Disconnect sind getestet.
- Kein Future bleibt nach Session-Ende unerledigt.

## T023 - Diagnose-Logging und Export ergaenzen

**Abhaengigkeiten:** T022  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Definiere strukturierte Events fuer Scan, Connect, Frames, Parserfehler,
  Kommandos, Safety-Entscheidungen und Reconnect.
- Begrenze In-Memory-Logs und redigiere Geraeteadressen, Seriennummern und
  sensible Parameter.
- Baue einen expliziten Diagnoseexport und repariere den Live-Debug-Screen.

### Tests und Akzeptanz

- Redaction, Ringbuffer-Grenze und Exportformat sind getestet.
- Logs unterscheiden Transporterfolg, ACK, Read-back und fachlichen Erfolg.
- Standardbetrieb schreibt keine unbeschraenkte Rohdatenmenge auf den Speicher.

## Phasen-Gate

Reconnect, Paketfragmentierung, spaete Consumer und konkurrierende Kommandos sind
ohne Hardware automatisiert reproduzierbar. Die reale Hardware besteht einen
Disconnect-/Reconnect-Smoke-Test.
