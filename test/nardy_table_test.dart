import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_app/games/nardy/nardy_client.dart';
import 'package:schedule_app/games/nardy/nardy_table.dart';

void main() {
  testWidgets('доска нард рисуется', (t) async {
    t.view.physicalSize = const Size(390 * 2, 780 * 2);
    t.view.devicePixelRatio = 2;
    final c = NardyClient.instance;
    c.room = {
      'id': 'ABCDE', 'private': true,
      'seats': [{'id': 1, 'nick': 'Я', 'online': true, 'ready': true}, {'id': -2, 'nick': 'Бот', 'online': true, 'ready': true}],
    };
    c.me = 1;
    final board = List.filled(24, 0);
    board[0] = 9; board[3] = 2; board[19] = 1; board[22] = 3;
    board[12] = -8; board[14] = -2; board[7] = -4; board[9] = -1;
    c.game = {
      'board': board, 'off': [0, 0], 'pips': [300, 290], 'color': 0, 'turn': 0, 'me': 0, 'my_turn': true,
      'dice': [5, 3], 'left': [3], 'moves': [{'from': 0, 'to': 3}, {'from': 3, 'to': 6}, {'from': 19, 'to': 22}],
      'can_undo': true, 'finished': false, 'winner': null, 'mars': false, 'note': '', 'last': null, 'version': 3,
    };
    await t.pumpWidget(const MaterialApp(home: NardyTableScreen()));
    await t.pump();
    await t.tapAt(const Offset(370, 200)); // мимо — ничего не ломается
    await t.pump();
    expect(find.text('Отменить'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
