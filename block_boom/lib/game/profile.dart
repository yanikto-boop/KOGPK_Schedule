import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/skins.dart';
import 'game_model.dart';

class LevelInfo {
  const LevelInfo(this.level, this.into, this.need);
  final int level;

  /// Опыта набрано внутри текущего уровня.
  final int into;

  /// Сколько нужно на следующий уровень.
  final int need;
  double get progress => need == 0 ? 0 : into / need;
}

/// Итог партии для экрана результатов.
class GameRecord {
  GameRecord({
    required this.score,
    required this.oldBest,
    required this.oldXp,
    required this.newXp,
    required this.unlocked,
  });

  final int score;
  final int oldBest;
  final int oldXp;
  final int newXp;
  final List<Skin> unlocked;
  bool get newBest => score > oldBest && score > 0;
  LevelInfo get before => Profile.levelFor(oldXp);
  LevelInfo get after => Profile.levelFor(newXp);
}

/// Прогресс игрока, настройки и сохранённая партия.
class Profile extends ChangeNotifier {
  late SharedPreferences _p;

  int best = 0;
  int xp = 0;
  int games = 0;
  int bestCombo = 0;
  int totalLines = 0;
  bool sound = true;
  bool vibration = true;
  bool tutorialDone = false;
  String skinId = kSkins.first.id;

  Skin get skin => kSkins.firstWhere((s) => s.id == skinId, orElse: () => kSkins.first);
  LevelInfo get levelInfo => levelFor(xp);
  bool isUnlocked(Skin s) => levelInfo.level >= s.unlockLevel;
  bool get hasSavedGame => _p.getString('game') != null;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    best = _p.getInt('best') ?? 0;
    xp = _p.getInt('xp') ?? 0;
    games = _p.getInt('games') ?? 0;
    bestCombo = _p.getInt('bestCombo') ?? 0;
    totalLines = _p.getInt('totalLines') ?? 0;
    sound = _p.getBool('sound') ?? true;
    vibration = _p.getBool('vibration') ?? true;
    tutorialDone = _p.getBool('tutorial') ?? false;
    skinId = _p.getString('skin') ?? kSkins.first.id;
    if (!isUnlocked(skin)) skinId = kSkins.first.id;
  }

  /// Опыт, нужный для перехода с уровня [level] на следующий.
  static int needFor(int level) => (400 * pow(level, 1.4)).round();

  /// Звание игрока по уровню.
  static String rankFor(int level) => switch (level) {
        < 3 => 'Новичок',
        < 5 => 'Любитель',
        < 8 => 'Знаток',
        < 12 => 'Мастер',
        < 16 => 'Эксперт',
        < 22 => 'Гроссмейстер',
        _ => 'Легенда',
      };

  static LevelInfo levelFor(int xp) {
    var level = 1;
    var rest = xp;
    while (rest >= needFor(level)) {
      rest -= needFor(level);
      level++;
    }
    return LevelInfo(level, rest, needFor(level));
  }

  void setSound(bool v) {
    sound = v;
    _p.setBool('sound', v);
    notifyListeners();
  }

  void setVibration(bool v) {
    vibration = v;
    _p.setBool('vibration', v);
    notifyListeners();
  }

  void setSkin(Skin s) {
    if (!isUnlocked(s)) return;
    skinId = s.id;
    _p.setString('skin', s.id);
    notifyListeners();
  }

  void markTutorialDone() {
    if (tutorialDone) return;
    tutorialDone = true;
    _p.setBool('tutorial', true);
  }

  // ---------- Партия ----------

  GameModel? loadGame() {
    final raw = _p.getString('game');
    if (raw == null) return null;
    try {
      return GameModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  void saveGame(GameModel m) => _p.setString('game', jsonEncode(m.toJson()));

  void clearGame() => _p.remove('game');

  /// Засчитывает законченную партию: рекорд, опыт, статистика.
  GameRecord recordGame(GameModel m) {
    final before = levelInfo.level;
    final rec = GameRecord(
      score: m.score,
      oldBest: best,
      oldXp: xp,
      newXp: xp + m.score,
      unlocked: [],
    );
    xp += m.score;
    games++;
    best = max(best, m.score);
    bestCombo = max(bestCombo, m.bestStreak);
    totalLines += m.linesCleared;
    final after = levelInfo.level;
    rec.unlocked.addAll(kSkins.where((s) => s.unlockLevel > before && s.unlockLevel <= after));
    _p
      ..setInt('xp', xp)
      ..setInt('games', games)
      ..setInt('best', best)
      ..setInt('bestCombo', bestCombo)
      ..setInt('totalLines', totalLines)
      ..remove('game');
    notifyListeners();
    return rec;
  }
}
