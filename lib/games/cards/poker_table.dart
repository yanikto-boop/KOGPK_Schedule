import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../durak/cards.dart';
import 'casino_client.dart';
import 'casino_lobby.dart';

const _gold = Color(0xFFFFD166);
const _feltLight = Color(0xFF1E7A4C);
const _feltDark = Color(0xFF0C3B26);

/// Карта «влетает» на стол: сдвиг сверху + плавное появление (как в дураке).
class DealIn extends StatelessWidget {
  final Widget child;
  final Offset from;
  const DealIn({super.key, required this.child, this.from = const Offset(0, -40)});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        builder: (_, t, ch) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(from.dx * (1 - t), from.dy * (1 - t)), child: ch),
        ),
        child: child,
      );
}

class PokerTableScreen extends StatefulWidget {
  const PokerTableScreen({super.key});
  @override
  State<PokerTableScreen> createState() => _PokerTableScreenState();
}

class _PokerTableScreenState extends State<PokerTableScreen> {
  final c = CasinoClient.instance;
  StreamSubscription? _err;
  Timer? _tick;
  bool _popped = false;
  double _raise = 0;
  String _raiseKey = '';

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    _err = c.errors.stream.listen((e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e), duration: const Duration(seconds: 2)));
      }
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _err?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    if (c.room == null && !_popped) {
      _popped = true;
      Navigator.pop(context);
      return;
    }
    setState(() {});
  }

  Future<void> _leave() async {
    final st = c.state;
    final playing = st != null && st['street'] != 'wait' && st['street'] != 'show';
    if (playing) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Встать из-за стола?'),
          content: const Text('Текущая раздача будет сброшена, остаток стека вернётся в кошелёк.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Остаться')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Уйти')),
          ],
        ),
      );
      if (ok != true) return;
    }
    c.leave();
  }

  @override
  Widget build(BuildContext context) {
    final st = c.state;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: _feltDark,
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment(0, -0.1), radius: 1.1, colors: [_feltLight, _feltDark]),
          ),
          child: st == null ? const SizedBox() : _body(st),
        ),
      ),
    );
  }

  Widget _body(Map<String, dynamic> st) {
    final seats = (st['seats'] as List).cast<Map<String, dynamic>>();
    final meIdx = st['me'] as int;
    final mine = seats.where((s) => s['i'] == meIdx).firstOrNull;
    final others = seats.where((s) => s['i'] != meIdx).toList();
    final cur = st['cur'] as int;
    final board = (st['board'] as List).cast<String>();
    final result = st['result'] as Map<String, dynamic>?;
    final street = st['street'] as String;
    final left = c.deadline == null ? null : c.deadline!.difference(DateTime.now()).inSeconds.clamp(0, 99);
    final myTurn = cur >= 0 && cur == meIdx;
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 8, 0),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: _leave),
            Expanded(
              child: Text('Холдем · блайнды ${(st['blinds'] as List).join('/')} · стол ${c.room!['id']}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.white70)),
            ),
            ChipsBadge(c.chips),
          ]),
        ),
        // соперники
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [for (final s in others) _seatTile(s, cur == s['i'], left)],
          ),
        ),
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(14)),
                child: Text('Банк: ${st['pot']}', style: const TextStyle(color: _gold, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 10),
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: i < board.length
                        ? DealIn(key: ValueKey('b$i${board[i]}'), child: PlayingCard(board[i], width: 54))
                        : Opacity(
                            opacity: 0.18,
                            child: Container(
                              width: 54,
                              height: 54 * 1.45,
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white, width: 1.5)),
                            ),
                          ),
                  ),
              ]),
              const SizedBox(height: 12),
              _banner(st, result, street, seats.length, mine),
            ]),
          ),
        ),
        if (mine != null) _mySeat(mine, cur == meIdx, left),
        _actions(st, mine, myTurn),
      ]),
    );
  }

  Widget _banner(Map<String, dynamic> st, Map<String, dynamic>? result, String street, int n, Map<String, dynamic>? mine) {
    String text = '';
    if (result != null) {
      final ws = (result['winners'] as List).cast<Map<String, dynamic>>();
      text = ws
          .map((w) => '🏆 ${w['name']} +${w['amount']}${(w['hand'] as String).isEmpty ? '' : ' · ${w['hand']}'}')
          .join('\n');
    } else if (street == 'wait') {
      text = n < 2 ? 'Ждём игроков…' : 'Раздача…';
    } else if (mine != null && mine['waiting'] == true) {
      text = 'Вы сядете в следующей раздаче';
    }
    if (text.isEmpty) return const SizedBox(height: 20);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(12)),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
    );
  }

  Widget _seatTile(Map<String, dynamic> s, bool active, int? left) {
    final folded = s['folded'] == true || s['waiting'] == true;
    final cards = (s['cards'] as List?)?.cast<String>();
    final has = s['has_cards'] == true || cards != null;
    return Opacity(
      opacity: folded ? 0.45 : 1,
      child: Container(
        width: 108,
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.32),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? _gold : Colors.transparent, width: 2),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (s['dealer'] == true) _dealerDot(),
            Flexible(
              child: Text('${s['bot'] == true ? '🤖 ' : ''}${s['name']}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            ),
            if (active && left != null) Text(' $left', style: const TextStyle(color: _gold, fontWeight: FontWeight.w700, fontSize: 12)),
          ]),
          Text('🪙 ${s['stack']}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 4),
          SizedBox(
            height: 38 * 1.45,
            child: has
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < 2; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: cards != null && i < cards.length
                            ? DealIn(key: ValueKey('o${s['uid']}${cards[i]}'), child: PlayingCard(cards[i], width: 38))
                            : DealIn(key: ValueKey('ob${s['uid']}$i${c.state?['hand_no']}'), child: const PlayingCard(null, width: 38)),
                      ),
                  ])
                : const SizedBox(),
          ),
          SizedBox(
            height: 16,
            child: Text(
                (s['hand'] as String?)?.isNotEmpty == true
                    ? s['hand'] as String
                    : (s['last'] as String? ?? ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: _gold, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  Widget _dealerDot() => Container(
        width: 16,
        height: 16,
        margin: const EdgeInsets.only(right: 4),
        alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
        child: const Text('D', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900)),
      );

  Widget _mySeat(Map<String, dynamic> s, bool active, int? left) {
    final cards = (s['cards'] as List?)?.cast<String>() ?? const <String>[];
    final folded = s['folded'] == true;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? _gold : Colors.transparent, width: 2),
      ),
      child: Row(children: [
        Opacity(
          opacity: folded ? 0.4 : 1,
          child: Row(children: [
            for (final cd in cards)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: DealIn(key: ValueKey('m$cd'), from: const Offset(0, 60), child: PlayingCard(cd, width: 64)),
              ),
            if (cards.isEmpty) const SizedBox(width: 64, height: 64 * 1.45),
          ]),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (s['dealer'] == true) _dealerDot(),
              const Flexible(child: Text('Вы', style: TextStyle(fontWeight: FontWeight.w800))),
              if (active && left != null) Text('  $left с', style: const TextStyle(color: _gold, fontWeight: FontWeight.w700)),
            ]),
            Text('🪙 ${s['stack']}', style: const TextStyle(color: Colors.white70)),
            if ((s['bet'] as num) > 0) Text('Ставка: ${s['bet']}', style: const TextStyle(color: _gold, fontSize: 12)),
            if ((s['last'] as String? ?? '').isNotEmpty)
              Text(s['last'] as String, style: const TextStyle(color: _gold, fontWeight: FontWeight.w700, fontSize: 12)),
            if ((s['hand'] as String?)?.isNotEmpty == true)
              Text(s['hand'] as String, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Widget _actions(Map<String, dynamic> st, Map<String, dynamic>? mine, bool myTurn) {
    final can = st['can'] as Map<String, dynamic>?;
    final pad = EdgeInsets.fromLTRB(10, 8, 10, 10 + MediaQuery.of(context).padding.bottom);
    if (!myTurn || can == null || mine == null) {
      return Container(
        color: const Color(0xFF0A2A1B),
        padding: pad,
        height: 78,
        alignment: Alignment.center,
        child: Text(
            st['street'] == 'show' || st['street'] == 'wait' ? 'Следующая раздача скоро…' : 'Ход соперника…',
            style: const TextStyle(color: Colors.white54)),
      );
    }
    final need = (can['need'] as num).toInt();
    final callAmt = (can['call'] as num).toInt();
    final minR = (can['min_raise'] as num).toInt();
    final maxR = (can['max_raise'] as num).toInt();
    final myBet = (mine['bet'] as num).toInt();
    final maxBet = myBet + need;
    final canRaise = maxR > maxBet;
    final key = '${st['hand_no']}-${st['street']}-$maxBet';
    if (key != _raiseKey) {
      _raiseKey = key;
      _raise = minR.toDouble();
    }
    _raise = _raise.clamp(minR.toDouble(), maxR.toDouble()).toDouble();
    final raiseTo = _raise.round();
    final pot = (st['pot'] as num).toInt();
    Widget quick(String t, int to) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
              onPressed: () => setState(() => _raise = to.clamp(minR, maxR).toDouble()),
              child: Text(t, style: const TextStyle(fontSize: 11)),
            ),
          ),
        );
    return Container(
      color: const Color(0xFF0A2A1B),
      padding: pad,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (canRaise) ...[
          Row(children: [
            quick('Мин', minR),
            quick('½ банка', maxBet + pot ~/ 2),
            quick('Банк', maxBet + pot),
            quick('Олл-ин', maxR),
          ]),
          if (maxR > minR)
            Slider(
              value: _raise,
              min: minR.toDouble(),
              max: maxR.toDouble(),
              onChanged: (v) => setState(() => _raise = v),
            ),
        ],
        Row(children: [
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB23A48)),
              onPressed: () => c.act('fold'),
              child: const Text('Фолд'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2D8A56)),
              onPressed: () => c.act(need == 0 ? 'check' : 'call'),
              child: Text(need == 0 ? 'Чек' : (callAmt >= (mine['stack'] as num).toInt() ? 'Олл-ин $callAmt' : 'Колл $callAmt')),
            ),
          ),
          if (canRaise) ...[
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC98A1B)),
                onPressed: () => c.act('raise', raiseTo),
                child: Text(raiseTo >= maxR ? 'Олл-ин' : (need == 0 ? 'Ставка $raiseTo' : 'Рейз до $raiseTo')),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}
