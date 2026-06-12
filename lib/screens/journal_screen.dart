import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final _ctrl = TextEditingController();
  JournalData? _data;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('ticket_id');
    if (saved != null && saved.isNotEmpty) {
      _ctrl.text = saved;
      _load();
    }
  }

  Future<void> _load() async {
    final id = _ctrl.text.trim();
    if (id.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await Api.journal(id);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ticket_id', id);
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('journal unavailable') ||
        s.contains('502') ||
        s.contains('timeout') ||
        s.contains('connection') ||
        s.contains('closed')) {
      return 'Сайт колледжа сейчас не отвечает (журнал там периодически недоступен).\n'
          'Если зачётка верная — попробуй ещё раз чуть позже.';
    }
    if (s.contains('bad ticket')) return 'Неверный номер зачётки';
    return e.toString();
  }

  Future<void> _forget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ticket_id');
    _ctrl.clear();
    setState(() {
      _data = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Журнал'),
        actions: [
          if (_data != null)
            IconButton(
                onPressed: _forget,
                icon: const Icon(Icons.logout),
                tooltip: 'Сменить зачётку'),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.number,
                    onSubmitted: (_) => _load(),
                    decoration: InputDecoration(
                      hintText: 'Номер зачётки',
                      prefixIcon: const Icon(Icons.badge_outlined),
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
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: _loading ? null : _load,
                    child: const Text('ОК')),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const StatusView(
          message: 'Загружаю оценки…\nСайт колледжа отвечает медленно, это нормально');
    }
    if (_error != null) {
      return StatusView(message: _error!, isError: true, onRetry: _load);
    }
    if (_data == null) {
      return const StatusView(
          message: 'Введи номер зачётки,\nчтобы посмотреть оценки');
    }
    final d = _data!;
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          _summary(d),
          const SizedBox(height: 12),
          ...d.subjects.map((s) => _SubjectCard(subject: s)),
        ],
      ),
    );
  }

  Widget _summary(JournalData d) {
    final updated = d.cachedAt != null
        ? DateFormat('dd.MM HH:mm').format(d.cachedAt!.toLocal())
        : '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.primaryDim.withValues(alpha: 0.5),
          AppColors.surface
        ]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.school, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Зачётка ${d.ticketId}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('Средний балл',
                  d.overallAvg == 0 ? '—' : d.overallAvg.toStringAsFixed(1)),
              _stat('Оценок', '${d.totalGrades}'),
              _stat('Пропусков', '${d.totalMissed}'),
            ],
          ),
          if (updated.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Обновлено $updated',
                style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800)),
            Text(label,
                style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
          ],
        ),
      );
}

class _SubjectCard extends StatelessWidget {
  final SubjectGrades subject;
  const _SubjectCard({required this.subject});

  Color _gradeColor(String g) {
    switch (g) {
      case '5':
        return AppColors.green;
      case '4':
        return AppColors.blue;
      case '3':
        return AppColors.yellow;
      case '2':
        return AppColors.red;
      default:
        return AppColors.textDim;
    }
  }

  @override
  Widget build(BuildContext context) {
    final graded = subject.entries.where((e) => e.grade.isNotEmpty).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Text(subject.subject,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(
            subject.gradeCount > 0
                ? 'Средний: ${subject.avg}  •  оценок: ${subject.gradeCount}'
                : 'Нет оценок',
            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
          trailing: subject.gradeCount > 0
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _gradeColor(subject.avg.round().toString())
                        .withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(subject.avg.toStringAsFixed(1),
                      style: TextStyle(
                          color: _gradeColor(subject.avg.round().toString()),
                          fontWeight: FontWeight.w700)),
                )
              : const Icon(Icons.expand_more, color: AppColors.textDim),
          children: graded.isEmpty
              ? [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Оценок пока нет',
                        style: TextStyle(color: AppColors.textDim)),
                  )
                ]
              : graded.map((e) => _gradeRow(e)).toList(),
        ),
      ),
    );
  }

  Widget _gradeRow(GradeEntry e) {
    final date = e.date.split(',').first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _gradeColor(e.grade).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(e.grade,
                style: TextStyle(
                    color: _gradeColor(e.grade),
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date, style: const TextStyle(fontSize: 13)),
                if (e.homework.isNotEmpty)
                  Text(e.homework,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textDim, fontSize: 11.5)),
              ],
            ),
          ),
          Icon(e.present ? Icons.check_circle : Icons.cancel,
              size: 16,
              color: e.present ? AppColors.green : AppColors.red),
        ],
      ),
    );
  }
}
