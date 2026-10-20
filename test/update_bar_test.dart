import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_app/services/update_flow.dart';
import 'package:schedule_app/services/update_service.dart';

void main() {
  testWidgets('полоса обновления: скачивание, готово, ошибка', (t) async {
    final c = UpdateController.instance;
    await t.pumpWidget(const MaterialApp(home: Scaffold(bottomNavigationBar: UpdateBar())));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    c.update = AppUpdate(version: '9.9.9', notes: '', downloadUrl: 'x');
    c.phase = UpdatePhase.downloading;
    c.progress = 0.42;
    c.notifyListeners();
    await t.pump();
    expect(find.text('Скачиваю обновление 9.9.9 · 42%'), findsOneWidget);
    expect(find.text('Позже'), findsNothing);
    c.phase = UpdatePhase.ready;
    c.notifyListeners();
    await t.pump();
    expect(find.text('Установить'), findsOneWidget);
    c.phase = UpdatePhase.failed;
    c.notifyListeners();
    await t.pump();
    expect(find.text('Повторить'), findsOneWidget);
    c.phase = UpdatePhase.idle;
    c.notifyListeners();
  });
}
