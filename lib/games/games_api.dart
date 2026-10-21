import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'sealed_store.dart';

/// Игровой сервер (games_server на том же хосте, наружу — /gapi/):
/// ники, таблицы лидеров, дурак онлайн. Ник один на приложение и сайт.
class GamesApi {
  static const base = 'https://vpn-ornux.space/gapi';
  static const wsBase = 'wss://vpn-ornux.space/gapi/ws';
  static const _kToken = 'g_token', _kNick = 'g_nick', _kId = 'g_id', _kGroup = 'g_group';

  static String? token;
  static String? nick;
  static int? id;
  static String? groupTag; // своя группа тегом у ника в таблицах

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString(_kToken);
    nick = p.getString(_kNick);
    id = p.getInt(_kId);
    groupTag = p.getString(_kGroup);
  }

  static bool get registered => token != null;

  static http.Client _http = http.Client();
  @visibleForTesting
  static set client(http.Client c) => _http = c;

  static Map<String, String> get _auth =>
      {if (token != null) 'Authorization': 'Bearer $token'};

  static Future<Map<String, dynamic>> _post(String path, Map body) async {
    final r = await _http
        .post(Uri.parse('$base$path'),
            headers: {'Content-Type': 'application/json', ..._auth}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode != 200) throw GamesError(_detail(j));
    return j as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> _get(String path) async {
    final r = await _http
        .get(Uri.parse('$base$path'), headers: _auth)
        .timeout(const Duration(seconds: 15));
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode != 200) throw GamesError(_detail(j));
    return j as Map<String, dynamic>;
  }

  static String _detail(dynamic j) =>
      (j is Map && j['detail'] is String) ? j['detail'] : 'Сервер недоступен';

  /// Занимает ник; ошибка с текстом, если занят или запрещён.
  static Future<void> register(String n) async {
    final j = await _post('/register', {'nick': n});
    final p = await SharedPreferences.getInstance();
    token = j['token'] as String;
    nick = j['nick'] as String;
    id = j['id'] as int;
    await p.setString(_kToken, token!);
    await p.setString(_kNick, nick!);
    await p.setInt(_kId, id!);
  }

  static Future<void> rename(String n) async {
    final j = await _post('/rename', {'nick': n});
    nick = j['nick'] as String;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kNick, nick!);
  }

  /// Тег-группа: только из списка групп колледжа (проверяет сервер); '' — без тега.
  static Future<void> setGroupTag(String g) async {
    final j = await _post('/group_tag', {'group': g});
    final v = j['group'] as String? ?? '';
    groupTag = v.isEmpty ? null : v;
    final p = await SharedPreferences.getInstance();
    v.isEmpty ? await p.remove(_kGroup) : await p.setString(_kGroup, v);
  }

  /// Рекорд Block Boom: сначала в зашифрованную запись на устройстве, потом
  /// пробуем отправить. Нет сети или ника — уйдёт при следующем flushBb().
  static Future<void> submitBb(int best) async {
    if (best <= 0) return;
    final rec = await SealedStore.read('bb') ?? const {};
    final old = (rec['best'] as num?)?.toInt() ?? 0;
    if (best > old) {
      await SealedStore.write('bb', {...rec, 'best': best, 'at': DateTime.now().toIso8601String()});
    }
    await flushBb();
  }

  static bool _flushing = false;

  /// Отправляет неотправленный рекорд. Зовётся после партии, при запуске,
  /// возврате в приложение, открытии «Игр» и из фоновой задачи.
  static Future<void> flushBb() async {
    if (_flushing) return;
    _flushing = true;
    try {
      if (token == null) await load();
      if (!registered) return;
      final rec = await SealedStore.read('bb');
      final best = (rec?['best'] as num?)?.toInt() ?? 0;
      final sent = (rec?['sent'] as num?)?.toInt() ?? 0;
      if (best <= sent) return;
      await _post('/bb/score', {'score': best});
      await SealedStore.write('bb', {...rec!, 'sent': best});
    } catch (_) {
      // нет сети — попробуем в следующий раз
    } finally {
      _flushing = false;
    }
  }

  static Future<Leaderboard> bbTop() => _board('/bb/top?limit=100', 'lb_bb');

  static Future<Leaderboard> durakTop() => _board('/durak/top?limit=100', 'lb_durak');

  static Future<Leaderboard> _board(String path, String key) async {
    final p = await SharedPreferences.getInstance();
    try {
      final j = await _get(path);
      await p.setString(key, jsonEncode(j));
      return Leaderboard.fromJson(j);
    } catch (e) {
      final c = p.getString(key);
      if (c == null || e is GamesError) rethrow;
      return Leaderboard.fromJson(jsonDecode(c) as Map<String, dynamic>, offline: true);
    }
  }
}

class GamesError implements Exception {
  final String message;
  GamesError(this.message);
  @override
  String toString() => message;
}

class LeaderRow {
  final int rank;
  final String nick;
  final bool me;
  final Map<String, dynamic> raw;
  LeaderRow(this.rank, this.nick, this.me, this.raw);
  factory LeaderRow.fromJson(Map<String, dynamic> j) =>
      LeaderRow(j['rank'] as int, j['nick'] as String, j['me'] == true, j);
  int field(String k) => (raw[k] as num?)?.toInt() ?? 0;
}

class Leaderboard {
  final List<LeaderRow> top;
  final LeaderRow? me;
  final bool offline; // показана сохранённая копия
  Leaderboard(this.top, this.me, {this.offline = false});
  factory Leaderboard.fromJson(Map<String, dynamic> j, {bool offline = false}) => Leaderboard(
        (j['top'] as List).map((e) => LeaderRow.fromJson(e)).toList(),
        j['me'] == null ? null : LeaderRow.fromJson({...j['me'], 'me': true}),
        offline: offline,
      );
}
