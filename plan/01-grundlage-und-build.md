# Phase 1: Grundlage und Build

## Phasenziel

ArcDash besitzt eine reproduzierbare, analysierbare und testbare Android-Basis.
Funktionale Erweiterungen beginnen erst, wenn der Build nicht mehr von
zufaelligen lokalen Toolversionen oder widerspruechlichen Gradle-Dateien abhaengt.

## T004 - Toolchain reproduzierbar festlegen

**Abhaengigkeiten:** T003  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Leite aus `pubspec.lock` und Flutter-Kompatibilitaet einen konkreten
  Flutter-/Dart-Stand ab und pinne das Docker-Image auf eine feste Version.
- Gleiche SDK-Constraints, README, Dockerfile und Conductor Tech Stack ab.
- Dokumentiere Aktualisierungsverfahren und Cache-Neuaufbau.

### Tests und Akzeptanz

- Ein frischer Container meldet die dokumentierten Flutter-, Dart-, Java- und
  Android-SDK-Versionen.
- Zweimaliges `flutter pub get` veraendert `pubspec.lock` nicht.
- Docker-Build und `flutter doctor -v` laufen nicht-interaktiv.

## T005 - Android-Gradle-Konfiguration reparieren

**Abhaengigkeiten:** T004  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Entscheide dich fuer genau eine Gradle-DSL und entferne nur die konkurrierende
  Projektdatei.
- Stelle Plugin-Anwendung, Namespace, min/target/compile SDK, Java/Kotlin 17 und
  Flutter-Integration konsistent her.
- Stelle einen funktionierenden Gradle Wrapper bereit und korrigiere dessen
  Ignore-Regeln.
- Release-Signing bleibt in diesem Task ausdruecklich unkonfiguriert, darf aber
  nicht irrefuehrend als produktiv dokumentiert sein.

### Tests und Akzeptanz

- `flutter build apk --debug` ist im frischen Container erfolgreich.
- `./android/gradlew --version` funktioniert reproduzierbar.
- Es existiert nur eine aktive `android/app/build.gradle*`-Datei.
- Ein Test oder Skript prueft die erwartete Android-Konfiguration, soweit
  sinnvoll automatisierbar.

## T006 - Projekt zu ArcDash umbenennen

**Abhaengigkeiten:** T005, bestaetigte Angaben aus T002  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Benenne Dart-Paket, Imports, Android Application-ID/Namespace, MainActivity,
  App-Label und Exportdateinamen konsistent zu ArcDash um.
- Aktualisiere sichtbare BikeTunes-Texte, README und Plattformmetadaten.
- Ersetze App-Icon und Splash nur durch vorhandene freigegebene Assets; falls
  keine Assets existieren, dokumentiere den Design-Blocker statt Platzhalter zu
  erfinden.

### Tests und Akzeptanz

- Suche nach `biketunes` und `BikeTunes` liefert nur absichtlich dokumentierte
  Herkunftshinweise.
- Dart-Analyse, Tests und Debug-APK-Build bestehen.
- Android startet `MainActivity` unter dem neuen Namespace.

## T007 - Abhaengigkeiten und Lints bereinigen

**Abhaengigkeiten:** T006  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Ermittle tatsaechlich verwendete Pakete und entferne ungenutzte Codegen- oder
  Lint-Abhaengigkeiten, sofern fuer die Zielarchitektur kein konkreter Einsatz
  geplant ist.
- Alternativ richte Riverpod-Codegen und `riverpod_lint` vollstaendig ein, wenn
  dies vorab im Tech Stack begruendet wurde.
- Aktiviere sinnvolle projektweite Lints ohne den Bestand durch pauschale
  Ignore-Regeln stummzuschalten.

### Tests und Akzeptanz

- `flutter pub get`, Format-Check, Analyse und Tests sind erfolgreich.
- Keine deklarierte direkte Abhaengigkeit ist ohne nachvollziehbaren Einsatz.
- Der dokumentierte Codegen-Befehl entspricht dem tatsaechlichen Projekt.

## T008 - Build- und Test-Baseline stabilisieren

**Abhaengigkeiten:** T007  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Ersetze den Platzhaltertest durch minimale Smoke-Tests fuer App-Start,
  Navigation und vorhandene Kernutilities.
- Behebe Baseline-Analyse- und Formatfehler ohne funktionale Neuentwicklung.
- Erweitere Makefile-Kommandos nur dort, wo sie fuer reproduzierbare Checks
  fehlen.

### Tests und Akzeptanz

- `make check` und `make build-apk` sind erfolgreich.
- Kein Test besteht nur aus `expect(true, isTrue)`.
- Der Testlauf benoetigt weder BLE-Hardware noch Netzwerkzugriff.
- `plan/baseline.md` enthaelt einen datierten Nachtrag mit der gruenen Baseline.

## Phasen-Gate

Ein frischer Checkout kann mit den dokumentierten Docker-Kommandos formatiert,
analysiert, getestet und als Debug-APK gebaut werden.
