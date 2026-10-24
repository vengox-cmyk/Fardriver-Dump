import 'package:flutter/services.dart';

/// Keeps the display on during a calibration ride (Android
/// FLAG_KEEP_SCREEN_ON on the activity window; no extra permission).
class ScreenAwake {
  static const _channel = MethodChannel('com.arcdash.arcdash/service');

  const ScreenAwake();

  Future<void> set(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepScreenOn', {'on': on});
    } on MissingPluginException {
      // Tests / non-Android hosts.
    } on PlatformException {
      // Best effort only.
    }
  }
}
