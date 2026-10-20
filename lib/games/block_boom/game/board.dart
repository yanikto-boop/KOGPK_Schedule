import 'shapes.dart';

const int kN = 8;

/// Какие строки/столбцы собраны.
class Lines {
  const Lines(this.rows, this.cols);
  final List<int> rows;
  final List<int> cols;
  int get count => rows.length + cols.length;
  bool get isEmpty => count == 0;

  bool containsCell(int index) =>
      rows.contains(index ~/ kN) || cols.contains(index % kN);
}

class BoardPlacement {
  BoardPlacement(this.placed, this.lines, this.cleared);

  /// Индексы клеток, куда встала фигура.
  final List<int> placed;
  final Lines lines;

  /// Очищенные клетки: индекс -> цвет, который там был.
  final Map<int, int> cleared;
}

/// Поле 8×8. В клетке -1 (пусто) или индекс цвета.
class Board {
  Board() : cells = List<int>.filled(kN * kN, -1);
  Board.copy(Board other) : cells = List<int>.of(other.cells);
  Board.fromList(List<int> list) : cells = List<int>.of(list) {
    assert(list.length == kN * kN);
  }

  final List<int> cells;

  int at(int r, int c) => cells[r * kN + c];
  bool get isClear => cells.every((v) => v < 0);
  int get filled => cells.where((v) => v >= 0).length;

  bool canPlace(Shape s, int r, int c) {
    if (r < 0 || c < 0 || r + s.rows > kN || c + s.cols > kN) return false;
    for (final p in s.cells) {
      if (cells[(r + p.r) * kN + c + p.c] >= 0) return false;
    }
    return true;
  }

  bool fitsAnywhere(Shape s) {
    for (var r = 0; r <= kN - s.rows; r++) {
      for (var c = 0; c <= kN - s.cols; c++) {
        if (canPlace(s, r, c)) return true;
      }
    }
    return false;
  }

  /// Линии, которые соберутся, если поставить фигуру (поле не меняется).
  Lines linesIfPlaced(Shape s, int r, int c) {
    final piece = <int>{for (final p in s.cells) (r + p.r) * kN + c + p.c};
    bool filledAt(int i) => cells[i] >= 0 || piece.contains(i);
    final rows = <int>[];
    for (var rr = r; rr < r + s.rows; rr++) {
      var full = true;
      for (var cc = 0; cc < kN && full; cc++) {
        full = filledAt(rr * kN + cc);
      }
      if (full) rows.add(rr);
    }
    final cols = <int>[];
    for (var cc = c; cc < c + s.cols; cc++) {
      var full = true;
      for (var rr = 0; rr < kN && full; rr++) {
        full = filledAt(rr * kN + cc);
      }
      if (full) cols.add(cc);
    }
    return Lines(rows, cols);
  }

  /// Может ли фигура где-нибудь собрать линию.
  bool canClearSomewhere(Shape s) {
    for (var r = 0; r <= kN - s.rows; r++) {
      for (var c = 0; c <= kN - s.cols; c++) {
        if (canPlace(s, r, c) && !linesIfPlaced(s, r, c).isEmpty) return true;
      }
    }
    return false;
  }

  /// Ставит фигуру и сразу очищает собранные линии.
  BoardPlacement place(Shape s, int r, int c, int color) {
    final lines = linesIfPlaced(s, r, c);
    final placed = <int>[];
    for (final p in s.cells) {
      final i = (r + p.r) * kN + c + p.c;
      cells[i] = color;
      placed.add(i);
    }
    final cleared = <int, int>{};
    for (final row in lines.rows) {
      for (var cc = 0; cc < kN; cc++) {
        cleared[row * kN + cc] = cells[row * kN + cc];
      }
    }
    for (final col in lines.cols) {
      for (var rr = 0; rr < kN; rr++) {
        cleared[rr * kN + col] = cells[rr * kN + col];
      }
    }
    for (final i in cleared.keys) {
      cells[i] = -1;
    }
    return BoardPlacement(placed, lines, cleared);
  }
}
