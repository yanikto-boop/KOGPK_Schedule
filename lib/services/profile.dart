import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';
import '../theme.dart';
import 'notif_service.dart';

/// Режим «я преподаватель»: Главная, Расписание, виджеты и уведомления
/// показывают пары выбранного преподавателя вместо группы.
/// Группа в prefs ('group') при этом не трогается — «Я студент» вернёт как было.
class Profile {
  static const _kRole = 'role';
  static const _kTeacher = 'teacher_name';

  static const _kSubgroup = 'subgroup';

  /// Растёт при смене режима, группы или подгруппы — экраны в IndexedStack
  /// перезагружаются.
  static final changed = ValueNotifier<int>(0);

  /// Подгруппа студента: 0 — показывать все, иначе номер (1, 2…).
  static Future<int> subgroup() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kSubgroup) ?? 0;
  }

  static Future<void> setSubgroup(int n) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kSubgroup, n);
    changed.value++;
  }

  /// Студент выбрал другую группу: у неё своя лента изменений.
  static Future<void> setGroup(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('group', name);
    await NotifService.resetSeen();
    changed.value++;
  }

  /// Расписание текущего профиля: преподавателя либо группы (с учётом
  /// подгруппы). null — группа ещё не выбрана.
  static Future<({ScheduleData data, String label, bool teacher})?>
      loadSchedule() async {
    final t = await teacher();
    if (t != null) {
      return (data: await Api.teacher(t), label: short(t), teacher: true);
    }
    final p = await SharedPreferences.getInstance();
    final g = p.getString('group');
    if (g == null || g.isEmpty) return null;
    final data = (await Api.schedule(g)).forSubgroup(p.getInt(_kSubgroup) ?? 0);
    return (data: data, label: g, teacher: false);
  }

  /// ФИО, если включён режим преподавателя, иначе null.
  static Future<String?> teacher() async {
    final p = await SharedPreferences.getInstance();
    if (p.getString(_kRole) != 'teacher') return null;
    final t = p.getString(_kTeacher);
    return (t == null || t.isEmpty) ? null : t;
  }

  /// null — вернуться в режим студента.
  static Future<void> setTeacher(String? name) async {
    final p = await SharedPreferences.getInstance();
    if (name == null) {
      await p.setString(_kRole, 'student');
    } else {
      await p.setString(_kRole, 'teacher');
      await p.setString(_kTeacher, name);
    }
    await NotifService.resetSeen();
    changed.value++;
  }

  /// «Иванов Иван Иванович» -> «Иванов И. И.»
  static String short(String full) {
    final p = full.trim().split(RegExp(r'\s+'));
    if (p.length < 2) return full;
    return [p.first, ...p.skip(1).take(2).map((s) => '${s[0]}.')].join(' ');
  }

  static Future<String?> pickTeacher(BuildContext context) =>
      showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppColors.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => const _TeacherPicker(),
      );
}

class _TeacherPicker extends StatefulWidget {
  const _TeacherPicker();
  @override
  State<_TeacherPicker> createState() => _TeacherPickerState();
}

class _TeacherPickerState extends State<_TeacherPicker> {
  List<String>? _all;
  String _q = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    Api.teachers().then((l) {
      if (mounted) setState(() => _all = l);
    }).catchError((_) {
      if (mounted) setState(() => _error = 'Не удалось загрузить список');
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = _all ?? const <String>[];
    final filtered = all
        .where((t) => t.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 12),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            const Text('Кто вы?',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 10),
            TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'Фамилия…',
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
              child: _error != null
                  ? Center(
                      child: Text(_error!,
                          style: const TextStyle(color: AppColors.textDim)))
                  : _all == null
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => ListTile(
                            title: Text(filtered[i]),
                            onTap: () => Navigator.pop(context, filtered[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
