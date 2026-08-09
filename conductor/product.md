# Initial Concept

ArcDash — ein moderner, nativer Android-App-Fork (Flutter) des Biketunes-Projekts für das Elektro-Motorrad **Arctic Leopard Xe Pro S** mit Fardriver-Controller. Das bestehende Protokoll-Handling, die BLE-Kommunikation, das Parameter-Schreiben und das Backup-System von Biketunes bleiben als Fundament erhalten und werden stark erweitert sowie optisch und funktional komplett überarbeitet.

# Product Guide

## Overview

ArcDash ist ein modernes, natives Android-Cockpit (Flutter) für das Elektro-Motorrad Arctic Leopard Xe Pro S mit Fardriver-Controller. Es verbindet sich über Bluetooth BLE UART und spricht das reverse-engineerte FarDriver-Serialprotokoll. Das Produkt kombiniert ein zuverlässiges Live-Telemetrie-Dashboard mit einem leistungsfähigen Profil-Manager, Hintergrund-Fähigkeit und einer selbstlernenden Reichweitenprognose — mit einem deutlichen Fokus auf Sicherheit beim Schreiben von Parametern.

Plattform: **Primär Android** (iOS nur Nice-to-have).

## Target Users

- **Besitzer eines Arctic Leopard Xe Pro S (oder ähnlicher FarDriver-betriebener E-Motorbikes)**, die ihr Fahrzeug verstehen, tunen und zwischen Straßen- und Offroad-Konfigurationen wechseln möchten — ohne auf die original Fardriver-App angewiesen zu sein.
- Technisch interessierte Fahrer, die Wert auf ein klares, verlässliches Cockpit legen statt auf ein überladenes Tuning-Werkzeug.

## Goals

- **Deutlich bessere, modernere und übersichtlichere Benutzeroberfläche** als die originale Fardriver-App.
- **Zuverlässige Live-Telemetrie** — Geschwindigkeit, Leistung (kW), Spannung, Strom, SOC, Temperaturen, Rekuperation, Gang/DNR.
- **Profilverwaltung mit schnellem Wechsel** — besonders das Profil „Street Legal" muss extrem zuverlässig und schnell ladbar sein.
- **Hintergrund-fähig und steuerbar über MacroDroid** — Profilwechsel per Volume-Down-Doppelklick ohne dass der Bildschirm angeht.
- **Selbstlernende, realistische Reichweitenprognose** mit Unsicherheitsangabe.
- **Hohe Sicherheit beim Schreiben von Parametern** — Motorstillstand-Pflicht, harte Obergrenzen, Read-back-Verifikation, funktionierendes Stock-Backup.

## Core Features (Version 1)

- **Live-Telemetrie-Dashboard (Hauptbildschirm)** — von Grund auf neu gebautes, AMOLED-optimiertes Cockpit fuer Hoch- und Querformat. Der Nutzer bestimmt getrennt je Ausrichtung, welche Werte angezeigt werden, wo sie liegen und wie gross sie sind. Verfuegbar sind Geschwindigkeit (bevorzugt GPS, Fallback Controller-RPM), Live-Leistung in kW, Spannung (V), Strom (A), SOC (%), Restreichweite mit Unsicherheit (± km), aktuelles Profil, Controller- und Motor-Temperatur, Rekuperations-Status, Gang/DNR, Fehler und Verbindung. Visuelles Highlight: halbkreisfoermiger Leistungsindikator, der sich je nach Leistung verfaerbt und bei Rekuperation gruen wird. Bedienbar mit Handschuhen und bei Sonneneinstrahlung.
- **Profil-System (sehr wichtig)** — benannte Profile (Stock, Street Legal, Offroad/Trail, Sport/Race, Eco), Erstellen/Umbenennen/Löschen/Duplizieren, aktuelles Profil anzeigen, einfacher Diff zwischen Profilen, Export/Import als JSON, gezieltes Schreiben nur der nötigen Parameter.
- **Hintergrundbetrieb + MacroDroid-Trigger (kritisch)** — Foreground Service, Intent/Deep-Link-Empfang, Profil „Street Legal" im Hintergrund laden und schreiben, dezente Rückmeldung (Vibration + optionale stille Benachrichtigung), ohne dass der Bildschirm angeht.
- **Sicherheitsregeln beim Schreiben** — Motorstillstand-Pflicht (RPM ≈ 0), optional „auch beim Ausrollen erlauben", harte Obergrenzen für kritische Werte (MaxLineCurr, MaxPhaseCurr etc.), Read-back nach dem Schreiben, Stock-Backup, klare Bestätigungen.
- **Selbstlernende Reichweitenprognose** — Coulomb Counting, Komplementärfilter mit spannungsbasiertem SOC, Lernen der real nutzbaren Kapazität über Lade-/Entladezyklen, gleitendes Verbrauchsfenster (Wh/km) auf GPS-Distanz, Anpassung an den Fahrstil.
- **Session-Statistiken** — Distanz, Verbrauch, max. Leistung, Durchschnittstemperaturen.
- **Einfache Anzeige von Controller-Fehlern.**
- **Einstellungen** — Einheiten, Dark Mode erzwingen, Safety-Optionen.
- **Zuverlässiges automatisches Wiederverbinden.**

## Spätere Features (Version 2+)

Architektonisch vorbereitet, aber nicht zwingend in Version 1 fertig:

- Navigation mit realistischer Reichweitenberechnung.
- Einbeziehung von Höhenmetern in die Verbrauchsprognose.
- End-SOC-Vorhersage für geplante Routen.
- Routing-Optionen (schnellste Route, Waldwege/Trails bevorzugen, große Straßen meiden).
- Alles ohne laufende Kosten — bevorzugt `flutter_map` + kostenlose Routing-Engine (GraphHopper / Valhalla / OSRM).

## Non-Goals

- Kein überladenes Tuning-Tool mit Unmengen an Parametern im Vordergrund — es geht um ein klares Cockpit + Profil-Manager.
- Keine bezahlten externen APIs in der Basisversion.
- iOS ist Nice-to-have, kein Veröffentlichungsziel der ersten Version.

## Safety

Sicherheit geht vor Komfort. Lieber etwas strenger beim Schreiben von Parametern sein: Motorstillstand-Pflicht, harte Obergrenzen, Read-back-Verifikation, funktionierendes Stock-Backup und klare Warnungen. Das Street-Legal-Profil und der Hintergrund-Trigger sind geschäftskritisch. Tuned Bikes können im Straßenverkehr illegal sein — der Fahrer ist für die Einhaltung lokaler Vorschriften verantwortlich.
