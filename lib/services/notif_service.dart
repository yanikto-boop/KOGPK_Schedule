import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../api.dart';
import 'profile.dart';
import 'widget_service.dart';
import '../screens/changes_screen.dart';
import '../games/games_api.dart';

const _taskName = 'kogpk_changes_check';
const _channelId = 'schedule_changes';
const _channelName = 'Изменения расписания';
const _prefNotifiedTs = 'changes_notified_ts';
const _prefEnabled = 'notif_changes';
const _prefSeenTs = 'changes_seen_ts';

/// Точка входа фоновой задачи (workmanager, отдельный изолят).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await NotifService.checkChangesBackground();
    } catch (_) {}
    try {
      await NotifService.refreshWidgetsBackground();
    } catch (_) {}
    await GamesApi.flushBb(); // рекорд, набранный без сети
    return true;
  });
}

class NotifService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Навигатор приложения — чтобы тап по уведомлению открыл «Изменения».
  static final navKey = GlobalKey<NavigatorState>();

  static void _openChanges() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const ChangesScreen()));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Инициализация в foreground + регистрация фоновой задачи.
  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android),
        onDidReceiveNotificationResponse: (_) => _openChanges());
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) _openChanges();
    } catch (_) {}
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
    // один и тот же id: новое уведомление заменяет прежнее, а не копится
    await _plugin.show(1001, title, body, details, payload: 'changes');
  }

  /// Смена режима: у новой ленты своя история — первый проход только запомнит.
  static Future<void> resetSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefNotifiedTs);
    await prefs.remove(_prefSeenTs);
    unread.value = false;
  }

  /// Есть изменения, которые пользователь ещё не открывал (точка на колокольчике).
  static final unread = ValueNotifier<bool>(false);

  /// Сверяет ленту с последним просмотром; вызывается с Главной.
  static Future<void> refreshUnread() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final teacher = await Profile.teacher();
      final group = prefs.getString('group');
      if (teacher == null && (group == null || group.isEmpty)) {
        unread.value = false;
        return;
      }
      final changes = teacher != null
          ? await Api.teacherChanges(teacher)
          : await Api.changes(group!);
      if (changes.isEmpty) {
        unread.value = false;
        return;
      }
      final seen = prefs.getString(_prefSeenTs);
      if (seen == null) {
        // первый запуск / новая группа: старое непрочитанным не считаем
        await prefs.setString(_prefSeenTs, changes.first.ts);
        unread.value = false;
        return;
      }
      unread.value = changes.first.ts.compareTo(seen) > 0;
    } catch (_) {}
  }

  /// «четверг 12.11, суббота 14.11» — дни, которых касаются [changes].
  /// Прошедшие дни пропускаются; пусто — упоминать нечего.
  static String daysSummary(Iterable<ScheduleChange> changes, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final days = <DateTime, String>{};
    for (final c in changes) {
      final d = c.day;
      if (d == null || d.isBefore(today)) continue;
      days.putIfAbsent(d, () => c.weekday);
    }
    final sorted = days.keys.toList()..sort();
    String two(int v) => v.toString().padLeft(2, '0');
    return sorted.map((d) {
      final wd = days[d]!;
      final dm = '${two(d.day)}.${two(d.month)}';
      return wd.isEmpty ? dm : '$wd $dm';
    }).join(', ');
  }

  /// Фон: перекачать расписание и перерисовать виджеты, чтобы они не
  /// зависели от того, открывали ли приложение.
  static Future<void> refreshWidgetsBackground() async {
    final r = await Profile.loadSchedule();
    if (r == null) return;
    await WidgetService.update(r.data, r.label, fresh: !Api.offline.value);
  }

  /// Помечает текущие изменения как просмотренные (вызывается из экрана).
  static Future<void> markSeen(String newestTs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefNotifiedTs, newestTs);
    await prefs.setString(_prefSeenTs, newestTs);
    unread.value = false;
  }

  /// Проверка из фоновой задачи: новые изменения → локальное уведомление.
  static Future<void> checkChangesBackground() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // фоновый изолят: настройки могли поменять в приложении
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
      final fresh = changes.where((c) => c.ts.compareTo(last) > 0);
      final days = daysSummary(fresh, DateTime.now());
      // всё новое — про уже прошедшие дни: беспокоить незачем
      if (days.isNotEmpty) {
        // инициализация плагина в фоновом изоляте
        const android = AndroidInitializationSettings('@mipmap/ic_launcher');
        await _plugin
            .initialize(const InitializationSettings(android: android));
        await _show(
          teacher != null
              ? 'Изменения в вашем расписании'
              : 'Изменения в расписании · $group',
          'На: $days',
        );
      }
      await prefs.setString(_prefNotifiedTs, newest);
    }
  }
}
