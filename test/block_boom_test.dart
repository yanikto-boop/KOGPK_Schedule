import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:schedule_app/games/block_boom/block_boom.dart';
import 'package:schedule_app/games/block_boom/game/profile.dart';
import 'package:schedule_app/games/block_boom/ui/menu_screen.dart';

void main() {
  testWidgets('меню Block Boom открывается внутри приложения', (tester) async {
    SharedPreferences.setMockInitialValues({'group': '170П'});
    final profile = Profile();
    await profile.load();
    await tester.pumpWidget(MaterialApp(home: bbTheme(MenuScreen(profile: profile))));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MenuScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('прогресс игры хранится под своими ключами', () async {
    SharedPreferences.setMockInitialValues({'group': '170П', 'sound': false});
    final profile = Profile();
    await profile.load();
    expect(profile.sound, isTrue); // чужой 'sound' не подхватился
    profile.setSound(false);
    final p = await SharedPreferences.getInstance();
    expect(p.getBool('bb_sound'), isFalse);
    expect(p.getString('group'), '170П');
  });
}
