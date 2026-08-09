import 'dart:convert';

enum DiagnosticEventType {
  scan,
  connect,
  frame,
  parserError,
  command,
  safety,
  reconnect,
}

class DiagnosticEvent {
  final DateTime timestamp;
  final DiagnosticEventType type;
  final Map<String, Object?> details;

  const DiagnosticEvent({
    required this.timestamp,
    required this.type,
    required this.details,
  });

  Map<String, Object?> toJson() => {
        'timestamp': timestamp.toUtc().toIso8601String(),
        'type': type.name,
        'details': details,
      };
}

typedef DiagnosticClock = DateTime Function();

class DiagnosticLog {
  final int maxEvents;
  final DiagnosticClock _clock;
  final List<DiagnosticEvent> _events = [];

  DiagnosticLog({this.maxEvents = 1000, DiagnosticClock clock = DateTime.now})
      : _clock = clock {
    if (maxEvents < 1) throw ArgumentError.value(maxEvents, 'maxEvents');
  }

  List<DiagnosticEvent> get events => List.unmodifiable(_events);

  void add(
    DiagnosticEventType type, {
    Map<String, Object?> details = const {},
  }) {
    _events.add(DiagnosticEvent(
      timestamp: _clock(),
      type: type,
      details: details,
    ));
    if (_events.length > maxEvents) _events.removeAt(0);
  }

  String exportJson() => jsonEncode({
        'format': 'arcdash-diagnostics-v1',
        'events': _events
            .map((event) => DiagnosticEvent(
                  timestamp: event.timestamp,
                  type: event.type,
                  details: _redactMap(event.details),
                ).toJson())
            .toList(),
      });

  String exportAsText({bool redact = false}) {
    final buffer = StringBuffer();
    buffer.writeln('=== ArcDash Diagnose-Log ===');
    buffer.writeln('Exportiert: ${DateTime.now().toUtc().toIso8601String()}');
    buffer.writeln('Anzahl Events: ${_events.length}');
    buffer.writeln('========================================\n');
    for (final event in _events) {
      final ts = event.timestamp.toUtc().toIso8601String();
      final typeStr = event.type.name.toUpperCase().padRight(10);
      final detailsMap = redact ? _redactMap(event.details) : event.details;
      final detailsStr =
          detailsMap.entries.map((e) => '${e.key}: ${e.value}').join(' | ');
      buffer.writeln('[$ts] $typeStr $detailsStr');
    }
    return buffer.toString();
  }

  static Map<String, Object?> _redactMap(Map<String, Object?> values) =>
      values.map((key, value) => MapEntry(key, _redactValue(key, value)));

  static Object? _redactValue(String key, Object? value) {
    final normalized = key.toLowerCase();
    if (normalized.contains('address') ||
        normalized.contains('mac') ||
        normalized.contains('serial') ||
        normalized.contains('remoteid') ||
        normalized == 'deviceid' ||
        normalized == 'parameter' ||
        normalized == 'value') {
      return '<redacted>';
    }
    if (value is Map<String, Object?>) return _redactMap(value);
    if (value is Map) {
      return _redactMap(value.map((k, v) => MapEntry(k.toString(), v)));
    }
    if (value is Iterable) {
      return value.map((item) => _redactValue('', item)).toList();
    }
    return value;
  }
}
