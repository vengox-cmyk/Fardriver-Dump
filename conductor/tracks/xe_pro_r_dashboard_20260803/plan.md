# Implementierungsplan: Fullscreen-Dashboard im XE-Pro-R-Stil

## Phase 1: Dashboard-Datenmodell und Layoutvertrag

- [x] 6283833 Task: Dashboard-Modell testgetrieben für frei wählbare Darstellungsarten erweitern
    - [x] Fehlende Model-Tests für die unabhängige Auswahl von Telemetriegröße und Darstellungsart schreiben
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Unterstützte Darstellungsarten für Bogen, Balken, Kreis und reine Information modellieren
    - [x] Kompatible Kombinationen aus Telemetriegröße und Darstellung definieren und validieren
    - [x] Mindestgrößen und Größenbeschränkungen pro Darstellungsart festlegen
    - [x] Tests erneut ausführen und den Green-Zustand bestätigen
    - [x] Model-Code refaktorieren und relevante Tests erneut ausführen

- [x] 65cd4db Task: Trip-Distanz und Dashboard-Telemetrie testgetrieben anbinden
    - [x] Tests für Trip-Distanz, fehlende Session-Daten und Datenqualität schreiben
    - [x] Tests für die Aktualisierung der Restreichweite bei geändertem Fahrmodus beziehungsweise Prognosewert schreiben
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Trip-Distanz als auswählbare Dashboard-Metrik ergänzen
    - [x] Bestehende Session-Distanz als Datenquelle verwenden
    - [x] Bestehende Reichweitenprognose einschließlich Unsicherheit und Fahrmodusänderungen anbinden
    - [x] Fehlende, veraltete, ungültige und getrennte Daten eindeutig abbilden
    - [x] Tests erneut ausführen und den Green-Zustand bestätigen

- [x] aa5d862 Task: R-inspiriertes Querformat-Standardlayout testgetrieben definieren
    - [x] Tests für das neue Querformat-Standardlayout und das unveränderte unabhängige Hochformatlayout schreiben
    - [x] Prüfen, dass Geschwindigkeit, Leistungsbogen, Akku, Reichweite, Temperaturen, Trip und Modus enthalten sind
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Relatives Raster für das R-inspirierte Querformatlayout definieren
    - [x] Zentrale Geschwindigkeit und oberen Leistungsbogen anordnen
    - [x] Pflichtinformationen kompakt im unteren Bereich anordnen
    - [x] Layout validieren und Tests in den Green-Zustand bringen

- [x] ace8c17 Task: Conductor - Automated Phase Verification 'Phase 1: Dashboard-Datenmodell und Layoutvertrag' (Protocol in workflow.md) [checkpoint: ace8c17]

# Implementierungsplan: Fullscreen-Dashboard im XE-Pro-R-Stil

## Phase 1: Dashboard-Datenmodell und Layoutvertrag

- [x] 6283833 Task: Dashboard-Modell testgetrieben für frei wählbare Darstellungsarten erweitern
    - [x] Fehlende Model-Tests für die unabhängige Auswahl von Telemetriegröße und Darstellungsart schreiben
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Unterstützte Darstellungsarten für Bogen, Balken, Kreis und reine Information modellieren
    - [x] Kompatible Kombinationen aus Telemetriegröße und Darstellung definieren und validieren
    - [x] Mindestgrößen und Größenbeschränkungen pro Darstellungsart festlegen
    - [x] Tests erneut ausführen und den Green-Zustand bestätigen
    - [x] Model-Code refaktorieren und relevante Tests erneut ausführen

- [x] 65cd4db Task: Trip-Distanz und Dashboard-Telemetrie testgetrieben anbinden
    - [x] Tests für Trip-Distanz, fehlende Session-Daten und Datenqualität schreiben
    - [x] Tests für die Aktualisierung der Restreichweite bei geändertem Fahrmodus beziehungsweise Prognosewert schreiben
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Trip-Distanz als auswählbare Dashboard-Metrik ergänzen
    - [x] Bestehende Session-Distanz als Datenquelle verwenden
    - [x] Bestehende Reichweitenprognose einschließlich Unsicherheit und Fahrmodusänderungen anbinden
    - [x] Fehlende, veraltete, ungültige und getrennte Daten eindeutig abbilden
    - [x] Tests erneut ausführen und den Green-Zustand bestätigen

- [x] aa5d862 Task: R-inspiriertes Querformat-Standardlayout testgetrieben definieren
    - [x] Tests für das neue Querformat-Standardlayout und das unveränderte unabhängige Hochformatlayout schreiben
    - [x] Prüfen, dass Geschwindigkeit, Leistungsbogen, Akku, Reichweite, Temperaturen, Trip und Modus enthalten sind
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Relatives Raster für das R-inspirierte Querformatlayout definieren
    - [x] Zentrale Geschwindigkeit und oberen Leistungsbogen anordnen
    - [x] Pflichtinformationen kompakt im unteren Bereich anordnen
    - [x] Layout validieren und Tests in den Green-Zustand bringen

- [x] ace8c17 Task: Conductor - Automated Phase Verification 'Phase 1: Dashboard-Datenmodell und Layoutvertrag' (Protocol in workflow.md) [checkpoint: ace8c17]

## Phase 2: R-inspiriertes Fahrdisplay

- [x] Task: Immersive Querformat-Darstellung testgetrieben implementieren
    - [x] Widget-Tests für Querformat, Fullscreen-Aktivierung und Wiederherstellung der Systemleisten schreiben
    - [x] Tests für getrenntes Verhalten im Hochformat schreiben
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Normale App-Navigation im immersiven Fahrmodus ausblenden
    - [x] Android-Status- und Navigationsleisten im Querformat ausblenden
    - [x] Systemleisten beim Verlassen des Dashboards oder Wechsel ins Hochformat zuverlässig wiederherstellen
    - [x] Sichere Möglichkeit zum Verlassen des immersiven Modus erhalten
    - [x] Tests erneut ausführen und den Green-Zustand bestätigen

- [x] Task: Zentrale Geschwindigkeitsanzeige und Leistungsbogen testgetrieben gestalten
    - [x] Golden- oder Widget-Tests für Informationshierarchie, Beschriftungen und Telemetriezustände schreiben
    - [x] Tests für positive Leistung, Rekuperation und nicht verfügbare Werte schreiben
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Große zentrale Geschwindigkeitsanzeige mit dynamischer Einheit implementieren
    - [x] Breiten R-typischen Bogen mit Skala, Live-Wert und Einheit implementieren
    - [x] Abgestufte Farben für positive Leistung implementieren
    - [x] Grünen, textlich gekennzeichneten Rekuperationszustand implementieren
    - [x] Fehlende oder unzuverlässige Werte ohne plausible Ersatzwerte darstellen
    - [x] Tests erneut ausführen und den Green-Zustand bestätigen

- [x] Task: Untere Informationszone testgetrieben implementieren
    - [x] Widget-Tests für Akku, SOC, Reichweite, Unsicherheit, Temperaturen, Trip und Modus schreiben
    - [x] Tests für lange Profilnamen sowie Warn- und Fehlerzustände schreiben
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Akkusymbol mit SOC-Prozent implementieren
    - [x] Modusabhängige Restreichweite mit Unsicherheit darstellen
    - [x] Motor- und Controller-Temperatur eindeutig beschriften
    - [x] Trip-Distanz und aktiven Fahrmodus darstellen
    - [x] Grün-, Amber- und Rot-Zustände mit zusätzlicher textlicher oder ikonografischer Kennzeichnung umsetzen
    - [x] Tests erneut ausführen und den Green-Zustand bestätigen

- [x] Task: Conductor - Automated Phase Verification 'Phase 2: R-inspiriertes Fahrdisplay' (Protocol in workflow.md)

## Phase 3: Widget-ähnlicher Dashboard-Editor

- [x] Task: Expliziten Editiermodus testgetrieben implementieren
    - [x] Widget-Tests für Bearbeitungsstift, Editorstatus und gesperrten Fahrmodus schreiben
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Bearbeitungsstift in einer oberen Ecke integrieren
    - [x] Klar erkennbaren Editiermodus mit Speichern beziehungsweise Beenden umsetzen
    - [x] Sämtliche Layoutgesten außerhalb des Editiermodus blockieren
    - [x] Ausreichend große Touch-Flächen und semantische Beschriftungen ergänzen
    - [x] Tests erneut ausführen und den Green-Zustand bestätigen

- [x] Task: Drag-and-drop und zweidimensionale Größenänderung testgetrieben implementieren
    - [x] Tests für Verschieben, horizontales Skalieren und vertikales Skalieren schreiben
    - [x] Tests für Rastergrenzen, Kollisionen, Mindestgrößen und Abbruch ungültiger Änderungen schreiben
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Drag-and-drop mit Einrasten im relativen Raster implementieren
    - [x] Sichtbare Ziehpunkte für Breite und Höhe implementieren
    - [x] Live-Vorschau der Zielposition und Zielgröße anzeigen
    - [x] Überlappungen, Bildschirmüberschreitungen und unzulässige Größen verhindern
    - [x] Touch-Interaktion an Android-Widgets anlehnen
    - [x] Tests erneut ausführen und den Green-Zustand bestätigen

- [x] Task: Datenquelle und Darstellungsart testgetrieben konfigurierbar machen
    - [x] Widget-Tests für das Antippen eines Elements und Öffnen seiner Konfiguration schreiben
    - [x] Tests für Telemetrieauswahl und kompatible Darstellungsarten schreiben
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Element-Konfiguration als für Querformat geeigneten Dialog oder Bottom-Sheet implementieren
    - [x] Wechsel der Telemetriegröße ermöglichen
    - [x] Wechsel zwischen Bogen, Balken, Kreis und reiner Information ermöglichen
    - [x] Nicht kompatible Kombinationen ausblenden oder deaktivieren
    - [x] Änderungen unmittelbar in der Dashboard-Vorschau darstellen
    - [x] Tests erneut ausführen und den Green-Zustand bestätigen

- [x] Task: Conductor - Automated Phase Verification 'Phase 3: Widget-ähnlicher Dashboard-Editor' (Protocol in workflow.md)

## Phase 4: Persistenz, Migration und Qualitätsabsicherung

- [x] Task: Layout-Persistenz und Schema-Migration testgetrieben erweitern
    - [x] Repository-Tests für das erweiterte Layoutschema schreiben
    - [x] Tests für bestehende Schema-Versionen, beschädigte Daten und unbekannte Darstellungsarten schreiben
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Dashboard-Schema versionieren und bestehende gültige Layouts migrieren
    - [x] Nicht migrierbare Layouts kontrolliert auf ein gültiges Standardlayout zurücksetzen
    - [x] Änderungen getrennt nach Hoch- und Querformat automatisch speichern
    - [x] Zurücksetzen auf das R-inspirierte Querformat-Standardlayout ermöglichen
    - [x] Tests erneut ausführen und den Green-Zustand bestätigen

- [x] Task: Responsive Darstellung und Barrierefreiheit testgetrieben absichern
    - [x] Widget-Tests für mehrere typische Querformatgrößen und Seitenverhältnisse schreiben
    - [x] Tests mit Textskalierung, Displayausschnitten und langen Beschriftungen schreiben
    - [x] Semantik-Tests für Werte, Warnzustände und Editoraktionen schreiben
    - [x] Tests ausführen und das erwartete Fehlschlagen bestätigen
    - [x] Größen, Abstände und Typografie responsiv begrenzen
    - [x] Sichere Randbereiche und Systemgesten berücksichtigen
    - [x] Überläufe und abgeschnittene Pflichtinformationen verhindern
    - [x] Semantische Beschriftungen und nicht ausschließlich farbliche Zustandskennzeichnung ergänzen
    - [x] Tests erneut ausführen und den Green-Zustand bestätigen

- [x] Task: Dashboard-Gesamtintegration und Regressionen prüfen
    - [x] Integrations- beziehungsweise Widget-Flow für Anzeigen, Bearbeiten, Speichern und erneutes Laden ergänzen
    - [x] Vollständige Testsuite mit `docker compose run --rm flutter flutter test` ausführen
    - [x] Coverage mit `docker compose run --rm flutter flutter test --coverage` erzeugen
    - [x] Für neuen Code eine Testabdeckung von mehr als 80 Prozent prüfen
    - [x] Statische Analyse mit `docker compose run --rm flutter flutter analyze --no-fatal-infos` ausführen
    - [x] Formatierung mit `docker compose run --rm flutter dart format --set-exit-if-changed lib test` prüfen
    - [x] Android-Build mit `docker compose run --rm flutter flutter build apk` verifizieren
    - [x] Abweichungen dokumentieren und gefundene Regressionen beheben

- [x] Task: Manuelle Dashboard-Verifikation vorbereiten
    - [x] Prüfschritte für ein Android-Gerät im Querformat dokumentieren
    - [x] Fullscreen-Eintritt und zuverlässige Wiederherstellung der Systemleisten prüfen
    - [x] Ablesbarkeit, Telemetrieaktualisierung und Rekuperationszustand während einer simulierten Fahrt prüfen
    - [x] Editor mit Touch, Drag-and-drop und Größenänderung prüfen
    - [x] Persistenz nach App-Neustart und Orientierungswechsel prüfen
    - [x] Verhalten bei BLE-Trennung und veralteten Daten prüfen

- [x] Task: Conductor - Automated Phase Verification 'Phase 4: Persistenz, Migration und Qualitätsabsicherung' (Protocol in workflow.md)

