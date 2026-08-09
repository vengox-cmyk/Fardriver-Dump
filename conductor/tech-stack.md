# Tech Stack

## Platform & Framework

- **Dart 3.12.0** (SDK constraint `>=3.10.3 <4.0.0` from `pubspec.lock`) — primary programming language.
- **Flutter 3.44.0** (`ghcr.io/cirruslabs/flutter:stable@sha256:46691e311715845de03a3ba4753a475476936805b29431b1f00f1816981033f8`) — UI framework. **Primär Android** (iOS nur Nice-to-have); weitere Desktop-Targets (macOS, Windows, Linux) vorhanden, aber sekundär.

## State Management

- **flutter_riverpod** — reactive state management.

## Bluetooth

- **flutter_blue_plus** — BLE communication with the FarDriver dongle (BLE UART service `0000FFE0-...`, characteristic `0000FFE1-...`).

## Background & Platform Integration

- **Android Foreground Service** (`connectedDevice`-Typ) — stabiler BLE-Hintergrundbetrieb mit persistenter Benachrichtigung.
- **MacroDroid-Integration** — Empfang eines Intents/Deep-Links (Volume-Down-Doppelklick) zum Auslösen von Profilwechseln im Hintergrund, ohne dass der Bildschirm angeht.
- **permission_handler** — runtime permissions (Bluetooth, Standort für BLE-Scan).

### Foreground-Service-Architektur T046

Der native Android-Foreground-Service besitzt genau eine `ControllerSession` und
ist die einzige Instanz mit langlebigem BLE-Lifecycle. Flutter bleibt Beobachter
und sendet nur versionierte, validierte Kommandos über eine Method-/Event-Bridge;
die Write-Engine und ihr Lock bleiben auch im Service verpflichtend. Start und
Stop erfolgen nur durch sichtbare Nutzeraktion oder den später dokumentierten,
eng begrenzten Street-Legal-Vertrag. Activity-Neustarts erzeugen keine zweite
GATT-Verbindung; der Service veröffentlicht den aktuellen Zustand erneut.

Nach Process Death wird kein automatischer Write gestartet. Der Service beendet
BLE-Ressourcen, verwirft aktive Transaktionen und darf erst nach einer neuen
Safety-/Identity-/Snapshot-Prüfung reconnecten. WorkManager wird nicht für eine
dauerhafte BLE-Session verwendet. Android 12-14, Notification-Recht ab Android
13 sowie OEM-Battery-Saver-Einschränkungen werden als explizite Lifecycle-Zustände
behandelt, nicht als Erfolgsannahmen.

## Storage & Persistence

- **shared_preferences** — lightweight key/value settings storage.
- **path_provider** — platform file-system directories (Profil-Export/Import, Backups).
- **JSON** — Profil-Format für Export/Import.

### Persistenzentscheidung T024

Settings bleiben in `shared_preferences`. Wachsende strukturierte Daten (Profile,
Snapshots, Sessions und Lernzustand) werden zunächst als versionierte JSON-
Dokumente über einen Repository-Vertrag gespeichert. Der Dateischreiber legt
zuerst eine temporäre Datei an und ersetzt das Zieldokument erst nach
erfolgreichem Schreiben. So bleibt ein abgebrochener Schreibvorgang unsichtbar.

SQLite/Drift und Hive wurden als Alternativen bewertet: SQLite/Drift bietet
Transaktionen und Abfragen, würde aber eine zusätzliche Android-/Migrations-
Abhängigkeit einführen; Hive ist leichtgewichtig, hat aber für die geplante
Backup-Integrität weniger passende Standardsemantik. Die aktuelle Dateilösung
passt zur kleinen V1-Datenmenge und hält den Repository-Vertrag unabhängig von
der späteren Speicherengine. Ein Wechsel auf SQLite/Drift erfolgt, wenn
Abfragen, Datengröße oder konkurrierende Schreibvorgänge die JSON-Dokumente
überfordern; dann wird jede Dokumentversion über eine explizite Migration
angehoben. Unbekannte Versionen werden nie stillschweigend geladen.

## Telemetry & Range Prediction

- **fl_chart** — Telemetrie-Visualisierungen.
- **Coulomb Counting** — Integration von Spannung × Strom für die Reichweitenprognose.
- **Komplementärfilter** — mit spannungsbasiertem SOC.
- **GPS** — Distanzmessung für gleitendes Verbrauchsfenster (Wh/km).
- **csv** — Datenexport (Session-Statistiken).

## Future Navigation (Version 2+)

- **flutter_map** — Karten-Anzeige (kostenlos, OpenStreetMap-basiert).
- **Kostenlose Routing-Engine** (GraphHopper / Valhalla / OSRM) — keine bezahlten APIs.

## Utilities

- **intl** (`^0.20.2`, durch Flutter-Lokalisierung vorgegeben) — Datums-/Zahlenformatierung.
- **google_fonts** — Font-Theming.

## Testing & Linting

- **flutter_test** — Unit-/Widget-Testing.
- **flutter_lints** — default lint rules.
- Provider werden bewusst ohne Codegen und Annotationen implementiert.

## Build & Test Environment

All build processes, tests, and linting run **exclusively inside Docker containers**. No local Dart/Flutter dependencies are installed on the host.

- **Dockerfile** — base image `ghcr.io/cirruslabs/flutter:stable` (includes Flutter SDK, Android SDK, Java). Disables analytics and treats the mounted repo as a trusted git worktree.
- **docker-compose.yml** — single `flutter` service mounting the project into `/app`, with persistent volumes for the Dart package cache (`flutter_pub_cache`) and the Gradle cache (`gradle_cache`).
- **Makefile** — convenience targets that wrap `docker compose run --rm flutter ...`.

The toolchain is intentionally pinned to the image digest above. To update it,
run `docker compose build --pull`, record the new digest and the output of
`flutter --version`, `dart --version`, `java -version` and
`flutter doctor -v` in `plan/baseline.md`, then run `flutter pub get` twice and
confirm that `pubspec.lock` is unchanged. To rebuild caches, remove only the
named `flutter_pub_cache` and `gradle_cache` Docker volumes before rebuilding;
never delete project source or lockfiles.

Standard commands:

```bash
docker compose build                                    # build the image
docker compose run --rm flutter flutter pub get         # install dependencies
# No code generation is currently used; providers are explicit Dart values.
docker compose run --rm flutter flutter analyze --no-fatal-infos # lint / static analysis
docker compose run --rm flutter flutter test            # run tests
docker compose run --rm flutter flutter test --coverage # coverage report
docker compose run --rm flutter flutter build apk       # build Android APK
docker compose run --rm flutter flutter build linux     # build Linux desktop
```

Equivalent Make targets: `make build`, `make pub-get`, `make analyze`, `make test`, `make coverage`, `make build-apk`, `make build-linux`, `make check`.

## Architecture

Single Flutter application (fork of Biketunes) with a strict separation: **BLE/Protocol Layer ↔ State Management ↔ UI**.

- `lib/models/` — domain models (controller state, ride stats, tuning profiles).
- `lib/providers/` — Riverpod providers (Bluetooth, controller state, tuning, stats).
- `lib/services/` — services (Bluetooth, FarDriver protocol, storage, background/profile).
- `lib/screens/` — UI screens (connection, dashboard, tuning, stats, debug, settings).
- `lib/widgets/` — reusable widgets (gauges, indicators, tiles, cards).
- `lib/utils/` — helpers (CRC calculator, packet parser, unit converter).

Bestehendes Protokoll-Handling, BLE-Kommunikation, Parameter-Schreiben und Backup-System von Biketunes werden als Fundament wiederverwendet und nur abgesichert/erweitert.
