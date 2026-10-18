import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import 'native.dart';

/// Просит разрешение на точные будильники, когда на рабочем столе есть
/// виджет-таймер. Без разрешения виджет всё равно работает, но стадия
/// («до конца половины» → «перерыв») может смениться на минуту-другую позже.
class ExactAlarmPrompt {
  static const _askedAtKey = 'exact_alarm_asked_at';
  static const _cooldown = Duration(days: 3);
  static bool _showing = false;

  static Future<void> maybeAsk(BuildContext context) async {
    if (_showing) return;
    if (await Native.exactAlarmAllowed()) return;
    if (!await Native.countdownWidgetsPlaced()) return;

    final prefs = await SharedPreferences.getInstance();
    final askedAt = prefs.getInt(_askedAtKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - askedAt < _cooldown.inMilliseconds) return;
    await prefs.setInt(_askedAtKey, now);

    if (!context.mounted) return;
    _showing = true;
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Точный таймер в виджете'),
          content: const Text(
              'Чтобы виджет переключался ровно по звонку — с «до конца '
              'половины» на «перерыв» и дальше, — разреши приложению '
              'будильники и напоминания.\n\n'
              'Без этого таймер всё равно работает, но смена может '
              'запаздывать на минуту-другую.',
              style: TextStyle(color: AppColors.textDim, height: 1.35)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Не сейчас')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Разрешить')),
          ],
        ),
      );
      if (ok == true) await Native.requestExactAlarm();
    } finally {
      _showing = false;
    }
  }
}
