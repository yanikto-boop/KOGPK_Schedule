import 'dart:convert';
import 'package:home_widget/home_widget.dart';
import '../api.dart';

/// Готовит данные для виджетов на главный экран и обновляет их.
///
/// Сохраняет список ближайших учебных дней (с парами) в виде JSON.
/// Нативный код сам выбирает, какой день показать: пока не закончилась
/// последняя пара текущего дня — показывает сегодня, после — следующий день.
class WidgetService {
  static String _todayIso() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// "08:00 - 08:45 08:55 - 09:40" -> "08:00"
  static String _startTime(String time) {
    final m = RegExp(r'\d{1,2}:\d{2}').firstMatch(time);
    return m?.group(0) ?? '';
  }

  /// Последнее "HH:mm" во всей строке времени — конец пары.
  static String _endTime(String time) {
    final all = RegExp(r'\d{1,2}:\d{2}').allMatches(time).toList();
    return all.isEmpty ? '' : all.last.group(0)!;
  }

  static String _shortSubject(String s) {
    var v = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (v.length > 34) v = '${v.substring(0, 33)}…';
    return v;
  }

  static Future<void> update(ScheduleData data, String group) async {
    final today = _todayIso();
    final days = <Map<String, dynamic>>[];

    for (final d in data.days) {
      if (d.date == null || d.date!.compareTo(today) < 0) continue;
      final lessons = d.lessons.where((l) => l.subgroups.isNotEmpty).toList();
      if (lessons.isEmpty) continue;

      final lines = lessons
          .map((l) =>
              '${l.num}|${_startTime(l.time)}|${_shortSubject(l.subgroups.first.subject)}')
          .toList();

      // конец последней пары дня (внутренне — для переключения на след. день)
      String end = '';
      for (final l in lessons) {
        final e = _endTime(l.time);
        if (e.isNotEmpty) end = e;
      }

      // из «15 июня 2026, понедельник» -> dm="15 июня", wd="понедельник"
      String dm = '', wd = '';
      final parts = d.title.split(',');
      if (parts.isNotEmpty) {
        final left = parts[0].trim().split(' ');
        if (left.length >= 2) dm = '${left[0]} ${left[1]}';
      }
      if (parts.length >= 2) wd = parts[1].trim();

      days.add({
        'date': d.date,
        'dm': dm,
        'wd': wd,
        'end': end,
        'lessons': lines,
      });

      if (days.length >= 10) break;
    }

    await HomeWidget.saveWidgetData<String>('w_group', group);
    await HomeWidget.saveWidgetData<String>('w_days', jsonEncode(days));

    await HomeWidget.updateWidget(
        androidName: 'ScheduleWidgetSmall', name: 'ScheduleWidgetSmall');
    await HomeWidget.updateWidget(
        androidName: 'ScheduleWidgetWide', name: 'ScheduleWidgetWide');
  }
}
