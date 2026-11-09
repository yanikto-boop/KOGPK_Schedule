import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'bj_table.dart';
import 'casino_client.dart';
import 'poker_table.dart';

/// Лобби покера или блэкджека: список комнат, создание, вход по коду.
class CasinoLobbyScreen extends StatefulWidget {
  final String kind; // 'poker' | 'bj'
  const CasinoLobbyScreen({super.key, required this.kind});
  @override
  State<CasinoLobbyScreen> createState() => _CasinoLobbyScreenState();
}

class _CasinoLobbyScreenState extends State<CasinoLobbyScreen> {
  final c = CasinoClient.instance;
  StreamSubscription? _err;
  bool _tableOpen = false;

  bool get _poker => widget.kind == 'poker';

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    _err = c.errors.stream.listen((e) {
      if (mounted && !_tableOpen) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e)));
    });
    c.start();
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _err?.cancel();
    c.stop();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    if (c.room != null && !_tableOpen) {
      _tableOpen = true;
      final poker = c.kind == 'poker';
      Navigator.push(context,
              MaterialPageRoute(builder: (_) => poker ? const PokerTableScreen() : const BjTableScreen()))
          .then((_) => _tableOpen = false);
    }
  }

  Future<void> _joinByCode() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Код комнаты'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'Например, K7M2Q'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Войти')),
        ],
      ),
    );
    if (code != null && code.trim().isNotEmpty) c.join(code.trim());
  }

  void _create() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _poker ? const _PokerCreate() : const _BjCreate(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rooms = c.rooms.where((r) => r['kind'] == widget.kind).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(_poker ? 'Покер' : 'Блэкджек'),
        actions: [
          Center(child: Padding(padding: const EdgeInsets.only(right: 4), child: ChipsBadge(c.chips))),
          IconButton(tooltip: 'Войти по коду', icon: const Icon(Icons.vpn_key_outlined), onPressed: _joinByCode),
          IconButton(icon: const Icon(Icons.refresh), onPressed: c.refreshRooms),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: c.connected ? _create : null,
        icon: const Icon(Icons.add),
        label: const Text('Создать'),
      ),
      body: !c.connected
          ? const Center(child: Text('Подключаюсь…', style: TextStyle(color: AppColors.textDim)))
          : rooms.isEmpty
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                      _poker
                          ? 'Открытых столов нет.\nСоздайте свой — можно сразу с ботами.'
                          : 'Открытых столов нет.\nСоздайте стол: соло против дилера или с друзьями.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textDim)),
                ))
              : RefreshIndicator(
                  onRefresh: () async => c.refreshRooms(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                    itemCount: rooms.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _roomTile(rooms[i]),
                  ),
                ),
    );
  }

  Widget _roomTile(Map<String, dynamic> r) {
    final players = (r['players'] as List).cast<String>();
    final max = (r['max'] as num).toInt();
    final full = players.length >= max;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
        title: Text('${r['owner']} · ${players.length}/$max', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
            '${_poker ? 'Блайнды ${r['blinds']} · ' : ''}${r['status'] == 'playing' ? 'идёт раздача' : 'ждёт игроков'}\n${players.join(', ')}',
            style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
        isThreeLine: true,
        trailing: full
            ? const Text('мест нет', style: TextStyle(color: AppColors.textDim, fontSize: 12))
            : FilledButton(onPressed: () => c.join(r['id'] as String), child: const Text('За стол')),
      ),
    );
  }
}

/// Баланс фишек.
class ChipsBadge extends StatelessWidget {
  final int chips;
  const ChipsBadge(this.chips, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFD166).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFD166)),
        ),
        child: Text('🪙 $chips', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      );
}

class _PokerCreate extends StatefulWidget {
  const _PokerCreate();
  @override
  State<_PokerCreate> createState() => _PokerCreateState();
}

class _PokerCreateState extends State<_PokerCreate> {
  int bots = 0;
  bool private = false;
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Новый стол', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Техасский холдем · блайнды 10/20 · вход до 500 фишек, остаток вернётся в кошелёк',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            const SizedBox(height: 14),
            Text(bots == 0 ? 'Боты: без ботов (ждать игроков)' : 'Ботов за столом: $bots',
                style: const TextStyle(color: AppColors.textDim)),
            Slider(
              value: bots.toDouble(),
              min: 0,
              max: 5,
              divisions: 5,
              label: '$bots',
              onChanged: (v) => setState(() => bots = v.round()),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Только по коду'),
              subtitle: const Text('Стола не будет в общем списке (с ботами — всегда)',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              value: private || bots > 0,
              onChanged: bots > 0 ? null : (v) => setState(() => private = v),
            ),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: () {
                CasinoClient.instance.createPoker(private: private, bots: bots);
                Navigator.pop(context);
              },
              child: const Padding(padding: EdgeInsets.all(12), child: Text('Сесть за стол')),
            ),
          ]),
        ),
      );
}

class _BjCreate extends StatefulWidget {
  const _BjCreate();
  @override
  State<_BjCreate> createState() => _BjCreateState();
}

class _BjCreateState extends State<_BjCreate> {
  bool solo = true;
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Новый стол', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Ставки 10–1000 · блэкджек платит 3:2 · дилер стоит на 17',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Соло против дилера')),
                ButtonSegment(value: false, label: Text('Стол до 5 игроков')),
              ],
              selected: {solo},
              onSelectionChanged: (s) => setState(() => solo = s.first),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                CasinoClient.instance.createBj(solo: solo);
                Navigator.pop(context);
              },
              child: const Padding(padding: EdgeInsets.all(12), child: Text('Сесть за стол')),
            ),
          ]),
        ),
      );
}
