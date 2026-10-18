import '../api.dart';
import '../pair.dart';

/// Одна стадия для виджета-таймера: с [from] до [to] виджет показывает
/// одно и то же. Нативный код только ищет стадию, в которую попало текущее
/// время, и ставит будильник на её конец — вся логика расписания здесь.
class WidgetPhase {
  final DateTime from;
  final DateTime to;
  final String label; // «До конца 1 половины»
  final String title; // предмет
  final String sub; // «2 пара · 301» / «Завтра в 08:00»
  /// true — тикающий отсчёт до [to]; false — статичный текст [sub].
  final bool timer;

  const WidgetPhase(
      this.from, this.to, this.label, this.title, this.sub, this.timer);

  Map<String, dynamic> toJson() => {
        'f': from.millisecondsSinceEpoch,
        't': to.millisecondsSinceEpoch,
        'lb': label,
        'tl': title,
        'sb': sub,
        'tm': timer,
      };
}

class CountdownTimeline {
  /// Дольше этого до первой пары — вместо отсчёта пишем «Завтра в 08:00»:
  /// тикающие «14:22:10» на ночь никому не нужны.
  static const longWait = Duration(hours: 3);

  static const _weekdays = [
    'в понедельник', 'во вторник', 'в среду', 'в четверг',
    'в пятницу', 'в субботу', 'в воскресенье',
  ];

  /// Стадии от начала сегодняшнего дня до конца последней загруженной пары.
  static List<WidgetPhase> build(List<DaySchedule> days, DateTime now,
      {int maxDays = 10}) {
    final today = DateTime(now.year, now.month, now.day);
    final out = <WidgetPhase>[];
    var cursor = today;
    var used = 0;

    for (final d in days) {
      if (d.date == null) continue;
      final date = DateTime.tryParse(d.date!);
      if (date == null || date.isBefore(today)) continue;
      final blocks = PairBlock.ofDay(d, date);
      if (blocks.isEmpty) continue;
      if (++used > maxDays) break;

      _addWait(out, cursor, blocks.first);
      PairBlock? prev;
      for (final b in blocks) {
        if (prev != null) {
          _add(out, prev.end, b.start, 'Перемена', b.subject, _where(b), true);
        }
        for (var i = 0; i < b.segments.length; i++) {
          final s = b.segments[i];
          if (i > 0) {
            _add(out, b.segments[i - 1].end, s.start,
                'Перерыв · до ${i + 1} половины', b.subject, _where(b), true);
          }
          _add(
              out,
              s.start,
              s.end,
              b.segments.length > 1 ? 'До конца ${i + 1} половины' : 'До конца пары',
              b.subject,
              _where(b),
              true);
        }
        prev = b;
      }
      if (blocks.last.end.isAfter(cursor)) cursor = blocks.last.end;
    }

    out.removeWhere((p) => !p.to.isAfter(now));
    return out;
  }

  /// Ожидание первой пары дня: статичное «Завтра в 08:00» (по кусочку на
  /// каждые сутки, чтобы «завтра» после полуночи стало «сегодня»), а за
  /// [longWait] до звонка — живой отсчёт.
  static void _addWait(List<WidgetPhase> out, DateTime from, PairBlock first) {
    var timerFrom = first.start.subtract(longWait);
    if (timerFrom.isBefore(from)) timerFrom = from;

    var piece = from;
    while (piece.isBefore(timerFrom)) {
      final nextMidnight = DateTime(piece.year, piece.month, piece.day + 1);
      final end = nextMidnight.isBefore(timerFrom) ? nextMidnight : timerFrom;
      _add(out, piece, end, 'Следующая пара', first.subject,
          '${_when(piece, first.start)} в ${_hm(first.start)}', false);
      piece = end;
    }
    _add(out, timerFrom, first.start, 'До начала пар', first.subject,
        _where(first), true);
  }

  static void _add(List<WidgetPhase> out, DateTime from, DateTime to,
      String label, String title, String sub, bool timer) {
    if (!to.isAfter(from)) return;
    out.add(WidgetPhase(from, to, label, title, sub, timer));
  }

  /// «Сегодня» / «Завтра» / «В среду» — относительно дня [at].
  static String _when(DateTime at, DateTime target) {
    final a = DateTime(at.year, at.month, at.day);
    final t = DateTime(target.year, target.month, target.day);
    final days = (t.difference(a).inHours / 24).round();
    if (days <= 0) return 'Сегодня';
    if (days == 1) return 'Завтра';
    final w = _weekdays[target.weekday - 1];
    return w[0].toUpperCase() + w.substring(1);
  }

  static String _where(PairBlock b) =>
      b.room.isEmpty ? '${b.num} пара' : '${b.num} пара · ${b.room}';

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
