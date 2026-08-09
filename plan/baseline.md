# ArcDash Baseline

Stand: `2026-08-02`
Arbeitsbaum bei Beginn: sauberer Anwendungscode; eine bereits vorhandene,
nicht von T003 erzeugte unversionierte Datei `reference/gedankengang.md` blieb
unangetastet.

## Toolchain

Alle Befehle wurden einzeln mit Docker Compose ausgefuehrt. Die verwendete
Umgebung meldet:

```text
Flutter 3.44.0 • channel [user-branch] • unknown source
Framework • revision 559ffa3f75
Engine • hash fcf463a2242790d1fdcd9d044f533080f5022e18
Tools • Dart 3.12.0 • DevTools 2.57.0
Dart SDK version: 3.12.0 (stable) ... on "linux_x64"
```

Der Container wird aus `Dockerfile` mit `ghcr.io/cirruslabs/flutter:stable`
gebaut. `docker-compose.yml` setzt `CI=true`, mountet das Repository unter
`/app` und persistiert Pub- und Gradle-Caches.

## Reproduzierbare Befehle

| Zweck | Exakter Befehl | Exit | Beobachtung |
|---|---|---:|---|
| Docker-Image | `docker compose build` | 0 | Image `biketunes-flutter:latest` gebaut |
| Dependencies | `docker compose run --rm flutter flutter pub get` | 0 | Abhaengigkeiten aufgeloest; 62 Pakete mit neueren inkompatiblen Versionen gemeldet |
| Format-Check | `docker compose run --rm flutter dart format --set-exit-if-changed lib test` | 0 | Der Befehl formatierte 28 Dateien und veraenderte 19. Die automatisch erzeugten Aenderungen wurden verworfen, da T003 keinen Anwendungscode veraendern darf; die Ausgabe zeigt vorhandene Formatabweichungen nicht als stabilen Check an |
| Analyse | `docker compose run --rm flutter flutter analyze` | 1 | 196 Issues, darunter Fehler in `lib/app.dart:190` (`CupertinoPageTransitionsBuilder` undefiniert) und Warnungen/Deprecations |
| Tests | `docker compose run --rm flutter flutter test` | 0 | Nur `test/widget_test.dart` mit einem Placeholder-Test; 1 Test bestanden |
| Android Debug APK | `docker compose run --rm flutter flutter build apk --debug` | 1 | `Build failed due to use of deleted Android v1 embedding.` |

Der Testlauf wurde direkt wiederholt:

```text
docker compose run --rm flutter flutter test  -> Exit 0
docker compose run --rm flutter flutter build apk --debug -> Exit 1
```

Damit sind ein erfolgreicher und ein fehlgeschlagener Baseline-Befehl
reproduziert.

## Beobachtete Architektur

- `lib/services/bluetooth_service.dart` kapselt Scan, Connect, Service-/Characteristic-Erkennung und BLE-Schreiben.
- `lib/services/protocol_service.dart` erzeugt 8-Byte-Schreibpakete, Systemkommandos und einfache ACK-Pruefung.
- `lib/utils/crc_calculator.dart` und `lib/utils/packet_parser.dart` bilden CRC und Paketdecodierung ab.
- `lib/providers/` verbindet BLE, Controllerzustand, Tuning und Fahrstatistik mit Riverpod.
- `lib/services/storage_service.dart` speichert Settings, Stock-Backup, Profile und die letzten 50 Sessions lokal.
- `lib/screens/` enthaelt Connection, Dashboard, Tuning, Stats, Debug und Settings; die UI ist bereits dunkel, aber weiterhin BikeTunes-benannt.
- Die einzige versionierte Anwendungstestdatei ist `test/widget_test.dart`; fachliche Unit-, Widget-, Golden-, Integrations- und Android-Tests fehlen.

## Bekannte Defekte und Risiken

- `android/app/build.gradle` und `android/app/build.gradle.kts` existieren
  parallel und tragen unterschiedliche, kollidierende Konfigurationen.
- Beide Android-Konfigurationen verwenden noch die Application-ID und den
  Namespace `com.biketunes.biketunes`; die Umbenennung ist T006.
- Der APK-Build scheitert am entfernten Android-V1-Embedding und ist T005
  zugeordnet.
- `flutter analyze` scheitert an einer undefinierten
  `CupertinoPageTransitionsBuilder`-Verwendung sowie mehreren ungenutzten
  Imports; Deprecated-APIs und Formatprobleme sind ebenfalls vorhanden. Dies
  wird in T007/T008 behoben.
- Die Anwendung hat BLE-Telemetrie, Parameter-Schreiben und Stock-Restore,
  aber deren Sicherheitslogik ist noch nicht fail-closed: unbekannter Zustand,
  fehlende Vollstaendigkeit des Backups, ACK-/Read-back-Abgleich und
  Write-Serialisierung sind nicht als zentrale Gates implementiert.
- Es gibt keinen Android-Foreground-Service, keinen MacroDroid-Vertrag und
  keine Runtime-Permission-/Lifecycle-Matrix.
- GPS-basierte Geschwindigkeit und Reichweitenlernen fehlen; die bestehende
  Geschwindigkeit basiert auf Controllerdaten.
- Das Backup ist ein unversionierter Shared-Preferences-JSON-Wert ohne
  Controlleridentitaet, atomaren Dateischreibpfad oder Vollstaendigkeitsbeleg.
- `reference/upstream/Biketunes/` liegt innerhalb des Arbeitsbaums. Die Analyse
  erfasst deshalb auch dessen Dart-Dateien und meldet die gleichen historischen
  Probleme; die Upstream-Referenz wird nicht als Anwendungscode behandelt.
- Reale Controller-Fixtures, HEB-Daten, Stromlimits und rechtsverbindliche
  Street-Legal-Werte fehlen. Reale Writes bleiben gemaess
  `plan/hardwareprofil.md` blockiert.

## Baseline-Abgrenzung

T003 hat keinen Anwendungscode und keine Abhaengigkeiten veraendert. Die
Formatierungsausgabe wurde nach der Messung zurueckgenommen. Die dokumentierten
Fehler werden den nachfolgenden Tasks zugeordnet:

- Toolchain/Android-Build: T004-T005 und T008
- Umbenennung und Lints: T006-T007
- Protokoll- und Write-Sicherheit: T009-T016 sowie T030-T036
- Backup: T024-T029
- Background/GPS: T046-T056 und T061-T069
- Testabdeckung und Release: T076-T083

## T008 Gruene Baseline

Stand: `2026-08-02`
Die Placeholder-Pruefung wurde durch vier hardwarefreie Tests in
`test/widget_test.dart` ersetzt: App-Start auf Dashboard, CRC-Erfolg und
-Mutation, Paketparser mit Kurzpaketfehler sowie zentrale Einheiten-/Grenzwert-
Konvertierungen. Die aktuelle Docker-Pruefkette ist gruen:

```text
docker compose run --rm flutter dart format --set-exit-if-changed lib test -> 0
docker compose run --rm flutter flutter analyze --no-fatal-infos -> 0
docker compose run --rm flutter flutter test -> 0 (4 Tests)
docker compose run --rm flutter flutter build apk --debug -> 0
```

Der Analyzer meldet weiterhin 111 `info`-Hinweise aus dem bestehenden UI-Code;
mit `--no-fatal-infos` sind sie sichtbar, blockieren aber den Baseline-Check
nicht. Upstream-Dart-Code wird ueber `analysis_options.yaml` ausgeschlossen.
Der Host dieses Baseline-Laufs stellt `make` nicht bereit; die Makefile-Targets
entsprechen den oben ausgefuehrten Docker-Kommandos und werden in einer CI mit
GNU Make aufgerufen.
