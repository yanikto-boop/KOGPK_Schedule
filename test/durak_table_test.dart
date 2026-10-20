import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_app/games/durak/cards.dart';
import 'package:schedule_app/games/durak/durak_client.dart';
import 'package:schedule_app/games/durak/table_screen.dart';

Map<String, dynamic> room({List seats = const [], String status = 'playing'}) => {
      'id': 'K7M2Q',
      'rules': {'players': 3, 'deck': 36, 'transfer': true, 'throw_all': true},
      'status': status,
      'seats': [
        {'id': 1, 'nick': 'Я', 'online': true, 'ready': false},
        {'id': 2, 'nick': 'Петя', 'online': true, 'ready': false},
        {'id': 3, 'nick': 'Лена', 'online': false, 'ready': false},
      ],
    };

Map<String, dynamic> game({
  required List<String> hand,
  List table = const [],
  int attacker = 1,
  int defender = 2,
  List<int> waiting = const [1],
  Map<String, bool> can = const {},
  bool finished = false,
}) =>
    {
      'seats': [1, 2, 3],
      'hand': hand,
      'counts': {'1': hand.length, '2': 6, '3': 6},
      'table': table,
      'trump': 'H',
      'trump_card': '9H',
      'deck': 12,
      'discard': 0,
      'attacker': attacker,
      'defender': defender,
      'taking': false,
      'passed': [],
      'limit': 5,
      'out': [],
      'waiting': waiting,
      'finished': finished,
      'loser': finished ? 2 : null,
      'version': 1,
      'can': {'throw': false, 'transfer': false, 'take': false, 'pass': false, 'defend': false, ...can},
    };

Future<void> show(WidgetTester t, Map<String, dynamic> g, {Map<String, dynamic>? result}) async {
  final c = DurakClient.instance;
  c.room = room();
  c.game = g;
  c.result = result;
  c.me = 1;
  c.deadline = DateTime.now().add(const Duration(seconds: 25));
  await t.pumpWidget(const MaterialApp(home: DurakTableScreen()));
  await t.pump();
}

void main() {
  test('кто кого бьёт', () {
    expect(beats('7S', '6S', 'H'), isTrue);
    expect(beats('6S', '7S', 'H'), isFalse);
    expect(beats('6H', 'AS', 'H'), isTrue);
    expect(beats('AS', '6H', 'H'), isFalse);
    expect(beats('KD', '6S', 'H'), isFalse);
  });

  testWidgets('мой первый ход: выбрал карту — «Ходить»', (t) async {
    await show(t, game(hand: ['6S', '7D', 'QH'], can: {'throw': true}));
    expect(find.text('Ваш ход'), findsOneWidget);
    expect(find.text('Ходить'), findsNothing);
    await t.tap(find.byType(PlayingCard).at(4)); // 3 рубашки у соперников + козырь = 0..3
    await t.pump();
    expect(find.text('Ходить'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('защита: «Побить» и «Беру», перевод', (t) async {
    await show(
        t,
        game(
            hand: ['7S', '6C', 'KD'],
            table: [
              ['6S', null]
            ],
            attacker: 2,
            defender: 1,
            can: {'defend': true, 'take': true, 'transfer': true}));
    expect(find.textContaining('Отбивайтесь или берите'), findsOneWidget);
    expect(find.text('Беру'), findsOneWidget);
    await t.tap(find.byWidgetPredicate((w) => w is PlayingCard && w.card == '7S'));
    await t.pump();
    expect(find.text('Побить'), findsOneWidget);
    await t.tap(find.byWidgetPredicate((w) => w is PlayingCard && w.card == '6C'));
    await t.pump();
    expect(find.text('Перевести'), findsOneWidget);
    expect(find.text('Побить'), findsNothing);
  });

  testWidgets('всё побито — «Бито»', (t) async {
    await show(
        t,
        game(
            hand: ['8C'],
            table: [
              ['6S', '7S']
            ],
            can: {'pass': true, 'throw': true}));
    expect(find.text('Бито'), findsOneWidget);
  });

  testWidgets('итог партии и реванш', (t) async {
    await show(t, game(hand: [], finished: true, waiting: []),
        result: {'loser': 2, 'loser_nick': 'Петя', 'out': []});
    expect(find.text('Победа! 🎉'), findsOneWidget);
    expect(find.textContaining('Ещё раз'), findsOneWidget);
  });
}
