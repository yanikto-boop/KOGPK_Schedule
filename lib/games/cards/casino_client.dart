import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../games_api.dart';

/// Соединение с казино (/gapi/cws): покер и блэкджек. Сервер хранит комнаты и фишки,
/// присылает полное состояние стола («room») после каждого изменения.
class CasinoClient extends ChangeNotifier {
  CasinoClient._();
  static final instance = CasinoClient._();

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _retry, _ping;
  bool _wanted = false;
  int _attempt = 0;

  bool connected = false;
  List<Map<String, dynamic>> rooms = [];
  Map<String, dynamic>? room; // null — в лобби
  Map<String, dynamic>? state;
  int? me; // мой id
  int chips = 0;
  DateTime? deadline;
  final errors = StreamController<String>.broadcast();

  String? get kind => room?['kind'] as String?;

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
      _ch = WebSocketChannel.connect(Uri.parse('${GamesApi.casinoWs}?token=${Uri.encodeQueryComponent(tok)}'));
    } catch (_) {
      _scheduleRetry();
      return;
    }
    _sub = _ch!.stream.listen(_onMessage, onDone: _onClosed, onError: (_) => _onClosed(), cancelOnError: true);
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
        room = state = null;
        deadline = null;
        if (m['chips'] != null) chips = (m['chips'] as num).toInt();
      case 'room':
        room = m['room'] as Map<String, dynamic>;
        state = m['state'] as Map<String, dynamic>;
        me = (m['me'] as num?)?.toInt();
        if (m['chips'] != null) chips = (m['chips'] as num).toInt();
        final d = m['deadline'];
        deadline = (d == null || d == 0) ? null : DateTime.now().add(Duration(seconds: d as int));
      case 'error':
        errors.add(m['msg'] as String? ?? 'Ошибка');
        if (m['auth'] == false) _wanted = false;
        return;
      default:
        return;
    }
    notifyListeners();
  }

  void send(Map<String, dynamic> m) => _ch?.sink.add(jsonEncode(m));

  void createPoker({required bool private, int bots = 0}) =>
      send({'t': 'create', 'kind': 'poker', 'private': private, 'bots': bots});
  void createBj({required bool solo}) => send({'t': 'create', 'kind': 'bj', 'solo': solo, 'private': solo});
  void join(String id) => send({'t': 'join', 'room': id});
  void leave() => send({'t': 'leave'});
  void refreshRooms() => send({'t': 'rooms'});
  void act(String a, [int amount = 0]) => send({'t': 'act', 'a': a, 'amount': amount});
  void bet(int amount) => send({'t': 'bet', 'amount': amount});
  void clearBet() => send({'t': 'clear_bet'});
  void move(String t) => send({'t': t}); // hit | stand | double
}
