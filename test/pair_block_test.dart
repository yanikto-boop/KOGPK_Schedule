// Разбор времени пары на половины и определение текущей стадии.
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_app/screens/home_screen.dart';

void main() {
  final day = DateTime(2026, 9, 14);
  DateTime at(int h, int m) => DateTime(2026, 9, 14, h, m);

  PairBlock block(String time) =>
      PairBlock('2', PairBlock.parseSegments(time, day), 'Матан', '301', 'Иванов');

  group('parseSegments', () {
    test('обычная пара из двух половин', () {
      final segs = PairBlock.parseSegments('08:00 - 08:45 08:55 - 09:40', day);
      expect(segs.length, 2);
      expect(segs.first.start, at(8, 0));
      expect(segs.first.end, at(8, 45));
      expect(segs.last.start, at(8, 55));
      expect(segs.last.end, at(9, 40));
    });

    test('пара без разбивки на половины', () {
      final segs = PairBlock.parseSegments('08:00 - 09:40', day);
      expect(segs.length, 1);
      expect(segs.single.start, at(8, 0));
      expect(segs.single.end, at(9, 40));
    });

    test('пустая строка времени даёт пустой список', () {
      expect(PairBlock.parseSegments('уточняется', day), isEmpty);
    });

    test('нечётное число меток не теряет конец пары', () {
      final segs = PairBlock.parseSegments('08:00 - 08:45 09:40', day);
      expect(segs.last.end, at(9, 40));
    });
  });

  group('phaseAt', () {
    final b = block('08:00 - 08:45 08:55 - 09:40');

    test('идёт первая половина', () {
      final p = b.phaseAt(at(8, 10));
      expect(p.label, 'До конца 1 половины');
      expect(p.target, at(8, 45));
      expect(p.onBreak, isFalse);
    });

    test('перерыв между половинами', () {
      final p = b.phaseAt(at(8, 45).add(const Duration(minutes: 5)));
      expect(p.label, 'Перерыв · до 2 половины');
      expect(p.target, at(8, 55));
      expect(p.onBreak, isTrue);
    });

    test('идёт вторая половина', () {
      final p = b.phaseAt(at(9, 0));
      expect(p.label, 'До конца 2 половины');
      expect(p.target, at(9, 40));
      expect(p.onBreak, isFalse);
    });

    test('граница: ровно звонок с первой половины — ещё первая', () {
      final p = b.phaseAt(at(8, 45));
      expect(p.label, 'До конца 1 половины');
      expect(p.onBreak, isFalse);
    });

    test('пара без половин отсчитывает до конца пары', () {
      final p = block('08:00 - 09:40').phaseAt(at(8, 10));
      expect(p.label, 'До конца пары');
      expect(p.target, at(9, 40));
      expect(p.onBreak, isFalse);
    });
  });

  test('start и end охватывают всю пару', () {
    final b = block('08:00 - 08:45 08:55 - 09:40');
    expect(b.start, at(8, 0));
    expect(b.end, at(9, 40));
  });
}
