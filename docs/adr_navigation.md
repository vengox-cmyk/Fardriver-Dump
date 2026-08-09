# ADR: Navigation, Routing & Elevation Architecture (Version 2)

* **Status:** Vorbereitet (Phase 11 / T084)
* **Datum:** 2026-08-03
* **Kontext:** ArcDash Version 1 konzentriert sich auf zuverlässige Controller-Telemetrie, sichere Parametrierung und reichweitenbasierte Prognose ohne externe Netzwerkanbindungen. Für Version 2 wird Navigation, Routing, Trailpräferenz und Höhenprofil vorbereitet.

## 1. Entscheidungsgegenstand

Wie wird Navigation und Kartendarstellung in ArcDash integriert, ohne:
1. Version 1 durch API-Key-Pflichten, Laufzeitkosten oder Fremd-SDK-Komplexität zu belasten.
2. Das Kern-Reichweitenmodell an spezifische Routing-Anbieter zu koppeln.

## 2. Optionsevaluierung

### Option A: Proprietsäre Routing & Karten-SDKs (Google Maps, Mapbox)
* **Vorteile:** Hohe Kartendetailgenauigkeit, fertige Navigations-UI.
* **Nachteile:** Laufende API-Kosten, Key-Pflicht, Registrierungszwang für Nutzer, Datenschutzbedenken (Standort-Tracking), schlechtere Offline-Verfügbarkeit auf Offroad-Trails.
* **Bewertung:** **Abgelehnt.** Widerspricht der ArcDash-Philosophie von Kostenfreiheit und voller Kontrolle.

### Option B: Open-Source Map & Open-Source Routing Engine (GraphHopper / Valhalla / OSRM + flutter_map)
* **Vorteile:**
  - **Kartenanzeige:** `flutter_map` (OpenStreetMap / OpenTopoMap Kacheln, Vektor oder Raster).
  - **Routing-Engines:**
    - **GraphHopper / Valhalla:** Hervorragende Unterstützung für Custom Elevation Profiling, Trail-Gewichtung (unpaved/gravel) und "Große Straßen meiden".
    - **OSRM:** Sehr schnell für Standard-Straßenrouting.
  - **Self-Hosting / Offline:** Eigenes Hosting möglich (z. B. auf Docker/VPS) oder Offline-Pakete / BRouter-Integration auf dem Gerät.
  - **Kosten:** Keine Lizenzkosten oder API-Keys für den Endnutzer.
* **Bewertung:** **Ausgewählt.**

## 3. Entschiedene Architektur

1. **Abstraktion über Domain-Interfaces:**
   - Logik zur Routen- und Energieberechnung hängt nur von `RoutingService`, `ElevationService` und `EnergyProfile` (`lib/domain/navigation/navigation_interfaces.dart`) ab.
   - Version 1 und Reichweitenprognose bleiben ohne Kartendienst voll funktionsfähig.

2. **Karten-Framework:**
   - Verwenden von `flutter_map` zur Darstellung von Tracks, Segmenten, Pins und Höhenfarbcodierung in Version 2.

3. **Routing & Elevation Engine:**
   - Standardmäßig Anbindung an kostenfreie / self-hostbare Routing-APIs (z. B. GraphHopper / Valhalla) mit Fallback auf Offline-Elevation (SRTM / DEM Tiles).

## 4. Konsequenzen & Risiken

- **Offline-Nutzung:** Für lückenlosen Offroad-Betrieb muss ein lokaler Kachel-Cache sowie Offline-Routing (z. B. BRouter / Valhalla offline) im V2-Backlog vorgesehen werden.
- **Kachel-Server Fair-Use:** Öffentliche OSM Tile Server besitzen Fair-Use-Regeln. ArcDash sollte Caching nutzen und mittelfristig eigene Kachel-Proxy- oder Vector-Tile-Optionen anbieten.
