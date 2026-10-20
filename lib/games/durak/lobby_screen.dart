import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'durak_client.dart';
import 'table_screen.dart';

String rulesLabel(Map r) =>
    '${r['deck']} карт · ${r['transfer'] == true ? 'переводной' : 'подкидной'} · '
    '${r['throw_all'] == true ? 'подкидывают все' : 'подкидывают соседи'}';

class DurakLobbyScreen extends StatefulWidget {
  const DurakLobbyScreen({super.key});
  @override
  State<DurakLobbyScreen> createState() => _DurakLobbyScreenState();
}

class _DurakLobbyScreenState extends State<DurakLobbyScreen> {
  final c = DurakClient.instance;
  StreamSubscription? _err;
  bool _tableOpen = false;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    _err = c.errors.stream.listen((e) {
      if (mounted && !_tableOpen) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e)));
      }
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
      Navigator.push(context, MaterialPageRoute(builder: (_) => const DurakTableScreen()))
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

  @override
  Widget build(BuildContext context) {
    final rooms = c.rooms;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Дурак онлайн'),
        actions: [
          IconButton(
              tooltip: 'Войти по коду', icon: const Icon(Icons.vpn_key_outlined), onPressed: _joinByCode),
          IconButton(icon: const Icon(Icons.refresh), onPressed: c.refreshRooms),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: c.connected
            ? () => showModalBottomSheet(
                  context: context,
                  backgroundColor: AppColors.surface,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => const _CreateSheet(),
                )
            : null,
        icon: const Icon(Icons.add),
        label: const Text('Создать'),
      ),
      body: !c.connected
          ? const Center(child: Text('Подключаюсь…', style: TextStyle(color: AppColors.textDim)))
          : rooms.isEmpty
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Открытых комнат нет.\nСоздайте свою — и позовите одногруппников!',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
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
    final rules = r['rules'] as Map;
    final players = (r['players'] as List).cast<String>();
    final max = rules['players'] as int;
    final waiting = r['status'] == 'waiting' || (r['status'] == 'finished' && players.length < max);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.border)),
        title: Text('${r['owner']} · ${players.length}/$max',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${rulesLabel(rules)}\n${players.join(', ')}',
            style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
        isThreeLine: true,
        trailing: waiting
            ? FilledButton(onPressed: () => c.join(r['id'] as String), child: const Text('Играть'))
            : const Text('идёт игра', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
      ),
    );
  }
}

class _CreateSheet extends StatefulWidget {
  const _CreateSheet();
  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  int deck = 36, players = 2;
  bool transfer = false, throwAll = true, private = false;

  int get maxPlayers => deck == 24 ? 4 : 6;

  @override
  Widget build(BuildContext context) {
    if (players > maxPlayers) players = maxPlayers;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Новая комната',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 14),
            const Text('Колода', style: TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 24, label: Text('24')),
                ButtonSegment(value: 36, label: Text('36')),
                ButtonSegment(value: 52, label: Text('52')),
              ],
              selected: {deck},
              onSelectionChanged: (s) => setState(() => deck = s.first),
            ),
            const SizedBox(height: 12),
            Text('Игроков: $players', style: const TextStyle(color: AppColors.textDim)),
            Slider(
              value: players.toDouble(),
              min: 2,
              max: maxPlayers.toDouble(),
              divisions: maxPlayers - 2,
              label: '$players',
              onChanged: (v) => setState(() => players = v.round()),
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Подкидной')),
                ButtonSegment(value: true, label: Text('Переводной')),
              ],
              selected: {transfer},
              onSelectionChanged: (s) => setState(() => transfer = s.first),
            ),
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Подкидывают все')),
                ButtonSegment(value: false, label: Text('Соседи')),
              ],
              selected: {throwAll},
              onSelectionChanged: (s) => setState(() => throwAll = s.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Только по коду'),
              subtitle: const Text('Комнаты не будет в общем списке',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              value: private,
              onChanged: (v) => setState(() => private = v),
            ),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: () {
                DurakClient.instance.create(
                    players: players, deck: deck, transfer: transfer, throwAll: throwAll, private: private);
                Navigator.pop(context);
              },
              child: const Padding(padding: EdgeInsets.all(12), child: Text('Создать')),
            ),
          ],
        ),
      ),
    );
  }
}
