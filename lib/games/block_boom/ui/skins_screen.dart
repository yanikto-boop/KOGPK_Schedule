import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import '../game/profile.dart';
import 'background.dart';
import 'blocks.dart';
import 'skins.dart';
import 'widgets.dart';

class SkinsScreen extends StatelessWidget {
  const SkinsScreen({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: profile,
      builder: (context, _) {
        final skin = profile.skin;
        return Scaffold(
          backgroundColor: skin.bg.last,
          body: Stack(
            children: [
              Positioned.fill(child: Backdrop(skin: skin)),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Row(
                        children: [
                          SquareButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
                          const Expanded(child: Center(child: OutlinedText('Темы', size: 34))),
                          const SizedBox(width: 46),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: kSkins.length,
                        itemBuilder: (context, i) => _SkinCard(
                          skin: kSkins[i],
                          selected: kSkins[i].id == skin.id,
                          unlocked: profile.isUnlocked(kSkins[i]),
                          onTap: () {
                            final s = kSkins[i];
                            if (profile.isUnlocked(s)) {
                              profile.setSkin(s);
                              Sfx.play('pick');
                            } else {
                              Sfx.play('bad', volume: 0.6);
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(SnackBar(
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: const Color(0xFF2A1E6E),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  content: Text(
                                    'Тема «${s.name}» откроется на уровне ${s.unlockLevel}',
                                    style: const TextStyle(fontFamily: 'Russo', color: Colors.white),
                                  ),
                                ));
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkinCard extends StatelessWidget {
  const _SkinCard({required this.skin, required this.selected, required this.unlocked, required this.onTap});

  final Skin skin;
  final bool selected;
  final bool unlocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      sound: false,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: skin.bg),
          border: Border.all(
            color: selected ? const Color(0xFFFFCF33) : Colors.white.withValues(alpha: 0.2),
            width: selected ? 3.5 : 1.5,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6)),
            if (selected) BoxShadow(color: const Color(0xFFFFCF33).withValues(alpha: 0.4), blurRadius: 18),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: CustomPaint(painter: _PreviewPainter(skin)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedText(skin.name, size: 19, strokeWidth: 4),
                  const SizedBox(height: 4),
                  Text(
                    selected ? 'Выбрана' : (unlocked ? 'Выбрать' : 'Уровень ${skin.unlockLevel}'),
                    style: TextStyle(
                      fontFamily: 'Russo',
                      fontSize: 13,
                      color: selected ? const Color(0xFFFFE27A) : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            if (!unlocked)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Center(
                    child: Icon(Icons.lock_rounded, color: Colors.white, size: 44,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 10)]),
                  ),
                ),
              ),
            if (selected)
              const Positioned(
                right: 8,
                top: 8,
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: Color(0xFFFFCF33),
                  child: Icon(Icons.check_rounded, size: 18, color: kInk),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Мини-поле 4×4 с блоками в стиле темы.
class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.skin);
  final Skin skin;

  static const _pattern = [
    [0, 0, -1, 3],
    [1, -1, -1, 3],
    [1, 2, 2, 3],
    [-1, 5, 6, 7],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.08)),
      Paint()..color = skin.board.withValues(alpha: 0.85),
    );
    final pad = size.width * 0.05;
    final cell = (size.width - pad * 2) / 4;
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        final cr = Rect.fromLTWH(pad + c * cell, pad + r * cell, cell, cell);
        final v = _pattern[r][c];
        if (v < 0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(cr.deflate(cell * 0.05), Radius.circular(cell * 0.14)),
            Paint()..color = skin.cell,
          );
        } else {
          Blocks.draw(canvas, cr, skin.palette[v], skin.style);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.skin != skin;
}
