/// v1.4: a write is no longer just "ok" or "failed". Controllers can accept
/// some fields and silently keep others (e.g. CONTROLDM309 keeps its
/// over-voltage values), so each write is ok / partial / failed and each
/// field says what actually happened.
enum WriteOutcome {
  /// Every field was saved and read back.
  ok,

  /// Some fields were saved and verified, others were not.
  partial,

  /// Nothing was verified.
  failed;

  String get label => name;

  static WriteOutcome? parse(String? s) {
    for (final v in values) {
      if (v.name == s?.trim()) return v;
    }
    return null;
  }
}

/// What happened to one field, in plain words.
enum FieldOutcome {
  saved('saved'),

  /// Sent, but the controller kept its old value.
  rejectedUnchanged('rejected (unchanged)'),

  /// Sent, but the controller reports a third value.
  rejectedOther('rejected (different value)'),
  notConfirmed('not confirmed (no read-back)'),
  notSent('not sent');

  const FieldOutcome(this.text);
  final String text;

  bool get verified => this == saved;
}

/// Shared by live results and decoded logs.
class WriteSummary {
  WriteSummary._();

  static WriteOutcome outcomeOf(Iterable<FieldOutcome> fields,
      {bool stoppedEarly = false}) {
    final list = fields.toList();
    final good = list.where((f) => f.verified).length;
    if (list.isNotEmpty && good == list.length && !stoppedEarly) {
      return WriteOutcome.ok;
    }
    return good > 0 ? WriteOutcome.partial : WriteOutcome.failed;
  }

  /// "Low voltage protect saved, Over voltage protect rejected (unchanged)".
  static String message(Iterable<(String label, FieldOutcome outcome)> rows) {
    final parts = [for (final (l, o) in rows) '$l ${o.text}'];
    if (parts.isEmpty) return 'Nothing was changed';
    final s = parts.join(', ');
    return s[0].toUpperCase() + s.substring(1);
  }
}
