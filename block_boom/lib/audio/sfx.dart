import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Звуки и вибрация. Звуки не забирают аудиофокус — музыка пользователя
/// продолжает играть.
class Sfx {
  Sfx._();

  static bool sound = true;
  static bool vibration = true;

  static const _names = [
    'pick', 'place', 'bad', 'great', 'over', 'record', 'levelup', 'tap', 'deal',
    'clear1', 'clear2', 'clear3', 'clear4', 'clear5', 'clear6', 'clear7', 'clear8',
  ];

  /// По несколько плееров на звук, чтобы одинаковые звуки могли наслаиваться.
  static final Map<String, List<AudioPlayer>> _players = {};
  static final Map<String, int> _next = {};

  static Future<void> init() async {
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
      );
      await Future.wait(_names.map((name) async {
        final copies = name.startsWith('clear') || name == 'place' || name == 'pick' ? 3 : 2;
        final list = <AudioPlayer>[];
        for (var i = 0; i < copies; i++) {
          final p = AudioPlayer();
          await p.setPlayerMode(PlayerMode.lowLatency);
          await p.setReleaseMode(ReleaseMode.stop);
          await p.setSource(AssetSource('sfx/$name.wav'));
          list.add(p);
        }
        _players[name] = list;
      }));
    } catch (e) {
      debugPrint('sfx init failed: $e');
    }
  }

  static Future<void> play(String name, {double volume = 1}) async {
    if (!sound) return;
    final list = _players[name];
    if (list == null || list.isEmpty) return;
    final i = (_next[name] ?? 0) % list.length;
    _next[name] = i + 1;
    final p = list[i];
    try {
      await p.stop();
      await p.setVolume(volume);
      await p.resume();
    } catch (_) {}
  }

  static void clear(int streak) => play('clear${streak.clamp(1, 8)}');

  static void haptic(int strength) {
    if (!vibration) return;
    switch (strength) {
      case 0:
        HapticFeedback.selectionClick();
      case 1:
        HapticFeedback.lightImpact();
      case 2:
        HapticFeedback.mediumImpact();
      default:
        HapticFeedback.heavyImpact();
    }
  }
}
