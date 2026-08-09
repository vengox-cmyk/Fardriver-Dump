# Product Guidelines

## Design Tone

ArcDash folgt einem **streng dunklen, minimalistischen Design** (AMOLED-schwarz). Die Oberfläche wirkt **premium und ruhig** — kein überladenes Tuning-Werkzeug, sondern ein klares, verlässliches Cockpit + Profil-Manager. Sehr hohe Kontraste, große, klar lesbare Zahlen, wenig Text, viel Visualisierung. Die wichtigsten Aktionen (insbesondere der Profilwechsel) sind schnell erreichbar.

## Prose Style

Alle Texte sind **knapp, klar und instruktiv**. Die App erklärt in kurzer, verständlicher Sprache, was passiert (besonders bei Schreibvorgängen an den Controller) — ohne Alarmismus, aber ohne die Risiken des Tuning zu beschönigen. Standardsprache ist **Deutsch**, Englisch optional.

## Visual Identity

- **Dunkles Theme mit AMOLED-schwarzem Hintergrund**, sehr hohe Kontraste, große leicht lesbare Zahlen.
- **Safety-Signal-Farben** für Zustände:
  - **Grün** — gesund, sicher, verbunden, im Limit; auch aktive Rekuperation (negativer Strom).
  - **Amber** — Vorsicht, nahe an einem Limit (z. B. steigende Temperaturen, niedriger SOC).
  - **Rot** — Gefahr, Fehler oder blockierte Aktion (z. B. Bewegung während eines Schreibversuchs).
- Der **Leistungsindikator** verfärbt sich je nach aktueller Leistung und wird bei Rekuperation grün — als visuelles Highlight des Dashboards.
- Optimiert für Ablesbarkeit bei Sonneneinstrahlung und Bedienung mit Handschuhen.
- Das Dashboard besitzt getrennt konfigurierbare Hoch- und Querformatlayouts.
  Werte koennen hinzugefuegt, entfernt, verschoben und skaliert werden, ohne dass
  der Bearbeitungsmodus waehrend der normalen Fahrt versehentlich aktiv wird.
- Das Raster passt sich an die Geraetegroesse an. Gespeichert werden relative
  Rasterpositionen statt Pixelwerte; kritische Inhalte duerfen weder abgeschnitten
  noch durch Navigation oder Systemleisten verdeckt werden.

## Safety Communication

Sicherheit geht vor Komfort — die Safety-Schicht ist **streng**, aber informierte Nutzer können zügig arbeiten:

- Schreiben nur bei Motorstillstand (RPM ≈ 0); optional „auch beim Ausrollen erlauben" (Gas = 0).
- **Harte Obergrenzen** für kritische Werte (MaxLineCurr, MaxPhaseCurr etc.), die der Nutzer nicht überschreiten kann.
- **Read-back-Verifikation** nach dem Schreiben.
- Immer ein funktionierendes **Stock-Backup**.
- Klare Bestätigungen und Warnungen bei kritischen Änderungen.
- Hintergrund-Profilwechsel (MacroDroid) gibt eine dezente Rückmeldung (Vibration + optionale stille Benachrichtigung).

## Brand Messaging

ArcDash ist das verlässliche Cockpit für den Arctic Leopard Xe Pro S: ein Profil-Manager und Telemetrie-Dashboard, dem man vertraut — auch im Hintergrund, auch auf Knopfdruck. Premium, ruhig, sicher. Kein Hype, keine laufenden Kosten, kein unnötiger Ballast.
