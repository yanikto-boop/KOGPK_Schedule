import 'package:flutter/services.dart';

/// Мост к нативному Android-коду (установка APK, закрепление виджетов).
class Native {
  static const _ch = MethodChannel('com.kogpk.schedule/native');

  static Future<void> installApk(String path) =>
      _ch.invokeMethod('installApk', {'path': path});

  static Future<bool> canPinWidget() async {
    try {
      return await _ch.invokeMethod<bool>('canPinWidget') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// which: 'small' (2×2) или 'wide' (4×2)
  static Future<bool> pinWidget(String which) async {
    try {
      return await _ch.invokeMethod<bool>('pinWidget', {'which': which}) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
