import 'dart:async';
import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'changes_screen.dart';
import '../errors.dart';
import '../pair.dart';
import '../services/profile.dart';
import '../services/notif_service.dart';
import '../games/games_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _again = false;
  String? _group;
  List<PairBlock> _today = [];
  // режим преподавателя: пары сегодня кончились/их нет — показываем
  // ближайший день с парами; здесь его подпись («Завтра», «пт, 24 октября»)
  String? _dayLabel;
  bool _loading = true;
  String? _error;
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      // полночь или кончились пары показанного дня — пора показать следующий
      final rolled = !DateUtils.isSameDay(_now, now) ||
          (_dayLabel == null &&
              _today.isNotEmpty &&
              !_now.isAfter(_today.last.end) &&
              now.isAfter(_today.last.end));
      setState(() => _now = now);
      if (rolled) _load(silent: true);
    });
    Profile.changed.addListener(_onProfile);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Profile.changed.removeListener(_onProfile);
    _ticker?.cancel();
    super.dispose();
  }

  static String _todayIso() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  DateTime? _loadedAt;

  void _onProfile() => _load();

  /// [silent] — фоновое обновление: без экрана «Загрузка…», ошибка не
  /// затирает уже показанные пары.
  Future<void> _load({bool silent = false}) async {
    if (_busy) {
      _again = true; // профиль сменили посреди загрузки — перечитаем после
      return;
    }
    _busy = true;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final r = await Profile.loadSchedule();
      if (!mounted) return;
      if (r == null) {
        setState(() {
          _group = null;
          _today = [];
          _dayLabel = null;
          _loading = false;
        });
        return;
      }
      _show(r.data, r.label);
      _loadedAt = DateTime.now();
      NotifService.refreshUnread();
    } catch (e) {
      if (!mounted) return;
      if (silent && _group != null && _error == null) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    } finally {
      _busy = false;
      if (_again) {
        _again = false;
        _load(silent: silent);
      }
    }
  }

  /// Сегодняшние пары, пока они не кончились; иначе ближайший день с парами
  /// и его подпись («Завтра», «понедельник, 16 ноября 2026»).
  void _show(ScheduleData data, String label) {
    final now = DateTime.now();
    final today = _todayIso();
    var blocks = <PairBlock>[];
    var todayBlocks = <PairBlock>[];
    String? dayLabel;
    for (final d in data.days) {
      if (d.date == null || d.date!.compareTo(today) < 0) continue;
      final date = DateTime.tryParse(d.date!);
      if (date == null) continue;
      final b = PairBlock.ofDay(d, date);
      if (b.isEmpty) continue;
      if (d.date == today) {
        todayBlocks = b;
        if (now.isAfter(b.last.end)) continue; // сегодня уже всё
        blocks = b;
        break;
      }
      blocks = b;
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      dayLabel = DateUtils.isSameDay(date, tomorrow)
          ? 'Завтра'
          : d.title.split(',').reversed.join(', ').trim();
      break;
    }
    setState(() {
      _group = label;
      // впереди пар нет вовсе — показываем «Пары закончились» по сегодняшним
      _today = blocks.isEmpty ? todayBlocks : blocks;
      _dayLabel = dayLabel;
      _error = null;
      _loading = false;
    });
  }

  /// Приложение вернули на экран или наступил новый день — данные могли устареть.
  void _refreshIfStale() {
    final at = _loadedAt;
    if (at == null || _loading) return;
    final now = DateTime.now();
    if (!DateUtils.isSameDay(at, now) ||
        now.difference(at) > const Duration(minutes: 10)) {
      _load(silent: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshIfStale();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: NotifService.unread,
            builder: (_, unread, _) => IconButton(
              icon: Badge(
                isLabelVisible: unread,
                smallSize: 9,
                backgroundColor: AppColors.red,
                child: Icon(unread
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_outlined),
              ),
              tooltip: 'Изменения расписания',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ChangesScreen())),
            ),
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
      body: Column(children: [
        Expanded(child: _body()),
        const BoredStrip(),
      ]),
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
    if (_dayLabel != null && _today.isNotEmpty) return _futureDay();
    if (_today.isEmpty) {
      return [
        const SizedBox(height: 60),
        _bigCard(
          label: 'Ближайших пар нет',
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
          final phase = b.phaseAt(now);
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
      widgets.add(_bigCard(label: label, value: '✓', sub: 'На сегодня всё'));
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

  /// Ближайший день с парами (режим преподавателя): таймер до первой пары
  /// и весь список пар этого дня.
  List<Widget> _futureDay() {
    final first = _today.first;
    return [
      _bigCard(
        label: 'До первой пары · ${_dayLabel!}',
        value: _fmtCountdown(first.start.difference(_now)),
        sub: 'Начало в ${_hm(first.start)}',
      ),
      const SizedBox(height: 16),
      for (final b in _today) ...[
        _pairCard(b == first ? 'Первая пара' : '${b.num} пара', b,
            accent: b == first),
        const SizedBox(height: 10),
      ],
    ];
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
                        if (b.group.isNotEmpty)
                          _meta(Icons.groups_outlined, b.group),
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
