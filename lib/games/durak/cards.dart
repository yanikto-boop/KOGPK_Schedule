import 'package:flutter/material.dart';

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
    final color = c != null && isRed(c) ? const Color(0xFFD7263D) : const Color(0xFF1B1B1F);
    Widget face;
    if (c == null) {
      face = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.12),
          gradient: const LinearGradient(
              colors: [Color(0xFF3557C9), Color(0xFF1C2E73)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1.5),
        ),
      );
    } else {
      final r = _rankRu[cardRank(c)] ?? cardRank(c);
      face = Container(
        padding: EdgeInsets.all(width * 0.07),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.12),
          border: Border.all(color: Colors.black26),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Stack(children: [
          Align(
            alignment: Alignment.topLeft,
            child: Text('$r\n${suitSymbol(cardSuit(c))}',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: width * 0.26,
                    height: 1.0)),
          ),
          Align(
            alignment: Alignment.center,
            child: Text(suitSymbol(cardSuit(c)),
                style: TextStyle(color: color, fontSize: width * 0.5)),
          ),
        ]),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.translationValues(0, selected ? -14 : 0, 0),
        width: width,
        height: h,
        child: face,
      ),
    );
  }
}
