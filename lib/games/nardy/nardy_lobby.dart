import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'nardy_client.dart';
import 'nardy_table.dart';

const nardyRules = 'Длинные нарды. Бить нельзя: на пункт с чужой шашкой не встать. С головы — одна шашка '
    'за ход (первым ходом при 6:6, 4:4, 3:3 — две). Нельзя ставить шесть пунктов подряд, если впереди нет '
    'ни одной чужой шашки. Собрали все 15 в доме — выбрасывайте. Кто первым выбросил все — победил; '
    'у соперника ни одной выброшенной — марс.';

class NardyLobbyScreen extends StatefulWidget {
  const NardyLobbyScreen({super.key});
  @override
  State<NardyLobbyScreen> createState() => _NardyLobbyScreenState();
}

class _NardyLobbyScreenState extends State<NardyLobbyScreen> {
  final c = NardyClient.instance;
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
      Navigator.push(context, MaterialPageRoute(builder: (_) => const NardyTableScreen()))
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

  void _sheet(bool bot) => showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _CreateSheet(bot: bot),
      );

  @override
  Widget build(BuildContext context) {
    final rooms = c.rooms;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Нарды'),
        actions: [
          IconButton(tooltip: 'Войти по коду', icon: const Icon(Icons.vpn_key_outlined), onPressed: _joinByCode),
          IconButton(icon: const Icon(Icons.refresh), onPressed: c.refreshRooms),
        ],
      ),
      body: !c.connected
          ? const Center(child: Text('Подключаюсь…', style: TextStyle(color: AppColors.textDim)))
          : RefreshIndicator(
              onRefresh: () async => c.refreshRooms(),
              child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
                FilledButton.icon(
                  onPressed: () => _sheet(true),
                  icon: const Icon(Icons.smart_toy_outlined),
                  label: const Padding(padding: EdgeInsets.all(12), child: Text('Играть с ботом')),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _sheet(false),
                  icon: const Icon(Icons.group_outlined),
                  label: const Padding(padding: EdgeInsets.all(12), child: Text('Создать комнату для друга')),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
                  child: Text('Открытые комнаты', style: TextStyle(color: AppColors.textDim)),
                ),
                if (rooms.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Пока никого — создайте свою и позовите одногруппников!',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
                  ),
                for (final r in rooms) Padding(padding: const EdgeInsets.only(bottom: 8), child: _roomTile(r)),
              ]),
            ),
    );
  }

  Widget _roomTile(Map<String, dynamic> r) {
    final players = (r['players'] as List).cast<String>();
    final open = r['status'] != 'playing' && players.length < 2;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
        title: Text('${r['owner']} · ${players.length}/2', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('Длинные нарды', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        trailing: open
            ? FilledButton(onPressed: () => c.join(r['id'] as String), child: const Text('Играть'))
            : const Text('идёт игра', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
      ),
    );
  }
}

class _CreateSheet extends StatefulWidget {
  final bool bot;
  const _CreateSheet({required this.bot});
  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  int level = 2;
  bool private = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.bot ? 'Игра с ботом' : 'Новая комната',
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 10),
            const Text(nardyRules, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            const SizedBox(height: 12),
            if (widget.bot) ...[
              const Text('Уровень', style: TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('Лёгкий')),
                  ButtonSegment(value: 2, label: Text('Средний')),
                  ButtonSegment(value: 3, label: Text('Сильный')),
                ],
                selected: {level},
                onSelectionChanged: (s) => setState(() => level = s.first),
              ),
              const SizedBox(height: 6),
              const Text('Игры с ботом в таблицу лидеров не идут.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            ] else
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Только по коду'),
                subtitle: const Text('Комнаты не будет в общем списке',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                value: private,
                onChanged: (v) => setState(() => private = v),
              ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () {
                final c = NardyClient.instance;
                widget.bot ? c.withBot(level) : c.create(private: private);
                Navigator.pop(context);
              },
              child: Padding(padding: const EdgeInsets.all(12), child: Text(widget.bot ? 'Начать' : 'Создать')),
            ),
          ],
        ),
      ),
    );
  }
}
