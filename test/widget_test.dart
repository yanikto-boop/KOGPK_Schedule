// Базовый smoke-тест: приложение поднимается без исключений.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:schedule_app/main.dart';

void main() {
  setUp(() {
    // без этого RootScreen лезет в реальные prefs, которых в тесте нет
    SharedPreferences.setMockInitialValues({'onboarding_done': true});
  });

  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const ScheduleApp());
    expect(find.text('Расписание'), findsWidgets);
  });
}
