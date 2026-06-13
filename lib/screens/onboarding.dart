import 'package:flutter/material.dart';
import '../theme.dart';

class _Step {
  final int? tab; // индекс вкладки для подсветки (null = по центру)
  final IconData icon;
  final String title;
  final String desc;
  const _Step(this.tab, this.icon, this.title, this.desc);
}

const _steps = <_Step>[
  _Step(null, Icons.school, 'Привет! 👋',
      'Это твой колледж в кармане: расписание, преподаватели, журнал и даже маршрутки Когалыма. Коротко покажу, что где.'),
  _Step(2, Icons.home, 'Главная',
      'Здесь видно, сколько осталось до конца пары или до начала следующей, и какая пара дальше.'),
  _Step(0, Icons.calendar_month, 'Расписание',
      'Выбери свою группу — и листай дни. Сегодня подсвечено, пары на две недели вперёд.'),
  _Step(1, Icons.person_search, 'Преподаватели',
      'Поиск по преподавателю и его расписание — удобно узнать, где пара.'),
  _Step(3, Icons.assignment, 'Журнал',
      'Введи номер зачётки — увидишь оценки, средний балл и пропуски.'),
  _Step(4, Icons.directions_bus, 'Ещё: транспорт и виджеты',
      'Маршрутки Когалыма с прибытием в реальном времени и картой, виджеты на экран и поддержка проекта — всё тут.'),
];

class OnboardingOverlay extends StatefulWidget {
  final void Function(int tab) onStep;
  final VoidCallback onDone;
  const OnboardingOverlay({super.key, required this.onStep, required this.onDone});

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay> {
  int _i = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  void _emit() {
    final t = _steps[_i].tab;
    if (t != null) widget.onStep(t);
  }

  void _next() {
    if (_i >= _steps.length - 1) {
      widget.onDone();
      return;
    }
    setState(() => _i++);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final step = _steps[_i];

    Offset? hole;
    if (step.tab != null) {
      final cx = size.width * (step.tab! + 0.5) / 5;
      final cy = size.height - bottomInset - 32;
      hole = Offset(cx, cy);
    }

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // затемнение с «дыркой» на подсвечиваемой вкладке
          Positioned.fill(
            child: CustomPaint(painter: _ScrimPainter(hole)),
          ),
          if (hole != null)
            Positioned(
              left: hole.dx - 30,
              top: hole.dy - 30,
              child: IgnorePointer(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
            ),
          // карточка
          Positioned(
            left: 20,
            right: 20,
            bottom: bottomInset + 90,
            child: _card(step),
          ),
          // пропустить
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: TextButton(
              onPressed: widget.onDone,
              child: const Text('Пропустить',
                  style: TextStyle(color: Colors.white70)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(_Step step) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(step.icon, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(step.title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(step.desc,
              style: const TextStyle(
                  color: AppColors.textDim, fontSize: 14, height: 1.35)),
          const SizedBox(height: 16),
          Row(
            children: [
              // индикаторы шагов
              Row(
                children: List.generate(_steps.length, (k) {
                  final active = k == _i;
                  return Container(
                    width: active ? 18 : 7,
                    height: 7,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _next,
                child: Text(_i >= _steps.length - 1 ? 'Понятно' : 'Далее'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  final Offset? hole;
  _ScrimPainter(this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.78);
    final full = Path()..addRect(Offset.zero & size);
    if (hole == null) {
      canvas.drawPath(full, paint);
      return;
    }
    final cut = Path()
      ..addOval(Rect.fromCircle(center: hole!, radius: 30));
    final diff = Path.combine(PathOperation.difference, full, cut);
    canvas.drawPath(diff, paint);
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole;
}
