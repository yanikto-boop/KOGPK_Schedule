import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../durak/cards.dart';
import 'casino_client.dart';
import 'casino_lobby.dart';
import 'poker_table.dart' show DealIn;

const _gold = Color(0xFFFFD166);
const _feltLight = Color(0xFF1B6E5A);
const _feltDark = Color(0xFF0B3A30);

class BjTableScreen extends StatefulWidget {
  const BjTableScreen({super.key});
  @override
  State<BjTableScreen> createState() => _BjTableScreenState();
}

class _BjTableScreenState extends State<BjTableScreen> {
  final c = CasinoClient.instance;
  StreamSubscription? _err;
  Timer? _tick;
  bool _popped = false;
  int _bet = 0; // набираемая ставка
  int _lastBet = 0;
  int _round = -1;

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
    final st = c.state;
    if (st != null) {
      final me = _mySeat(st);
      // новая фаза ставок — набираем с нуля
      if (st['phase'] == 'bet' && me != null && (me['bet'] as num) == 0 && _round != st['round_no']) {
        _round = st['round_no'] as int;
        _bet = 0;
      }
      if (me != null && (me['bet'] as num) > 0) _lastBet = (me['bet'] as num).toInt();
    }
    setState(() {});
  }

  Map<String, dynamic>? _mySeat(Map<String, dynamic> st) {
    final i = st['me'] as int;
    return (st['seats'] as List).cast<Map<String, dynamic>>().where((s) => s['i'] == i).firstOrNull;
  }

  Future<void> _leave() async {
    final st = c.state;
    final inRound = st != null && (st['phase'] == 'play' || st['phase'] == 'dealer');
    final me = st == null ? null : _mySeat(st);
    if (inRound && me != null && ['play', 'stand', 'bj'].contains(me['state'])) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Встать из-за стола?'),
          content: const Text('Ставка текущей раздачи сгорит.'),
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
            gradient: RadialGradient(center: Alignment(0, -0.2), radius: 1.1, colors: [_feltLight, _feltDark]),
          ),
          child: st == null ? const SizedBox() : _body(st),
        ),
      ),
    );
  }

  Widget _body(Map<String, dynamic> st) {
    final seats = (st['seats'] as List).cast<Map<String, dynamic>>();
    final me = _mySeat(st);
    final others = seats.where((s) => s['i'] != st['me']).toList();
    final dealer = (st['dealer'] as List).cast<String?>();
    final phase = st['phase'] as String;
    final left = c.deadline == null ? null : c.deadline!.difference(DateTime.now()).inSeconds.clamp(0, 99);
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 8, 0),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: _leave),
            Expanded(
              child: Text('Блэкджек · ${st['solo'] == true ? 'соло' : 'стол ${c.room!['id']}'}',
                  style: const TextStyle(fontSize: 13, color: Colors.white70)),
            ),
            ChipsBadge(c.chips),
          ]),
        ),
        // дилер
        const SizedBox(height: 4),
        Text(
            dealer.isEmpty ? 'Дилер' : 'Дилер · ${st['dealer_value']}${phase == 'play' ? '+?' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white70)),
        const SizedBox(height: 6),
        SizedBox(
          height: 62 * 1.45,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < dealer.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: DealIn(
                    key: ValueKey('d$i${dealer[i] ?? 'back'}${st['round_no']}'),
                    child: PlayingCard(dealer[i], width: 62)),
              ),
          ]),
        ),
        Expanded(
          child: Center(
            child: others.isEmpty
                ? (phase == 'bet' && st['solo'] != true
                    ? const Text('Ждём других игроков (можно играть и одному)', style: TextStyle(color: Colors.white38, fontSize: 12))
                    : const SizedBox())
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(children: [for (final s in others) _otherSeat(s, st)]),
                  ),
          ),
        ),
        if (me != null) _mine(me, st, left),
        _controls(st, me, left),
      ]),
    );
  }

  Widget _otherSeat(Map<String, dynamic> s, Map<String, dynamic> st) {
    final cards = (s['cards'] as List).cast<String>();
    final active = st['cur'] == s['i'];
    return Container(
      width: 120,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? _gold : Colors.transparent, width: 2),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(s['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        Text(((s['bet'] as num) > 0) ? '🪙 ${s['bet']}' : '—', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        const SizedBox(height: 4),
        SizedBox(
          height: 36 * 1.45,
          child: Stack(children: [
            for (var i = 0; i < cards.length; i++)
              Positioned(
                left: i * 18.0,
                child: DealIn(key: ValueKey('o${s['uid']}${cards[i]}'), child: PlayingCard(cards[i], width: 36)),
              ),
          ]),
        ),
        Text(_stateText(s), style: TextStyle(fontSize: 11, color: _stateColor(s), fontWeight: FontWeight.w700)),
      ]),
    );
  }

  String _stateText(Map<String, dynamic> s) {
    final v = s['value'];
    switch (s['outcome']) {
      case 'bj':
        return 'Блэкджек! +${(s['payout'] as num) - (s['bet'] as num)}';
      case 'win':
        return 'Победа +${(s['payout'] as num) - (s['bet'] as num)}';
      case 'push':
        return 'Ничья';
      case 'lose':
        return s['state'] == 'bust' ? 'Перебор $v' : 'Проигрыш';
    }
    switch (s['state']) {
      case 'bust':
        return 'Перебор $v';
      case 'bj':
        return 'Блэкджек!';
      case 'stand':
        return 'Стоит · $v';
      case 'play':
        return '$v';
      case 'bet':
        return 'Ставка сделана';
      case 'out':
        return 'Ждёт раздачу';
    }
    return '';
  }

  Color _stateColor(Map<String, dynamic> s) {
    switch (s['outcome']) {
      case 'bj':
      case 'win':
        return const Color(0xFF5BE38A);
      case 'lose':
        return const Color(0xFFFF7A7A);
    }
    return s['state'] == 'bust' ? const Color(0xFFFF7A7A) : _gold;
  }

  Widget _mine(Map<String, dynamic> s, Map<String, dynamic> st, int? left) {
    final cards = (s['cards'] as List).cast<String>();
    final active = st['cur'] == s['i'];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? _gold : Colors.transparent, width: 2),
      ),
      child: Row(children: [
        SizedBox(
          width: 64 + (cards.length > 1 ? (cards.length - 1) * 26.0 : 0),
          height: 64 * 1.45,
          child: Stack(children: [
            for (var i = 0; i < cards.length; i++)
              Positioned(
                left: i * 26.0,
                child: DealIn(key: ValueKey('m${cards[i]}'), from: const Offset(0, 60), child: PlayingCard(cards[i], width: 64)),
              ),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Вы', style: TextStyle(fontWeight: FontWeight.w800)),
              if (cards.isNotEmpty) Text('  ${s['value']}', style: const TextStyle(fontWeight: FontWeight.w800, color: _gold, fontSize: 18)),
              if (active && left != null) Text('   $left с', style: const TextStyle(color: _gold, fontWeight: FontWeight.w700)),
            ]),
            if ((s['bet'] as num) > 0)
              Text('Ставка: ${s['bet']}${s['doubled'] == true ? ' (удвоено)' : ''}', style: const TextStyle(color: Colors.white70)),
            Text(_stateText(s), style: TextStyle(fontWeight: FontWeight.w800, color: _stateColor(s))),
          ]),
        ),
      ]),
    );
  }

  Widget _controls(Map<String, dynamic> st, Map<String, dynamic>? me, int? left) {
    final pad = EdgeInsets.fromLTRB(10, 8, 10, 10 + MediaQuery.of(context).padding.bottom);
    final phase = st['phase'] as String;
    final limits = (st['limits'] as List).cast<num>();
    final minBet = limits[0].toInt(), maxBet = limits[1].toInt();
    Widget bar(Widget child) => Container(color: const Color(0xFF082A22), padding: pad, child: child);
    if (me == null) return bar(const SizedBox(height: 40));

    if (phase == 'bet') {
      final placed = (me['bet'] as num).toInt();
      if (placed > 0) {
        return bar(Row(children: [
          Expanded(
            child: Text('Ставка $placed принята · ждём ${st['solo'] == true ? '' : 'остальных · '}${left ?? ''} с',
                style: const TextStyle(color: Colors.white70)),
          ),
          TextButton(onPressed: c.clearBet, child: const Text('Изменить')),
        ]));
      }
      Widget chip(int v) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                onPressed: _bet + v <= c.chips && _bet + v <= maxBet ? () => setState(() => _bet += v) : null,
                child: Text('+$v'),
              ),
            ),
          );
      return bar(Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text('Ставка: $_bet', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _gold)),
          const Spacer(),
          if (left != null) Text('$left с', style: const TextStyle(color: Colors.white54)),
          TextButton(onPressed: _bet > 0 ? () => setState(() => _bet = 0) : null, child: const Text('Сброс')),
          if (_lastBet > 0)
            TextButton(
                onPressed: () => setState(() => _bet = _lastBet.clamp(minBet, maxBet).clamp(0, c.chips).toInt()),
                child: Text('Повтор $_lastBet')),
        ]),
        Row(children: [chip(10), chip(50), chip(100), chip(500)]),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _bet >= minBet && _bet <= c.chips ? () => c.bet(_bet) : null,
            child: Padding(padding: const EdgeInsets.all(10), child: Text(_bet >= minBet ? 'Поставить $_bet' : 'Минимум $minBet')),
          ),
        ),
      ]));
    }

    if (phase == 'play' && st['cur'] == st['me']) {
      return bar(Row(children: [
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2D8A56)),
            onPressed: () => c.move('hit'),
            child: const Padding(padding: EdgeInsets.all(10), child: Text('Ещё')),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB23A48)),
            onPressed: () => c.move('stand'),
            child: const Padding(padding: EdgeInsets.all(10), child: Text('Хватит')),
          ),
        ),
        if (st['can_double'] == true && c.chips >= (me['bet'] as num)) ...[
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC98A1B)),
              onPressed: () => c.move('double'),
              child: const Padding(padding: EdgeInsets.all(10), child: Text('Удвоить')),
            ),
          ),
        ],
      ]));
    }

    final msg = phase == 'result'
        ? 'Раунд окончен · скоро новая ставка'
        : phase == 'dealer'
            ? 'Дилер берёт карты…'
            : 'Ход другого игрока…';
    return bar(SizedBox(height: 44, child: Center(child: Text(msg, style: const TextStyle(color: Colors.white54)))));
  }
}
