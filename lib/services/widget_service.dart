import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import '../api.dart';

/// Готовит данные для виджетов на главный экран и обновляет их.
/// Виджеты показывают ближайший учебный день (сегодня или следующий с парами).
class WidgetService {
  static String _todayIso() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static String _startTime(String time) {
    final t = time.trim();
    if (t.isEmpty) return '';
    return t.split(RegExp(r'\s+')).first; // "08:00 - 08:45 ..." -> "08:00"
  }

  static String _shortSubject(String s) {
    var v = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (v.length > 34) v = '${v.substring(0, 33)}…';
    return v;
  }

  /// Метка дня: «Сегодня» / «Завтра» / «Пн, 15 июня».
  static String _dayLabel(DaySchedule day) {
    final today = _todayIso();
    if (day.date == today) return 'Сегодня';
    if (day.date != null) {
      final d = DateTime.tryParse(day.date!);
      final t = DateTime.tryParse(today);
      if (d != null && t != null && d.difference(t).inDays == 1) {
        return 'Завтра';
      }
    }
    // из «15 июня 2026, понедельник» берём «понедельник, 15 июня»
    final parts = day.title.split(',');
    if (parts.length == 2) {
      final dm = parts[0].trim();
      final wd = parts[1].trim();
      return '${wd[0].toUpperCase()}${wd.substring(1)}, $dm';
    }
    return day.title;
  }

  static DaySchedule? _pickDay(ScheduleData data) {
    final today = _todayIso();
    DaySchedule? withLessons(bool Function(DaySchedule) cond) {
      for (final d in data.days) {
        if (cond(d) && d.lessons.any((l) => l.subgroups.isNotEmpty)) return d;
      }
      return null;
    }

    // ближайший день с парами, начиная с сегодня
    return withLessons((d) => d.date != null && d.date!.compareTo(today) >= 0) ??
        // если впереди ничего — хотя бы сегодня (пусть пустой)
        _firstFrom(data, today);
  }

  static DaySchedule? _firstFrom(ScheduleData data, String today) {
    for (final d in data.days) {
      if (d.date != null && d.date!.compareTo(today) >= 0) return d;
    }
    return data.days.isNotEmpty ? data.days.last : null;
  }

  static Future<void> update(ScheduleData data, String group) async {
    final day = _pickDay(data);
    final lessons =
        day?.lessons.where((l) => l.subgroups.isNotEmpty).toList() ?? [];

    final lines = lessons.map((l) {
      final subj = _shortSubject(l.subgroups.first.subject);
      return '${l.num}|${_startTime(l.time)}|$subj';
    }).toList();

    await HomeWidget.saveWidgetData<String>('w_group', group);
    await HomeWidget.saveWidgetData<String>(
        'w_day', day != null ? _dayLabel(day) : '—');
    await HomeWidget.saveWidgetData<int>('w_count', lessons.length);
    await HomeWidget.saveWidgetData<String>('w_lessons', lines.join('\n'));
    await HomeWidget.saveWidgetData<String>(
        'w_updated', DateFormat('HH:mm').format(DateTime.now()));

    await HomeWidget.updateWidget(
        androidName: 'ScheduleWidgetSmall', name: 'ScheduleWidgetSmall');
    await HomeWidget.updateWidget(
        androidName: 'ScheduleWidgetWide', name: 'ScheduleWidgetWide');
  }
}
