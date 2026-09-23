import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import '../errors.dart';

/// Кабинеты: список с поиском и этажами + «Свободные сейчас».
/// Данные сервер собирает из расписания групп — отдельного источника нет.
class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});
  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  List<RoomRef> _all = [];
  String _q = '';
  String? _floor; // null — все этажи
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await Api.rooms();
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final filtered = _all
        .where((r) => _floor == null || r.floor == _floor)
        .where((r) => q.isEmpty || r.name.toLowerCase().contains(q))
        .toList();
    // этажи в порядке сервера, только те, где есть кабинеты
    final floors = <String, String>{};
    for (final r in _all) {
      floors.putIfAbsent(r.floor, () => r.floorLabel);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Кабинеты')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'Номер или название кабинета…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
          ),
          if (floors.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _chip('Все', null),
                  for (final e in floors.entries) _chip(e.value, e.key),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(child: _list(filtered)),
        ],
      ),
    );
  }

  Widget _chip(String label, String? floor) {
    final selected = _floor == floor;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _floor = floor),
        selectedColor: AppColors.primary.withValues(alpha: 0.25),
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.border),
        labelStyle: TextStyle(
            fontSize: 13,
            color: selected ? AppColors.primary : AppColors.text),
      ),
    );
  }

  Widget _list(List<RoomRef> filtered) {
    if (_loading) return const StatusView(message: 'Загрузка…');
    if (_error != null) {
      return StatusView(message: _error!, isError: true, onRetry: _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        itemCount: filtered.length + 1,
        separatorBuilder: (_, i) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          if (i == 0) return _freeCard();
          final room = filtered[i - 1];
          final number = RegExp(r'^\d+').stringMatch(room.name) ?? '•';
          return Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.border)),
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text(number,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
              title: Text(room.name, style: const TextStyle(fontSize: 14.5)),
              subtitle: Text(room.floorLabel,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textDim),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => RoomScheduleScreen(name: room.name))),
            ),
          );
        },
      ),
    );
  }

  Widget _freeCard() => Material(
        color: AppColors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.green.withValues(alpha: 0.4))),
          leading: const Icon(Icons.meeting_room, color: AppColors.green),
          title: const Text('Свободные сейчас',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Какие кабинеты не заняты на этой паре',
              style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textDim),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const FreeRoomsScreen())),
        ),
      );
}

class RoomScheduleScreen extends StatefulWidget {
  final String name;
  const RoomScheduleScreen({super.key, required this.name});
  @override
  State<RoomScheduleScreen> createState() => _RoomScheduleScreenState();
}

class _RoomScheduleScreenState extends State<RoomScheduleScreen> {
  ScheduleData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await Api.room(widget.name);
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name, style: const TextStyle(fontSize: 16))),
      body: _loading
          ? const StatusView(message: 'Загрузка…')
          : _error != null
              ? StatusView(message: _error!, isError: true, onRetry: _load)
              : ScheduleDayList(data: _data!, onRefresh: _load),
    );
  }
}

/// Свободные кабинеты колледжа на выбранную пару сегодня.
/// Кабинеты СОШ №10 не учитываются — их занятость нам не видна.
class FreeRoomsScreen extends StatefulWidget {
  const FreeRoomsScreen({super.key});
  @override
  State<FreeRoomsScreen> createState() => _FreeRoomsScreenState();
}

class _FreeRoomsScreenState extends State<FreeRoomsScreen> {
  FreeRooms? _data;
  String? _num; // null — сервер выберет текущую/следующую пару
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await Api.roomsFree(num: _num);
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  void _pick(String num) {
    _num = num;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Свободные кабинеты')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const StatusView(message: 'Загрузка…');
    if (_error != null) {
      return StatusView(message: _error!, isError: true, onRetry: _load);
    }
    final d = _data!;
    if (d.title == null) {
      return const StatusView(message: 'Сегодня занятий нет — свободно всё 😴');
    }
    final slot = d.pairs.where((p) => p.num == d.num).firstOrNull;
    final when = switch (d.state) {
      'now' => 'идёт сейчас',
      'next' => 'следующая',
      _ => '',
    };
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          Text(d.title!,
              style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in d.pairs)
                ChoiceChip(
                  label: Text('${p.num} пара'),
                  selected: p.num == d.num,
                  onSelected: (_) => _pick(p.num),
                  selectedColor: AppColors.primary.withValues(alpha: 0.25),
                  backgroundColor: AppColors.surface,
                  side: const BorderSide(color: AppColors.border),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (d.num == null)
            const Text('Пары на сегодня закончились — свободно всё 🎉',
                style: TextStyle(fontSize: 15))
          else ...[
            Text(
              '${d.num} пара${when.isEmpty ? '' : ' · $when'}'
              '${slot == null ? '' : ' · ${slot.start}–${slot.end}'}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('Свободно ${d.free.length}, занято ${d.busy}',
                style: const TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            const SizedBox(height: 10),
            if (d.free.isEmpty)
              const Text('Свободных кабинетов нет',
                  style: TextStyle(color: AppColors.textDim))
            else
              for (final r in d.free)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppColors.border)),
                      leading: const Icon(Icons.check_circle_outline,
                          color: AppColors.green),
                      title: Text(r, style: const TextStyle(fontSize: 14.5)),
                      trailing: const Icon(Icons.chevron_right,
                          color: AppColors.textDim),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => RoomScheduleScreen(name: r))),
                    ),
                  ),
                ),
            const SizedBox(height: 8),
            const Text('Кабинеты СОШ №10 не учитываются.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
