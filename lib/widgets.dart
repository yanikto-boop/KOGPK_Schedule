import 'package:flutter/material.dart';
import 'theme.dart';
import 'api.dart';

String _todayIso() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// Список дней расписания (для групп и преподавателей).
class ScheduleDayList extends StatelessWidget {
  final ScheduleData data;
  final bool teacherMode;
  final Future<void> Function() onRefresh;
  const ScheduleDayList({
    super.key,
    required this.data,
    required this.onRefresh,
    this.teacherMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final today = _todayIso();
    // Показываем дни от сегодня и далее, плюс прошедшие в конце скрываем —
    // оставляем все, но прошлые дни приглушаем не будем, просто упорядочены.
    final days = data.days;
    if (days.isEmpty) {
      return _EmptyState(
        icon: Icons.event_busy,
        text: 'Расписание не найдено',
        onRefresh: onRefresh,
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: days.length,
        itemBuilder: (_, i) {
          final d = days[i];
          final isToday = d.date == today;
          return _DayCard(day: d, isToday: isToday, teacherMode: teacherMode);
        },
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final DaySchedule day;
  final bool isToday;
  final bool teacherMode;
  const _DayCard(
      {required this.day, required this.isToday, required this.teacherMode});

  @override
  Widget build(BuildContext context) {
    final lessons = day.lessons.where((l) => l.subgroups.isNotEmpty).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Row(
              children: [
                Text(
                  _capitalize(day.title),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isToday ? AppColors.primary : AppColors.text,
                  ),
                ),
                if (isToday) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('сегодня',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
          if (lessons.isEmpty)
            _noLessons()
          else
            ...lessons.map((l) => _LessonTile(lesson: l, teacherMode: teacherMode)),
        ],
      ),
    );
  }

  Widget _noLessons() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text('Нет пар 🎉',
            style: TextStyle(color: AppColors.textDim)),
      );
}

class _LessonTile extends StatelessWidget {
  final Lesson lesson;
  final bool teacherMode;
  const _LessonTile({required this.lesson, required this.teacherMode});

  @override
  Widget build(BuildContext context) {
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
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(lesson.num,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lesson.time,
                    style: const TextStyle(
                        color: AppColors.textDim, fontSize: 12)),
                const SizedBox(height: 4),
                ...lesson.subgroups.map((s) => _subgroup(s)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subgroup(Subgroup s) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.subject,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14.5, height: 1.25)),
          const SizedBox(height: 2),
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              if (s.room.isNotEmpty)
                _meta(Icons.meeting_room_outlined, s.room),
              if (teacherMode && s.group.isNotEmpty)
                _meta(Icons.groups_outlined, s.group),
              if (!teacherMode && s.teacher.isNotEmpty)
                _meta(Icons.person_outline, s.teacher),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textDim),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(text,
                style: const TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          ),
        ],
      );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final Future<void> Function() onRefresh;
  const _EmptyState(
      {required this.icon, required this.text, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: onRefresh,
      child: ListView(
        children: [
          const SizedBox(height: 120),
          Icon(icon, size: 56, color: AppColors.textDim),
          const SizedBox(height: 12),
          Center(
              child: Text(text,
                  style: const TextStyle(color: AppColors.textDim))),
        ],
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Универсальный индикатор загрузки/ошибки.
class StatusView extends StatelessWidget {
  final String message;
  final bool isError;
  final VoidCallback? onRetry;
  const StatusView(
      {super.key, required this.message, this.isError = false, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isError ? Icons.cloud_off : Icons.hourglass_empty,
              size: 48, color: AppColors.textDim),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textDim)),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ],
      ),
    );
  }
}
