import 'package:flutter/material.dart';

import '../theme.dart';
import 'block_boom/block_boom.dart';
import 'durak/lobby_screen.dart';
import 'games_api.dart';

/// Дурак: сначала ник (если ещё нет), потом лобби.
Future<void> openDurak(BuildContext context) async {
  await GamesApi.load();
  if (!context.mounted) return;
  if (!GamesApi.registered) {
    final ok = await showDialog<bool>(context: context, builder: (_) => const NickDialog());
    if (ok != true || !context.mounted) return;
  }
  Navigator.push(context, MaterialPageRoute(builder: (_) => const DurakLobbyScreen()));
}

/// Полоска на главной над нижней панелью: «Если скучно на парах».
class BoredStrip extends StatelessWidget {
  const BoredStrip({super.key});

  @override
  Widget build(BuildContext context) {
    Widget btn(String emoji, String title, VoidCallback onTap) => Expanded(
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ]),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 6),
          child: Text('Если скучно на парах', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
        ),
        Row(children: [
          btn('🧩', 'Block Boom', () => openBlockBoom(context)),
          const SizedBox(width: 10),
          btn('🃏', 'Дурак онлайн', () => openDurak(context)),
        ]),
      ]),
    );
  }
}

/// «Ещё» → «Игры»: ник, Block Boom, дурак онлайн, таблицы лидеров.
class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});
  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    GamesApi.load().then((_) {
      if (mounted) setState(() => _loaded = true);
      GamesApi.flushBb();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Игры')),
      body: !_loaded
          ? const SizedBox()
          : ListView(padding: const EdgeInsets.all(12), children: [
              _card(
                icon: Icons.badge_outlined,
                title: GamesApi.registered ? GamesApi.nick! : 'Ник не выбран',
                subtitle: GamesApi.registered
                    ? 'Ваш ник в таблицах лидеров и в дураке · нажмите, чтобы сменить'
                    : 'Нужен для таблиц лидеров и игры с другими',
                onTap: () async {
                  await showDialog<bool>(
                      context: context, builder: (_) => NickDialog(rename: GamesApi.registered));
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 8),
              _card(
                icon: Icons.grid_view_rounded,
                title: 'Block Boom',
                subtitle: 'Головоломка с блоками — на перемену',
                onTap: () => openBlockBoom(context),
              ),
              _card(
                icon: Icons.style_outlined,
                title: 'Дурак онлайн',
                subtitle: 'До 6 игроков · подкидной и переводной · 24/36/52 карты',
                onTap: () async {
                  await openDurak(context);
                  if (mounted) setState(() {});
                },
              ),
              _card(
                icon: Icons.emoji_events_outlined,
                title: 'Таблица лидеров',
                subtitle: 'Рекорды Block Boom и победы в дураке',
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
              ),
            ]),
    );
  }

  Widget _card({required IconData icon, required String title, required String subtitle, VoidCallback? onTap}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
            leading: Icon(icon, color: AppColors.primary),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textDim),
            onTap: onTap,
          ),
        ),
      );
}

class NickDialog extends StatefulWidget {
  final bool rename;
  const NickDialog({super.key, this.rename = false});
  @override
  State<NickDialog> createState() => _NickDialogState();
}

class _NickDialogState extends State<NickDialog> {
  final _ctrl = TextEditingController(text: GamesApi.nick ?? '');
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.rename) {
        await GamesApi.rename(_ctrl.text);
      } else {
        await GamesApi.register(_ctrl.text);
        // накопленный офлайн рекорд Block Boom сразу в таблицу
        await GamesApi.flushBb();
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e is GamesError ? e.message : 'Нет связи с сервером';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.rename ? 'Сменить ник' : 'Придумайте ник'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _ctrl,
          autofocus: true,
          maxLength: 16,
          decoration: InputDecoration(hintText: 'От 3 до 16 символов', errorText: _error),
          onSubmitted: (_) => _save(),
        ),
        const Text('Ник уникальный: «Вася», «Vasya» и «ВАСЯ» считаются одним.',
            style: TextStyle(color: AppColors.textDim, fontSize: 12)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Сохранить')),
      ],
    );
  }
}

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Таблица лидеров'),
          bottom: const TabBar(tabs: [Tab(text: 'Block Boom'), Tab(text: 'Дурак')]),
        ),
        body: TabBarView(children: [
          _Board(load: GamesApi.bbTop, value: (r) => '${r.field('bb_best')}'),
          _Board(
              load: GamesApi.durakTop,
              value: (r) => '${r.field('durak_wins')} побед из ${r.field('durak_games')}'),
        ]),
      ),
    );
  }
}

class _Board extends StatefulWidget {
  final Future<Leaderboard> Function() load;
  final String Function(LeaderRow) value;
  const _Board({required this.load, required this.value});
  @override
  State<_Board> createState() => _BoardState();
}

class _BoardState extends State<_Board> {
  late Future<Leaderboard> _f;
  @override
  void initState() {
    super.initState();
    _f = GamesApi.load().then((_) => widget.load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Leaderboard>(
      future: _f,
      builder: (_, s) {
        if (s.hasError) {
          return Center(child: Text('${s.error}', style: const TextStyle(color: AppColors.textDim)));
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final b = s.data!;
        if (b.top.isEmpty) {
          return const Center(child: Text('Пока пусто — будьте первым!', style: TextStyle(color: AppColors.textDim)));
        }
        final mineOutside = b.me != null && !b.top.any((r) => r.me);
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _f = widget.load());
            await _f;
          },
          child: ListView(padding: const EdgeInsets.all(12), children: [
            if (b.offline)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Нет сети — показана сохранённая таблица',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
              ),
            for (final r in b.top) _row(r),
            if (mineOutside) ...[const Divider(), _row(b.me!)],
          ]),
        );
      },
    );
  }

  Widget _row(LeaderRow r) {
    final medal = {1: '🥇', 2: '🥈', 3: '🥉'}[r.rank];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: r.me ? AppColors.primary.withValues(alpha: 0.18) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: r.me ? AppColors.primary : AppColors.border),
      ),
      child: Row(children: [
        SizedBox(width: 38, child: Text(medal ?? '${r.rank}', style: const TextStyle(fontWeight: FontWeight.w700))),
        Expanded(child: Text(r.nick, style: const TextStyle(fontWeight: FontWeight.w600))),
        Text(widget.value(r), style: const TextStyle(color: AppColors.textDim)),
      ]),
    );
  }
}
