import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'changes_screen.dart';

/// Половина пары: от звонка на урок до звонка с урока.
class PairSegment {
  final DateTime start;
  final DateTime end;
  const PairSegment(this.start, this.end);
}

/// Пара как единый блок: от начала первой половины до конца второй.
class PairBlock {
  final String num;
  final List<PairSegment> segments;
  final String subject;
  final String room;
  final String teacher;
  PairBlock(this.num, this.segments, this.subject, this.room, this.teacher);

  DateTime get start => segments.first.start;
  DateTime get end => segments.last.end;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _group;
  List<PairBlock> _today = [];
  bool _loading = true;
  String? _error;
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _todayIso() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  List<DateTime> _times(String time) {
    final today = DateTime.now();
    final ms = RegExp(r'(\d{1,2}):(\d{2})').allMatches(time);
    return ms
        .map((m) => DateTime(today.year, today.month, today.day,
            int.parse(m.group(1)!), int.parse(m.group(2)!)))
        .toList();
  }

  /// "08:00 - 08:45 08:55 - 09:40" -> две половины с перерывом между ними.
  List<PairSegment> _segments(String time) {
    final ts = _times(time);
    if (ts.isEmpty) return [];
    if (ts.length == 1) return [PairSegment(ts.first, ts.first)];
    final out = <PairSegment>[];
    for (var i = 0; i + 1 < ts.length; i += 2) {
      out.add(PairSegment(ts[i], ts[i + 1]));
    }
    // нечётное число меток: последняя всё равно конец пары
    if (ts.length.isOdd) {
      out[out.length - 1] = PairSegment(out.last.start, ts.last);
    }
    return out;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final group = prefs.getString('group');
      _group = group;
      if (group == null) {
        setState(() => _loading = false);
        return;
      }
      final data = await Api.schedule(group);
      final today = _todayIso();
      DaySchedule? day;
      for (final d in data.days) {
        if (d.date == today) {
          day = d;
          break;
        }
      }
      final blocks = <PairBlock>[];
      if (day != null) {
        for (final l in day.lessons) {
          if (l.subgroups.isEmpty) continue;
          final segs = _segments(l.time);
          if (segs.isEmpty) continue;
          final sg = l.subgroups.first;
          blocks.add(
              PairBlock(l.num, segs, sg.subject, sg.room, sg.teacher));
        }
      }
      blocks.sort((a, b) => a.start.compareTo(b.start));
      setState(() {
        _today = blocks;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Изменения расписания',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ChangesScreen())),
          ),
          if (_group != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(_group!,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
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
          message:
              'Сначала выбери группу\nна вкладке «Расписание»');
    }
    if (_error != null) {
      return StatusView(message: _error!, isError: true, onRetry: _load);
    }
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: _content(),
      ),
    );
  }

  List<Widget> _content() {
    if (_today.isEmpty) {
      return [
        const SizedBox(height: 60),
        _bigCard(
          label: 'Сегодня пар нет',
          value: '🎉',
          sub: 'Отдыхай',
        ),
      ];
    }

    // Определяем состояние
    final now = _now;
    PairBlock? current;
    PairBlock? next;
    String label = '';
    DateTime? target;
    bool onBreak = false; // перерыв между половинами текущей пары

    final first = _today.first;
    final last = _today.last;

    if (now.isBefore(first.start)) {
      label = 'До начала пар';
      target = first.start;
      next = first;
    } else if (now.isAfter(last.end)) {
      label = 'Пары закончились';
      target = null;
    } else {
      // ищем текущую пару или перемену
      for (var i = 0; i < _today.length; i++) {
        final b = _today[i];
        if (!now.isBefore(b.start) && !now.isAfter(b.end)) {
          current = b;
          next = i + 1 < _today.length ? _today[i + 1] : null;
          final phase = _phaseOf(b, now);
          label = phase.label;
          target = phase.target;
          onBreak = phase.onBreak;
          break;
        }
        if (now.isBefore(b.start)) {
          // перемена перед парой b
          next = b;
          label = 'Перемена · до следующей пары';
          target = b.start;
          break;
        }
      }
      if (target == null && current == null && next == null) {
        label = 'Пары закончились';
      }
    }

    final widgets = <Widget>[];

    if (target != null) {
      final diff = target.difference(now);
      widgets.add(_bigCard(
        label: label,
        value: _fmtCountdown(diff),
        sub: current == null
            ? 'Начало в ${_hm(target)}'
            : onBreak
                ? '${current.num} пара · звонок в ${_hm(target)}'
                : 'Идёт ${current.num} пара · до ${_hm(target)}',
      ));
    } else {
      widgets.add(_bigCard(label: label, value: '✓', sub: 'До завтра!'));
    }

    widgets.add(const SizedBox(height: 16));

    if (current != null) {
      widgets.add(_pairCard('Сейчас', current, accent: true));
      widgets.add(const SizedBox(height: 10));
    }
    if (next != null) {
      widgets.add(_pairCard('Следующая пара', next));
    } else if (current != null) {
      widgets.add(_infoCard('Это последняя пара сегодня'));
    }

    return widgets;
  }

  /// На какой стадии пары мы сейчас: идёт половина или перерыв между ними.
  ({String label, DateTime target, bool onBreak}) _phaseOf(
      PairBlock b, DateTime now) {
    final segs = b.segments;
    for (var i = 0; i < segs.length; i++) {
      final s = segs[i];
      if (now.isAfter(s.end)) continue;
      if (now.isBefore(s.start)) {
        return (
          label: 'Перерыв · до ${i + 1} половины',
          target: s.start,
          onBreak: true
        );
      }
      return (
        label: segs.length > 1 ? 'До конца ${i + 1} половины' : 'До конца пары',
        target: s.end,
        onBreak: false
      );
    }
    return (label: 'До конца пары', target: b.end, onBreak: false);
  }

  String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtCountdown(Duration d) {
    if (d.isNegative) return '0 мин';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '$h ч $m мин';
    if (m > 0) return '$m:${s.toString().padLeft(2, '0')}';
    return '$s сек';
  }

  Widget _bigCard(
      {required String label, required String value, required String sub}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryDim.withValues(alpha: 0.55),
            AppColors.surface
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(label.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(value,
              style: const TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  color: AppColors.text)),
          const SizedBox(height: 8),
          Text(sub,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _pairCard(String title, PairBlock b, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: accent ? AppColors.primary : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title.toUpperCase(),
                  style: TextStyle(
                      color: accent ? AppColors.primary : AppColors.textDim,
                      fontSize: 11,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Flexible(
                child: Text(
                    b.segments.length > 1
                        ? '${_hm(b.segments.first.start)}–${_hm(b.segments.first.end)} · '
                            '${_hm(b.segments.last.start)}–${_hm(b.segments.last.end)}'
                        : '${_hm(b.start)} – ${_hm(b.end)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textDim, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(b.num,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.subject,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            height: 1.25)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 2,
                      children: [
                        if (b.room.isNotEmpty)
                          _meta(Icons.meeting_room_outlined, b.room),
                        if (b.teacher.isNotEmpty)
                          _meta(Icons.person_outline, b.teacher),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoCard(String text) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(text, style: const TextStyle(color: AppColors.textDim)),
      );

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textDim),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(text,
                style:
                    const TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          ),
        ],
      );
}
