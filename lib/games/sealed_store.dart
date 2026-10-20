import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Зашифрованная и подписанная запись в prefs (рекорд Block Boom до отправки).
///
/// Шифр — поток HMAC-SHA256(ключ, nonce‖счётчик), подпись — HMAC от
/// nonce‖шифротекст. Ключ = SHA-256(соль приложения ‖ случайный секрет
/// устройства). Подделанная или испорченная запись не проходит подпись и
/// читается как пустая. От того, кто разберёт APK, это не спасает — ключ
/// внутри, но правкой файла настроек рекорд больше не накрутить.
class SealedStore {
  static const _salt = 'kogpk/games/sealed/v1/7c1e9b52';
  static const _kDevice = 'g_dev';

  static Future<List<int>> _key(SharedPreferences p) async {
    var dev = p.getString(_kDevice);
    if (dev == null) {
      final r = Random.secure();
      dev = base64Url.encode(List<int>.generate(32, (_) => r.nextInt(256)));
      await p.setString(_kDevice, dev);
    }
    return sha256.convert(utf8.encode('$_salt|$dev')).bytes;
  }

  static List<int> _stream(List<int> key, List<int> nonce, int len) {
    final out = <int>[];
    final h = Hmac(sha256, key);
    for (var i = 0; out.length < len; i++) {
      out.addAll(h.convert([...nonce, i >> 24 & 255, i >> 16 & 255, i >> 8 & 255, i & 255]).bytes);
    }
    return out.sublist(0, len);
  }

  static Future<void> write(String name, Map<String, dynamic> data) async {
    final p = await SharedPreferences.getInstance();
    final key = await _key(p);
    final r = Random.secure();
    final nonce = List<int>.generate(16, (_) => r.nextInt(256));
    final plain = utf8.encode(jsonEncode(data));
    final ks = _stream(key, nonce, plain.length);
    final cipher = [for (var i = 0; i < plain.length; i++) plain[i] ^ ks[i]];
    final mac = Hmac(sha256, key).convert([...nonce, ...cipher]).bytes;
    await p.setString('sealed_$name', base64Url.encode(Uint8List.fromList([...nonce, ...cipher, ...mac])));
  }

  static Future<Map<String, dynamic>?> read(String name) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('sealed_$name');
    if (raw == null) return null;
    try {
      final b = base64Url.decode(raw);
      if (b.length < 16 + 32) return null;
      final key = await _key(p);
      final nonce = b.sublist(0, 16);
      final cipher = b.sublist(16, b.length - 32);
      final mac = b.sublist(b.length - 32);
      final want = Hmac(sha256, key).convert([...nonce, ...cipher]).bytes;
      var diff = 0;
      for (var i = 0; i < 32; i++) {
        diff |= mac[i] ^ want[i];
      }
      if (diff != 0) return null;
      final ks = _stream(key, nonce, cipher.length);
      final plain = [for (var i = 0; i < cipher.length; i++) cipher[i] ^ ks[i]];
      return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
