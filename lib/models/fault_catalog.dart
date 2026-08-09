enum FaultSeverity { warning, error, critical, unknown }

class FaultDefinition {
  final int bitIndex;
  final String rawCode;
  final String titleGerman;
  final String descriptionGerman;
  final FaultSeverity severity;
  final String safetyGuidelineGerman;

  const FaultDefinition({
    required this.bitIndex,
    required this.rawCode,
    required this.titleGerman,
    required this.descriptionGerman,
    required this.severity,
    required this.safetyGuidelineGerman,
  });
}

class FaultCatalog {
  const FaultCatalog();

  static const Map<int, FaultDefinition> _knownFaults = {
    0: FaultDefinition(
      bitIndex: 0,
      rawCode: '0x00000001',
      titleGerman: 'Motor Hall-Sensor Fehler',
      descriptionGerman: 'Störung bei der Erfassung der Motorposition.',
      severity: FaultSeverity.error,
      safetyGuidelineGerman:
          'Motor anhalten und Hall-Sensor Verkabelung prüfen.',
    ),
    1: FaultDefinition(
      bitIndex: 1,
      rawCode: '0x00000002',
      titleGerman: 'Gasgriff (Throttle) Fehler',
      descriptionGerman:
          'Gasgriff-Signal außerhalb des zulässigen Spannungsbereichs.',
      severity: FaultSeverity.error,
      safetyGuidelineGerman:
          'Gasgriff loslassen. Falls der Fehler bestehen bleibt, Verbindung trennen.',
    ),
    6: FaultDefinition(
      bitIndex: 6,
      rawCode: '0x00000040',
      titleGerman: 'Motor Übertemperatur-Schutz',
      descriptionGerman: 'Motortemperatur hat die Warnschwelle überschritten.',
      severity: FaultSeverity.warning,
      safetyGuidelineGerman:
          'Leistung reduzieren oder Fahrzeug abkühlen lassen.',
    ),
    7: FaultDefinition(
      bitIndex: 7,
      rawCode: '0x00000080',
      titleGerman: 'Controller Übertemperatur-Schutz',
      descriptionGerman: 'MOSFET-/Controller-Temperatur ist kritisch hoch.',
      severity: FaultSeverity.warning,
      safetyGuidelineGerman:
          'Fahrt unterbrechen und Controller abkühlen lassen.',
    ),
  };

  FaultDefinition lookupBit({required int bitIndex}) {
    if (_knownFaults.containsKey(bitIndex)) {
      return _knownFaults[bitIndex]!;
    }
    final rawHex =
        '0x${(1 << bitIndex).toRadixString(16).padLeft(8, '0').toUpperCase()}';
    return FaultDefinition(
      bitIndex: bitIndex,
      rawCode: rawHex,
      titleGerman: 'Unbekannter Fehlercode ($rawHex)',
      descriptionGerman:
          'Ein nicht definierter Systemfehler wurde vom Controller gemeldet.',
      severity: FaultSeverity.unknown,
      safetyGuidelineGerman:
          'Diagnosecode $rawHex notieren und Fachpersonal kontaktieren.',
    );
  }

  List<FaultDefinition> parseMask(int mask) {
    final list = <FaultDefinition>[];
    for (int i = 0; i < 32; i++) {
      if ((mask & (1 << i)) != 0) {
        list.add(lookupBit(bitIndex: i));
      }
    }
    return list;
  }
}
