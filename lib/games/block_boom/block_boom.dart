// Block Boom — игра на перемене. Исходники перенесены из yanikto-boop/games
// (block_boom/), правки: ключи prefs с префиксом bb_, звуки в
// assets/block_boom/, тема игры навешивается на каждый её экран через bbTheme.
import 'dart:async';

import 'package:flutter/material.dart';

import 'audio/sfx.dart';
import 'game/profile.dart';
import 'ui/menu_screen.dart';

final _theme = ThemeData(
  brightness: Brightness.dark,
  fontFamily: 'Russo',
  colorSchemeSeed: const Color(0xFF4A7BFF),
);

/// Тёмная тема и шрифт игры поверх темы приложения. Игра свёрстана под
/// фиксированные размеры шрифта — системное масштабирование отключаем.
Widget bbTheme(Widget child) => Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: Theme(
          data: _theme,
          child: DefaultTextStyle(
            style: const TextStyle(fontFamily: 'Russo', color: Colors.white),
            child: child,
          ),
        ),
      ),
    );

Profile? _profile;

Future<void> openBlockBoom(BuildContext context) async {
  var profile = _profile;
  if (profile == null) {
    profile = Profile();
    await profile.load();
    final p = profile;
    void sync() {
      Sfx.sound = p.sound;
      Sfx.vibration = p.vibration;
    }

    sync();
    p.addListener(sync);
    unawaited(Sfx.init());
    _profile = p;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(fadeRoute(MenuScreen(profile: profile)));
}
