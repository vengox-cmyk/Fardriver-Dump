Hier ist die vollständige Anweisung, die du dem Coding-Agenten geben kannst:

---

# ArcDash – Vollständige Produkt- und technische Spezifikation

## 1. Projektübersicht

**ArcDash** ist eine moderne, native Android-App (Flutter) für das Elektro-Motorrad **Arctic Leopard Xe Pro S** mit **Fardriver-Controller**.

Die App basiert auf einem Fork von **Biketunes** (https://github.com/caydenchapple/Biketunes).  
Das bestehende Protokoll-Handling, BLE-Kommunikation, Parameter-Schreiben und Backup-System von Biketunes soll als Fundament erhalten bleiben und stark erweitert bzw. optisch und funktional komplett überarbeitet werden.

**Hauptziele:**
- Deutlich bessere, modernere und übersichtlichere Benutzeroberfläche als die originale Fardriver-App
- Zuverlässige Live-Telemetrie
- Profilverwaltung mit schnellem Wechsel (besonders „Street Legal“)
- Hintergrund-fähig + steuerbar über MacroDroid (Volume-Down-Doppelklick)
- Selbstlernende, realistische Reichweitenprognose
- Hohe Sicherheit beim Schreiben von Parametern

**Plattform:** Primär Android (iOS nur Nice-to-have)  
**Framework:** Flutter (Beibehaltung von Biketunes)

---

## 2. Was aus Biketunes übernommen werden soll

Behalte und baue darauf auf:

- BLE-Verbindung zum Fardriver (Service UUID & Characteristic)
- Parsing der 16-Byte Telemetrie-Frames + CRC
- Schreiben von Parametern über die reverse-engineerten Adressen
- Bestehende Safety-Ansätze (Motion-Lockout)
- Stock-Backup & Restore-Logik
- Ride-Mode-Presets als Ausgangspunkt

Alles UI-bezogene und die Architektur der Screens soll neu gestaltet werden.

---

## 3. Kern-Features (Version 1)

### 3.1 Live-Telemetrie-Dashboard (Hauptbildschirm)

Modernes, dunkles (AMOLED-optimiertes) Dashboard mit hoher Ablesbarkeit:

- Große Geschwindigkeitsanzeige (bevorzugt GPS, Fallback Controller-RPM)
- Aktuelle Leistung in kW (live)
- Spannung (V), Strom (A), State of Charge (%)
- Restreichweite mit Unsicherheitsangabe (z. B. „42 km ± 5 km“)
- Aktuelles Profil (Name + kurze Kennzeichnung)
- Controller- und Motor-Temperatur
- Rekuperations-Status (optisch hervorheben, wenn negativer Strom)
- Gang / DNR-Status

Visuelles Highlight: Ein halbkreisförmiger oder bogenförmiger Leistungsindikator, der sich je nach aktueller Leistung verfärbt und bei Rekuperation grün wird.

Das Dashboard muss auch bei Sonneneinstrahlung und mit Handschuhen gut bedienbar/ablesbar sein.

### 3.2 Profil-System (sehr wichtig)

Die App muss mehrere benannte Profile speichern und laden können.

**Mindest-Profile:**
- Stock (automatisches Backup beim ersten Verbinden)
- Street Legal
- Offroad / Trail
- Sport / Race
- Eco

**Funktionen:**
- Profile erstellen, umbenennen, löschen, duplizieren
- Aktuelles Profil anzeigen
- Unterschiede zwischen Profilen sichtbar machen (einfacher Diff)
- Profile exportieren/importieren (JSON)
- Beim Laden eines Profils nur die wirklich notwendigen Parameter schreiben (nicht unnötig den kompletten Speicher)

**Street Legal Profil:**
- Besonders wichtig
- Soll möglichst „leicht“ sein (nur Speed-Limit + moderate Stromreduzierung + ggf. Throttle-Response)
- Muss extrem zuverlässig und schnell ladbar sein

### 3.3 Hintergrundbetrieb + MacroDroid-Trigger (kritisch)

Die App muss im Hintergrund stabil laufen können (Foreground Service).

**Anforderung:**
- MacroDroid soll über einen Volume-Down-Doppelklick einen Intent / Deep Link an ArcDash senden können.
- Daraufhin soll die App **im Hintergrund** (Bildschirm aus) das Profil „Street Legal“ laden und an den Controller schreiben.
- Der Nutzer soll eine dezente Rückmeldung bekommen (Vibration + optionale stille Benachrichtigung), dass der Wechsel erfolgreich war.
- Der Bildschirm darf dafür **nicht** angehen müssen.

Das ist eines der wichtigsten Features der App.

### 3.4 Sicherheitsregeln beim Schreiben von Parametern

Sehr strenge Safety-Schicht:

- Standardmäßig darf nur geschrieben werden, wenn der Motor stillsteht (RPM ≈ 0).
- Optional: „Auch beim Ausrollen erlauben“ (Gas = 0).
- Harte Obergrenzen für kritische Werte (MaxLineCurr, MaxPhaseCurr etc.), die der Nutzer nicht überschreiten kann.
- Nach dem Schreiben sollen die Werte zur Kontrolle wieder ausgelesen werden (Read-back).
- Immer ein funktionierendes Stock-Backup vorhanden halten.
- Klare Bestätigungen und Warnungen bei kritischen Änderungen.

### 3.5 Selbstlernende Reichweitenprognose

Die App soll eine deutlich bessere Restreichweite berechnen als die originale Fardriver-App.

**Methode:**
1. Coulomb Counting (Integration von Spannung × Strom)
2. Komplementärfilter mit spannungsbasiertem SOC
3. Lernen der real nutzbaren Kapazität durch vollständige Lade-/Entladezyklen
4. Gleitendes Fenster für aktuellen Verbrauch (Wh/km) auf Basis von GPS-Distanz
5. Anpassung an den aktuellen Fahrstil

Anzeige: Restreichweite + Unsicherheitsbereich (z. B. ± km).

Nach 2–3 vollen Zyklen sollte die Prognose brauchbar, nach 1–2 Wochen gut werden.

### 3.6 Weitere Version-1-Features

- Session-Statistiken (Distanz, Verbrauch, max. Leistung, Durchschnittstemperaturen etc.)
- Einfache Anzeige von Controller-Fehlern
- Einstellungen (Einheiten, Dark Mode erzwingen, Safety-Optionen, etc.)
- Zuverlässiges automatisches Wiederverbinden

---

## 4. Spätere Features (Version 2+)

Diese sollen architektonisch vorbereitet, aber nicht in Version 1 zwingend fertig sein:

- Navigation mit realistischer Reichweitenberechnung
- Einbeziehung von Höhenmetern in die Verbrauchsprognose
- End-SOC-Vorhersage für eine geplante Route
- Routing-Optionen:
  - Schnellste Route
  - Waldwege / Trails bevorzugen
  - Große Straßen meiden / kleinere Straßen bevorzugen
- Alles muss **ohne laufende Kosten** funktionieren (kein bezahlter Google/Mapbox Directions-Betrieb). Bevorzugt: `flutter_map` + kostenlose Routing-Engine (GraphHopper / Valhalla / OSRM).

---

## 5. UI/UX-Richtlinien

- Streng Dark Mode (AMOLED-schwarz)
- Sehr hohe Kontraste
- Große, klar lesbare Zahlen
- Minimalistische, moderne Optik
- Wenig Text, viel Visualisierung
- Schnelle Erreichbarkeit der wichtigsten Aktionen (Profilwechsel)
- Deutsche Sprache als Standard (Englisch optional)

---

## 6. Technische Leitplanken

- Flutter beibehalten
- Bestehende Protokoll- und Write-Logik von Biketunes möglichst wiederverwenden und nur absichern/erweitern
- Foreground Service für Hintergrundbetrieb
- Saubere Trennung: BLE/Protocol Layer ↔ State Management ↔ UI
- Defensives Programmieren besonders beim Schreiben von Parametern
- Keine laufenden Kosten durch externe APIs in der Basisversion

---

## 7. Entwicklungsreihenfolge (Empfehlung)

1. Projekt forken, umbenennen in **ArcDash**, grundlegend aufräumen
2. Telemetrie stabil zum Laufen bringen + neues Dashboard
3. Profil-System + sicheres Schreiben implementieren
4. Hintergrund-Service + MacroDroid-Intent bauen
5. Lernende Reichweitenprognose
6. Feinschliff, Statistiken, Polish
7. Später: Navigation + Höhenmeter

---

## 8. Wichtige Hinweise an den Entwickler (KI)

- Sicherheit geht vor Komfort. Lieber etwas strenger beim Schreiben sein.
- Das Street-Legal-Profil und der Hintergrund-Trigger sind geschäftskritisch.
- Orientiere dich bei Protokoll und Write-Befehlen eng an Biketunes und jackhumbert/fardriver-controllers.
- Baue von Anfang an gutes Logging und Read-back-Verification ein.
- Die App soll sich premium und ruhig anfühlen – kein überladenes Tuning-Tool, sondern ein klares, verlässliches Cockpit + Profil-Manager.

---

Das ist die vollständige Anweisung.  
Du kannst diesen Text direkt an deinen Coding-Agenten übergeben, nachdem du das Biketunes-Repository geklont hast.