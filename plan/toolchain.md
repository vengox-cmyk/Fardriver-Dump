# ArcDash Reproduzierbare Toolchain

Stand: `2026-08-02`  
Container: `ghcr.io/cirruslabs/flutter:stable@sha256:46691e311715845de03a3ba4753a475476936805b29431b1f00f1816981033f8`

## Festgelegte Versionen

| Werkzeug | Version / Quelle |
|---|---|
| Flutter | 3.44.0, revision `559ffa3f75` |
| Dart | 3.12.0, SDK constraint `>=3.10.3 <4.0.0` |
| Java | Container-Version, bei jedem Toolchain-Update mit `java -version` erfassen |
| Android SDK | Container-Version, bei jedem Toolchain-Update mit `flutter doctor -v` erfassen |
| Dependency-Aufloesung | `pubspec.lock` committed; zweimal `flutter pub get` muss ohne Diff bleiben |

Die Java- und Android-SDK-Versionen werden nicht aus Host-Installationen
uebernommen. Sie sind Bestandteil des Digest-gepinnten Containers und muessen
bei jeder Digest-Aenderung neu in diesem Dokument und in `plan/baseline.md`
aufgezeichnet werden.

## Standardpruefung

```bash
docker compose build
docker compose run --rm flutter flutter --version
docker compose run --rm flutter dart --version
docker compose run --rm flutter java -version
docker compose run --rm flutter flutter doctor -v
docker compose run --rm flutter flutter pub get
docker compose run --rm flutter flutter pub get
git diff --exit-code -- pubspec.lock
```

Alle Befehle sind nicht-interaktiv. Der zweite `pub get` darf keine Aenderung
an `pubspec.lock` erzeugen. Bei einer absichtlichen Toolchain-Aktualisierung
werden Cache-Neuaufbau, neue Versionen, Lockfile-Diff und alle Build-/Test-Gates
als eigener Task dokumentiert.

## Cache-Neuaufbau

1. `docker compose down` ausfuehren.
2. Nur die benannten Volumes `arcdash_flutter_pub_cache` und
   `arcdash_gradle_cache` entfernen, sofern sie tatsaechlich so benannt sind.
3. `docker compose build --pull` ausfuehren.
4. `flutter pub get` zweimal ausfuehren und `pubspec.lock` pruefen.
5. `flutter doctor -v`, Analyse, Tests und APK-Build wiederholen.

Projektdateien, Lockfiles und unbekannte Docker-Volumes werden nicht geloescht.
