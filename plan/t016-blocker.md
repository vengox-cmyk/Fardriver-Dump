# T016 Blocker

Status: **BLOCKIERT**  
Stand: `2026-08-02`

T016 kann ohne freigegebene Hardwaredaten nicht abgenommen werden. Es fehlen:

- ein anonymisiertes Write-Capture mit konkretem Controller-Modell und Firmware,
- die zugehörige Antwort, deren Bedeutung als ACK oder Echo bewiesen ist,
- ein Read-back desselben Parameters nach einer einzeln freigegebenen harmlosen Änderung,
- ein originales vollständiges HEB-/Stock-Backup mit Layout, Metadaten und Checksumme,
- ein reproduzierter Persistenz-/Save-Nachweis.

Die App korreliert in Fake-Tests CRC, Adresse und erwarteten Rohwert. Das ist
keine Controllerfreigabe. Insbesondere wird `0xA0 / 0x88 0x01` weiterhin nicht
als Speicherbefehl interpretiert. Reale Writes bleiben gesperrt; der Blocker
wird erst nach manueller Fahrzeugeigentuemerfreigabe und Read-back-Nachweis
entfernt.
