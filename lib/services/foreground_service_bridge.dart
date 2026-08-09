import 'dart:convert';

import 'package:flutter/services.dart';

enum ServiceMessageType { status, streetLegalRequest, result, error }

class ServiceMessage {
  final int version;
  final ServiceMessageType type;
  final String? code;
  final Map<String, Object?> data;

  const ServiceMessage({
    this.version = 1,
    required this.type,
    this.code,
    this.data = const {},
  });

  Map<String, Object?> toJson() => {
        'version': version,
        'type': type.name,
        if (code != null) 'code': code,
        'data': data,
      };

  String encode() => jsonEncode(toJson());

  factory ServiceMessage.decode(Object? value) {
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['type'] is! String) {
      throw const FormatException('invalid service message');
    }
    final type =
        ServiceMessageType.values.where((item) => item.name == decoded['type']);
    if (type.length != 1 || decoded['data'] is! Map) {
      throw const FormatException('unknown service message');
    }
    return ServiceMessage(
      type: type.single,
      code: decoded['code'] as String?,
      data: Map<String, Object?>.from(decoded['data'] as Map),
    );
  }
}

class ForegroundServiceBridge {
  static const _channel = MethodChannel('com.arcdash.arcdash/service');

  const ForegroundServiceBridge();

  Future<void> start() => _channel.invokeMethod<void>('start');
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
