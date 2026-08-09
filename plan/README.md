# ArcDash Entwicklungsroadmap

Diese Datei ist die zentrale Source of Truth fuer die Entwicklung von ArcDash.
Die Tasks werden grundsaetzlich in der angegebenen Reihenfolge bearbeitet. Die
zugehoerigen Phasendateien enthalten Umfang, Tests und Akzeptanzkriterien.

## Status

- `[ ]` offen
- `[~]` in Arbeit
- `[x]` abgeschlossen
- `[!]` blockiert

Vor dem Beginn eines Tasks wird ausschliesslich sein Status in dieser Datei auf
`[~]` gesetzt. Nach erfolgreicher Abnahme wird er auf `[x]` gesetzt und um den
kurzen Commit-SHA ergaenzt, sofern fuer den Auftrag ein Commit erstellt wurde.

## Verbindliche Regeln

- [Ausfuehrungsregeln](./00-ausfuehrungsregeln.md)
- Anforderungen: [`reference/ziel.md`](../reference/ziel.md)
- Upstream-Referenzrepos: [`reference/upstream/`](../reference/upstream/)
- Produktkontext: [`conductor/product.md`](../conductor/product.md)
- Produktgestaltung: [`conductor/product-guidelines.md`](../conductor/product-guidelines.md)
- Technik: [`conductor/tech-stack.md`](../conductor/tech-stack.md)
- Workflow: [`conductor/workflow.md`](../conductor/workflow.md)

## Phase 0: Projektsteuerung [checkpoint: b02f99d]

- [x] **T001** Anforderungs-Traceability erstellen (`5b739c5`) ([Details](./00-ausfuehrungsregeln.md#t001---anforderungs-traceability-erstellen))
- [x] **T002** Hardware- und Produktentscheidungen erfassen (`ec2db1c`) ([Details](./00-ausfuehrungsregeln.md#t002---hardware--und-produktentscheidungen-erfassen))
- [x] **T003** Reproduzierbaren Ist-Zustand dokumentieren (`87a0202`) ([Details](./00-ausfuehrungsregeln.md#t003---reproduzierbaren-ist-zustand-dokumentieren))

## Phase 1: Grundlage und Build [checkpoint: 9531be3]

- [x] **T004** Flutter-, Dart-, Docker- und Android-Versionen festlegen (`8aad3e5`) ([Details](./01-grundlage-und-build.md#t004---toolchain-reproduzierbar-festlegen))
- [x] **T005** Android-Gradle-Konfiguration reparieren (`b1be29e`) ([Details](./01-grundlage-und-build.md#t005---android-gradle-konfiguration-reparieren))
- [x] **T006** BikeTunes vollstaendig zu ArcDash umbenennen (`496858f`) ([Details](./01-grundlage-und-build.md#t006---projekt-zu-arcdash-umbenennen))
- [x] **T007** Abhaengigkeiten und Lints bereinigen (`251b0f2`) ([Details](./01-grundlage-und-build.md#t007---abhaengigkeiten-und-lints-bereinigen))
- [x] **T008** Build- und Test-Baseline stabilisieren (`0e4b1a6`) ([Details](./01-grundlage-und-build.md#t008---build--und-test-baseline-stabilisieren))

## Phase 1.5: Sichere Schreibengine (zurueckgestellt)

Diese optionale Phase wird erst nach der Read-only-Version aktiviert. Bis dahin
werden keine Write-Features, Write-Abnahmen oder hardwareabhängigen Write-Tests
bearbeitet. Die vorhandenen Safety-Modelle bleiben als fail-closed Grundlagen
erhalten.

- [!] **T030** Parameterkatalog und Hardwaregrenzen erstellen (ZURUECKGESTELLT: finale Controller-, Motor-, Batterie- und BMS-Grenzen fehlen) ([Details](./05-sichere-schreibengine.md#t030---parameterkatalog-und-hardwaregrenzen-erstellen))
- [!] **T031** Fail-closed Safety-Evaluator bauen (ZURUECKGESTELLT: Write-Track nicht aktiv) ([Details](./05-sichere-schreibengine.md#t031---fail-closed-safety-evaluator-bauen))
- [!] **T032** Optionales Schreiben beim Ausrollen modellieren (ZURUECKGESTELLT: Hardware-Freigabe fehlt) ([Details](./05-sichere-schreibengine.md#t032---optionales-schreiben-beim-ausrollen-modellieren))
- [!] **T033** Diff und Read-modify-write implementieren (ZURUECKGESTELLT: Write-Track nicht aktiv) ([Details](./05-sichere-schreibengine.md#t033---diff-und-read-modify-write-implementieren))
- [!] **T034** Transaktionales Schreiben mit Read-back bauen (ZURUECKGESTELLT: reale ACK-/Read-back-Abnahme fehlt) ([Details](./05-sichere-schreibengine.md#t034---transaktionales-schreiben-mit-read-back-bauen))
- [!] **T035** Teilfehler und Rollback behandeln (ZURUECKGESTELLT: reale verifizierte Rollback-Parameter fehlen) ([Details](./05-sichere-schreibengine.md#t035---teilfehler-und-rollback-behandeln))
- [!] **T036** Write-Lock, Idempotenz und Audit-Log ergaenzen (ZURUECKGESTELLT: Write-Track nicht aktiv) ([Details](./05-sichere-schreibengine.md#t036---write-lock-idempotenz-und-audit-log-ergaenzen))
- [!] **T037** Safety-UX und Hardware-Testplan fertigstellen (ZURUECKGESTELLT: Read-only-Version zuerst) ([Details](./05-sichere-schreibengine.md#t037---safety-ux-und-hardware-testplan-fertigstellen))

## Phase 2: Protokoll und Parameter

- [x] **T009** Protokoll-Belegmatrix erstellen (`e41a7d1`) ([Details](./02-protokoll-und-parameter.md#t009---protokoll-belegmatrix-erstellen))
- [x] **T010** BLE-Captures und Paket-Fixtures definieren (`0ad9ecf`) ([Details](./02-protokoll-und-parameter.md#t010---ble-captures-und-paket-fixtures-definieren))
- [x] **T011** CRC durch Golden-Tests absichern (`9434f27`) ([Details](./02-protokoll-und-parameter.md#t011---crc-durch-golden-tests-absichern))
- [x] **T012** Fragmentierungsfesten Paket-Framer bauen (`6a95ff0`) ([Details](./02-protokoll-und-parameter.md#t012---fragmentierungsfesten-paket-framer-bauen))
- [x] **T013** FarDriver-Speichermodell abbilden (`e550cf7`) ([Details](./02-protokoll-und-parameter.md#t013---fardriver-speichermodell-abbilden))
- [x] **T014** Telemetrie-, Fehler- und Safety-Register decodieren (`981f044`) ([Details](./02-protokoll-und-parameter.md#t014---telemetrie--fehler--und-safety-register-decodieren))
- [x] **T015** Parameter-Snapshots aus dem Datenstrom aufbauen (`fb080b1`) ([Details](./02-protokoll-und-parameter.md#t015---parameter-snapshots-aus-dem-datenstrom-aufbauen))
- [!] **T016** Schreibprotokoll, ACK und HEB validieren (BLOCKIERT: freigegebene Controller-Fixture, HEB und Read-back fehlen) ([Details](./02-protokoll-und-parameter.md#t016---schreibprotokoll-ack-und-heb-validieren))

## Phase 3: BLE und Controller-Session

- [x] **T017** Testbare Transport-Schnittstelle einfuehren (`746623d`) ([Details](./03-ble-und-controller-session.md#t017---testbare-transport-schnittstelle-einfuehren))
- [x] **T018** Zustandsbehaftete Controller-Session bauen (`8be4515`) ([Details](./03-ble-und-controller-session.md#t018---zustandsbehaftete-controller-session-bauen))
- [x] **T019** Android-Runtime-Permissions implementieren (`dbc21d5`) ([Details](./03-ble-und-controller-session.md#t019---android-runtime-permissions-implementieren))
- [x] **T020** Scan, Pairing und Service-Erkennung haerten (`164dbd4`) ([Details](./03-ble-und-controller-session.md#t020---scan-pairing-und-service-erkennung-haerten))
- [x] **T021** Automatisches Wiederverbinden implementieren (`b8ef6d7`) ([Details](./03-ble-und-controller-session.md#t021---automatisches-wiederverbinden-implementieren))
- [x] **T022** Command-Queue und Protokollzugriff serialisieren (`ab63b52`) ([Details](./03-ble-und-controller-session.md#t022---command-queue-und-protokollzugriff-serialisieren))
- [x] **T023** Diagnose-Logging und Export ergaenzen (`8fea1a8`) ([Details](./03-ble-und-controller-session.md#t023---diagnose-logging-und-export-ergaenzen))

## Phase 4: Backup und Snapshots

- [x] **T024** Versionierte Persistenzarchitektur festlegen (`635f11e`) ([Details](./04-backup-und-snapshots.md#t024---versionierte-persistenzarchitektur-festlegen))
- [x] **T025** Controller-Identitaet und Kompatibilitaet erfassen (`f1d8c46`) ([Details](./04-backup-und-snapshots.md#t025---controller-identitaet-und-kompatibilitaet-erfassen))
- [x] **T026** Vollstaendige Parametersnapshots atomar speichern (`f30b3d2`) ([Details](./04-backup-und-snapshots.md#t026---vollstaendige-parametersnapshots-atomar-speichern))
- [!] **T027** Verlaessliches Stock-Backup erzeugen (BLOCKIERT: Hardware-Abnahme und verifiziertes Stock-Read-back fehlen) ([Details](./04-backup-und-snapshots.md#t027---verlaessliches-stock-backup-erzeugen))
- [x] **T028** Backup-Import und -Export implementieren (`7872fba`) ([Details](./04-backup-und-snapshots.md#t028---backup-import-und--export-implementieren))
- [x] **T029** Sicheren Restore-Ablauf vorbereiten (`8f27871`) ([Details](./04-backup-und-snapshots.md#t029---sicheren-restore-ablauf-vorbereiten))

## Phase 5: Profilsystem

- [x] **T038** Versioniertes Profilmodell implementieren (`54de30a`) ([Details](./06-profilsystem.md#t038---versioniertes-profilmodell-implementieren))
- [!] **T039** Integrierte Profile definieren (BLOCKIERT: verifiziertes Stock-Backup und Hardwaregrenzen fehlen) ([Details](./06-profilsystem.md#t039---integrierte-profile-definieren))
- [x] **T040** Profilverwaltung implementieren (`c1239ca`) ([Details](./06-profilsystem.md#t040---profilverwaltung-implementieren))
- [!] **T041** Sicheren Profileditor bauen (BLOCKIERT: kein Parameter mit bestaetigten Schreibgrenzen freigegeben) ([Details](./06-profilsystem.md#t041---sicheren-profileditor-bauen))
- [x] **T042** Profil-Diff und Kompatibilitaet anzeigen (`03aae75`) ([Details](./06-profilsystem.md#t042---profil-diff-und-kompatibilitaet-anzeigen))
- [x] **T043** JSON-Import und -Export implementieren (`03aae75`) ([Details](./06-profilsystem.md#t043---json-import-und--export-implementieren))
- [!] **T044** Profile verifiziert anwenden (WRITE-ABHAENGIG: fuer Read-only-V1 uebersprungen) ([Details](./06-profilsystem.md#t044---profile-verifiziert-anwenden))
- [!] **T045** Street-Legal-Fast-Path optimieren (WRITE-ABHAENGIG: fuer Read-only-V1 uebersprungen) ([Details](./06-profilsystem.md#t045---street-legal-fast-path-optimieren))

## Phase 6: Android-Hintergrundbetrieb

- [x] **T046** Foreground-Service-Architektur festlegen (`95ef4ea`) ([Details](./07-android-hintergrundbetrieb.md#t046---foreground-service-architektur-festlegen))
- [!] **T047** Android-Service und Berechtigungen konfigurieren (BLOCKIERT: Android-12-bis-14-Geräteabnahme fehlt; Code und APK-Build vorbereitet) ([Details](./07-android-hintergrundbetrieb.md#t047---android-service-und-berechtigungen-konfigurieren))
- [ ] **T048** BLE-Session in den Service integrieren ([Details](./07-android-hintergrundbetrieb.md#t048---ble-session-in-den-service-integrieren))
- [!] **T049** Native Flutter-Kommandobruecke bauen (BLOCKIERT: T048 und T047 fehlen) ([Details](./07-android-hintergrundbetrieb.md#t049---native-flutter-kommandobruecke-bauen))
- [!] **T050** Sicheren MacroDroid-Vertrag definieren (BLOCKIERT: T049 fehlt) ([Details](./07-android-hintergrundbetrieb.md#t050---sicheren-macrodroid-vertrag-definieren))
- [!] **T051** Street Legal bei ausgeschaltetem Bildschirm anwenden (WRITE-ABHAENGIG: fuer Read-only-V1 uebersprungen) ([Details](./07-android-hintergrundbetrieb.md#t051---street-legal-bei-ausgeschaltetem-bildschirm-anwenden))
- [!] **T052** Hintergrund-Feedback implementieren (WRITE-ABHAENGIG: fuer Read-only-V1 uebersprungen) ([Details](./07-android-hintergrundbetrieb.md#t052---hintergrund-feedback-implementieren))
- [!] **T053** Android-Lifecycle-Matrix validieren (WRITE-ABHAENGIG: fuer Read-only-V1 uebersprungen) ([Details](./07-android-hintergrundbetrieb.md#t053---android-lifecycle-matrix-validieren))

## Phase 7: Dashboard und Telemetrie

- [x] **T054** App-Shell, Designsystem, Navigation und Lokalisierung neu aufbauen (`ff506b0`) ([Details](./08-dashboard-und-telemetrie.md#t054---app-shell-designsystem-navigation-und-lokalisierung-neu-aufbauen))
- [x] **T055** Telemetriequalitaet und Stale-State implementieren ([Details](./08-dashboard-und-telemetrie.md#t055---telemetriequalitaet-und-stale-state-implementieren))
- [!] **T056** GPS-Geschwindigkeit mit Fallback implementieren (BLOCKIERT: Android-Geräteabnahme mit Standortberechtigung fehlt; Simulation und Fallbacklogik getestet) ([Details](./08-dashboard-und-telemetrie.md#t056---gps-geschwindigkeit-mit-fallback-implementieren))
- [x] **T057** Versioniertes Dashboard-Layoutmodell und Persistenz bauen (`ccdaec8`) ([Details](./08-dashboard-und-telemetrie.md#t057---versioniertes-dashboard-layoutmodell-und-persistenz-bauen))
- [x] **T058** Dashboard-Renderer und konfigurierbare Werte von Grund auf bauen (`206091a`) ([Details](./08-dashboard-und-telemetrie.md#t058---dashboard-renderer-und-konfigurierbare-werte-von-grund-auf-bauen))
- [~] **T059** Dashboard-Editor fuer Hoch- und Querformat bauen ([Details](./08-dashboard-und-telemetrie.md#t059---dashboard-editor-fuer-hoch--und-querformat-bauen))
- [ ] **T060** Dashboard-Polish, Accessibility und Verbindungs-UX abschliessen ([Details](./08-dashboard-und-telemetrie.md#t060---dashboard-polish-accessibility-und-verbindungs-ux-abschliessen))

## Phase 8: Reichweitenprognose

- [x] **T061** Reichweiten-Domainmodell definieren (`a9b1ff8`) ([Details](./09-reichweitenprognose.md#t061---reichweiten-domainmodell-definieren))
- [x] **T062** GPS-Distanz filtern (`f2c07ce`) ([Details](./09-reichweitenprognose.md#t062---gps-distanz-filtern))
- [x] **T063** Energie und Ladung integrieren (`a9b1ff8`) ([Details](./09-reichweitenprognose.md#t063---energie-und-ladung-integrieren))
- [x] **T064** Spannungsbasierten SOC-Filter bauen (`b7be018`) ([Details](./09-reichweitenprognose.md#t064---spannungsbasierten-soc-filter-bauen))
- [x] **T065** Nutzbare Kapazitaet lernen (`b7be018`) ([Details](./09-reichweitenprognose.md#t065---nutzbare-kapazitaet-lernen))
- [x] **T066** Verbrauchsfenster und Fahrstil modellieren (`b7be018`) ([Details](./09-reichweitenprognose.md#t066---verbrauchsfenster-und-fahrstil-modellieren))
- [x] **T067** Unsicherheitsintervall berechnen (`b7be018`) ([Details](./09-reichweitenprognose.md#t067---unsicherheitsintervall-berechnen))
- [x] **T068** Lernzustand persistieren (`3e49604`) ([Details](./09-reichweitenprognose.md#t068---lernzustand-persistieren))
- [x] **T069** Simulation und Dashboard-Integration abschliessen (`aafc4ec`) ([Details](./09-reichweitenprognose.md#t069---simulation-und-dashboard-integration-abschliessen))

## Phase 9: Sessions, Fehler und Einstellungen

- [x] **T070** Serviceweiten Session-Lifecycle implementieren (`1f94641`) ([Details](./10-sessions-fehler-einstellungen.md#t070---serviceweiten-session-lifecycle-implementieren))
- [x] **T071** Sessionmetriken aggregieren (`d5f66f9`) ([Details](./10-sessions-fehler-einstellungen.md#t071---sessionmetriken-aggregieren))
- [x] **T072** Sessionhistorie persistieren (`72ccb54`) ([Details](./10-sessions-fehler-einstellungen.md#t072---sessionhistorie-persistieren))
- [x] **T073** Sessionexport und Sharing implementieren (`ee922aa`) ([Details](./10-sessions-fehler-einstellungen.md#t073---sessionexport-und-sharing-implementieren))
- [x] **T074** Fehlerkatalog und Fehlerhistorie bauen (`a061d29`) ([Details](./10-sessions-fehler-einstellungen.md#t074---fehlerkatalog-und-fehlerhistorie-bauen))
- [x] **T075** Einstellungen und Datenverwaltung konsolidieren (`85ab874`) ([Details](./10-sessions-fehler-einstellungen.md#t075---einstellungen-und-datenverwaltung-konsolidieren))

## Phase 10: Qualitaet und Release

- [x] **T076** Kernmodule auf mehr als 80 Prozent Coverage bringen (`f402a7b`) ([Details](./11-qualitaet-und-release.md#t076---kernmodule-auf-mehr-als-80-prozent-coverage-bringen))
- [x] **T077** Widget-, Golden- und Accessibility-Tests ergaenzen (`b48faf6`) ([Details](./11-qualitaet-und-release.md#t077---widget--golden--und-accessibility-tests-ergaenzen))
- [x] **T078** Kritische Flutter-Integrationstests erstellen (`d860695`) ([Details](./11-qualitaet-und-release.md#t078---kritische-flutter-integrationstests-erstellen))
- [!] **T079** Android-Instrumentationstests erstellen (BLOCKIERT: Android-Emulator/Gerät für Ausführung fehlt) ([Details](./11-qualitaet-und-release.md#t079---android-instrumentationstests-erstellen))
- [!] **T080** Hardware-in-the-loop-Matrix durchfuehren (BLOCKIERT: Reale Fardriver-Hardware & BLE-Verbindung fehlen) ([Details](./11-qualitaet-und-release.md#t080---hardware-in-the-loop-matrix-durchfuehren))
- [!] **T081** Performance und Akkuverbrauch pruefen (BLOCKIERT: Reale Hardware & Profiling-Umgebung fehlen) ([Details](./11-qualitaet-und-release.md#t081---performance-und-akkuverbrauch-pruefen))
- [x] **T082** Release-Sicherheit fertigstellen (`7a89b01`) ([Details](./11-qualitaet-und-release.md#t082---release-sicherheit-fertigstellen))
- [x] **T083** CI und Version-1-Abnahme einrichten (`7a89b01`) ([Details](./11-qualitaet-und-release.md#t083---ci-und-version-1-abnahme-einrichten))

## Phase 11: Version 2 vorbereiten

- [x] **T084** Navigation hinter stabilen Schnittstellen vorbereiten (`128c0e5`) ([Details](./12-version-2-vorbereitung.md#t084---navigation-hinter-stabilen-schnittstellen-vorbereiten))
- [x] **T085** Version-2-Backlog konkretisieren (`f62c15b`) ([Details](./12-version-2-vorbereitung.md#t085---version-2-backlog-konkretisieren))

## Phasen-Gates

Eine Phase ist erst abgeschlossen, wenn alle ihre Tasks abgeschlossen sind und
das Checkpointing-Protokoll aus `conductor/workflow.md` erfolgreich durchlaufen
wurde. Fuer sicherheitskritische Phasen gelten zusaetzlich diese Gates:

- Nach Phase 2 bleiben reale Schreibvorgaenge deaktiviert, solange keine echten
  Controller-Fixtures und bestaetigten Registerdefinitionen vorliegen.
- Nach Phase 4 darf nur ein vollstaendiges, identitaetsgebundenes Backup als
  Stock-Backup angeboten werden.
- Bei spaeterer Aktivierung von Phase 1.5 darf kein Write bei unbekanntem,
  veraltetem oder bewegtem Fahrzeugzustand moeglich sein.
- Nach Phase 5 gilt ein Profil erst nach erfolgreichem Read-back als aktiv.
- Nach Phase 6 muss der Street-Legal-Wechsel ohne sichtbare App und ohne
  Einschalten des Bildschirms funktionieren.
- Version 1 ist erst nach T083 abgeschlossen.
