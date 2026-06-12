import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import '../services/widget_service.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  List<GroupRef> _groups = [];
  String? _selected;
  ScheduleData? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final groups = await Api.groups();
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('group');
      _groups = groups;
      _selected = (saved != null && groups.any((g) => g.name == saved))
          ? saved
          : null;
      if (_selected != null) {
        await _load();
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _load() async {
    if (_selected == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Api.schedule(_selected!);
      setState(() {
        _data = data;
        _loading = false;
      });
      // обновляем виджеты на главном экране (не блокируем UI)
      WidgetService.update(data, _selected!).catchError((_) {});
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickGroup() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _GroupPicker(groups: _groups, selected: _selected),
    );
    if (picked != null && picked != _selected) {
      _selected = picked;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('group', picked);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Расписание'),
        actions: [
          if (_selected != null)
            TextButton.icon(
              onPressed: _pickGroup,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: Text(_selected!,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const StatusView(message: 'Загрузка…');
    }
    if (_error != null && _data == null) {
      return StatusView(message: _error!, isError: true, onRetry: _selected == null ? _init : _load);
    }
    if (_selected == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_month, size: 64, color: AppColors.textDim),
            const SizedBox(height: 16),
            const Text('Выбери свою группу',
                style: TextStyle(fontSize: 16, color: AppColors.textDim)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _pickGroup,
              icon: const Icon(Icons.list),
              label: const Text('Выбрать группу'),
            ),
          ],
        ),
      );
    }
    return ScheduleDayList(data: _data!, onRefresh: _load);
  }
}

class _GroupPicker extends StatefulWidget {
  final List<GroupRef> groups;
  final String? selected;
  const _GroupPicker({required this.groups, this.selected});
  @override
  State<_GroupPicker> createState() => _GroupPickerState();
}

class _GroupPickerState extends State<_GroupPicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final filtered = widget.groups
        .where((g) => g.name.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 12),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'Поиск группы…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surface2,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                childAspectRatio: 2.4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: filtered.map((g) {
                  final sel = g.name == widget.selected;
                  return InkWell(
                    onTap: () => Navigator.pop(context, g.name),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel
                            ? AppColors.primary.withValues(alpha: 0.2)
                            : AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: sel ? AppColors.primary : AppColors.border),
                      ),
                      child: Text(g.name,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: sel ? AppColors.primary : AppColors.text)),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
