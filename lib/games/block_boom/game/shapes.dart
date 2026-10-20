import 'dart:math';

typedef Cell = ({int r, int c});

/// Фигура из клеток. [id] — индекс в [kShapes], он же пишется в сохранение.
class Shape {
  Shape(this.id, this.cells, this.weight, this.tier)
      : rows = cells.map((e) => e.r).reduce(max) + 1,
        cols = cells.map((e) => e.c).reduce(max) + 1;

  final int id;
  final List<Cell> cells;
  final int rows;
  final int cols;

  /// Базовая частота выпадения.
  final double weight;

  /// 0 — мелкие, 1 — средние, 2 — крупные (к концу партии их больше).
  final int tier;

  int get size => cells.length;
}

/// Все фигуры. Порядок не менять — на него завязаны сохранения.
final List<Shape> kShapes = _buildShapes();

List<Shape> _buildShapes() {
  const defs = <(List<String>, double, int)>[
    (['X'], 0.45, 0),
    (['XX'], 0.9, 0),
    (['X', 'X'], 0.9, 0),
    (['XXX'], 1.0, 1),
    (['X', 'X', 'X'], 1.0, 1),
    (['XXXX'], 0.75, 1),
    (['X', 'X', 'X', 'X'], 0.75, 1),
    (['XXXXX'], 0.45, 2),
    (['X', 'X', 'X', 'X', 'X'], 0.45, 2),
    (['XX', 'XX'], 1.1, 1),
    (['XXX', 'XXX', 'XXX'], 0.3, 2),
    (['XXX', 'XXX'], 0.45, 2),
    (['XX', 'XX', 'XX'], 0.45, 2),
    // уголки из трёх клеток
    (['XX', 'X.'], 0.6, 0),
    (['XX', '.X'], 0.6, 0),
    (['X.', 'XX'], 0.6, 0),
    (['.X', 'XX'], 0.6, 0),
    // Г-образные из четырёх
    (['X.', 'X.', 'XX'], 0.4, 1),
    (['.X', '.X', 'XX'], 0.4, 1),
    (['XX', 'X.', 'X.'], 0.4, 1),
    (['XX', '.X', '.X'], 0.4, 1),
    (['XXX', 'X..'], 0.4, 1),
    (['XXX', '..X'], 0.4, 1),
    (['X..', 'XXX'], 0.4, 1),
    (['..X', 'XXX'], 0.4, 1),
    // Т-образные
    (['XXX', '.X.'], 0.45, 1),
    (['.X.', 'XXX'], 0.45, 1),
    (['X.', 'XX', 'X.'], 0.45, 1),
    (['.X', 'XX', '.X'], 0.45, 1),
    // зигзаги
    (['.XX', 'XX.'], 0.4, 1),
    (['XX.', '.XX'], 0.4, 1),
    (['X.', 'XX', '.X'], 0.4, 1),
    (['.X', 'XX', 'X.'], 0.4, 1),
    // большие уголки 3×3
    (['XXX', 'X..', 'X..'], 0.3, 2),
    (['XXX', '..X', '..X'], 0.3, 2),
    (['X..', 'X..', 'XXX'], 0.3, 2),
    (['..X', '..X', 'XXX'], 0.3, 2),
  ];
  final list = <Shape>[];
  for (var i = 0; i < defs.length; i++) {
    final (rows, weight, tier) = defs[i];
    final cells = <Cell>[];
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        if (rows[r][c] == 'X') cells.add((r: r, c: c));
      }
    }
    list.add(Shape(i, cells, weight, tier));
  }
  return list;
}
