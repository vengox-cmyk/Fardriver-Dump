# Phase 6: Android-Hintergrundbetrieb

## Phasenziel

ArcDash haelt die bestaetigte BLE-Verbindung in einem Android Foreground Service
und kann den Street-Legal-Wechsel ueber MacroDroid bei ausgeschaltetem Bildschirm
sicher ausfuehren.

## T046 - Foreground-Service-Architektur festlegen

**Abhaengigkeiten:** T018, T022, T045  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Entscheide anhand Android-Dokumentation, ob native Kotlin-Ownership,
  Flutter-Isolate oder ein gepflegtes Plugin den langlebigen BLE-Lifecycle
  kontrolliert.
- Dokumentiere Prozessmodell, Single Source of State, Start/Stop, Reconnect,
  Flutter-Bindung und Verhalten nach Process Death.
- Bewerte Companion Device APIs; WorkManager darf keine dauerhafte BLE-Session
  vortaeuschen.

### Tests und Akzeptanz

- Architektur verhindert eine zweite BLE- oder Write-Session neben dem Service.
- Android-12-bis-14-Einschraenkungen und Hersteller-Battery-Saver sind erfasst.
- Tech-Stack-Aenderungen sind vor Implementierung dokumentiert.

## T047 - Android-Service und Berechtigungen konfigurieren

**Abhaengigkeiten:** T046  
**Hardware erforderlich:** Android-Geraet

### Arbeitsumfang

- Implementiere Foreground Service mit passendem `connectedDevice`-Typ,
  Manifest-Rechten, Notification Channel und Android-13+-Notification-Flow.
- Entferne die falsche Service-Deklaration der FlutterBluePlus-Pluginklasse.
- Definiere klar, wann und durch welche sichtbare Nutzeraktion der Service startet.

### Tests und Akzeptanz

- Service startet regelkonform auf Android 12, 13 und 14.
- Eine persistente, knappe deutsche Benachrichtigung ist vorhanden.
- Ablehnung der Notification-/Bluetooth-Rechte wird kontrolliert behandelt.
- Service ist nicht unnoetig exportiert.

## T048 - BLE-Session in den Service integrieren

**Abhaengigkeiten:** T021, T022, T047  
**Hardware erforderlich:** Ja

### Arbeitsumfang

- Mache den Service zum Besitzer der Controller-Session und Reconnect-Logik.
- Stelle dem sichtbaren Flutter-Teil nur beobachtbaren Zustand und Kommandos zur
  Verfuegung.
- Halte die Session bei gesperrtem Bildschirm und App im Hintergrund stabil.

### Tests und Akzeptanz

- UI schliessen/oeffnen erzeugt keine zweite GATT-Verbindung.
- Bildschirm aus, App-Wechsel und Activity-Neustart verlieren die Session nicht.
- Serviceende schliesst BLE und alle Ressourcen sauber.

## T049 - Native Flutter-Kommandobruecke bauen

**Abhaengigkeiten:** T048  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Definiere versionierte Nachrichten fuer Status, Profilanforderung, Ergebnis und
  Fehler zwischen Android-Service und Flutter.
- Behandle kalten Start, noch nicht initialisierte Engine und Process Death.
- Serialisiere Kommandos und Ergebnisse typisiert statt freier Maps, soweit
  praktikabel.

### Tests und Akzeptanz

- Ungueltige, doppelte und unbekannte Nachrichten sind getestet.
- Ein Ergebnis geht nicht verloren, wenn gerade keine Activity sichtbar ist.
- Fehler enthalten stabile Codes fuer Benachrichtigung und Diagnose.

## T050 - Sicheren MacroDroid-Vertrag definieren

**Abhaengigkeiten:** T049  
**Hardware erforderlich:** Android-Geraet mit MacroDroid

### Arbeitsumfang

- Definiere genau eine externe Aktion zum Anwenden des lokal konfigurierten
  Street-Legal-Profils; akzeptiere keine beliebigen Parameter oder Profilnamen.
- Waehle Broadcast, expliziten Intent oder Deep Link anhand Android-Sicherheit
  und MacroDroid-Unterstuetzung.
- Begrenze Export, validiere Action/Daten, rate-limit Spam und dokumentiere die
  MacroDroid-Einrichtung.

### Tests und Akzeptanz

- Manipulierte Extras koennen keine Werte oder anderen Profile schreiben.
- Unbekannte Actions werden ignoriert und protokolliert.
- Wiederholte Trigger starten hoechstens eine idempotente Anwendung.
- Ein Instrumentationstest sendet den oeffentlichen Vertrag realistisch.

## T051 - Street Legal bei ausgeschaltetem Bildschirm anwenden

**Abhaengigkeiten:** T045, T048, T050  
**Hardware erforderlich:** Ja

### Arbeitsumfang

- Fuehre Intent -> Service -> Session/Reconnect -> Safety -> Fast Path ->
  Read-back ohne sichtbare Activity aus.
- Definiere begrenzte Zeitouts und klare Ergebnisse fuer nicht verbunden,
  Bewegung, stale Telemetrie und Hardwarefehler.
- Wecke niemals Display oder Activity fuer den Normalfall.

### Tests und Akzeptanz

- Erfolg wird erst nach Read-back gemeldet.
- Gesperrter Bildschirm bleibt waehrend des gesamten Vorgangs aus.
- Bewegung und unklarer Zustand sperren auch den Hintergrundpfad.
- Tests decken verbunden, reconnect erforderlich, offline und Doppeltrigger ab.

## T052 - Hintergrund-Feedback implementieren

**Abhaengigkeiten:** T051  
**Hardware erforderlich:** Android-Geraet

### Arbeitsumfang

- Implementiere unterscheidbare, dezente Vibrationsmuster fuer Erfolg und Fehler.
- Aktualisiere optional die stille Servicebenachrichtigung mit knappem Ergebnis.
- Respektiere Android-Einstellungen und eine ArcDash-Option zum Ergebnisfeedback.

### Tests und Akzeptanz

- Feedback erfolgt genau einmal pro abgeschlossener Anforderung.
- Ein Safety-Block klingt/fuehlt sich nicht wie Erfolg an.
- Keine Activity und kein Bildschirm-Wakeup werden ausgeloest.

## T053 - Android-Lifecycle-Matrix validieren

**Abhaengigkeiten:** T047 bis T052  
**Hardware erforderlich:** Ja

### Arbeitsumfang

- Teste Android 12, 13 und 14: Vordergrund, Hintergrund, Screen-off,
  Activity-Kill, Process Death, Bluetooth aus/an, Controller ausser Reichweite,
  Doze und Hersteller-Battery-Saver.
- Dokumentiere Geraet, Version, Schritte, Zeiten und Ergebnis.
- Behebe reproduzierbare Lifecycle-Fehler mit Tests vor der Korrektur.

### Tests und Akzeptanz

- Kritischer Screen-off-Street-Legal-Flow besteht auf allen Zielversionen.
- Service und Notification entsprechen `adb`-Status und Android-Vorgaben.
- Bekannte OEM-Einschraenkungen besitzen Nutzerhinweise statt falscher Garantien.

## Phasen-Gate

MacroDroid kann bei ausgeschaltetem Bildschirm ausschliesslich Street Legal
anfordern. Safety, Hardwarelimits, Write-Lock und Read-back bleiben unveraendert
aktiv.
