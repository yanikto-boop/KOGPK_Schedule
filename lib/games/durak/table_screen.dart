import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import 'cards.dart';
import 'durak_client.dart';
import 'lobby_screen.dart';

class DurakTableScreen extends StatefulWidget {
  const DurakTableScreen({super.key});
  @override
  State<DurakTableScreen> createState() => _DurakTableScreenState();
}

class _DurakTableScreenState extends State<DurakTableScreen> {
  final c = DurakClient.instance;
  String? _sel;
  Timer? _tick;
  StreamSubscription? _err;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _err = c.errors.stream.listen((e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e), duration: const Duration(seconds: 2)));
      }
    });
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _tick?.cancel();
    _err?.cancel();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    if (c.room == null && !_popped) {
      _popped = true;
      Navigator.pop(context);
      return;
    }
    final hand = (c.game?['hand'] as List?)?.cast<String>() ?? const [];
    if (_sel != null && !hand.contains(_sel)) _sel = null;
    setState(() {});
  }

  bool get _playing => c.game != null && c.game!['finished'] != true;

  Future<void> _leave() async {
    if (_playing) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Выйти из партии?'),
          content: const Text('Партия закончится, и дураком будете вы.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Остаться')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти')),
          ],
        ),
      );
      if (ok != true) return;
    }
    c.leave();
  }

  String _nick(int id) {
    final seats = (c.room?['seats'] as List?) ?? const [];
    for (final s in seats) {
      if (s['id'] == id) return s['nick'] as String;
    }
    return '?';
  }

  bool _online(int id) {
    final seats = (c.room?['seats'] as List?) ?? const [];
    return seats.any((s) => s['id'] == id && s['online'] == true);
  }

  @override
  Widget build(BuildContext context) {
    final room = c.room;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F3D2E),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B2E22),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _leave),
          title: Text(room == null ? '' : 'Комната ${room['id']}', style: const TextStyle(fontSize: 16)),
          actions: [
            if (room != null)
              IconButton(
                tooltip: 'Скопировать код',
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: room['id'] as String));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Код скопирован')));
                },
              ),
          ],
        ),
        body: room == null
            ? const SizedBox()
            : c.game == null
                ? _waiting(room)
                : _table(room, c.game!),
      ),
    );
  }

  Widget _waiting(Map room) {
    final seats = (room['seats'] as List);
    final max = (room['rules'] as Map)['players'] as int;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Ждём игроков: ${seats.length} из $max',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 6),
          Text(rulesLabel(room['rules'] as Map),
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          for (final s in seats)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text('• ${s['nick']}', style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
          const SizedBox(height: 16),
          Text('Код комнаты: ${room['id']}',
              style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 2)),
          const SizedBox(height: 6),
          const Text('Партия начнётся сама, когда соберутся все',
              style: TextStyle(color: Colors.white60, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _table(Map room, Map g) {
    final me = c.me!;
    final seats = (g['seats'] as List).cast<int>();
    final counts = (g['counts'] as Map).map((k, v) => MapEntry(int.parse(k as String), v as int));
    final hand = (g['hand'] as List).cast<String>();
    final table = (g['table'] as List).map((p) => (p as List).cast<String?>()).toList();
    final trump = g['trump'] as String;
    final can = (g['can'] as Map).cast<String, dynamic>();
    final waiting = (g['waiting'] as List).cast<int>();
    final attacker = g['attacker'] as int, defender = g['defender'] as int;
    final out = (g['out'] as List).cast<int>();
    final i = seats.indexOf(me);
    final others = [for (var k = 1; k < seats.length; k++) seats[(i + k) % seats.length]];
    final left = c.deadline == null ? null : c.deadline!.difference(DateTime.now()).inSeconds.clamp(0, 99);

    final unbeaten = [for (var k = 0; k < table.length; k++) if (table[k][1] == null) k];
    final tableRanks = {for (final p in table) for (final x in p) if (x != null) cardRank(x)};
    bool canThrowCard(String x) => can['throw'] == true && (table.isEmpty || tableRanks.contains(cardRank(x)));
    bool canTransferCard(String x) => can['transfer'] == true && table.isNotEmpty && cardRank(x) == cardRank(table[0][0]!);
    List<int> targets(String x) => can['defend'] == true
        ? unbeaten.where((k) => beats(x, table[k][0]!, trump)).toList()
        : const [];
    bool usable(String x) => canThrowCard(x) || canTransferCard(x) || targets(x).isNotEmpty;

    String status;
    if (g['finished'] == true) {
      status = '';
    } else if (me == defender && waiting.contains(me)) {
      status = 'Отбивайтесь или берите';
    } else if (me == attacker && table.isEmpty) {
      status = 'Ваш ход';
    } else if (waiting.contains(me)) {
      status = g['taking'] == true ? 'Подкидывайте вдогонку или «Пас»' : 'Подкидывайте или «Бито»';
    } else if (out.contains(me)) {
      status = 'Вы вышли из игры 🎉';
    } else {
      status = 'Ходит ${waiting.map(_nick).join(', ')}';
    }

    final sel = _sel;
    final actions = <Widget>[];
    if (sel != null && canThrowCard(sel)) {
      actions.add(_btn(table.isEmpty ? 'Ходить' : 'Подкинуть', () => _do('throw', card: sel)));
    }
    if (sel != null && canTransferCard(sel)) {
      actions.add(_btn('Перевести', () => _do('transfer', card: sel)));
    }
    if (sel != null && targets(sel).length == 1) {
      actions.add(_btn('Побить', () => _do('defend', card: sel, idx: targets(sel).first)));
    }
    if (can['take'] == true) actions.add(_btn('Беру', () => _do('take'), warn: true));
    if (can['pass'] == true) actions.add(_btn(g['taking'] == true ? 'Пас' : 'Бито', () => _do('pass')));

    return Stack(children: [
      Column(children: [
        // соперники
        SizedBox(
          height: 92,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            children: [
              for (final p in others)
                _opponent(p, counts[p] ?? 0,
                    role: p == attacker ? 'ходит' : p == defender ? 'бьётся' : null,
                    turn: waiting.contains(p),
                    out: out.contains(p),
                    left: left),
            ],
          ),
        ),
        // колода и козырь
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            if ((g['deck'] as int) > 0) ...[
              PlayingCard(g['trump_card'] as String, width: 38),
              const SizedBox(width: 6),
              Text('×${g['deck']}', style: const TextStyle(color: Colors.white70)),
            ] else
              Text('Козырь ${suitSymbol(trump)}',
                  style: TextStyle(
                      color: 'DH'.contains(trump) ? const Color(0xFFFF6B6B) : Colors.white, fontSize: 18)),
            const Spacer(),
            Text('Бито: ${g['discard']}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
        // стол
        Expanded(
          child: Center(
            child: table.isEmpty
                ? Text(status, style: const TextStyle(color: Colors.white70, fontSize: 16))
                : Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var k = 0; k < table.length; k++)
                        SizedBox(
                          width: 72,
                          height: 104,
                          child: Stack(children: [
                            PlayingCard(table[k][0],
                                width: 60,
                                highlight: sel != null && table[k][1] == null && targets(sel).contains(k),
                                onTap: sel != null && targets(sel).contains(k)
                                    ? () => _do('defend', card: sel, idx: k)
                                    : null),
                            if (table[k][1] != null)
                              Positioned(left: 12, top: 16, child: PlayingCard(table[k][1], width: 60)),
                          ]),
                        ),
                    ],
                  ),
          ),
        ),
        if (table.isNotEmpty || status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
                [if (table.isNotEmpty) status, if (waiting.contains(me) && left != null) '⏱ $left с']
                    .join('   '),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        // действия
        SizedBox(
          height: 52,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final a in actions) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: a),
          ]),
        ),
        // рука
        SafeArea(
          top: false,
          child: SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(10, 18, 10, 6),
              children: [
                for (final x in hand)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: PlayingCard(x,
                        width: 58,
                        selected: x == sel,
                        dim: !usable(x),
                        onTap: () => setState(() => _sel = _sel == x ? null : x)),
                  ),
              ],
            ),
          ),
        ),
      ]),
      if (g['finished'] == true) _result(room),
    ]);
  }

  void _do(String t, {String? card, int? idx}) {
    c.act(t, card: card, idx: idx);
    setState(() => _sel = null);
  }

  Widget _btn(String label, VoidCallback onTap, {bool warn = false}) => FilledButton(
        style: FilledButton.styleFrom(
            backgroundColor: warn ? const Color(0xFFE0A030) : AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 18)),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  Widget _opponent(int p, int n, {String? role, required bool turn, required bool out, int? left}) {
    return Container(
      width: 96,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: turn ? const Color(0xFFFFD166) : Colors.transparent, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.circle, size: 8, color: _online(p) ? Colors.greenAccent : Colors.white24),
          const SizedBox(width: 4),
          Expanded(
              child: Text(_nick(p),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12))),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          const PlayingCard(null, width: 18),
          const SizedBox(width: 4),
          Text(out ? 'вышел' : '$n', style: const TextStyle(color: Colors.white70)),
        ]),
        const Spacer(),
        Text(turn && left != null ? '⏱ $left' : (role ?? ''),
            style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ]),
    );
  }

  Widget _result(Map room) {
    final res = c.result ?? const {};
    final loser = res['loser'];
    final me = c.me;
    final seats = (room['seats'] as List);
    final ready = seats.where((s) => s['ready'] == true).length;
    final full = seats.length == (room['rules'] as Map)['players'];
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.all(28),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              loser == null
                  ? 'Ничья!'
                  : loser == me
                      ? 'Вы дурак 🙈'
                      : 'Победа! 🎉',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (loser != null && loser != me)
            Text('Дурак: ${res['loser_nick']}', style: const TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 16),
          if (full)
            FilledButton(onPressed: c.rematch, child: Text('Ещё раз ($ready/${seats.length})'))
          else
            const Text('Кто-то вышел — ждём нового игрока', style: TextStyle(color: AppColors.textDim)),
          TextButton(onPressed: c.leave, child: const Text('Выйти')),
        ]),
      ),
    );
  }
}
