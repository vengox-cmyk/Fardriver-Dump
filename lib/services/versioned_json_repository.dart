import 'dart:convert';
import 'dart:io';

class VersionedDocument {
  final String type;
  final int schemaVersion;
  final Map<String, Object?> payload;

  const VersionedDocument({
    required this.type,
    required this.schemaVersion,
    required this.payload,
  });

  Map<String, Object?> toJson() => {
        'type': type,
        'schemaVersion': schemaVersion,
        'payload': payload,
      };

  factory VersionedDocument.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    if (json['type'] is! String ||
        json['schemaVersion'] is! int ||
        payload is! Map) {
      throw const FormatException('invalid versioned document');
    }
    return VersionedDocument(
      type: json['type'] as String,
      schemaVersion: json['schemaVersion'] as int,
      payload: payload.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}

abstract interface class AtomicJsonStore {
  Future<String?> read();
  Future<void> replace(String contents);
}

class AtomicJsonFileStore implements AtomicJsonStore {
  final File file;

  const AtomicJsonFileStore(this.file);

  @override
  Future<String?> read() async {
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> replace(String contents) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(file.path);
  }
}

class VersionedJsonRepository {
  final AtomicJsonStore _store;
  final String type;
  final int schemaVersion;

  const VersionedJsonRepository({
    required AtomicJsonStore store,
    required this.type,
    required this.schemaVersion,
  }) : _store = store;

  Future<void> save(Map<String, Object?> payload) async {
    final document = VersionedDocument(
      type: type,
      schemaVersion: schemaVersion,
      payload: payload,
    );
    await _store.replace(jsonEncode(document.toJson()));
  }

  Future<Map<String, Object?>?> load() async {
    final contents = await _store.read();
    if (contents == null) return null;
    final decoded = jsonDecode(contents);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('document must be a JSON object');
    }
    final document = VersionedDocument.fromJson(decoded);
    if (document.type != type || document.schemaVersion != schemaVersion) {
      throw const FormatException('unsupported document version or type');
    }
    return document.payload;
  }
}
