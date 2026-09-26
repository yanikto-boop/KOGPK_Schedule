// Расписание стадий для виджетов-таймеров.
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_app/api.dart';
import 'package:schedule_app/services/countdown_timeline.dart';

Lesson lesson(String num, String time, String subject, {String room = ''}) =>
    Lesson(num, time, [Subgroup(subject: subject, room: room)]);

DaySchedule day(String iso, List<Lesson> lessons) =>
    DaySchedule(iso, iso, lessons);

void main() {
  // понедельник 14.09.2026: две пары по две половины
  final monday = day('2026-09-14', [
    lesson('1', '08:00 - 08:45 08:55 - 09:40', 'Матан', room: '301'),
    lesson('2', '09:50 - 10:35 10:45 - 11:30', 'Физика'),
  ]);
  final tuesday = day('2026-09-15', [
    lesson('1', '08:00 - 08:45 08:55 - 09:40', 'История', room: '105'),
  ]);
  DateTime at(int d, int h, int m) => DateTime(2026, 9, d, h, m);

  WidgetPhase phaseAt(List<WidgetPhase> ps, DateTime t) => ps.firstWhere(
      (p) => !t.isBefore(p.from) && t.isBefore(p.to),
      orElse: () => throw StateError('нет стадии на $t'));

  group('внутри учебного дня', () {
    final ps = CountdownTimeline.build([monday, tuesday], at(14, 0, 0));

    test('первая половина', () {
      final p = phaseAt(ps, at(14, 8, 10));
      expect(p.label, 'До конца 1 половины');
      expect(p.to, at(14, 8, 45));
      expect(p.title, 'Матан');
      expect(p.sub, '1 пара · 301');
      expect(p.timer, isTrue);
    });

    test('перерыв между половинами', () {
      final p = phaseAt(ps, at(14, 8, 50));
      expect(p.label, 'Перерыв · до 2 половины');
      expect(p.to, at(14, 8, 55));
    });

    test('вторая половина', () {
      final p = phaseAt(ps, at(14, 9, 0));
      expect(p.label, 'До конца 2 половины');
      expect(p.to, at(14, 9, 40));
    });

    test('перемена между парами показывает следующую пару', () {
      final p = phaseAt(ps, at(14, 9, 45));
      expect(p.label, 'Перемена');
      expect(p.to, at(14, 9, 50));
      expect(p.title, 'Физика');
      expect(p.sub, '2 пара');
    });

    test('ровно в момент звонка уже следующая стадия', () {
      expect(phaseAt(ps, at(14, 8, 45)).label, 'Перерыв · до 2 половины');
    });
  });

  group('ожидание первой пары', () {
    final ps = CountdownTimeline.build([monday, tuesday], at(14, 0, 0));

    test('ночью — статичное время, а не многочасовой отсчёт', () {
      final p = phaseAt(ps, at(14, 2, 0));
      expect(p.timer, isFalse);
      expect(p.label, 'Следующая пара');
      expect(p.sub, 'Сегодня в 08:00');
      expect(p.to, at(14, 5, 0));
    });

    test('за три часа до пары включается отсчёт', () {
      final p = phaseAt(ps, at(14, 5, 30));
      expect(p.timer, isTrue);
      expect(p.label, 'До начала пар');
      expect(p.to, at(14, 8, 0));
    });

    test('вечером после пар — «Завтра», после полуночи — «Сегодня»', () {
      final evening = phaseAt(ps, at(14, 20, 0));
      expect(evening.sub, 'Завтра в 08:00');
      expect(evening.title, 'История');
      expect(evening.to, at(15, 0, 0));

      final night = phaseAt(ps, at(15, 1, 0));
      expect(night.sub, 'Сегодня в 08:00');
    });

    test('через выходные — день недели', () {
      final friday = day('2026-09-18', [
        lesson('1', '08:00 - 08:45 08:55 - 09:40', 'Физра'),
      ]);
      final nextMonday = day('2026-09-21', [
        lesson('1', '09:00 - 09:45 09:55 - 10:40', 'Химия'),
      ]);
      final ps2 =
          CountdownTimeline.build([friday, nextMonday], at(18, 0, 0));
      expect(phaseAt(ps2, at(19, 12, 0)).sub, 'В понедельник в 09:00');
      expect(phaseAt(ps2, at(20, 12, 0)).sub, 'Завтра в 09:00');
    });
  });

  group('общие свойства', () {
    test('стадии идут встык без дыр до конца последней пары', () {
      final ps = CountdownTimeline.build([monday, tuesday], at(14, 0, 0));
      for (var i = 1; i < ps.length; i++) {
        expect(ps[i].from, ps[i - 1].to, reason: 'дыра перед ${ps[i].label}');
      }
      expect(ps.first.from, at(14, 0, 0));
      expect(ps.last.to, at(15, 9, 40));
    });

    test('прошедшие стадии отбрасываются', () {
      final ps = CountdownTimeline.build([monday, tuesday], at(14, 12, 0));
      expect(ps.every((p) => p.to.isAfter(at(14, 12, 0))), isTrue);
      expect(ps.first.label, 'Следующая пара');
    });

    test('прошедшие дни и дни без пар пропускаются', () {
      final past = day('2026-09-10', [
        lesson('1', '08:00 - 08:45 08:55 - 09:40', 'Прошлое'),
      ]);
      final empty = day('2026-09-16', []);
      final ps =
          CountdownTimeline.build([past, monday, empty], at(14, 0, 0));
      expect(ps.any((p) => p.title == 'Прошлое'), isFalse);
      expect(ps.last.to, at(14, 11, 30));
    });

    test('пара без разбивки на половины', () {
      final ps = CountdownTimeline.build([
        day('2026-09-14', [lesson('3', '12:00 - 13:30', 'Практика')])
      ], at(14, 0, 0));
      expect(phaseAt(ps, at(14, 12, 30)).label, 'До конца пары');
    });

    test('JSON в формате, который читает нативный виджет', () {
      final p = CountdownTimeline.build([monday], at(14, 0, 0)).first;
      final j = p.toJson();
      expect(j.keys, containsAll(['f', 't', 'lb', 'tl', 'sb', 'tm']));
      expect(j['f'], at(14, 0, 0).millisecondsSinceEpoch);
    });
  });
}
