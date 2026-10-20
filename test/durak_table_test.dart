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
  int version = 1,
  List<Map> events = const [],
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
      'version': version,
      'events': events,
      'can': {'throw': false, 'transfer': false, 'take': false, 'pass': false, 'defend': false, ...can},
    };

Future<void> show(WidgetTester t, Map<String, dynamic>? g,
    {Map<String, dynamic>? result, Map<String, dynamic>? r}) async {
  final c = DurakClient.instance;
  c.room = r ?? room();
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

  testWidgets('без подсказок: карты не затемняются, кнопок хода нет', (t) async {
    await show(t, game(hand: ['6S', '7D', 'QH'], can: {'throw': true}));
    expect(find.text('Ваш ход'), findsOneWidget);
    expect(find.byType(Opacity).evaluate().where((e) => (e.widget as Opacity).opacity < 1), isEmpty);
    for (final b in ['Ходить', 'Подкинуть', 'Побить', 'Перевести']) {
      expect(find.text(b), findsNothing);
    }
  });

  testWidgets('перетащил карту на стол — ход', (t) async {
    final sent = <Map>[];
    DurakClient.instance.onSend = sent.add;
    await show(t, game(hand: ['6S', '7D', 'QH'], can: {'throw': true}));
    await t.drag(find.byWidgetPredicate((w) => w is PlayingCard && w.card == '7D'), const Offset(0, -260));
    await t.pumpAndSettle();
    expect(sent, [
      {'t': 'throw', 'card': '7D'}
    ]);
  });

  testWidgets('защитник: на карту — побить, на стол — перевести; тап как запасной путь', (t) async {
    final sent = <Map>[];
    DurakClient.instance.onSend = sent.add;
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
    await t.pumpAndSettle();
    expect(find.text('Беру'), findsOneWidget);
    final target = t.getCenter(find.byWidgetPredicate((w) => w is PlayingCard && w.card == '6S'));
    final from = t.getCenter(find.byWidgetPredicate((w) => w is PlayingCard && w.card == '7S'));
    await t.dragFrom(from, target - from);
    await t.pumpAndSettle();
    expect(sent.last, {'t': 'defend', 'card': '7S', 'idx': 0});
    final from2 = t.getCenter(find.byWidgetPredicate((w) => w is PlayingCard && w.card == '6C'));
    await t.dragFrom(from2, Offset(target.dx - 130 - from2.dx, target.dy - from2.dy)); // пустое место стола
    await t.pumpAndSettle();
    expect(sent.last, {'t': 'transfer', 'card': '6C'});
    await t.tap(find.byWidgetPredicate((w) => w is PlayingCard && w.card == 'KD'));
    await t.pump();
    await t.tap(find.byWidgetPredicate((w) => w is PlayingCard && w.card == '6S'));
    await t.pump();
    expect(sent.last, {'t': 'defend', 'card': 'KD', 'idx': 0});
    DurakClient.instance.onSend = null;
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

  testWidgets('комната ждёт «Готов»: кнопка шлёт ready и пропадает', (t) async {
    final sent = <Map>[];
    DurakClient.instance.onSend = sent.add;
    await show(t, null, r: room(status: 'waiting'));
    expect(find.text('Все в сборе'), findsOneWidget);
    await t.tap(find.text('Готов'));
    expect(sent.last, {'t': 'ready'});
    DurakClient.instance.onSend = null;
  });

  testWidgets('раздача и ход соперника летят анимацией, без автоматики в конце', (t) async {
    final c = DurakClient.instance;
    await show(
        t,
        game(hand: ['6S', '7D', 'QH', '8C', '9C', 'JD'], version: 0, events: [
          {'type': 'deal', 'v': 0, 'order': [1, 2, 3], 'n': 6}
        ]));
    await t.pump(const Duration(milliseconds: 50));
    // карты летят из колоды — в руке пока не все
    final hidden = find.byWidgetPredicate((w) => w is Visibility && !w.visible);
    expect(hidden, findsWidgets);
    await t.pumpAndSettle();
    expect(hidden, findsNothing);
    // соперник походил: карта прилетает от его аватарки
    c.game = game(
        hand: ['6S', '7D', 'QH', '8C', '9C', 'JD'],
        table: [
          ['KS', null]
        ],
        attacker: 2,
        defender: 1,
        version: 1,
        can: {'defend': true, 'take': true},
        events: [
          {'type': 'deal', 'v': 0, 'order': [1, 2, 3], 'n': 6},
          {'type': 'play', 'v': 1, 'who': 2, 'card': 'KS'}
        ]);
    c.notifyListeners();
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(hidden, findsOneWidget);
    await t.pumpAndSettle();
    expect(hidden, findsNothing);
    expect(find.text('Беру'), findsOneWidget);
  });
}
