import 'dart:math';

import 'board.dart';
import 'shapes.dart';

const int kColors = 8;

/// Сколько ходов подряд без сбора линии можно сделать, не потеряв комбо.
const int kComboWindow = 3;

class TrayPiece {
  const TrayPiece(this.shape, this.color);
  final Shape shape;
  final int color;
}

class MoveResult {
  MoveResult({
    required this.placement,
    required this.gained,
    required this.streak,
    required this.boardCleared,
    required this.trayRefilled,
    required this.gameOver,
  });

  final BoardPlacement placement;
  final int gained;

  /// Текущая серия комбо (0 — нет).
  final int streak;
  final bool boardCleared;
  final bool trayRefilled;
  final bool gameOver;

  int get lines => placement.lines.count;
}

/// Вся логика партии: поле, три фигуры в лотке, очки и комбо.
class GameModel {
  GameModel({Random? rng}) : rng = rng ?? Random() {
    board = Board();
    refill();
  }

  GameModel._restore(this.rng);

  final Random rng;
  late Board board;
  List<TrayPiece?> tray = [null, null, null];
  int score = 0;
  int streak = 0;
  int movesSinceClear = 0;
  int placements = 0;
  int bestStreak = 0;
  int linesCleared = 0;
  bool reviveUsed = false;

  /// Сколько ходов осталось, чтобы продлить комбо.
  int get comboMovesLeft => streak == 0 ? 0 : kComboWindow - movesSinceClear;

  bool canPlace(int slot, int r, int c) {
    final p = tray[slot];
    return p != null && board.canPlace(p.shape, r, c);
  }

  bool pieceFits(int slot) {
    final p = tray[slot];
    return p != null && board.fitsAnywhere(p.shape);
  }

  bool get noMoves {
    for (var i = 0; i < tray.length; i++) {
      if (pieceFits(i)) return false;
    }
    return true;
  }

  static int linePoints(int lines) => 10 * lines * (lines + 1) ~/ 2;

  MoveResult place(int slot, int r, int c) {
    final piece = tray[slot]!;
    final placement = board.place(piece.shape, r, c, piece.color);
    tray[slot] = null;
    placements++;

    var gained = piece.shape.size;
    final lines = placement.lines.count;
    var cleared = false;
    if (lines > 0) {
      streak++;
      movesSinceClear = 0;
      bestStreak = max(bestStreak, streak);
      linesCleared += lines;
      gained += linePoints(lines) * streak;
      if (board.isClear) {
        cleared = true;
        gained += 300;
      }
    } else {
      movesSinceClear++;
      if (movesSinceClear >= kComboWindow) {
        streak = 0;
        movesSinceClear = 0;
      }
    }
    score += gained;

    var refilled = false;
    if (tray.every((p) => p == null)) {
      refill();
      refilled = true;
    }
    return MoveResult(
      placement: placement,
      gained: gained,
      streak: streak,
      boardCleared: cleared,
      trayRefilled: refilled,
      gameOver: noMoves,
    );
  }

  /// «Второй шанс»: убирает две самые заполненные строки и два столбца
  /// и раздаёт фигуры, которые точно можно поставить.
  Map<int, int> revive() {
    reviveUsed = true;
    streak = 0;
    movesSinceClear = 0;
    int rowFill(int r) => List.generate(kN, (c) => board.at(r, c)).where((v) => v >= 0).length;
    int colFill(int c) => List.generate(kN, (r) => board.at(r, c)).where((v) => v >= 0).length;
    final rows = List.generate(kN, (i) => i)..shuffle(rng);
    rows.sort((a, b) => rowFill(b).compareTo(rowFill(a)));
    final cols = List.generate(kN, (i) => i)..shuffle(rng);
    cols.sort((a, b) => colFill(b).compareTo(colFill(a)));
    final cleared = <int, int>{};
    for (final r in rows.take(2)) {
      for (var c = 0; c < kN; c++) {
        final i = r * kN + c;
        if (board.cells[i] >= 0) cleared[i] = board.cells[i];
      }
    }
    for (final c in cols.take(2)) {
      for (var r = 0; r < kN; r++) {
        final i = r * kN + c;
        if (board.cells[i] >= 0) cleared[i] = board.cells[i];
      }
    }
    for (final i in cleared.keys) {
      board.cells[i] = -1;
    }
    refill(forceSolvable: true);
    return cleared;
  }

  // ---------- Раздача фигур ----------

  /// Раздаёт три новые фигуры. В начале партии набор всегда проходимый
  /// и часто содержит фигуру, которая соберёт линию; чем больше очков,
  /// тем больше крупных фигур и тем реже помощь.
  void refill({bool forceSolvable = false}) {
    final d = (score / 6000).clamp(0.0, 1.0);
    final pHelp = 0.5 - 0.3 * d;
    final needSolvable = forceSolvable || rng.nextDouble() < 1.0 - 0.55 * d;
    final helpers = kShapes.where(board.canClearSomewhere).toList();

    for (var attempt = 0; attempt < 30; attempt++) {
      final shapes = <Shape>[];
      for (var i = 0; i < 3; i++) {
        if (helpers.isNotEmpty && rng.nextDouble() < pHelp) {
          shapes.add(helpers[rng.nextInt(helpers.length)]);
        } else {
          shapes.add(_weighted(d));
        }
      }
      final ok = needSolvable ? _solvable(board, shapes) : shapes.any(board.fitsAnywhere);
      if (ok) {
        _setTray(shapes);
        return;
      }
    }
    // Запасной вариант: гарантируем, что хоть что-то влезет.
    final fitting = kShapes.where(board.fitsAnywhere).toList()
      ..sort((a, b) => a.size.compareTo(b.size));
    final small = fitting.take(max(1, fitting.length ~/ 2)).toList();
    _setTray(List.generate(3, (_) => small[rng.nextInt(small.length)]));
  }

  Shape _weighted(double d) {
    double w(Shape s) => s.weight * switch (s.tier) {
          0 => 1 - 0.4 * d,
          2 => 1 + 1.2 * d,
          _ => 1.0,
        };
    final total = kShapes.fold<double>(0, (a, s) => a + w(s));
    var x = rng.nextDouble() * total;
    for (final s in kShapes) {
      x -= w(s);
      if (x <= 0) return s;
    }
    return kShapes.last;
  }

  void _setTray(List<Shape> shapes) {
    final colors = List.generate(kColors, (i) => i)..shuffle(rng);
    tray = [for (var i = 0; i < 3; i++) TrayPiece(shapes[i], colors[i])];
  }

  /// Можно ли поставить все фигуры в каком-нибудь порядке.
  static bool _solvable(Board board, List<Shape> shapes) {
    var budget = 5000;
    bool dfs(Board b, List<Shape> rest) {
      if (rest.length == 1) return b.fitsAnywhere(rest.first);
      final tried = <int>{};
      for (var i = 0; i < rest.length; i++) {
        final s = rest[i];
        if (!tried.add(s.id)) continue;
        final others = [...rest]..removeAt(i);
        for (var r = 0; r <= kN - s.rows; r++) {
          for (var c = 0; c <= kN - s.cols; c++) {
            if (!b.canPlace(s, r, c)) continue;
            if (--budget < 0) return true; // слишком долго считать — считаем проходимым
            final nb = Board.copy(b)..place(s, r, c, 0);
            if (dfs(nb, others)) return true;
          }
        }
      }
      return false;
    }

    return dfs(board, shapes);
  }

  // ---------- Сохранение ----------

  Map<String, dynamic> toJson() => {
        'b': board.cells,
        't': [for (final p in tray) p == null ? null : [p.shape.id, p.color]],
        's': score,
        'k': streak,
        'm': movesSinceClear,
        'p': placements,
        'bs': bestStreak,
        'lc': linesCleared,
        'r': reviveUsed,
      };

  static GameModel? fromJson(Map<String, dynamic> j, {Random? rng}) {
    try {
      final m = GameModel._restore(rng ?? Random());
      m.board = Board.fromList((j['b'] as List).cast<int>());
      m.tray = [
        for (final t in (j['t'] as List))
          t == null ? null : TrayPiece(kShapes[(t as List)[0] as int], t[1] as int),
      ];
      m.score = j['s'] as int;
      m.streak = j['k'] as int;
      m.movesSinceClear = j['m'] as int;
      m.placements = j['p'] as int;
      m.bestStreak = j['bs'] as int;
      m.linesCleared = j['lc'] as int;
      m.reviveUsed = j['r'] as bool;
      if (m.tray.length != 3) return null;
      if (m.tray.every((p) => p == null)) m.refill();
      return m;
    } catch (_) {
      return null;
    }
  }
}
