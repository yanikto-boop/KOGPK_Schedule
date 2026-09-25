import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio/sfx.dart';
import 'game/profile.dart';
import 'ui/menu_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final profile = Profile();
  await profile.load();
  void syncSettings() {
    Sfx.sound = profile.sound;
    Sfx.vibration = profile.vibration;
  }

  syncSettings();
  profile.addListener(syncSettings);
  unawaited(Sfx.init());

  runApp(BlockBoomApp(profile: profile));
}

class BlockBoomApp extends StatelessWidget {
  const BlockBoomApp({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Block Boom',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Russo',
        colorSchemeSeed: const Color(0xFF4A7BFF),
      ),
      builder: (context, child) => MediaQuery(
        // игра свёрстана под фиксированные размеры шрифта
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: child!,
      ),
      home: MenuScreen(profile: profile),
    );
  }
}
