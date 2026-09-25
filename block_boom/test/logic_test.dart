import 'dart:math';

import 'package:block_boom/game/board.dart';
import 'package:block_boom/game/game_model.dart';
import 'package:block_boom/game/profile.dart';
import 'package:block_boom/game/shapes.dart';
import 'package:flutter_test/flutter_test.dart';

Shape shapeOf(List<String> rows) => kShapes.firstWhere((s) {
      if (s.rows != rows.length || s.cols != rows.first.length) return false;
      for (var r = 0; r < s.rows; r++) {
        for (var c = 0; c < s.cols; c++) {
          final has = s.cells.contains((r: r, c: c));
          if (has != (rows[r][c] == 'X')) return false;
        }
      }
      return true;
    });

void main() {
  test('все фигуры уникальны и нормализованы', () {
    final keys = kShapes.map((s) => s.cells.map((c) => '${c.r},${c.c}').join(';')).toSet();
    expect(keys.length, kShapes.length);
    for (final s in kShapes) {
      expect(s.cells.any((c) => c.r == 0), isTrue);
      expect(s.cells.any((c) => c.c == 0), isTrue);
    }
  });

  test('нельзя ставить за край и поверх блоков', () {
    final b = Board();
    final i5 = shapeOf(['XXXXX']);
    expect(b.canPlace(i5, 0, 3), isTrue);
    expect(b.canPlace(i5, 0, 4), isFalse);
    b.place(i5, 0, 0, 1);
    expect(b.canPlace(shapeOf(['X']), 0, 2), isFalse);
    expect(b.canPlace(shapeOf(['X']), 0, 5), isTrue);
  });

  test('одновременный сбор строки и столбца', () {
    final b = Board();
    // строка 0 без клетки (0,7), столбец 7 без клетки (0,7)
    for (var c = 0; c < 7; c++) {
      b.cells[c] = 2;
    }
    for (var r = 1; r < kN; r++) {
      b.cells[r * kN + 7] = 3;
    }
    final res = b.place(shapeOf(['X']), 0, 7, 4);
    expect(res.lines.rows, [0]);
    expect(res.lines.cols, [7]);
    expect(res.cleared.length, 15);
    expect(b.isClear, isTrue);
  });

  test('очки: клетки + линии × комбо, бонус за чистое поле', () {
    final m = GameModel(rng: Random(1));
    m.board = Board();
    for (var c = 0; c < 7; c++) {
      m.board.cells[c] = 0;
    }
    m.board.cells[kN] = 0; // лишний блок — поле не станет пустым
    m.tray = [TrayPiece(shapeOf(['X']), 1), TrayPiece(shapeOf(['XX']), 2), TrayPiece(shapeOf(['X', 'X']), 3)];
    final r = m.place(0, 0, 7);
    expect(r.lines, 1);
    expect(r.streak, 1);
    expect(r.gained, 1 + 10);
    expect(r.boardCleared, isFalse);
  });

  test('комбо сгорает после трёх ходов без линий', () {
    final m = GameModel(rng: Random(2));
    m.board = Board();
    m.streak = 4;
    for (var i = 0; i < 3; i++) {
      m.tray = [TrayPiece(shapeOf(['X']), 0), TrayPiece(shapeOf(['X']), 1), TrayPiece(shapeOf(['X']), 2)];
      m.place(0, 7, i * 2);
      if (i < 2) expect(m.streak, 4);
    }
    expect(m.streak, 0);
  });

  test('раздача всегда даёт хотя бы одну влезающую фигуру', () {
    final rng = Random(3);
    for (var t = 0; t < 300; t++) {
      final m = GameModel(rng: rng);
      m.score = rng.nextInt(12000);
      m.board = Board();
      for (var i = 0; i < kN * kN; i++) {
        if (rng.nextDouble() < 0.55) m.board.cells[i] = 0;
      }
      m.refill();
      expect(m.tray.any((p) => p != null && m.board.fitsAnywhere(p.shape)), isTrue);
    }
  });

  test('второй шанс освобождает место', () {
    final m = GameModel(rng: Random(4));
    for (var i = 0; i < kN * kN; i++) {
      m.board.cells[i] = (i * 7) % 11 == 0 ? -1 : 1;
    }
    final before = m.board.filled;
    final cleared = m.revive();
    expect(cleared, isNotEmpty);
    expect(m.board.filled, before - cleared.length);
    expect(m.reviveUsed, isTrue);
    expect(m.noMoves, isFalse);
  });

  test('сохранение и загрузка партии', () {
    final m = GameModel(rng: Random(5));
    m.place(0, 0, 0);
    m.score = 777;
    final copy = GameModel.fromJson(m.toJson())!;
    expect(copy.board.cells, m.board.cells);
    expect(copy.score, 777);
    expect(copy.tray.map((p) => p?.shape.id), m.tray.map((p) => p?.shape.id));
  });

  test('уровни растут с опытом', () {
    expect(Profile.levelFor(0).level, 1);
    expect(Profile.levelFor(Profile.needFor(1)).level, 2);
    final l = Profile.levelFor(Profile.needFor(1) + 10);
    expect(l.into, 10);
    expect(l.need, Profile.needFor(2));
  });

  test('случайная партия доигрывается без ошибок', () {
    final rng = Random(6);
    for (var g = 0; g < 20; g++) {
      final m = GameModel(rng: rng);
      var moves = 0;
      while (!m.noMoves && moves < 2000) {
        final slots = [0, 1, 2]..shuffle(rng);
        var moved = false;
        for (final s in slots) {
          final p = m.tray[s];
          if (p == null) continue;
          final spots = <(int, int)>[];
          for (var r = 0; r < kN; r++) {
            for (var c = 0; c < kN; c++) {
              if (m.board.canPlace(p.shape, r, c)) spots.add((r, c));
            }
          }
          if (spots.isEmpty) continue;
          final (r, c) = spots[rng.nextInt(spots.length)];
          m.place(s, r, c);
          moved = true;
          break;
        }
        expect(moved, isTrue);
        moves++;
      }
      expect(m.score, greaterThan(0));
    }
  });
}
