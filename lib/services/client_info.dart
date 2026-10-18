import 'dart:io' show Platform;
import 'dart:math' show Random;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Заголовки, по которым сервер отличает приложение в аналитике:
/// X-Client, X-Vid (анонимный id установки), X-OS, X-Device.
class ClientInfo {
  static Map<String, String>? _headers;

  static Future<Map<String, String>> headers() async =>
      _headers ??= await _build();

  static Future<Map<String, String>> _build() async {
    final h = <String, String>{'X-Client': 'app'};
    try {
      final prefs = await SharedPreferences.getInstance();
      var vid = prefs.getString('analytics_vid');
      if (vid == null || vid.isEmpty) {
        vid = _uuid();
        await prefs.setString('analytics_vid', vid);
      }
      h['X-Vid'] = vid;
    } catch (_) {}
    try {
      final di = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await di.androidInfo;
        h['X-OS'] = 'Android ${a.version.release}';
        h['X-Device'] = _ascii('${a.manufacturer} ${a.model}');
      } else if (Platform.isIOS) {
        final i = await di.iosInfo;
        h['X-OS'] = 'iOS ${i.systemVersion}';
        h['X-Device'] = _ascii(i.utsname.machine);
      } else {
        h['X-OS'] = Platform.operatingSystem;
      }
    } catch (_) {}
    return h;
  }

  /// HTTP-заголовки только ASCII.
  static String _ascii(String s) =>
      s.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();

  static String _uuid() {
    final rnd = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    rnd[6] = (rnd[6] & 0x0F) | 0x40;
    rnd[8] = (rnd[8] & 0x3F) | 0x80;
    final x = rnd.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${x.substring(0, 8)}-${x.substring(8, 12)}-${x.substring(12, 16)}-'
        '${x.substring(16, 20)}-${x.substring(20)}';
  }
}

/// http-клиент, добавляющий [ClientInfo.headers] к каждому запросу.
class TaggedClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.addAll(await ClientInfo.headers());
    return _inner.send(request);
  }
}
