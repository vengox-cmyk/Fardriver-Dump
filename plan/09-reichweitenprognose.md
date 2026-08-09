# Phase 8: Reichweitenprognose

## Phasenziel

Die Reichweite basiert auf gemessener Energie, belastbarem SOC, GPS-Distanz und
gelerntem Fahrverhalten. Jede Prognose enthaelt eine nachvollziehbare
Unsicherheit und degradiert kontrolliert bei schlechten Daten.

## T061 - Reichweiten-Domainmodell definieren

**Abhaengigkeiten:** T002, T024, T055  
**Hardware erforderlich:** Hardwareprofil

### Arbeitsumfang

- Definiere Batterieparameter, Messsamples, Energiezustand, Fahrzyklus,
  Verbrauchsmodell, Prognose und Confidence als UI-unabhaengige Modelle.
- Definiere Vorzeichen fuer Verbrauch/Rekuperation und SI-Einheiten.
- Fuehre eine monotone Zeitabstraktion fuer Integrationen ein.

### Tests und Akzeptanz

- Modelle lehnen unmoegliche Kapazitaeten und nicht-finite Werte ab.
- Uhrzeitwechsel beeinflusst Integration nicht.
- Formeln und Annahmen sind mit Quellen dokumentiert.

## T062 - GPS-Distanz filtern

**Abhaengigkeiten:** T056, T061  
**Hardware erforderlich:** Nein fuer Simulation

### Arbeitsumfang

- Berechne Distanz nur aus ausreichend genauen, frischen Punkten.
- Filtere Drift im Stillstand, Teleports, unplausible Geschwindigkeit und
  schlechte Accuracy.
- Fuehre akzeptierte und verworfene Distanz samt Qualitaetsmetrik.

### Tests und Akzeptanz

- Aufgezeichnete synthetische Tracks decken Stillstand, Tunnel, Sprung und
  normalen Fahrverlauf ab.
- Distanz ist monoton und wird bei GPS-Ausfall nicht erfunden.
- Filterparameter sind begruendet und zentral konfiguriert.

## T063 - Energie und Ladung integrieren

**Abhaengigkeiten:** T061  
**Hardware erforderlich:** Nein fuer Simulation

### Arbeitsumfang

- Integriere Strom ueber Zeit fuer Ah sowie Spannung mal Strom fuer Wh.
- Behandle unregelmaessige Sampleabstaende, Luecken, Rekuperation und
  Sensoroffsets.
- Trenne entnommene, rekuperierte und netto Energie.

### Tests und Akzeptanz

- Konstante und stueckweise Signale stimmen innerhalb definierter Toleranz mit
  analytischen Ergebnissen ueberein.
- Zu grosse Datenluecken werden nicht ueberbrueckt und senken Confidence.
- Positive/negative Vorzeichen sind mit Fixtures abgesichert.

## T064 - Spannungsbasierten SOC-Filter bauen

**Abhaengigkeiten:** T002, T061, T063  
**Hardware erforderlich:** Batteriedaten fuer Kalibrierung

### Arbeitsumfang

- Hinterlege eine versionierte OCV/SOC-Kurve passend zur bestaetigten
  Batteriechemie statt einer universellen linearen Spannungskurve.
- Korrigiere Last-/Rekuperationseinfluss konservativ und gewichte Spannung bei
  Ruhe staerker als unter hoher Last.
- Kombiniere Coulomb Counting und OCV in einem nachvollziehbaren
  Komplementaerfilter.

### Tests und Akzeptanz

- SOC bleibt in 0 bis 100 Prozent und reagiert nicht sprunghaft auf Voltage Sag.
- Falsche/fehlende Batteriechemie liefert geringe Confidence statt Scheingenauigkeit.
- Ruhe-, Last- und Rekuperationsszenarien sind getestet.

## T065 - Nutzbare Kapazitaet lernen

**Abhaengigkeiten:** T063, T064  
**Hardware erforderlich:** Spaeter reale Ladezyklen

### Arbeitsumfang

- Erkenne hinreichend volle Lade- und tiefe Entladepunkte konservativ.
- Aktualisiere nutzbare Kapazitaet nur aus qualifizierten Zyklen und mit
  begrenzter Lernrate.
- Verwerfe Teilzyklen, Datenluecken und physikalisch unplausible Ergebnisse.

### Tests und Akzeptanz

- Simulationen zeigen Konvergenz nach mehreren guten Zyklen.
- Einzelne Ausreisser koennen Kapazitaet nicht stark veraendern.
- Nutzer kann Lernstand sehen und kontrolliert zuruecksetzen.

## T066 - Verbrauchsfenster und Fahrstil modellieren

**Abhaengigkeiten:** T062, T063  
**Hardware erforderlich:** Nein fuer Simulation

### Arbeitsumfang

- Berechne Wh/km nur fuer Distanzsegmente mit ausreichender GPS- und
  Energiedatenqualitaet.
- Fuehre kurze und laengere gleitende Fenster und gewichte aktuellen Fahrstil,
  ohne die Langzeithistorie sofort zu vergessen.
- Behandle Stop-and-go und Rekuperation explizit.

### Tests und Akzeptanz

- Keine Division durch sehr kleine Distanz und keine unendlichen Werte.
- Wechsel zwischen Eco- und aggressivem Fahrstil passt Prognose kontrolliert an.
- Fenster bleiben speicherbegrenzt.

## T067 - Unsicherheitsintervall berechnen

**Abhaengigkeiten:** T064 bis T066  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Leite Restenergie und Reichweite aus SOC, gelernter Kapazitaet und Verbrauch ab.
- Berechne Unsicherheit aus SOC-, Kapazitaets-, Verbrauchs- und Datenqualitaet
  statt eines festen Prozentwerts.
- Definiere Fallbacks fuer neue Installation und zu wenig Fahrdaten.

### Tests und Akzeptanz

- Wenige/schlechte Daten erzeugen sichtbar breitere Intervalle.
- Mehrere konsistente Zyklen reduzieren Unsicherheit begrenzt.
- Ergebnis ist endlich, nicht negativ und erklaerbar.

## T068 - Lernzustand persistieren

**Abhaengigkeiten:** T024, T065 bis T067  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Speichere Filter-, Kapazitaets- und Verbrauchszustand transaktional,
  schema-versioniert und an Batterie/Controller gebunden.
- Drossele Schreibfrequenz und sichere bei Sessionende.
- Implementiere Migration, Korruptionserkennung und kontrollierten Reset.

### Tests und Akzeptanz

- Neustart setzt eine Simulation ohne Sprung fort.
- Fremde Batterie-/Controlleridentitaet uebernimmt keinen Lernzustand.
- Korruptes oder neues Schema startet konservativ neu und bleibt diagnostizierbar.

## T069 - Simulation und Dashboard-Integration abschliessen

**Abhaengigkeiten:** T058, T062 bis T068
**Hardware erforderlich:** Reale Fahrdaten fuer finale Abnahme

### Arbeitsumfang

- Erstelle reproduzierbare Fahrfixture-Simulationen fuer Laden, Stadt, konstant,
  sportlich, GPS-Ausfall und Rekuperation.
- Zeige Reichweite als `km +/- km`, Confidence/Lernstatus und sinnvolle
  Startfallbacks im Dashboard.
- Vergleiche Prognose spaeter gegen reale Fahrten und dokumentiere Fehlermaasse.

### Tests und Akzeptanz

- Simulationen sind deterministisch und laufen in der normalen Testsuite.
- Dashboard behauptet ohne Daten keine hohe Genauigkeit.
- Nach 2 bis 3 qualifizierten Zyklen ist eine messbare Verbesserung dokumentiert.

## Phasen-Gate

Die Prognose ist offline, reproduzierbar und mit Unsicherheit versehen. Schlechte
GPS- oder Telemetriedaten verschlechtern Confidence statt Werte zu erfinden.
