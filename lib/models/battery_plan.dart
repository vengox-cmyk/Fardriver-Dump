import 'package:arcdash/services/write/write_allowlist.dart';

/// Battery protect suggestions per chemistry (issue §4). Suggestions only:
/// the rider reviews every value before anything is written.
///
/// Per-cell limits are conservative manufacturer / Battery University
/// figures (BU-205 "Types of Lithium-ion", BU-808 / cell datasheets):
///   NMC     charge max 4.20 V, discharge min 2.5–3.0 V
///   LiFePO4 charge max 3.65 V, discharge min 2.5 V
///   LTO     charge max 2.80–2.85 V, discharge min 1.5–1.8 V
enum Chemistry {
  nmc('NMC (Li-ion)', 3.6, 4.20, 4.25, 4.15, 4.30, 3.00, 2.80, 3.40),
  lifepo4('LiFePO4', 3.2, 3.65, 3.70, 3.55, 3.75, 2.80, 2.50, 3.10),
  lto('LTO', 2.3, 2.80, 2.85, 2.70, 2.90, 1.80, 1.50, 2.10);

  const Chemistry(this.label, this.nominal, this.chargeMax, this.overSuggest,
      this.overMin, this.overMax, this.lowSuggest, this.lowMin, this.lowMax);

  final String label;
  final double nominal;
  final double chargeMax;

  /// Over-voltage protect per cell: suggestion and the allowed window.
  final double overSuggest;
  final double overMin;
  final double overMax;

  /// Low-voltage protect per cell: suggestion and the allowed window.
  final double lowSuggest;
  final double lowMin;
  final double lowMax;
}

class BatteryPlan {
  final Chemistry chemistry;
  final int cells; // S
  final int capacityAh;

  const BatteryPlan(this.chemistry, this.cells, this.capacityAh);

  static const minCells = 3;
  static const maxCells = 40;

  /// Over-voltage restore sits this far (per cell) below protect.
  static const restoreGapPerCell = 0.05;

  double get nominalV => chemistry.nominal * cells;
  double get fullV => chemistry.chargeMax * cells;

  /// Suggested values in volts (0.1 V steps, as the controller stores).
  double get overProtectV => _round(chemistry.overSuggest * cells);
  double get overRestoreV =>
      _round((chemistry.overSuggest - restoreGapPerCell) * cells);
  double get lowProtectV => _round(chemistry.lowSuggest * cells);

  /// Raw (×0.1 V) values for the allowlisted fields. v1.4: over voltage
  /// protect/restore are read-only on the controller, so they are never
  /// included, whatever [includeOverVoltage] or the Experimental toggle say
  /// (the flag is kept for callers/tests and only honoured if a future
  /// allowlist makes the fields writable again).
  Map<String, int> suggestedRaw({bool includeOverVoltage = false}) => {
        'LowVolProtect': (lowProtectV * 10).round(),
        'BattRatedCap': capacityAh,
        if (includeOverVoltage &&
            !(WriteAllowlist.byKey('HighVolProtect')?.readOnly ?? true))
          'HighVolProtect': (overProtectV * 10).round(),
        if (includeOverVoltage &&
            !(WriteAllowlist.byKey('HighVolRestore')?.readOnly ?? true))
          'HighVolRestore': (overRestoreV * 10).round(),
      };

  /// The math shown under the suggestions.
  List<String> get math => [
        '${chemistry.label}, ${cells}S: nominal '
            '${nominalV.toStringAsFixed(1)} V, full '
            '${fullV.toStringAsFixed(1)} V (${chemistry.chargeMax} V × $cells)',
        'Low voltage protect: ${chemistry.lowSuggest} V × $cells = '
            '${lowProtectV.toStringAsFixed(1)} V '
            '(restore is set by the controller at +2 V)',
        'Over voltage protect: ${chemistry.overSuggest} V × $cells = '
            '${overProtectV.toStringAsFixed(1)} V (reference only, not written)',
        'Over voltage restore: ${(chemistry.overSuggest - restoreGapPerCell).toStringAsFixed(2)} V × $cells = '
            '${overRestoreV.toStringAsFixed(1)} V (reference only, not written)',
        'Capacity: $capacityAh Ah',
      ];

  /// Null when [raw] is inside the chemistry's safe window, otherwise why
  /// not. Raw keys as in [suggestedRaw].
  String? refusal(Map<String, int> raw) {
    if (cells < minCells || cells > maxCells) {
      return 'Cell count must be $minCells–$maxCells S.';
    }
    if (capacityAh < 20 || capacityAh > 250) {
      return 'Capacity must be 20–250 Ah (controller limit).';
    }
    String? window(String key, double min, double max) {
      final v = raw[key];
      if (v == null) return null;
      final perCell = v / 10.0 / cells;
      if (perCell < min - 1e-9 || perCell > max + 1e-9) {
        return '$key ${(v / 10).toStringAsFixed(1)} V is '
            '${perCell.toStringAsFixed(2)} V per cell; ${chemistry.label} '
            'must stay within $min–$max V per cell.';
      }
      return null;
    }

    return window('LowVolProtect', chemistry.lowMin, chemistry.lowMax) ??
        window('HighVolProtect', chemistry.overMin, chemistry.overMax) ??
        window('HighVolRestore', chemistry.overMin - restoreGapPerCell * 2,
            chemistry.overMax) ??
        _order(raw);
  }

  String? _order(Map<String, int> raw) {
    final p = raw['HighVolProtect'];
    final r = raw['HighVolRestore'];
    if (p != null && r != null && r >= p) {
      return 'Over voltage restore must be below protect.';
    }
    final low = raw['LowVolProtect'];
    if (p != null && low != null && low >= p) {
      return 'Low voltage protect must be below over voltage protect.';
    }
    return null;
  }

  static double _round(double v) => (v * 10).round() / 10;
}
