import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_app/games/pool/pool_client.dart';
import 'package:schedule_app/games/pool/pool_table.dart';

// Снимок настоящего ответа сервера: разбой в «восьмёрке» (billiards.py).
final fixture = jsonDecode(File('test/pool_fixture.json').readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> room() => {
      'id': 'K7M2Q',
      'mode': 'pool',
      'status': 'playing',
      'private': false,
      'bot': 0,
      'seats': [
        {'id': 1, 'nick': 'Я', 'online': true, 'ready': false},
        {'id': 2, 'nick': 'Петя', 'online': true, 'ready': false},
      ],
    };

Future<void> show(WidgetTester t, Map<String, dynamic>? g) async {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 3;
  final c = PoolClient.instance;
  c.room = room();
  c.game = g;
  c.result = null;
  c.me = 1;
  c.deadline = DateTime.now().add(const Duration(seconds: 40));
  await t.pumpWidget(const MaterialApp(home: PoolTableScreen()));
  await t.pump();
}

void main() {
  tearDown(() => PoolClient.instance.room = null);

  testWidgets('стол, прицел и удар', (t) async {
    final view = Map<String, dynamic>.from(fixture['view'] as Map);
    await show(t, view);
    expect(find.text('Я'), findsNothing); // ник с меткой «🫵 »
    expect(find.textContaining('Петя'), findsOneWidget);
    expect(find.textContaining('Сила'), findsOneWidget);
    // прицеливание пальцем по столу и сила
    final table = find.byType(CustomPaint).first;
    await t.dragFrom(t.getCenter(table), const Offset(40, -120));
    await t.pump();
    final bar = find.textContaining('Сила');
    await t.dragFrom(t.getTopLeft(bar) + const Offset(-60, 10), const Offset(150, 0));
    await t.pump();
    expect(tester(t), isNull);
  });

  testWidgets('кадры удара проигрываются и отдают состояние', (t) async {
    final c = PoolClient.instance;
    await show(t, Map<String, dynamic>.from(fixture['view'] as Map));
    c.animating = true;
    c.shots.add(Map<String, dynamic>.from(fixture['shot'] as Map));
    await t.pump();
    for (var i = 0; i < 60; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(c.animating, isFalse);
    c.game = Map<String, dynamic>.from(fixture['after'] as Map);
    c.notifyListeners();
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('ожидание соперника и итог', (t) async {
    await show(t, null);
    expect(find.text('K7M2Q'), findsOneWidget);
    expect(find.text('Готов'), findsOneWidget);
    final over = Map<String, dynamic>.from(fixture['after'] as Map)
      ..['finished'] = true
      ..['winner'] = 0
      ..['note'] = 'Чёрный шар в лузе — победа';
    PoolClient.instance.game = over;
    PoolClient.instance.notifyListeners();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('🏆 Победа!'), findsOneWidget);
  });
}

Object? tester(WidgetTester t) => t.takeException();
