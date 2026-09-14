// Подсчёт посещаемости по данным журнала.
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_app/api.dart';
import 'package:schedule_app/screens/attendance_screen.dart';

GradeEntry entry(String attendance, {String grade = ''}) =>
    GradeEntry('12.09.2026, пятница', attendance, grade, '');

SubjectGrades subject(List<GradeEntry> entries) =>
    SubjectGrades('Матан', entries, 4.0, entries.where((e) => e.grade.isNotEmpty).length);

void main() {
  group('GradeEntry', () {
    test('«Да» — был на занятии', () {
      final e = entry('Да');
      expect(e.present, isTrue);
      expect(e.absent, isFalse);
      expect(e.marked, isTrue);
    });

    test('«Нет» — пропуск', () {
      final e = entry('Нет');
      expect(e.present, isFalse);
      expect(e.absent, isTrue);
      expect(e.marked, isTrue);
    });

    test('пустая отметка — не пропуск, а отсутствие данных', () {
      final e = entry('');
      expect(e.present, isFalse);
      expect(e.absent, isFalse);
      expect(e.marked, isFalse);
    });

    test('дата без дня недели', () {
      expect(entry('Да').shortDate, '12.09.2026');
    });
  });

  group('SubjectGrades', () {
    test('считает явки и пропуски, игнорируя записи без отметки', () {
      final s = subject([
        entry('Да'),
        entry('Да'),
        entry('Нет'),
        entry(''),
      ]);
      expect(s.attended, 2);
      expect(s.missed, 1);
      expect(s.marked, 3);
      expect(s.attendanceRate, closeTo(2 / 3, 1e-9));
      expect(s.misses.length, 1);
    });

    test('без единой отметки посещаемость не занижается', () {
      final s = subject([entry(''), entry('')]);
      expect(s.marked, 0);
      expect(s.attendanceRate, 1);
    });
  });

  group('JournalData', () {
    JournalData journal(List<SubjectGrades> subjects) =>
        JournalData('123', null, subjects);

    test('суммирует по всем предметам', () {
      final d = journal([
        subject([entry('Да'), entry('Нет')]),
        subject([entry('Да'), entry('Да'), entry('Нет')]),
      ]);
      expect(d.totalAttended, 3);
      expect(d.totalMissed, 2);
      expect(d.totalMarked, 5);
      expect(d.attendanceRate, closeTo(0.6, 1e-9));
    });

    test('byMisses отдаёт только предметы с пропусками, худшие первыми', () {
      final clean = SubjectGrades('Физра', [entry('Да')], 0, 0);
      final one = SubjectGrades('История', [entry('Нет')], 0, 0);
      final three = SubjectGrades(
          'Матан', [entry('Нет'), entry('Нет'), entry('Нет')], 0, 0);
      final d = journal([clean, one, three]);
      expect(d.byMisses.map((s) => s.subject), ['Матан', 'История']);
    });

    test('пустой журнал не делит на ноль', () {
      final d = journal([]);
      expect(d.totalMarked, 0);
      expect(d.attendanceRate, 1);
      expect(d.byMisses, isEmpty);
    });
  });

  group('missWord', () {
    test('склонения', () {
      expect(AttendanceScreen.missWord(1), 'пропуск');
      expect(AttendanceScreen.missWord(2), 'пропуска');
      expect(AttendanceScreen.missWord(5), 'пропусков');
      expect(AttendanceScreen.missWord(11), 'пропусков');
      expect(AttendanceScreen.missWord(12), 'пропусков');
      expect(AttendanceScreen.missWord(21), 'пропуск');
      expect(AttendanceScreen.missWord(22), 'пропуска');
      expect(AttendanceScreen.missWord(25), 'пропусков');
      expect(AttendanceScreen.missWord(111), 'пропусков');
    });
  });

  group('rateColor', () {
    test('порог по уровню посещаемости', () {
      expect(AttendanceScreen.rateColor(1.0), isNot(AttendanceScreen.rateColor(0.5)));
      expect(AttendanceScreen.rateColor(0.95), AttendanceScreen.rateColor(0.9));
      expect(AttendanceScreen.rateColor(0.8), AttendanceScreen.rateColor(0.75));
      expect(AttendanceScreen.rateColor(0.5), AttendanceScreen.rateColor(0.0));
    });
  });
}
