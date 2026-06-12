// Базовый smoke-тест: приложение поднимается без исключений.
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_app/main.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const ScheduleApp());
    expect(find.text('Расписание'), findsWidgets);
  });
}
