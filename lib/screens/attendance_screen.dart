import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

/// Посещаемость по данным журнала: сколько всего пропусков и по каким
/// предметам. Даты пропусков видно, если развернуть предмет.
class AttendanceScreen extends StatelessWidget {
  final JournalData data;
  const AttendanceScreen({super.key, required this.data});

  static Color rateColor(double rate) {
    if (rate >= 0.9) return AppColors.green;
    if (rate >= 0.75) return AppColors.yellow;
    return AppColors.red;
  }

  /// «5 пропусков», «2 пропуска», «1 пропуск».
  static String missWord(int n) {
    final tens = n % 100;
    if (tens >= 11 && tens <= 14) return 'пропусков';
    switch (n % 10) {
      case 1:
        return 'пропуск';
      case 2:
      case 3:
      case 4:
        return 'пропуска';
      default:
        return 'пропусков';
    }
  }

  @override
  Widget build(BuildContext context) {
    final withMisses = data.byMisses;
    return Scaffold(
      appBar: AppBar(title: const Text('Посещаемость')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          _overall(),
          const SizedBox(height: 16),
          if (data.totalMarked == 0)
            const _Note('В журнале пока нет отметок о посещаемости.\n'
                'Считать нечего.')
          else if (withMisses.isEmpty)
            const _Note('Ни одного пропуска. Красава 🎉')
          else ...[
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text('ГДЕ ПРОПУСКИ',
                  style: TextStyle(
                      color: AppColors.textDim,
                      fontSize: 11,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700)),
            ),
            ...withMisses.map((s) => _SubjectMisses(subject: s)),
          ],
        ],
      ),
    );
  }

  Widget _overall() {
    final rate = data.attendanceRate;
    final color = rateColor(rate);
    final empty = data.totalMarked == 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.primaryDim.withValues(alpha: 0.45),
          AppColors.surface
        ]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(empty ? '—' : '${(rate * 100).round()}%',
                  style: TextStyle(
                      fontSize: 44,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      color: color)),
              const SizedBox(width: 10),
              const Flexible(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('посещаемость',
                      style:
                          TextStyle(color: AppColors.textDim, fontSize: 13)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: empty ? 0 : rate,
              minHeight: 8,
              backgroundColor: AppColors.red.withValues(alpha: 0.28),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat('Был', '${data.totalAttended}', AppColors.green),
              _stat('Пропущено', '${data.totalMissed}', AppColors.red),
              _stat('Всего занятий', '${data.totalMarked}', AppColors.text),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
          ],
        ),
      );
}

class _SubjectMisses extends StatelessWidget {
  final SubjectGrades subject;
  const _SubjectMisses({required this.subject});

  @override
  Widget build(BuildContext context) {
    final color = AttendanceScreen.rateColor(subject.attendanceRate);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      // Material, а не Container: иначе ExpansionTile рисует отклик нажатия
      // под фоном контейнера и его не видно.
      child: Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            title: Text(subject.subject,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${subject.missed} '
                      '${AttendanceScreen.missWord(subject.missed)} '
                      'из ${subject.marked} занятий',
                      style: const TextStyle(
                          color: AppColors.textDim, fontSize: 12)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: subject.attendanceRate,
                      minHeight: 5,
                      backgroundColor: AppColors.red.withValues(alpha: 0.28),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ],
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${subject.missed}',
                  style: const TextStyle(
                      color: AppColors.red, fontWeight: FontWeight.w700)),
            ),
            children: subject.misses.map((e) => _missRow(e)).toList(),
          ),
        ),
      ),
    );
  }

  Widget _missRow(GradeEntry e) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            const Icon(Icons.cancel, size: 15, color: AppColors.red),
            const SizedBox(width: 8),
            Expanded(
              child:
                  Text(e.shortDate, style: const TextStyle(fontSize: 13)),
            ),
            if (e.grade.isNotEmpty)
              Text('оценка ${e.grade}',
                  style:
                      const TextStyle(color: AppColors.textDim, fontSize: 12)),
          ],
        ),
      );
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(text,
            style: const TextStyle(color: AppColors.textDim, height: 1.4)),
      );
}
