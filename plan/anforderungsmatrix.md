# ArcDash Anforderungsmatrix

Diese Matrix ordnet jede Version-1-Anforderung aus
[`reference/ziel.md`](../reference/ziel.md) einem Umsetzungstask, einer
geplanten Abnahme und einer Zielphase zu. Ein `BLOCKIERT`-Hinweis beschreibt
eine fehlende Hardware- oder Rechtsgrundlage; er hebt die Anforderung nicht
auf und blockiert keine reine Simulation oder UI-Arbeit.

## Traceability

| ID | Anforderung und Quelle | Version | Kritisch | Task(s) | Geplanter Abnahmetest | Phase | Status / Hinweis |
|---|---|---:|:---:|---|---|---:|---|
| REQ-001 | Flutter-App fuer Arctic Leopard Xe Pro S mit FarDriver ([Ziel](../reference/ziel.md#1-projektübersicht)) | V1 | Nein | T004, T006, T008 | Toolchain-, Paket- und APK-Build | 1 | offen |
| REQ-002 | BLE-Service und Characteristic uebernehmen ([Ziel](../reference/ziel.md#2-was-aus-biketunes-übernommen-werden-soll)) | V1 | Ja | T009, T010, T017, T020 | Fake-Transport-Service- und Service-Erkennungstests | 2-3 | Hardware-Fixture erforderlich |
| REQ-003 | 16-Byte-Telemetrieframes und CRC ([Ziel](../reference/ziel.md#2-was-aus-biketunes-übernommen-werden-soll)) | V1 | Ja | T009-T012, T014 | CRC-Golden-, Fragmentierungs- und Decoder-Tests | 2 | Nur Rohdaten beweisen Registerbelegung |
| REQ-004 | Parameter schreiben, nur reverse-engineerte Adressen ([Ziel](../reference/ziel.md#2-was-aus-biketunes-übernommen-werden-soll)) | V1 | Ja | T013, T016, T030-T036 | Fake-Write-, ACK-, HEB-, Read-back- und Rollback-Tests | 2, 1.5 | Reale Writes bis bestaetigte Fixtures deaktiviert |
| REQ-005 | Motion-Lockout beim Schreiben ([Ziel](../reference/ziel.md#2-was-aus-biketunes-übernommen-werden-soll)) | V1 | Ja | T014, T031, T034 | Grenzwerttests fuer RPM, Gas und unbekannten Zustand | 2, 5 | fail-closed |
| REQ-006 | Stock-Backup und Restore ([Ziel](../reference/ziel.md#2-was-aus-biketunes-übernommen-werden-soll)) | V1 | Ja | T024-T029 | Atomaritaets-, Identitaets-, Import-/Export- und Restore-Tests | 4 | Vollstaendigkeit vor Angebot pruefen |
| REQ-007 | Ride-Mode-Presets als Ausgangspunkt ([Ziel](../reference/ziel.md#2-was-aus-biketunes-übernommen-werden-soll)) | V1 | Nein | T038-T045 | Profilmodell-, Diff-, Import-/Export- und Apply-Tests | 6 | Keine unbewiesenen Presetwerte |
| REQ-008 | Dashboard: Geschwindigkeit, bevorzugt GPS, RPM-Fallback ([Ziel](../reference/ziel.md#31-live-telemetrie-dashboard-hauptbildschirm)) | V1 | Nein | T054-T060 | Provider-, Fallback- und Widget-Tests | 8 | GPS-Datenquelle separat absichern |
| REQ-009 | Dashboard: Leistung in kW, Spannung, Strom, SOC ([Ziel](../reference/ziel.md#31-live-telemetrie-dashboard-hauptbildschirm)) | V1 | Nein | T014, T055, T057-T059 | Decoder- und Widget-Golden-Tests | 2, 8 | Unbekannte Werte nicht als sicher darstellen |
| REQ-010 | Dashboard: Reichweite mit Unsicherheit ([Ziel](../reference/ziel.md#31-live-telemetrie-dashboard-hauptbildschirm)) | V1 | Nein | T061-T069 | Domain-, Simulations- und Dashboard-Tests | 9 | Stale-/Unsicherheitszustand sichtbar |
| REQ-011 | Dashboard: Profil, Temperaturen, Rekuperation, DNR ([Ziel](../reference/ziel.md#31-live-telemetrie-dashboard-hauptbildschirm)) | V1 | Nein | T014, T055, T058 | Decoder-, State- und Widget-Tests | 2, 8 | Negativer Strom muss gruen markiert werden |
| REQ-012 | Halbkreis-Leistungsindikator ([Ziel](../reference/ziel.md#31-live-telemetrie-dashboard-hauptbildschirm)) | V1 | Nein | T054, T057 | Widget-Golden- und Accessibility-Tests | 8 | AMOLED und hoher Kontrast |
| REQ-013 | Handschuh- und Sonnenlicht-Bedienbarkeit ([Ziel](../reference/ziel.md#31-live-telemetrie-dashboard-hauptbildschirm)) | V1 | Nein | T054, T057, T059 | Widget-/Accessibility-Tests plus manuelle Android-Pruefung | 8 | Hardware-/Displaytest erforderlich |
| REQ-014 | Benannte Profile Stock, Street Legal, Offroad/Trail, Sport/Race, Eco ([Ziel](../reference/ziel.md#32-profil-system-sehr-wichtig)) | V1 | Ja | T038-T040 | Fixture fuer integrierte Profile und Verwaltung | 6 | Street-Legal-Werte `BLOCKIERT`, bis Zulassung bestaetigt |
| REQ-015 | Profile erstellen, umbenennen, loeschen, duplizieren ([Ziel](../reference/ziel.md#32-profil-system-sehr-wichtig)) | V1 | Nein | T040-T043 | CRUD- und Persistenztests | 6 | - |
| REQ-016 | Profil-Diff und gezieltes Schreiben ([Ziel](../reference/ziel.md#32-profil-system-sehr-wichtig)) | V1 | Ja | T033, T040-T044 | Diff-, Read-modify-write- und Read-back-Tests | 5-6 | Nur notwendige Parameter schreiben |
| REQ-017 | Profil-JSON-Import/-Export ([Ziel](../reference/ziel.md#32-profil-system-sehr-wichtig)) | V1 | Nein | T043 | Schema-, Roundtrip- und ungueltige JSON-Tests | 6 | Versioniertes Format |
| REQ-018 | Schneller, zuverlaessiger Street-Legal-Fast-Path ([Ziel](../reference/ziel.md#32-profil-system-sehr-wichtig)) | V1 | Ja | T045, T050-T052 | Minimal-Diff-, Queue- und Background-Integrationstest | 6-7 | Werte und Rechtslage `BLOCKIERT` |
| REQ-019 | Foreground-Service fuer stabilen Hintergrundbetrieb ([Ziel](../reference/ziel.md#33-hintergrundbetrieb--macrodroid-trigger-kritisch)) | V1 | Ja | T046-T049 | Android-Service- und Lifecycle-Instrumentationstest | 7 | Android-only |
| REQ-020 | MacroDroid Volume-Down-Doppelklick loest Intent aus ([Ziel](../reference/ziel.md#33-hintergrundbetrieb--macrodroid-trigger-kritisch)) | V1 | Ja | T050 | Intent-Vertrags- und Android-Integrationstest | 7 | Intent-Signatur muss stabil dokumentiert werden |
| REQ-021 | Street Legal im Hintergrund bei ausgeschaltetem Bildschirm anwenden ([Ziel](../reference/ziel.md#33-hintergrundbetrieb--macrodroid-trigger-kritisch)) | V1 | Ja | T048-T052 | Locked-screen Instrumentation-/HIL-Test | 7 | Hardware erforderlich |
| REQ-022 | Dezente Rueckmeldung per Vibration/Benachrichtigung ([Ziel](../reference/ziel.md#33-hintergrundbetrieb--macrodroid-trigger-kritisch)) | V1 | Nein | T052 | Notification-/Vibrations-Fake-Test und manuelle Pruefung | 7 | Bildschirm darf nicht aufwachen |
| REQ-023 | Schreiben nur bei Motorstillstand ([Ziel](../reference/ziel.md#34-sicherheitsregeln-beim-schreiben-von-parametern)) | V1 | Ja | T031, T034 | Safety-Evaluator Grenzwerttests | 5 | fail-closed |
| REQ-024 | Optional Schreiben beim Ausrollen mit Gas=0 ([Ziel](../reference/ziel.md#34-sicherheitsregeln-beim-schreiben-von-parametern)) | V1 | Ja | T031-T035 | Matrix fuer Option, Gas und RPM | 5 | Standard bleibt deaktiviert |
| REQ-025 | Harte Grenzen fuer MaxLineCurr/MaxPhaseCurr ([Ziel](../reference/ziel.md#34-sicherheitsregeln-beim-schreiben-von-parametern)) | V1 | Ja | T030-T032 | Boundary- und unbekannter-Hardware-Tests | 1.5 | Limits `BLOCKIERT`, bis Hardwareprofil bestaetigt |
| REQ-026 | Read-back nach jedem Schreiben ([Ziel](../reference/ziel.md#34-sicherheitsregeln-beim-schreiben-von-parametern)) | V1 | Ja | T016, T034-T036 | ACK-/Read-back-Mismatch- und Retry-Tests | 2, 5 | Kein Erfolg ohne Read-back |
| REQ-027 | Funktionierendes Stock-Backup vor kritischem Schreiben ([Ziel](../reference/ziel.md#34-sicherheitsregeln-beim-schreiben-von-parametern)) | V1 | Ja | T027, T029, T034 | Write-Gate mit fehlendem/alten Backup | 4-5 | - |
| REQ-028 | Coulomb Counting Spannung x Strom ([Ziel](../reference/ziel.md#35-selbstlernende-reichweitenprognose)) | V1 | Nein | T061, T063 | Zeitreihen- und Vorzeichen-Tests | 9 | - |
| REQ-029 | Komplementaerfilter mit spannungsbasiertem SOC ([Ziel](../reference/ziel.md#35-selbstlernende-reichweitenprognose)) | V1 | Nein | T061, T064 | Filter-Grenzwert- und Rauschtests | 9 | - |
| REQ-030 | Nutzbare Kapazitaet aus Lade-/Entladezyklen lernen ([Ziel](../reference/ziel.md#35-selbstlernende-reichweitenprognose)) | V1 | Nein | T063-T065, T068 | Zyklus- und Persistenztests | 9 | Qualitaetsstufe offen bis reale Fahrdaten vorliegen |
| REQ-031 | Gleitendes Wh/km-Fenster per GPS-Distanz ([Ziel](../reference/ziel.md#35-selbstlernende-reichweitenprognose)) | V1 | Nein | T062, T066 | GPS-Ausreisser-, Stillstands- und Fenster-Tests | 9 | GPS-Berechtigung beruecksichtigen |
| REQ-032 | Fahrstil-Anpassung und Unsicherheitsintervall ([Ziel](../reference/ziel.md#35-selbstlernende-reichweitenprognose)) | V1 | Nein | T066-T069 | Szenario-/Simulations- und UI-Tests | 9 | Unsicherheit bis Lernstand ehrlich anzeigen |
| REQ-033 | Session-Statistiken ([Ziel](../reference/ziel.md#36-weitere-version-1-features)) | V1 | Nein | T070-T073 | Aggregations-, Persistenz- und Exporttests | 10 | - |
| REQ-034 | Controller-Fehler anzeigen ([Ziel](../reference/ziel.md#36-weitere-version-1-features)) | V1 | Nein | T014, T074 | Fehlerregister- und Historientests | 2, 10 | Unbekannte Fehler als unbekannt markieren |
| REQ-035 | Einstellungen: Einheiten, Dark Mode, Safety ([Ziel](../reference/ziel.md#36-weitere-version-1-features)) | V1 | Nein | T059, T075 | Settings-Persistenz- und Widget-Tests | 8, 10 | Deutsch als Standard |
| REQ-036 | Automatisches Wiederverbinden ([Ziel](../reference/ziel.md#36-weitere-version-1-features)) | V1 | Ja | T018, T021, T022 | Zustandsautomat-, Backoff- und Queue-Tests | 3 | Kein Write bei unsicherem Zustand |
| REQ-037 | Trennung BLE/Protocol, State Management und UI ([Ziel](../reference/ziel.md#6-technische-leitplanken)) | V1 | Nein | T017-T018, T054, T070 | Architektur-/Provider-Tests und Analyse | 3, 8, 10 | - |
| REQ-038 | Defensive Programmierung beim Schreiben ([Ziel](../reference/ziel.md#6-technische-leitplanken)) | V1 | Ja | T030-T036 | Fuzz-/Fehlerpfad- und Coverage-Tests | 1.5 | - |
| REQ-039 | Deutsche, minimalistische AMOLED-Oberflaeche ([Ziel](../reference/ziel.md#5-uiux-richtlinien)) | V1 | Nein | T054, T057-T060 | Golden-, Accessibility- und manuelle Displaytests | 8 | Englisch optional |
| REQ-040 | Telemetrie, Profilwechsel, Backup, Safety und Reichweite in Version 1 fertig ([Ziel](../reference/ziel.md#7-entwicklungsreihenfolge-empfehlung)) | V1 | Ja | T008, T016, T029, T037, T045, T069, T083 | Release-Gate und kritische Integrationstests | 11 | - |
| REQ-041 | Dashboard von Grund auf neu; getrennte Hoch-/Querformatlayouts und frei waehlbare Werte ([Produktentscheidung](../conductor/product.md#core-features-version-1)) | V1 | Nein | T054, T057-T060 | Layoutmodell-, Persistenz-, Editor-, Orientierungs- und Golden-Tests | 8 | Alte Fork-Dashboard-UI wird nicht weiterverwendet |

## Version-2-Abgrenzung

| ID | Anforderung und Quelle | Version | Vorbereitung | Keine V1-Abhaengigkeit |
|---|---|---:|---|:---:|
| REQ-101 | Navigation mit realistischer Reichweite ([Ziel](../reference/ziel.md#4-spätere-features-version-2)) | V2 | T084-T085 | Ja |
| REQ-102 | Hoehenmeter in Verbrauchsprognose ([Ziel](../reference/ziel.md#4-spätere-features-version-2)) | V2 | T084-T085 | Ja |
| REQ-103 | End-SOC fuer geplante Route ([Ziel](../reference/ziel.md#4-spätere-features-version-2)) | V2 | T084-T085 | Ja |
| REQ-104 | Routing-Optionen fuer schnell, Trail und Nebenstrassen ([Ziel](../reference/ziel.md#4-spätere-features-version-2)) | V2 | T084-T085 | Ja |
| REQ-105 | Kostenfreie Karten-/Routing-Engine ([Ziel](../reference/ziel.md#4-spätere-features-version-2)) | V2 | T084-T085 | Ja |

## Abweichungen und offene Punkte

- Die Zielbeschreibung nennt reale Controllerwerte und Schreibadressen, liefert
  aber keine verifizierten Rohdaten fuer das konkrete Fahrzeug. Daher bleiben
  Register, Stromlimits und Street-Legal-Werte bis T002/T010 `BLOCKIERT`.
- Die Zielbeschreibung nennt Biketunes als Fundament. Der aktuelle Code ist
  bereits ein Fork, weist aber noch den Paketnamen `biketunes` auf; die
  Umbenennung wird erst in T006 vorgenommen.
- Die Zielbeschreibung verlangt iOS nur als Nice-to-have. Die Matrix verfolgt
  daher Android- und Docker-Abnahmen fuer V1; Desktop/iOS werden nicht als
  Release-Gate behandelt.
- Rechtliche Zulassungswerte werden nicht aus den DOCX-Referenzen abgeleitet.
  T002 muss eine bestaetigende Person und lokale Rechtslage erfassen.

## Quellen und Linkpruefung

- Anforderungen: [`reference/ziel.md`](../reference/ziel.md)
- Ausfuehrungsregeln: [`00-ausfuehrungsregeln.md`](./00-ausfuehrungsregeln.md)
- Produktkontext: [`conductor/product.md`](../conductor/product.md)
- Gestaltung: [`conductor/product-guidelines.md`](../conductor/product-guidelines.md)
- Technik: [`conductor/tech-stack.md`](../conductor/tech-stack.md)

Die Links sind relativ zum Speicherort dieser Matrix formuliert. Die
Abschnittsanker entsprechen den nummerierten Ueberschriften in
`reference/ziel.md`.
