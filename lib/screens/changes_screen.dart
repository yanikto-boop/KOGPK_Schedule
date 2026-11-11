import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../services/profile.dart';
import '../theme.dart';
import '../widgets.dart';
import '../services/notif_service.dart';
import '../errors.dart';

/// Изменения расписания: сверху кнопки дней, в которых что-то поменяли,
/// ниже — карточки пар выбранного дня («было → стало»).
class ChangesScreen extends StatefulWidget {
  const ChangesScreen({super.key});
  @override
  State<ChangesScreen> createState() => _ChangesScreenState();
}

/// Изменения одного учебного дня.
class ChangeDay {
  final DateTime? date; // null — день из текста разобрать не удалось
  final String weekday;
  final List<ScheduleChange> items;
  ChangeDay(this.date, this.weekday, this.items);

  /// Группирует ленту по учебным дням (по возрастанию даты; неразобранные —
  /// в конце). Внутри дня — по номеру пары, свежие правки выше.
  static List<ChangeDay> group(List<ScheduleChange> all) {
    final map = <DateTime?, ChangeDay>{};
    for (final c in all) {
      map.putIfAbsent(c.day, () => ChangeDay(c.day, c.weekday, [])).items.add(c);
    }
    final days = map.values.toList()
      ..sort((a, b) {
        if (a.date == null) return b.date == null ? 0 : 1;
        if (b.date == null) return -1;
        return a.date!.compareTo(b.date!);
      });
    for (final d in days) {
      if (d.date != null) {
        final net = collapse(d.items);
        d.items
          ..clear()
          ..addAll(net);
      }
      d.items.sort((a, b) {
        final n = (int.tryParse(a.pairNum) ?? 99)
            .compareTo(int.tryParse(b.pairNum) ?? 99);
        return n != 0 ? n : b.ts.compareTo(a.ts);
      });
    }
    days.removeWhere((d) => d.items.isEmpty);
    return days;
  }

  /// Несколько правок одной пары -> один итог. Расписание на сайте правят в
  /// несколько заходов (и туда-обратно), лента копит каждый шаг, а человеку
  /// нужно «было в начале → стало сейчас». Поле, вернувшееся к исходному,
  /// выбрасывается; если среди шагов пару добавляли/снимали — берём последний шаг.
  static List<ScheduleChange> collapse(List<ScheduleChange> items) {
    final byKey = <String, List<ScheduleChange>>{};
    for (final c in items) {
      byKey.putIfAbsent('${c.pairNum}|${c.pairGroup}', () => []).add(c);
    }
    String norm(String v) => v.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
    final out = <ScheduleChange>[];
    for (final steps in byKey.values) {
      steps.sort((a, b) => a.ts.compareTo(b.ts)); // от старых к новым
      if (steps.length == 1) {
        out.add(steps.first);
        continue;
      }
      if (steps.any((c) => c.kind != ChangeKind.edited)) {
        out.add(steps.last);
        continue;
      }
      final first = <String, String>{}, last = <String, String>{};
      for (final c in steps) {
        for (final f in c.fields) {
          if (f.before.isEmpty) continue; // «Группа» и прочие подписи без «было»
          first.putIfAbsent(f.label, () => f.before);
          last[f.label] = f.after;
        }
      }
      final fields = [
        for (final l in first.keys)
          if (norm(first[l]!) != norm(last[l]!)) ChangeField(l, first[l]!, last[l]!)
      ];
      if (fields.isNotEmpty) out.add(steps.last.withFields(fields));
    }
    return out;
  }

  /// День по умолчанию: ближайший не прошедший, иначе последний.
  static int defaultIndex(List<ChangeDay> days, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final i =
        days.indexWhere((d) => d.date != null && !d.date!.isBefore(today));
    if (i >= 0) return i;
    final last = days.lastIndexWhere((d) => d.date != null);
    return last >= 0 ? last : 0;
  }
}

class _ChangesScreenState extends State<ChangesScreen> {
  List<ChangeDay> _days = [];
  int _sel = 0;
  String? _group;
  String? _error;
  bool _loading = true;
  final _chips = ScrollController();

  static const _wdShort = {
    'понедельник': 'Пн', 'вторник': 'Вт', 'среда': 'Ср', 'четверг': 'Чт',
    'пятница': 'Пт', 'суббота': 'Сб', 'воскресенье': 'Вс',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _chips.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final teacher = await Profile.teacher();
      final prefs = await SharedPreferences.getInstance();
      final group = prefs.getString('group');
      _group = teacher != null ? Profile.short(teacher) : group;
      if (teacher == null && group == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final items = teacher != null
          ? await Api.teacherChanges(teacher)
          : await Api.changes(group!);
      if (items.isNotEmpty) {
        await NotifService.markSeen(items.first.ts);
      }
      if (!mounted) return;
      final days = ChangeDay.group(items);
      // при обновлении остаёмся на том же дне, если он никуда не делся
      final keep = _days.isEmpty ? null : _days[_sel.clamp(0, _days.length - 1)].date;
      var sel = keep == null ? -1 : days.indexWhere((d) => d.date == keep);
      if (sel < 0) sel = ChangeDay.defaultIndex(days, DateTime.now());
      setState(() {
        _days = days;
        _sel = sel;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chips.hasClients && sel > 2) {
          _chips.jumpTo(((sel - 2) * 66.0)
              .clamp(0.0, _chips.position.maxScrollExtent));
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Изменения'),
        actions: [
          if (_group != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                  child: Text(_group!,
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700))),
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const StatusView(message: 'Загрузка…');
    if (_group == null) {
      return const StatusView(
          message: 'Выбери группу на вкладке «Расписание»,\n'
              'чтобы видеть её изменения');
    }
    if (_error != null) {
      return StatusView(message: _error!, isError: true, onRetry: _load);
    }
    if (_days.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: _load,
        child: ListView(children: const [
          SizedBox(height: 120),
          Icon(Icons.check_circle_outline, size: 56, color: AppColors.green),
          SizedBox(height: 12),
          Center(
              child: Text('За 2 недели изменений не было 👍',
                  style: TextStyle(color: AppColors.textDim))),
        ]),
      );
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = _days[_sel.clamp(0, _days.length - 1)];
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Какой день посмотреть?',
                style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          ),
        ),
        SizedBox(
          height: 78,
          child: ListView.builder(
            controller: _chips,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: _days.length,
            itemBuilder: (_, i) => _chip(i, today),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
                  child: Text(_dayHeader(day, today),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                for (final c in day.items) _card(c),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _dayHeader(ChangeDay d, DateTime today) {
    final date = d.date;
    if (date == null) return 'Прочие изменения';
    final title = d.items.first.dayTitle;
    final diff = date.difference(today).inDays;
    final rel = diff == 0
        ? 'сегодня'
        : diff == 1
            ? 'завтра'
            : diff < 0
                ? 'уже прошло'
                : '';
    return rel.isEmpty ? _cap(title) : '${_cap(title)} · $rel';
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _chip(int i, DateTime today) {
    final d = _days[i];
    final isSel = i == _sel;
    final past = d.date != null && d.date!.isBefore(today);
    final isToday = d.date == today;
    final wd = _wdShort[d.weekday] ?? '';
    final num = d.date == null
        ? '?'
        : '${d.date!.day.toString().padLeft(2, '0')}.${d.date!.month.toString().padLeft(2, '0')}';
    final dim = past && !isSel;
    return GestureDetector(
      onTap: () => setState(() => _sel = i),
      child: Opacity(
        opacity: dim ? 0.5 : 1,
        child: Container(
          width: 58,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: isSel ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isToday && !isSel ? AppColors.primary : AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(d.date == null ? 'Другое' : wd,
                  style: TextStyle(
                      fontSize: 11,
                      color: isSel ? Colors.white70 : AppColors.textDim)),
              const SizedBox(height: 2),
              Text(num,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isSel ? Colors.white : AppColors.text)),
              const SizedBox(height: 3),
              Text('${d.items.length}',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isSel ? Colors.white : AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(ScheduleChange c) {
    final (String label, Color color, IconData icon) = switch (c.kind) {
      ChangeKind.added => ('Добавлена', AppColors.green, Icons.add_circle_outline),
      ChangeKind.removed => ('Отменена', AppColors.red, Icons.remove_circle_outline),
      ChangeKind.edited => ('Изменена', AppColors.primary, Icons.edit_outlined),
      ChangeKind.other => ('Изменение', AppColors.textDim, Icons.sync_alt),
    };
    String found = '';
    try {
      found = DateFormat('dd.MM HH:mm').format(DateTime.parse(c.ts).toLocal());
    } catch (_) {}
    // текст неизвестного вида показываем как есть, чтобы ничего не потерять
    final raw = c.kind == ChangeKind.other || (c.fields.isEmpty && c.pairNum.isEmpty);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: c.pairNum.isEmpty
                ? Icon(icon, size: 18, color: color)
                : Text(c.pairNum,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 4),
                    Text(c.pairNum.isEmpty ? label : '$label пара',
                        style: TextStyle(
                            color: color,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (found.isNotEmpty)
                      Text(found,
                          style: const TextStyle(
                              color: AppColors.textDim, fontSize: 11)),
                  ],
                ),
                if (c.pairTime.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_time(c.pairTime),
                      style: const TextStyle(
                          color: AppColors.textDim, fontSize: 12)),
                ],
                const SizedBox(height: 4),
                if (raw)
                  Text(c.text, style: const TextStyle(fontSize: 14, height: 1.3))
                else
                  for (final f in c.fields) _field(f, c.kind),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// «10:00 - 10:30 10:00 - 10:30» -> «10:00 - 10:30» (сервер дублирует
  /// половины, когда пара без перерыва).
  static String _time(String t) {
    final m = RegExp(r'\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2}')
        .allMatches(t)
        .map((x) => x.group(0)!.replaceAll(RegExp(r'\s+'), ' '))
        .toList();
    if (m.length == 2 && m[0] == m[1]) return m[0];
    return m.isEmpty ? t : m.join(' · ');
  }

  Widget _field(ChangeField f, ChangeKind kind) {
    final isTime = f.label == 'Время';
    String v(String s) => isTime ? _time(s) : s.replaceAll(RegExp(r'\s+'), ' ');
    final icon = switch (f.label) {
      'Время' => Icons.schedule,
      'Кабинет' => Icons.meeting_room_outlined,
      'Преподаватель' => Icons.person_outline,
      'Группа' => Icons.groups_outlined,
      _ => Icons.menu_book_outlined,
    };
    final removed = kind == ChangeKind.removed;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 15, color: AppColors.textDim),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: f.before.isEmpty
                ? Text(v(f.after),
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.25,
                        fontWeight:
                            f.label == 'Предмет' ? FontWeight.w600 : null,
                        color: removed ? AppColors.textDim : AppColors.text,
                        decoration:
                            removed ? TextDecoration.lineThrough : null))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v(f.before),
                          style: const TextStyle(
                              fontSize: 13,
                              height: 1.25,
                              color: AppColors.textDim,
                              decoration: TextDecoration.lineThrough)),
                      Text(v(f.after),
                          style: const TextStyle(
                              fontSize: 14,
                              height: 1.25,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
