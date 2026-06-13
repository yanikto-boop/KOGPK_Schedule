import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import '../services/notif_service.dart';

class ChangesScreen extends StatefulWidget {
  const ChangesScreen({super.key});
  @override
  State<ChangesScreen> createState() => _ChangesScreenState();
}

class _ChangesScreenState extends State<ChangesScreen> {
  List<ScheduleChange>? _items;
  String? _group;
  String? _error;
  bool _loading = true;

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
      final prefs = await SharedPreferences.getInstance();
      final group = prefs.getString('group');
      _group = group;
      if (group == null) {
        setState(() => _loading = false);
        return;
      }
      final items = await Api.changes(group);
      if (items.isNotEmpty) {
        await NotifService.markSeen(items.first.ts);
      }
      setState(() {
        _items = items;
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
    final items = _items ?? [];
    if (items.isEmpty) {
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
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final c = items[i];
          String day = '';
          try {
            day = DateFormat('dd.MM HH:mm').format(DateTime.parse(c.ts).toLocal());
          } catch (_) {}
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sync_alt,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(day,
                        style: const TextStyle(
                            color: AppColors.textDim, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(c.text, style: const TextStyle(fontSize: 14, height: 1.3)),
              ],
            ),
          );
        },
      ),
    );
  }
}
