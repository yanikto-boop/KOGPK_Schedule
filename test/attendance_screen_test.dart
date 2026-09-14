// Экран посещаемости должен строиться без переполнений на узком экране.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_app/api.dart';
import 'package:schedule_app/screens/attendance_screen.dart';
import 'package:schedule_app/theme.dart';

GradeEntry entry(String attendance, {String grade = ''}) =>
    GradeEntry('12.09.2026, пятница', attendance, grade, '');

Future<void> pump(WidgetTester tester, JournalData data) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: AttendanceScreen(data: data),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('показывает процент, счётчики и предметы с пропусками',
      (tester) async {
    await pump(
      tester,
      JournalData('123', null, [
        SubjectGrades('Математический анализ и линейная алгебра',
            [entry('Да'), entry('Нет'), entry('Нет')], 4.0, 1),
        SubjectGrades('Физра', [entry('Да'), entry('Да')], 5.0, 1),
      ]),
    );

    // 3 явки из 5 отмеченных занятий -> 60%
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('посещаемость'), findsOneWidget);
    expect(find.text('Математический анализ и линейная алгебра'),
        findsOneWidget);
    // предмет без пропусков в список не попадает
    expect(find.text('Физра'), findsNothing);
    expect(find.text('2 пропуска из 3 занятий'), findsOneWidget);
  });

  testWidgets('разворачивает предмет и показывает даты пропусков',
      (tester) async {
    await pump(
      tester,
      JournalData('123', null, [
        SubjectGrades('История', [entry('Нет'), entry('Да')], 0, 0),
      ]),
    );

    expect(find.text('12.09.2026'), findsNothing);
    await tester.tap(find.text('История'));
    await tester.pumpAndSettle();
    expect(find.text('12.09.2026'), findsOneWidget);
  });

  testWidgets('без пропусков показывает поздравление', (tester) async {
    await pump(
      tester,
      JournalData('123', null, [
        SubjectGrades('История', [entry('Да'), entry('Да')], 0, 0),
      ]),
    );
    expect(find.text('100%'), findsOneWidget);
    expect(find.textContaining('Ни одного пропуска'), findsOneWidget);
  });

  testWidgets('без отметок посещаемости не выдумывает статистику',
      (tester) async {
    await pump(
      tester,
      JournalData('123', null, [
        SubjectGrades('История', [entry(''), entry('')], 0, 0),
      ]),
    );
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('нет отметок о посещаемости'), findsOneWidget);
  });
}
