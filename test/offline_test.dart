import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:schedule_app/api.dart';
import 'package:schedule_app/games/games_api.dart';
import 'package:schedule_app/games/sealed_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('kogpk');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
  });

  test('запись шифруется и не читается после подделки', () async {
    await SealedStore.write('bb', {'best': 1234});
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('sealed_bb')!;
    expect(raw.contains('1234'), isFalse);
    expect((await SealedStore.read('bb'))!['best'], 1234);
    final b = base64Url.decode(raw);
    b[20] ^= 1; // испортили байт шифротекста
    await p.setString('sealed_bb', base64Url.encode(b));
    expect(await SealedStore.read('bb'), isNull);
  });

  test('рекорд без сети копится и уходит, когда сеть появилась', () async {
    SharedPreferences.setMockInitialValues({'g_token': 't', 'g_nick': 'Вася', 'g_id': 1});
    await GamesApi.load();
    var online = false;
    final sent = <int>[];
    GamesApi.client = MockClient((r) async {
      if (!online) throw const SocketException('нет сети');
      sent.add(jsonDecode(r.body)['score'] as int);
      return http.Response(jsonEncode({'best': sent.last}), 200);
    });
    await GamesApi.submitBb(500);
    await GamesApi.submitBb(300); // хуже — не перезаписывает
    await GamesApi.submitBb(800);
    expect(sent, isEmpty);
    expect((await SealedStore.read('bb'))!['best'], 800);
    online = true;
    await GamesApi.flushBb();
    expect(sent, [800]);
    await GamesApi.flushBb(); // уже отправлено — повторно не шлём
    expect(sent, [800]);
  });

  test('расписание без сети — из сохранённой копии', () async {
    var online = true;
    Api.client = MockClient((r) async {
      if (!online) throw const SocketException('нет сети');
      return http.Response.bytes(utf8.encode(jsonEncode({'group_name': '170П', 'days': []})), 200);
    });
    final a = await Api.schedule('170П');
    expect(a.title, '170П');
    expect(Api.offline.value, isFalse);
    await Future.delayed(const Duration(milliseconds: 100)); // запись кэша
    online = false;
    final b = await Api.schedule('170П');
    expect(b.title, '170П');
    expect(Api.offline.value, isTrue);
    await expectLater(Api.schedule('999'), throwsA(isA<SocketException>()));
  });
}
