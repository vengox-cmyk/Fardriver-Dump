# Phase 10: Qualitaet und Release

## Phasenziel

Version 1 wird anhand automatisierter Tests, realer Hardware, Android-Lifecycle,
Performance und Sicherheitsanforderungen abgenommen. Ein erfolgreicher Build
allein ist keine Releasefreigabe.

## T076 - Kernmodule auf mehr als 80 Prozent Coverage bringen

**Abhaengigkeiten:** T075  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Ermittle Coverage getrennt fuer Protokoll, Safety, Write Engine, Backup,
  Profile, Session und Reichweite.
- Schliesse Luecken mit Verhaltens-, Fehler- und Grenzwerttests; keine Tests nur
  fuer Zeilenabdeckung.
- Definiere nachvollziehbare Ausschluesse fuer generierten oder rein nativen Glue.

### Tests und Akzeptanz

- Jedes Kernmodul erreicht mehr als 80 Prozent Line Coverage.
- Kritische Safety-Entscheidungen und Fehlerpfade besitzen Branch-Tests.
- Coverage-Bericht ist reproduzierbar ueber Makefile/Docker.

## T077 - Widget-, Golden- und Accessibility-Tests ergaenzen

**Abhaengigkeiten:** T060, T075  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Teste Dashboard, Profile, Diff, Write-Fortschritt, Sessions, Fehler und
  Einstellungen in zentralen Zustaenden.
- Erstelle stabile Goldens fuer definierte kleine/grosse Displaygroessen und
  Rekuperation/Warning/Stale-Zustaende.
- Pruefe Semantics, Kontrast und grosse Textskalierung.

### Tests und Akzeptanz

- Goldens verwenden gebuendelte Fonts und feste Locale/Clock.
- Kritische Aktionen sind semantisch auffindbar und ausreichend gross.
- Keine Tests haengen von Netzwerk oder realer BLE-Hardware ab.

## T078 - Kritische Flutter-Integrationstests erstellen

**Abhaengigkeiten:** T076, T077  
**Hardware erforderlich:** Nein mit Fake-Transport

### Arbeitsumfang

- Teste Erststart/Permission-Fake, Verbindung, Telemetrie, Stock-Backup,
  Profil-CRUD, Profilanwendung, Teilfehler, Reconnect und Sessionabschluss.
- Nutze kontrollierte Fixtures und Fake Clock.
- Integriere den Lauf in Docker und Makefile.

### Tests und Akzeptanz

- Kritische Version-1-Flows laufen deterministisch in CI.
- Fehlerszenarien pruefen sichtbare deutsche Rueckmeldungen.
- Testdaten koennen keine echten BLE-Writes ausloesen.

## T079 - Android-Instrumentationstests erstellen

**Abhaengigkeiten:** T053  
**Hardware erforderlich:** Emulator, fuer BLE-Zusatztests reales Geraet

### Arbeitsumfang

- Teste Foreground-Service-Start, Notification Channel, Intent-Validierung,
  Doppeltrigger, Screen-off-Verhalten soweit automatisierbar und Service-Neustart.
- Teste, dass fremde Actions/Extras keine Parameterwahl erlauben.
- Dokumentiere Emulatorgrenzen fuer BLE und Doze.

### Tests und Akzeptanz

- Instrumentationstests laufen nicht-interaktiv auf mindestens einer CI-faehigen
  Android-API.
- Exported-Komponenten und Intent-Filter entsprechen dem Sicherheitsvertrag.
- Servicefehler liefern stabile Result-Codes.

## T080 - Hardware-in-the-loop-Matrix durchfuehren

**Abhaengigkeiten:** T016, T037, T053, T069, T079  
**Hardware erforderlich:** Ja

### Arbeitsumfang

- Fuehre den freigegebenen Testplan fuer Read, Backup, Einzelwrite, Read-back,
  Profil, Restore, Reconnect, Screen-off und MacroDroid aus.
- Teste mindestens die Zielhardware und dokumentierte Android-Versionen.
- Dokumentiere App-/Firmwareversion, Stockhash, erwartete/tatsaechliche Werte und
  Rueckkehr zum Ausgangszustand.

### Tests und Akzeptanz

- Kein offener kritischer Safety-, Backup- oder Street-Legal-Defekt.
- Jeder reale Write ist im Audit-Log und Testprotokoll nachvollziehbar.
- Abweichende Hardwarevarianten werden nicht als pauschal kompatibel beworben.

## T081 - Performance und Akkuverbrauch pruefen

**Abhaengigkeiten:** T069, T080  
**Hardware erforderlich:** Ja

### Arbeitsumfang

- Messe UI-Frametimes, CPU, Speicher, Log-/DB-Wachstum und Akkuverbrauch bei
  Dashboard, Screen-off-Service und Langzeit-Reconnect.
- Profiliere mindestens eine mehrstuendige simulierte oder kontrollierte Session.
- Behebe Leaks, unnoetige Rebuilds und Polling mit Regressionstests.

### Tests und Akzeptanz

- Keine unbeschraenkt wachsenden Puffer, Logs oder Subscriptions.
- Dashboard bleibt auf Zielgeraeten fluessig.
- Gemessener Hintergrundverbrauch und Testbedingungen sind dokumentiert.

## T082 - Release-Sicherheit fertigstellen

**Abhaengigkeiten:** T080, T081  
**Hardware erforderlich:** Nein

### Arbeitsumfang

- Richte Release-Signing ueber nicht versionierte Secrets/Properties ein; niemals
  Schluessel ins Repository aufnehmen.
- Pruefe Manifest, Exporte, Backups, Logs, Dateifreigaben, Permissions und
  Abhaengigkeiten auf Sicherheits-/Datenschutzrisiken.
- Erstelle Datenschutzhinweise, Permission-Rationales, Tuning-/Rechtsdisclaimer
  und sichere Recovery-Anleitung.

### Tests und Akzeptanz

- Release-Build verwendet keinen Debug-Key.
- Repository enthaelt keine Secrets oder personenbezogenen Hardwarefixtures.
- `apkanalyzer`/Manifest-Pruefung zeigt nur notwendige exportierte Komponenten
  und Permissions.

## T083 - CI und Version-1-Abnahme einrichten

**Abhaengigkeiten:** T076 bis T082  
**Hardware erforderlich:** Ergebnisse aus T080

### Arbeitsumfang

- Richte CI fuer Format, Analyse, Unit/Widget/Integration, Coverage und
  Debug-/Release-Build ohne Signing-Secrets ein.
- Erstelle eine Abnahmematrix aus `plan/anforderungsmatrix.md` mit automatischem
  oder manuellem Nachweis je Requirement.
- Erstelle reproduzierbare Release-Checkliste, Versionierung und Changelog.

### Tests und Akzeptanz

- Frischer CI-Lauf ist vollstaendig gruen.
- Jede Version-1-Anforderung besitzt einen bestandenen Nachweis oder ist
  ausdruecklich als Releaseblocker markiert.
- Street Legal, Stock-Restore und Background-Trigger haben reale manuelle
  Abnahmeprotokolle.

## Phasen-Gate

Version 1 ist erst freigegeben, wenn alle kritischen Requirements nachgewiesen,
CI gruen und Hardwaretests ohne offenen kritischen Defekt abgeschlossen sind.
