import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Карта — строка «ранг+масть»: "6S", "10H", "QD", "AC".
const _suitSym = {'S': '♠', 'C': '♣', 'D': '♦', 'H': '♥'};
const _rankRu = {'J': 'В', 'Q': 'Д', 'K': 'К', 'A': 'Т'};
const ranks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];

String cardRank(String c) => c.substring(0, c.length - 1);
String cardSuit(String c) => c[c.length - 1];
String suitSymbol(String s) => _suitSym[s] ?? s;
bool isRed(String c) => 'DH'.contains(cardSuit(c));

bool beats(String d, String a, String trump) {
  if (cardSuit(d) == cardSuit(a)) {
    return ranks.indexOf(cardRank(d)) > ranks.indexOf(cardRank(a));
  }
  return cardSuit(d) == trump;
}

/// Колода — SVG-cards 4.0.2 (LGPL-2.1), отрисована в WebP с русскими индексами.
void registerCardLicense() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/cards/LICENSE.txt');
    yield LicenseEntryWithLineBreaks(const ['SVG-cards'],
        'SVG-cards 4.0.2 — © David Bellot, Huub de Beer. https://github.com/htdebeer/SVG-cards\n'
        'Изображения карт перерисованы (индексы Т/К/Д/В, своя рубашка).\n\n$text');
  });
}

class PlayingCard extends StatelessWidget {
  final String? card; // null — рубашка
  final double width;
  final bool selected;
  final VoidCallback? onTap;
  const PlayingCard(this.card,
      {super.key,
      this.width = 56,
      this.selected = false,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = width * 1.45;
    final c = card;
    final face = Image.asset(
      'assets/cards/${c ?? 'back'}.webp',
      width: width,
      height: h,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => _drawn(c, h),
    );
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.translationValues(0, selected ? -16 : 0, 0),
        width: width,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.07),
          boxShadow: [
            BoxShadow(
                color: selected ? const Color(0xAAFFD166) : Colors.black38,
                blurRadius: selected ? 10 : 3,
                offset: const Offset(0, 1)),
          ],
        ),
        child: face,
      ),
    );
  }

  /// Запасная отрисовка, если картинки нет.
  Widget _drawn(String? c, double h) {
    if (c == null) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.07),
          gradient: const LinearGradient(
              colors: [Color(0xFF3557C9), Color(0xFF1C2E73)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1.5),
        ),
      );
    }
    final color = isRed(c) ? const Color(0xFFD7263D) : const Color(0xFF1B1B1F);
    final r = _rankRu[cardRank(c)] ?? cardRank(c);
    return Container(
      padding: EdgeInsets.all(width * 0.07),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.07),
        border: Border.all(color: Colors.black26),
      ),
      child: Stack(children: [
        Align(
          alignment: Alignment.topLeft,
          child: Text('$r\n${suitSymbol(cardSuit(c))}',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: width * 0.26, height: 1.0)),
        ),
        Align(
          alignment: Alignment.center,
          child: Text(suitSymbol(cardSuit(c)), style: TextStyle(color: color, fontSize: width * 0.5)),
        ),
      ]),
    );
  }
}
