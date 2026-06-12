import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

class TeachersScreen extends StatefulWidget {
  const TeachersScreen({super.key});
  @override
  State<TeachersScreen> createState() => _TeachersScreenState();
}

class _TeachersScreenState extends State<TeachersScreen> {
  List<String> _all = [];
  String _q = '';
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
      final list = await Api.teachers();
      setState(() {
        _all = list;
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
    final filtered = _q.isEmpty
        ? _all
        : _all.where((t) => t.toLowerCase().contains(_q.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Преподаватели')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'Поиск преподавателя…',
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
          Expanded(child: _list(filtered)),
        ],
      ),
    );
  }

  Widget _list(List<String> filtered) {
    if (_loading) return const StatusView(message: 'Загрузка…');
    if (_error != null) {
      return StatusView(message: _error!, isError: true, onRetry: _load);
    }
    if (filtered.isEmpty) {
      return const StatusView(message: 'Никого не найдено');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: filtered.length,
      separatorBuilder: (_, i) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final name = filtered[i];
        return Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border)),
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: Text(
                name.isNotEmpty ? name[0] : '?',
                style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w700),
              ),
            ),
            title: Text(name, style: const TextStyle(fontSize: 14.5)),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textDim),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TeacherScheduleScreen(name: name))),
          ),
        );
      },
    );
  }
}

class TeacherScheduleScreen extends StatefulWidget {
  final String name;
  const TeacherScheduleScreen({super.key, required this.name});
  @override
  State<TeacherScheduleScreen> createState() => _TeacherScheduleScreenState();
}

class _TeacherScheduleScreenState extends State<TeacherScheduleScreen> {
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
      final d = await Api.teacher(widget.name);
      setState(() {
        _data = d;
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
      appBar: AppBar(title: Text(widget.name, style: const TextStyle(fontSize: 16))),
      body: _loading
          ? const StatusView(message: 'Загрузка…')
          : _error != null
              ? StatusView(message: _error!, isError: true, onRetry: _load)
              : ScheduleDayList(
                  data: _data!, onRefresh: _load, teacherMode: true),
    );
  }
}
