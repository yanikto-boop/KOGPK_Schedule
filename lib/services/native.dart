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

  /// which: 'small' (2×2), 'wide' (4×2), 'bus',
  /// 'countdown_small' (таймер 2×1) или 'countdown_medium' (таймер 2×2)
  static Future<bool> pinWidget(String which) async {
    try {
      return await _ch.invokeMethod<bool>('pinWidget', {'which': which}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Можно ли ставить точные будильники (на Android 12+ это разрешение
  /// пользователь выдаёт вручную). Без него таймер сменит стадию с опозданием.
  static Future<bool> exactAlarmAllowed() async {
    try {
      return await _ch.invokeMethod<bool>('exactAlarmAllowed') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Открывает системную настройку «Будильники и напоминания».
  static Future<bool> requestExactAlarm() async {
    try {
      return await _ch.invokeMethod<bool>('requestExactAlarm') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> countdownWidgetsPlaced() async {
    try {
      return await _ch.invokeMethod<bool>('countdownWidgetsPlaced') ?? false;
    } catch (_) {
      return false;
    }
  }
}
