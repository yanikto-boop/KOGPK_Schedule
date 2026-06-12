import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

class AdminScreen extends StatefulWidget {
  final String password;
  const AdminScreen({super.key, required this.password});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Map<String, dynamic>? _status;
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
      final s = await Api.adminStatus(widget.password);
      setState(() {
        _status = s;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refresh(String target, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Обновить $label?'),
        content: const Text(
            'Запустит полный перезабор с сайта колледжа. Это может занять несколько минут.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Запустить')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.adminRefresh(widget.password, target);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Обновление $label запущено')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Админ-панель'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const StatusView(message: 'Загрузка…')
          : _error != null
              ? StatusView(message: _error!, isError: true, onRetry: _load)
              : _content(),
    );
  }

  Widget _content() {
    final s = _status!;
    final gu = s['groups_updater'] as Map<String, dynamic>?;
    final tu = s['teachers_updater'] as Map<String, dynamic>?;
    final age = s['cache_age_min'] as Map<String, dynamic>? ?? {};
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _card(
          title: 'Расписание групп',
          icon: Icons.groups,
          status: gu,
          ageMin: (age['groups_week0'] as num?)?.toDouble(),
          total: s['groups_total'],
          onRefresh: () => _refresh('groups', 'групп'),
        ),
        const SizedBox(height: 10),
        _card(
          title: 'Расписание преподавателей',
          icon: Icons.person,
          status: tu,
          ageMin: (age['teachers_week0'] as num?)?.toDouble(),
          onRefresh: () => _refresh('teachers', 'преподавателей'),
        ),
      ],
    );
  }

  Widget _card({
    required String title,
    required IconData icon,
    required Map<String, dynamic>? status,
    double? ageMin,
    Object? total,
    required VoidCallback onRefresh,
  }) {
    final ok = status?['ok'];
    final failed = status?['failed'];
    final finishedAt = status?['finished_at']?.toString();
    String when = '—';
    if (finishedAt != null) {
      try {
        when = DateFormat('dd.MM HH:mm')
            .format(DateTime.parse(finishedAt).toLocal());
      } catch (_) {}
    }
    final hasFail = (failed is num) && failed > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          _row('Последнее обновление', when),
          _row('Загружено',
              status == null ? '—' : '$ok${total != null ? ' / $total' : ''}'),
          if (hasFail)
            _row('Сбоев', '$failed ⚠️', color: AppColors.red),
          if (ageMin != null)
            _row('Возраст кэша', _ageText(ageMin),
                color: ageMin > 60 * 30 ? AppColors.yellow : null),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: const Text('Обновить сейчас'),
            ),
          ),
        ],
      ),
    );
  }

  String _ageText(double min) {
    if (min < 60) return '${min.round()} мин назад';
    final h = min / 60;
    if (h < 24) return '${h.toStringAsFixed(1)} ч назад';
    return '${(h / 24).toStringAsFixed(1)} дн назад';
  }

  Widget _row(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: AppColors.textDim)),
            Text(v,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color ?? AppColors.text)),
          ],
        ),
      );
}
