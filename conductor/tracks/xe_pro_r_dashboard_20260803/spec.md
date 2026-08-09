# Fullscreen-Dashboard im XE-Pro-R-Stil

## Überblick

ArcDash erhält ein vollständig überarbeitetes, immersives Querformat-Dashboard, dessen Aufbau und Informationshierarchie vom Display der Arctic Leopard XE Pro R inspiriert sind.

Im Mittelpunkt steht eine große Geschwindigkeitsanzeige. Darüber befindet sich ein breiter, konfigurierbarer Telemetriebogen, der standardmäßig die aktuelle Leistung in kW anzeigt. Im unteren Bereich werden Akku, realistische Restreichweite, Motor- und Controller-Temperatur, Trip-Distanz sowie der aktive Fahrmodus kompakt dargestellt.

Das Dashboard bleibt frei konfigurierbar. Über einen Bearbeitungsstift in einer oberen Ecke wird ein expliziter Editiermodus geöffnet, in dem Elemente ähnlich Android-Widgets verschoben, in Breite und Höhe skaliert und hinsichtlich Datenquelle sowie Darstellungsart angepasst werden können.

## Funktionale Anforderungen

### 1. Immersives Querformat-Dashboard

- Das neue Standardlayout für das Querformat orientiert sich am XE-Pro-R-Display.
- Die Geschwindigkeit ist das visuell dominante Element und wird zentral mit Einheit angezeigt.
- Im Fahrmodus werden Android-Statusleiste, Navigationsleiste und die normale App-Navigation ausgeblendet.
- Das Dashboard nutzt den verfügbaren Bildschirm einschließlich sicher nutzbarer Randbereiche.
- Das Hochformat bleibt ein getrennt konfigurierbares Layout und wird nicht auf das R-Design festgelegt.
- Eine sichere und leicht verständliche Möglichkeit zum Verlassen des immersiven Modus bleibt verfügbar.
- Das Design ist vom Referenzdisplay inspiriert, verwendet aber keine geschützten Arctic-Leopard-Logos oder eine pixelgenaue Kopie.

### 2. R-typischer Telemetriebogen

- Oberhalb der Geschwindigkeit befindet sich ein breiter, segmentierter oder fließender Bogen.
- Der Bogen zeigt standardmäßig die aktuelle Motorleistung in kW.
- Positive Leistung verwendet abgestufte Zustandsfarben.
- Rekuperation wird als eigener grüner Zustand eindeutig dargestellt.
- Skala, Wert, Einheit und Datenqualität müssen eindeutig ablesbar sein.
- Fehlende, ungültige, veraltete oder bei getrennter Verbindung nicht verfügbare Werte dürfen nicht als plausible Live-Werte erscheinen.
- Der Bogen kann im Editiermodus einer anderen geeigneten Telemetriegröße zugewiesen werden.

### 3. Standardmäßig sichtbare Informationen

Das unveränderte Querformat-Standardlayout zeigt dauerhaft:

- Geschwindigkeit mit Einheit
- Live-Leistung in kW im oberen Bogen
- Akkusymbol mit SOC in Prozent
- Realistisch geschätzte Restreichweite in Kilometern
- Unsicherheit der Restreichweite, sofern verfügbar
- Motor-Temperatur
- Controller-Temperatur
- Trip-Distanz der aktuellen Fahrt
- Aktiven Fahrmodus beziehungsweise aktives Profil

Die Restreichweite muss die bereits von ArcDash berechnete Prognose verwenden und sich aktualisieren, wenn sich Fahrstil, Verbrauch oder aktiver Modus ändern.

### 4. Zustands- und Warnfarben

- AMOLED-Schwarz bildet den Hintergrund.
- Weiß beziehungsweise ein heller Cyan-Ton wird für normale primäre Werte verwendet.
- Grün kennzeichnet Rekuperation und gesunde Zustände.
- Amber kennzeichnet niedrigen SOC, erhöhte Temperaturen oder veraltete Daten.
- Rot kennzeichnet kritische Temperaturen, Fehler oder gefährliche Zustände.
- Farbe darf nie die einzige Information sein, durch die ein Zustand erkennbar wird.
- Warnfarben müssen auf fachlich definierten Grenzwerten beruhen und dürfen nicht allein dekorativ eingesetzt werden.

### 5. Dashboard-Editiermodus

- Ein Bearbeitungsstift in einer oberen Ecke öffnet den Editiermodus.
- Außerhalb des Editiermodus ist das Layout vollständig gesperrt.
- Das Antippen eines Elements im Editiermodus öffnet dessen Konfiguration.
- Für ein Element kann eine unterstützte Telemetriegröße gewählt werden.
- Für ein Element kann eine kompatible Darstellungsart gewählt werden, mindestens:
  - Bogen beziehungsweise Balken
  - Kreis
  - Reine Informationsanzeige
- Nicht jede Telemetriegröße muss jede Darstellung unterstützen; die Oberfläche bietet nur sinnvolle Kombinationen an.
- Elemente können per Drag-and-drop verschoben werden.
- Elemente können über sichtbare Griffe in Breite und Höhe skaliert werden.
- Verschieben und Skalieren orientieren sich am Verhalten von Android-Widgets.
- Elemente rasten in einem relativen Raster ein.
- Elemente dürfen sich nicht überlappen, den Bildschirm verlassen oder unbenutzbar klein werden.
- Änderungen werden automatisch und dauerhaft für die jeweilige Ausrichtung gespeichert.
- Das Standardlayout kann wiederhergestellt werden.
- Bestehende gespeicherte Dashboard-Layouts werden kontrolliert migriert oder sicher auf ein gültiges Standardlayout zurückgesetzt, ohne die App abstürzen zu lassen.

### 6. Trip-Distanz

- Die Trip-Distanz beschreibt ausschließlich die aktuelle Fahrt beziehungsweise Session.
- Die Anzeige verwendet die in ArcDash ermittelte Session-Distanz.
- Ist noch keine gültige Distanz verfügbar, wird ein eindeutiger Nicht-verfügbar-Zustand statt eines irreführenden Live-Werts angezeigt.
- Eine allgemeine Odometer-Anzeige ist nicht Bestandteil dieses Tracks.

### 7. Responsive Darstellung

- Das R-Standardlayout ist für Querformat optimiert.
- Es passt sich unterschiedlichen Android-Displaygrößen und Seitenverhältnissen an.
- Geschwindigkeit, Leistungsbogen und Pflichtinformationen dürfen weder abgeschnitten noch durch Displayausschnitte oder Systemgesten verdeckt werden.
- Werte, Einheiten und Beschriftungen skalieren innerhalb definierter Mindest- und Maximalgrößen.
- Sehr lange Profilnamen werden kontrolliert gekürzt und zerstören das Layout nicht.

## Nicht-funktionale Anforderungen

- Hoher Kontrast und gute Ablesbarkeit bei Sonnenlicht.
- Ruhiges, minimalistisches Premium-Design ohne unnötige Animationen.
- Fließende Aktualisierung der Live-Telemetrie ohne sichtbares Springen des gesamten Layouts.
- Der Bearbeitungsstift und alle Editor-Aktionen besitzen ausreichend große Touch-Flächen für Bedienung mit Handschuhen.
- Semantische Beschriftungen ermöglichen die Nutzung mit Android-Bedienungshilfen.
- Das Dashboard bleibt bei fehlenden oder fehlerhaften Telemetriedaten stabil.
- Neue Dashboard-Logik und Widgets werden gemäß Projekt-Workflow testgetrieben entwickelt.
- Neue Logik erreicht nach Möglichkeit mehr als 80 Prozent Testabdeckung.

## Akzeptanzkriterien

- [ ] Beim Öffnen des Dashboards im Querformat erscheint das R-inspirierte Standardlayout.
- [ ] Geschwindigkeit ist zentral und visuell dominant.
- [ ] Der obere Bogen zeigt standardmäßig Live-Leistung in kW.
- [ ] Bei Rekuperation wechselt der Leistungsbogen eindeutig in einen grünen Rekuperationszustand.
- [ ] Akku-Symbol, SOC, Restreichweite, beide Temperaturen, Trip und aktiver Modus sind im Standardlayout gleichzeitig sichtbar.
- [ ] Die Restreichweitenanzeige reagiert auf eine aktualisierte, modusabhängige Prognose.
- [ ] Der Fahrmodus verwendet den verfügbaren Bildschirm immersiv ohne normale Android- oder App-Leisten.
- [ ] Der Bearbeitungsstift öffnet und schließt einen eindeutig erkennbaren Editiermodus.
- [ ] Außerhalb des Editiermodus können Elemente nicht versehentlich verschoben oder skaliert werden.
- [ ] Im Editiermodus lassen sich Elemente per Touch verschieben sowie horizontal und vertikal skalieren.
- [ ] Durch Antippen eines Elements können Datenquelle und kompatible Darstellungsart geändert werden.
- [ ] Ungültige Positionen, Überlappungen und zu kleine Elemente werden verhindert.
- [ ] Änderungen bleiben nach App-Neustart und erneutem Wechsel ins Querformat erhalten.
- [ ] Das Hochformatlayout bleibt unabhängig vom Querformatlayout.
- [ ] Fehlende, veraltete, ungültige und getrennte Telemetriedaten werden eindeutig dargestellt.
- [ ] Das Layout funktioniert ohne Überlauf auf mehreren typischen Querformatgrößen und Seitenverhältnissen.
- [ ] Automatisierte Model-, Widget- und Persistenztests decken Standardlayout, Editoraktionen, Migration und Telemetriezustände ab.

## Nicht im Umfang

- Neugestaltung des Hochformat-Dashboards im XE-Pro-R-Stil
- Pixelgenaue Kopie des originalen Arctic-Leopard-Displays
- Verwendung originaler Arctic-Leopard-Markenassets
- Änderungen am BLE- oder FarDriver-Protokoll
- Entwicklung eines neuen Reichweitenprognose-Algorithmus
- Navigation oder Routenplanung
- Odometer- beziehungsweise Gesamtkilometer-Funktion
- Änderungen am Profil- oder Fahrmodus-System außerhalb der Dashboard-Anzeige
