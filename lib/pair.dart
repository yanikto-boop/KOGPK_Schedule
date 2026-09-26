import 'api.dart';

/// Половина пары: от звонка на урок до звонка с урока.
class PairSegment {
  final DateTime start;
  final DateTime end;
  const PairSegment(this.start, this.end);
}

/// Пара как единый блок: от начала первой половины до конца второй.
class PairBlock {
  final String num;
  final List<PairSegment> segments;
  final String subject;
  final String room;
  final String teacher;
  PairBlock(this.num, this.segments, this.subject, this.room, this.teacher);

  DateTime get start => segments.first.start;
  DateTime get end => segments.last.end;

  /// Пары одного дня по порядку звонков. [date] задаёт дату, к которой
  /// привязываются времена из строк расписания.
  static List<PairBlock> ofDay(DaySchedule day, DateTime date) {
    final blocks = <PairBlock>[];
    for (final l in day.lessons) {
      if (l.subgroups.isEmpty) continue;
      final segs = parseSegments(l.time, date);
      if (segs.isEmpty) continue;
      final sg = l.subgroups.first;
      blocks.add(PairBlock(l.num, segs, sg.subject, sg.room, sg.teacher));
    }
    blocks.sort((a, b) => a.start.compareTo(b.start));
    return blocks;
  }

  /// "08:00 - 08:45 08:55 - 09:40" -> две половины с перерывом между ними.
  /// Метки времени идут парами «начало-конец»; [day] задаёт дату.
  static List<PairSegment> parseSegments(String time, DateTime day) {
    final ts = RegExp(r'(\d{1,2}):(\d{2})')
        .allMatches(time)
        .map((m) => DateTime(day.year, day.month, day.day,
            int.parse(m.group(1)!), int.parse(m.group(2)!)))
        .toList();
    if (ts.isEmpty) return [];
    if (ts.length == 1) return [PairSegment(ts.first, ts.first)];
    final out = <PairSegment>[];
    for (var i = 0; i + 1 < ts.length; i += 2) {
      out.add(PairSegment(ts[i], ts[i + 1]));
    }
    // нечётное число меток: последняя всё равно конец пары
    if (ts.length.isOdd) {
      out[out.length - 1] = PairSegment(out.last.start, ts.last);
    }
    return out;
  }

  /// На какой стадии пары мы сейчас: идёт половина или перерыв между ними.
  ({String label, DateTime target, bool onBreak}) phaseAt(DateTime now) {
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      if (now.isAfter(s.end)) continue;
      if (now.isBefore(s.start)) {
        return (
          label: 'Перерыв · до ${i + 1} половины',
          target: s.start,
          onBreak: true
        );
      }
      return (
        label: segments.length > 1
            ? 'До конца ${i + 1} половины'
            : 'До конца пары',
        target: s.end,
        onBreak: false
      );
    }
    return (label: 'До конца пары', target: end, onBreak: false);
  }
}
