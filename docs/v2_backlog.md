# Version 2 Backlog: Navigation, Karte, Trail & End-SOC

Dieses Dokument enthält die konkretisierten Anforderungen und Epic-Tasks für ArcDash Version 2. Die Punkte bauen auf den Domain-Interfaces aus Phase 11 (`lib/domain/navigation/navigation_interfaces.dart`) auf und berühren nicht die Stabilität oder den Abnahmestatus von Version 1.

---

## Epic 1: Kartenanzeige & UI (flutter_map)

### V2-001: flutter_map Integration & Caching
* **Ziel:** Interaktive Kartenanzeige auf der Dashboard-/Navigations-Screen mit Zoom, Zentrierung auf aktuelle GPS-Position und Track-Line.
* **Abhängigkeit:** `flutter_map` Pub-Paket, `GeoLatLng` Domain-Modell.
* **Akzeptanzkriterium:** Smooth 60fps Kartenanzeige, automatisches Caching von OpenStreetMap / OpenTopoMap-Kacheln für Offline-Passagen.
* **Kosten / Lizenz:** Kostenlos (ODbL / OpenStreetMap Attribution verpflichtend).

---

## Epic 2: Routing & Streckenpräferenzen

### V2-002: Trailpräferenz & "Große Straßen meiden" Routing
* **Ziel:** Routenberechnung optimiert für Offroad-/Light-Trail-Nutzung (Sur-Ron / Arctic Leopard) mit Vermeidung von Bundesstraßen / Autobahnen.
* **Abhängigkeit:** `RoutingService` Interface, GraphHopper / Valhalla API.
* **Akzeptanzkriterium:** Die Routing-Anfrage berücksichtigt `RoutingPreference.trailPreferred` und `RoutingPreference.avoidHighways` und liefert entsprechende Segment-Eigenschaften (`surfaceType`).
* **Kosten / Lizenz:** Self-Hosted oder Open-Source Routing Endpoint.

---

## Epic 3: Höhenmodell & Höhenverbrauch

### V2-003: Höhenprofil-Integration (Elevation API / DEM)
* **Ziel:** Exakte Ermittlung von Steigungen und Gefällen pro Routensegment zur dynamischen Verbrauchsanpassung.
* **Abhängigkeit:** `ElevationService` Interface, SRTM / Open-Elevation Data.
* **Akzeptanzkriterium:** Jedes Routensegment erhält Start- und End-Höhenmeter; Steigungsmeter fließen direkt in den `EnergyProfile`-Rechner ein.
* **Kosten / Lizenz:** Kostenfrei bei Nutzung von SRTM Data Tiles / Open-Elevation.

---

## Epic 4: Energie- & End-SOC-Prognose für Routen

### V2-004: End-SOC Berechnung & Reichweiten-Warnung bei Routenplanung
* **Ziel:** Vorfahrt-Prognose, wie viel Batterie-% am Zielort (End-SOC) verbleiben und ob Zwischenladungen nötig sind.
* **Abhängigkeit:** `EnergyProfile`, `RangePredictionRepository` aus Version 1.
* **Akzeptanzkriterium:** Anzeige des erwarteten End-SOC in % und Wh vor Tourstart; Warnung, wenn der berechnete End-SOC unter 10% fällt.
* **Kosten / Lizenz:** Keine externen Kosten (rein lokale Berechnung).

---

## Forschungs-, Datenschutz- & Betriebsfragen (Spikes)

| Task-ID | Thema | Forschungsfrage / Aufgabe | Betriebsaufwand / Kosten |
|---|---|---|---|
| **V2-SPIKE-01** | Offline-Routing (BRouter) | Integration von BRouter Android Service für 100% offline Routing ohne Netzverbindung. | Null laufende Kosten; Aufwand für APK-BRouter-IPC / Intent-Schnittstelle. |
| **V2-SPIKE-02** | Tile-Server Fair-Use & Vector Tiles | Evaluierung von PMTiles / Vector Tiles für platzsparenden Offline-Kartendownload ganzer Regionen. | Eigenes Web-Hosting für Regionen-Downloads (~5 €/Monat VPS) oder Peer-to-Peer. |
| **V2-SPIKE-03** | Datenschutz & Tracking | Sicherstellen, dass keine Routen- oder Telemetriedaten an Dritte übertragen werden. | Standard: Lokale Verarbeitung; Kontrollierte API-Calls ohne Device-ID. |

---

## Verknüpfung mit reference/ziel.md

- **Ziel-Referenz "Navigation & Karten"**: Abgedeckt durch V2-001 und V2-002.
- **Ziel-Referenz "Topographie- & Höhenberücksichtigung"**: Abgedeckt durch V2-003 und V2-004.
- **V1-Abnahmestatus**: Bleibt durch dieses Backlog unangetastet.
