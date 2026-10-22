import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../games_api.dart';

/// Соединение с бильярдом (/gapi/pws). Удар считает сервер и присылает кадры
/// («shot»), следом — новое состояние («room»). Пока стол проигрывает кадры,
/// состояние ждёт в [_queued], чтобы шары не прыгнули в конец раньше времени.
class PoolClient extends ChangeNotifier {
  PoolClient._();
  static final instance = PoolClient._();

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
  Map<String, dynamic>? oppAim; // куда целится соперник
  bool animating = false;
  Map<String, dynamic>? _queued;
  final shots = StreamController<Map<String, dynamic>>.broadcast();
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
    animating = false;
    _queued = null;
  }

  void _connect() {
    final tok = GamesApi.token;
    if (tok == null) return;
    try {
      _ch = WebSocketChannel.connect(Uri.parse('${GamesApi.poolWs}?token=${Uri.encodeQueryComponent(tok)}'));
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
        room = game = result = null;
        animating = false;
        _queued = null;
      case 'room':
        if (animating) {
          _queued = m;
          return;
        }
        _apply(m);
      case 'shot':
        // некому показывать — сразу к итогу
        if (!shots.hasListener) return;
        animating = true;
        oppAim = null;
        shots.add(m['shot'] as Map<String, dynamic>);
        return;
      case 'aim':
        oppAim = m;
      case 'error':
        errors.add(m['msg'] as String? ?? 'Ошибка');
        if (m['auth'] == false) _wanted = false;
        return;
      default:
        return;
    }
    notifyListeners();
  }

  void _apply(Map<String, dynamic> m) {
    room = m['room'] as Map<String, dynamic>;
    game = m['game'] as Map<String, dynamic>?;
    result = m['result'] as Map<String, dynamic>?;
    me = m['me'] as int?;
    final d = m['deadline'];
    deadline = d == null ? null : DateTime.now().add(Duration(seconds: d as int));
  }

  /// Стол доиграл кадры — показать отложенное состояние.
  void animDone() {
    animating = false;
    final q = _queued;
    _queued = null;
    if (q != null) _apply(q);
    notifyListeners();
  }

  void send(Map<String, dynamic> m) => _ch?.sink.add(jsonEncode(m));

  void create(String mode, {required bool private}) => send({'t': 'create', 'mode': mode, 'private': private});
  void withBot(String mode, int level) => send({'t': 'bot', 'mode': mode, 'level': level});
  void join(String id) => send({'t': 'join', 'room': id});
  void leave() => send({'t': 'leave'});
  void ready() => send({'t': 'ready'});
  void refreshRooms() => send({'t': 'rooms'});
}
