import 'package:flutter/material.dart';

enum BlockStyle { bevel, neon, jelly, gem, metal }

/// Тема оформления: палитра блоков, фон, поле и форма блоков.
class Skin {
  const Skin({
    required this.id,
    required this.name,
    required this.unlockLevel,
    required this.style,
    required this.palette,
    required this.bg,
    required this.board,
    required this.cell,
    required this.accent,
  });

  final String id;
  final String name;
  final int unlockLevel;
  final BlockStyle style;
  final List<Color> palette;

  /// Градиент фона сверху вниз.
  final List<Color> bg;
  final Color board;
  final Color cell;
  final Color accent;
}

const kSkins = <Skin>[
  Skin(
    id: 'classic',
    name: 'Классика',
    unlockLevel: 1,
    style: BlockStyle.bevel,
    palette: [
      Color(0xFFFF4D5E),
      Color(0xFFFF9A2E),
      Color(0xFFFFCF33),
      Color(0xFF3DDC84),
      Color(0xFF2EC4F1),
      Color(0xFF4A7BFF),
      Color(0xFFA66BFF),
      Color(0xFFFF6FB5),
    ],
    bg: [Color(0xFF4458D8), Color(0xFF2B2F96), Color(0xFF1A1760)],
    board: Color(0xFF151A55),
    cell: Color(0xFF232C78),
    accent: Color(0xFFFFCF33),
  ),
  Skin(
    id: 'neon',
    name: 'Неон',
    unlockLevel: 2,
    style: BlockStyle.neon,
    palette: [
      Color(0xFFFF2E88),
      Color(0xFFFF7A00),
      Color(0xFFFFE600),
      Color(0xFF39FF14),
      Color(0xFF00F0FF),
      Color(0xFF3D8BFF),
      Color(0xFFB026FF),
      Color(0xFFFF3DF5),
    ],
    bg: [Color(0xFF1A0B3A), Color(0xFF0E0726), Color(0xFF05030F)],
    board: Color(0xFF0A0719),
    cell: Color(0xFF171131),
    accent: Color(0xFF00F0FF),
  ),
  Skin(
    id: 'jelly',
    name: 'Желейки',
    unlockLevel: 4,
    style: BlockStyle.jelly,
    palette: [
      Color(0xFFFF5C7C),
      Color(0xFFFF9D4D),
      Color(0xFFFFD452),
      Color(0xFF6EDC8C),
      Color(0xFF5CD0FF),
      Color(0xFF7A8CFF),
      Color(0xFFC78BFF),
      Color(0xFFFF8BD1),
    ],
    bg: [Color(0xFFB45FD0), Color(0xFF8A47C4), Color(0xFF5B2A9E)],
    board: Color(0xFF3E1B6E),
    cell: Color(0xFF55298C),
    accent: Color(0xFFFFD452),
  ),
  Skin(
    id: 'ocean',
    name: 'Океан',
    unlockLevel: 6,
    style: BlockStyle.gem,
    palette: [
      Color(0xFFFF7B9C),
      Color(0xFFFFB35C),
      Color(0xFFFFE066),
      Color(0xFF00E5B0),
      Color(0xFF3FD8FF),
      Color(0xFF3D7BFF),
      Color(0xFF8C6BFF),
      Color(0xFF5CF2E0),
    ],
    bg: [Color(0xFF0B87A8), Color(0xFF0A4F82), Color(0xFF06214A)],
    board: Color(0xFF042440),
    cell: Color(0xFF0A3558),
    accent: Color(0xFF5CF2E0),
  ),
  Skin(
    id: 'lava',
    name: 'Лава',
    unlockLevel: 9,
    style: BlockStyle.bevel,
    palette: [
      Color(0xFFFF3B30),
      Color(0xFFFF6A00),
      Color(0xFFFF9500),
      Color(0xFFFFC300),
      Color(0xFFFF2D6F),
      Color(0xFFE0115F),
      Color(0xFFFF8A65),
      Color(0xFFFFE066),
    ],
    bg: [Color(0xFF4A0E0E), Color(0xFF260606), Color(0xFF0C0202)],
    board: Color(0xFF1C0606),
    cell: Color(0xFF34110E),
    accent: Color(0xFFFF9500),
  ),
  Skin(
    id: 'gold',
    name: 'Сокровища',
    unlockLevel: 12,
    style: BlockStyle.metal,
    palette: [
      Color(0xFFE0115F),
      Color(0xFFCD7F32),
      Color(0xFFFFC83D),
      Color(0xFF2FBF71),
      Color(0xFFB9C6D6),
      Color(0xFF1F5FD1),
      Color(0xFF8E44D8),
      Color(0xFFF4A7A0),
    ],
    bg: [Color(0xFF3A2A0A), Color(0xFF1C1405), Color(0xFF070501)],
    board: Color(0xFF140E03),
    cell: Color(0xFF2A1F0A),
    accent: Color(0xFFFFC83D),
  ),
];
