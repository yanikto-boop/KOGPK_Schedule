import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../games_api.dart';

/// Соединение с сервером дурака. Сервер решает всё; здесь только последнее
/// присланное состояние и отправка намерений. Обрыв — переподключаемся сами,
/// сервер держит место в партии минуту.
class DurakClient extends ChangeNotifier {
  DurakClient._();
  static final instance = DurakClient._();

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _retry, _ping;
  bool _wanted = false;
  int _attempt = 0;

  bool connected = false;
  List<Map<String, dynamic>> rooms = [];
  Map<String, dynamic>? room; // null — в лобби
  Map<String, dynamic>? game;
  Map<String, dynamic>? result;
  int? me;
  DateTime? deadline;
  final errors = StreamController<String>.broadcast();

  void start() {
    _wanted = true;
    if (_ch == null) _connect();
  }

  void stop() {
    _wanted = false;
    _retry?.cancel();
    _ping?.cancel();
    _sub?.cancel();
    _ch?.sink.close();
    _ch = null;
    connected = false;
  }

  void _connect() {
    final tok = GamesApi.token;
    if (tok == null) return;
    try {
      _ch = WebSocketChannel.connect(
          Uri.parse('${GamesApi.wsBase}?token=${Uri.encodeQueryComponent(tok)}'));
    } catch (_) {
      _scheduleRetry();
      return;
    }
    _sub = _ch!.stream.listen(_onMessage,
        onDone: _onClosed, onError: (_) => _onClosed(), cancelOnError: true);
    _ping?.cancel();
    _ping = Timer.periodic(const Duration(seconds: 25), (_) => send({'t': 'ping'}));
  }

  void _onClosed() {
    _ch = null;
    _ping?.cancel();
    if (connected) {
      connected = false;
      notifyListeners();
    }
    if (_wanted) _scheduleRetry();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    final s = [1, 2, 3, 5, 8][_attempt.clamp(0, 4)];
    _attempt++;
    _retry = Timer(Duration(seconds: s), () {
      if (_wanted && _ch == null) _connect();
    });
  }

  void _onMessage(dynamic raw) {
    final m = jsonDecode(raw as String) as Map<String, dynamic>;
    connected = true;
    _attempt = 0;
    switch (m['t']) {
      case 'rooms':
        rooms = (m['rooms'] as List).cast<Map<String, dynamic>>();
        room = null;
        game = null;
        result = null;
      case 'room':
        room = m['room'] as Map<String, dynamic>;
        game = m['game'] as Map<String, dynamic>?;
        result = m['result'] as Map<String, dynamic>?;
        me = m['me'] as int?;
        final d = m['deadline'];
        deadline = d == null ? null : DateTime.now().add(Duration(seconds: d as int));
      case 'error':
        errors.add(m['msg'] as String? ?? 'Ошибка');
        if (m['auth'] == false) _wanted = false;
        return;
      default:
        return;
    }
    notifyListeners();
  }

  void send(Map<String, dynamic> m) {
    _ch?.sink.add(jsonEncode(m));
  }

  void create(
          {required int players,
          required int deck,
          required bool transfer,
          required bool throwAll,
          required bool private}) =>
      send({
        't': 'create',
        'players': players,
        'deck': deck,
        'transfer': transfer,
        'throw_all': throwAll,
        'private': private,
      });
  void join(String id) => send({'t': 'join', 'room': id});
  void leave() => send({'t': 'leave'});
  void rematch() => send({'t': 'rematch'});
  void refreshRooms() => send({'t': 'rooms'});
  void act(String t, {String? card, int? idx}) => send({
        't': t,
        if (card != null) 'card': card,
        if (idx != null) 'idx': idx,
      });
}
