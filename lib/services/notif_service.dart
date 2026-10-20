import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../api.dart';
import 'profile.dart';

const _taskName = 'kogpk_changes_check';
const _channelId = 'schedule_changes';
const _channelName = 'Изменения расписания';
const _prefNotifiedTs = 'changes_notified_ts';
const _prefEnabled = 'notif_changes';

/// Точка входа фоновой задачи (workmanager, отдельный изолят).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await NotifService.checkChangesBackground();
    } catch (_) {}
    return true;
  });
}

class NotifService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Инициализация в foreground + регистрация фоновой задачи.
  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: const Duration(hours: 1),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<bool> enabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabled) ?? true;
  }

  static Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, v);
  }

  static Future<void> _show(String title, String body) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId, _channelName,
        channelDescription: 'Уведомления об изменениях в расписании',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000, title, body, details);
  }

  /// Смена режима: у новой ленты своя история — первый проход только запомнит.
  static Future<void> resetSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefNotifiedTs);
  }

  /// Помечает текущие изменения как просмотренные (вызывается из экрана).
  static Future<void> markSeen(String newestTs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefNotifiedTs, newestTs);
  }

  /// Проверка из фоновой задачи: новые изменения → локальное уведомление.
  static Future<void> checkChangesBackground() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_prefEnabled) ?? true)) return;
    final teacher = await Profile.teacher();
    final group = prefs.getString('group');
    if (teacher == null && (group == null || group.isEmpty)) return;

    final changes = teacher != null
        ? await Api.teacherChanges(teacher)
        : await Api.changes(group!);
    if (changes.isEmpty) return;
    final newest = changes.first.ts;
    final last = prefs.getString(_prefNotifiedTs) ?? '';

    // первый запуск — просто запоминаем, без уведомления
    if (last.isEmpty) {
      await prefs.setString(_prefNotifiedTs, newest);
      return;
    }
    if (newest.compareTo(last) > 0) {
      final n = changes.where((c) => c.ts.compareTo(last) > 0).length;
      // инициализация плагина в фоновом изоляте
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin
          .initialize(const InitializationSettings(android: android));
      await _show(
        teacher != null
            ? 'Изменения в вашем расписании'
            : 'Изменения в расписании · $group',
        n > 1
            ? 'Найдено изменений: $n. Открой «Изменения», чтобы посмотреть.'
            : 'В расписании появились изменения. Открой «Изменения».',
      );
      await prefs.setString(_prefNotifiedTs, newest);
    }
  }
}
