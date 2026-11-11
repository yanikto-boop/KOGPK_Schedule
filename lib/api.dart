import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'services/client_info.dart';

/// Клиент к Schedule API (бэкенд на германском сервере).
class Api {
  // основной адрес — напрямую, без CDN (операторы душат наш домен за Cloudflare)
  static const base = 'https://kpk-rsp.space/sapi';
  // запасной: если основной недоступен (блокировки), его запрос стартует сам через 2,5 с
  static const baseAlt = 'https://api.ndhbh-relay.space/sapi';
  // адрес, который отвечал последним — со следующего запроса пробуем его первым
  static String _pref = base;
  static http.Client _c = TaggedClient();
  @visibleForTesting
  static set client(http.Client c) => _c = c;

  static Future<List<GroupRef>> groups() async {
    final r = await _get('/groups');
    final list = (r['groups'] as List).cast<Map<String, dynamic>>();
    return list.map(GroupRef.fromJson).toList();
  }

  static Future<ScheduleData> schedule(String group) async {
    final r = await _get('/schedule?group=${Uri.encodeQueryComponent(group)}');
    return ScheduleData.fromJson(r);
  }

  static Future<List<ScheduleChange>> changes(String group) async {
    final r = await _get('/changes?group=${Uri.encodeQueryComponent(group)}');
    return (r['changes'] as List)
        .map((e) => ScheduleChange.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<ScheduleChange>> teacherChanges(String name) async {
    final r =
        await _get('/teacher_changes?name=${Uri.encodeQueryComponent(name)}');
    return (r['changes'] as List)
        .map((e) => ScheduleChange.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<String>> teachers() async {
    final r = await _get('/teachers');
    return (r['teachers'] as List).cast<String>();
  }

  static Future<ScheduleData> teacher(String name) async {
    final r = await _get('/teacher?name=${Uri.encodeQueryComponent(name)}');
    return ScheduleData.fromJson(r, teacherMode: true);
  }

  // ── кабинеты (сервер собирает их из расписания групп) ──
  static Future<List<RoomRef>> rooms() async {
    final r = await _get('/rooms');
    return (r['rooms'] as List)
        .map((e) => RoomRef.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<ScheduleData> room(String name) async {
    final r = await _get('/room?name=${Uri.encodeQueryComponent(name)}');
    return ScheduleData.fromRoom(r);
  }

  /// Свободные кабинеты колледжа. Без [num] — текущая/следующая пара сегодня.
  static Future<FreeRooms> roomsFree({String? date, String? num}) async {
    final q = <String>[
      if (date != null) 'date=$date',
      if (num != null) 'num=${Uri.encodeQueryComponent(num)}',
    ];
    final r = await _get('/rooms/free${q.isEmpty ? '' : '?${q.join('&')}'}');
    return FreeRooms.fromJson(r);
  }

  static Future<JournalData> journal(String ticketId) async {
    final resp = await _post('/journal', {'ticket_id': ticketId},
        timeout: const Duration(seconds: 55));
    if (resp.statusCode != 200) {
      throw ApiException(_msg(resp));
    }
    return JournalData.fromJson(jsonDecode(utf8.decode(resp.bodyBytes)));
  }

  // ── городской транспорт ──
  static Future<List<BusRoute>> busRoutes() async {
    final r = await _get('/bus/routes');
    return (r['routes'] as List)
        .map((e) => BusRoute.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<BusStation>> busStations() async {
    final r = await _get('/bus/stations');
    return (r['stations'] as List)
        .map((e) => BusStation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<BusStation>> busRouteStations(int rid) async {
    final r = await _get('/bus/route_stations?rid=$rid');
    return (r['stations'] as List)
        .map((e) => BusStation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<List<double>>> busRouteNodes(int rid) async {
    final r = await _get('/bus/route_nodes?rid=$rid');
    return (r['points'] as List)
        .map((p) => (p as List).map((e) => (e as num).toDouble()).toList())
        .toList();
  }

  static Future<List<BusVehicle>> busVehicles({String? rids}) async {
    final r = await _get('/bus/vehicles${rids != null ? '?rids=$rids' : ''}');
    return (r['vehicles'] as List)
        .map((e) => BusVehicle.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<BusForecast>> busForecast(int sid) async {
    final r = await _get('/bus/forecast?sid=$sid');
    return (r['forecasts'] as List)
        .map((e) => BusForecast.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── поддержка проекта ──
  static Future<({double raised, double goal})> donateProgress() async {
    final r = await _get('/donate/progress');
    return (
      raised: (r['raised'] as num).toDouble(),
      goal: (r['goal'] as num).toDouble(),
    );
  }

  static Future<({String paymentId, String url})> donateCreate(
      int amount) async {
    final resp = await _post('/donate', {'amount': amount},
        timeout: const Duration(seconds: 25));
    if (resp.statusCode != 200) throw ApiException(_msg(resp));
    final m = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return (
      paymentId: m['payment_id'].toString(),
      url: m['confirmation_url'].toString()
    );
  }

  static Future<({String status, double raised, double goal})> donateCheck(
      String paymentId) async {
    final r = await _get('/donate/check?payment_id=${Uri.encodeQueryComponent(paymentId)}');
    return (
      status: r['status'].toString(),
      raised: (r['raised'] as num).toDouble(),
      goal: (r['goal'] as num).toDouble(),
    );
  }

  // ── admin ──
  static Future<bool> adminLogin(String password) async {
    final resp = await _post('/admin/login', {'password': password},
        timeout: const Duration(seconds: 20));
    if (resp.statusCode >= 500) throw ApiException('Ошибка ${resp.statusCode}');
    return resp.statusCode == 200;
  }

  static Future<Map<String, dynamic>> adminStatus(String password) async {
    final resp = await _c.get(Uri.parse('$_pref/admin/status'),
        headers: {'X-Admin-Password': password}).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) throw ApiException(_msg(resp));
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<void> adminRefresh(String password, String target) async {
    final resp = await _post('/admin/refresh', {'target': target},
        headers: {'X-Admin-Password': password},
        timeout: const Duration(seconds: 30));
    if (resp.statusCode != 200) throw ApiException(_msg(resp));
  }

  /// true — последний ответ взят из сохранённой копии (нет сети).
  static final offline = ValueNotifier<bool>(false);

  // Что сохраняем для офлайна: расписание и справочники. Живые данные
  // (автобусы, свободные кабинеты сейчас, админка) в старом виде бесполезны.
  static const _cacheable = [
    '/schedule', '/teacher', '/teachers', '/teacher_changes', '/groups',
    '/changes', '/rooms', '/room?',
  ];
  static bool _isCacheable(String path) =>
      !path.startsWith('/rooms/free') && _cacheable.any(path.startsWith);

  static Future<File> _cacheFile(String path) async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/api_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/${sha1.convert(utf8.encode(path))}.json');
  }

  /// GET с «подстраховкой»: второй адрес стартует через 2,5 с (или сразу, если первый упал),
  /// берём ответ того, кто успел раньше. 5xx считается неудачей адреса.
  static Future<http.Response> _getHedged(String path) {
    final first = _pref;
    final second = first == base ? baseAlt : base;
    final done = Completer<http.Response>();
    var failed = 0;
    var secondStarted = false;
    late final void Function(String) run;
    void fail(Object e, StackTrace st) {
      failed++;
      if (!secondStarted) {
        secondStarted = true;
        run(second);
      }
      if (failed >= 2 && !done.isCompleted) done.completeError(e, st);
    }

    run = (String b) {
      _c
          .get(Uri.parse('$b$path'))
          .timeout(const Duration(seconds: 12))
          .then((r) {
        if (r.statusCode >= 500) {
          fail(ApiException('HTTP ${r.statusCode}'), StackTrace.current);
        } else if (!done.isCompleted) {
          _pref = b;
          done.complete(r);
        }
      }).catchError((Object e, StackTrace st) => fail(e, st));
    };

    run(first);
    final hedge = Timer(const Duration(milliseconds: 2500), () {
      if (!secondStarted && !done.isCompleted) {
        secondStarted = true;
        run(second);
      }
    });
    return done.future.whenComplete(hedge.cancel);
  }

  /// POST с запасным адресом: сначала тот, что отвечал последним; если до него
  /// не достучались или он ответил 5xx — второй. Не параллельно, чтобы запрос
  /// (например, создание платежа) не выполнился дважды.
  static Future<http.Response> _post(String path, Map<String, dynamic> body,
      {Map<String, String> headers = const {},
      Duration timeout = const Duration(seconds: 25)}) async {
    final first = _pref;
    final second = first == base ? baseAlt : base;
    Object? err;
    http.Response? bad;
    for (final b in [first, second]) {
      try {
        final r = await _c
            .post(Uri.parse('$b$path'),
                headers: {'Content-Type': 'application/json', ...headers},
                body: jsonEncode(body))
            .timeout(timeout);
        if (r.statusCode >= 500) {
          bad = r;
          continue;
        }
        _pref = b;
        return r;
      } catch (e) {
        err = e;
      }
    }
    if (bad != null) return bad;
    throw err ?? ApiException('Нет связи с сервером');
  }

  static Future<Map<String, dynamic>> _get(String path) async {
    final cache = _isCacheable(path);
    http.Response resp;
    try {
      resp = await _getHedged(path);
    } catch (e) {
      // нет сети / таймаут — отдаём сохранённое, если есть
      if (cache) {
        try {
          final f = await _cacheFile(path);
          if (await f.exists()) {
            offline.value = true;
            return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
          }
        } catch (_) {}
      }
      rethrow;
    }
    if (resp.statusCode != 200) throw ApiException(_msg(resp));
    final body = utf8.decode(resp.bodyBytes);
    // плашку «нет сети» снимает только свежий ответ того же рода, что лежит
    // в кэше: живые автобусы не значат, что расписание на экране обновилось
    if (cache) {
      offline.value = false;
      _cacheFile(path).then((f) => f.writeAsString(body)).catchError((_) => File(''));
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  static String _msg(http.Response r) {
    try {
      final m = jsonDecode(utf8.decode(r.bodyBytes));
      return m['detail']?.toString() ?? 'Ошибка ${r.statusCode}';
    } catch (_) {
      return 'Ошибка ${r.statusCode}';
    }
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

// ── модели ──
class GroupRef {
  final String name;
  final String id;
  GroupRef(this.name, this.id);
  factory GroupRef.fromJson(Map<String, dynamic> j) =>
      GroupRef(j['name'] as String, j['id'] as String);
}

class Subgroup {
  final String subject;
  final String room;
  final String teacher;
  final String group; // для режима преподавателя
  Subgroup({this.subject = '', this.room = '', this.teacher = '', this.group = ''});
}

class Lesson {
  final String num;
  final String time;
  final List<Subgroup> subgroups;
  Lesson(this.num, this.time, this.subgroups);

  factory Lesson.fromGroup(Map<String, dynamic> j) {
    final subs = (j['subgroups'] as List?)
            ?.cast<Map<String, dynamic>>()
            .map((s) => Subgroup(
                  subject: (s['subject'] ?? '').toString(),
                  room: (s['room'] ?? '').toString(),
                  teacher: (s['teacher'] ?? '').toString(),
                ))
            .toList() ??
        [];
    return Lesson((j['num'] ?? '').toString(),
        (j['time'] ?? '').toString().trim(), subs);
  }

  factory Lesson.fromTeacher(Map<String, dynamic> j) {
    final sub = Subgroup(
      subject: (j['subject'] ?? '').toString(),
      room: (j['room'] ?? '').toString(),
      group: (j['group'] ?? '').toString(),
    );
    return Lesson((j['num'] ?? '').toString(),
        (j['time'] ?? '').toString().trim(), [sub]);
  }
}

class DaySchedule {
  final String title;
  final String? date; // ISO yyyy-MM-dd
  final List<Lesson> lessons;
  DaySchedule(this.title, this.date, this.lessons);
}

class ScheduleData {
  final String title; // имя группы или преподавателя
  final List<DaySchedule> days;
  ScheduleData(this.title, this.days);

  /// Номер подгруппы из названия предмета: «Информатика  (2 гр.)» -> 2.
  /// null — пара общая для всей группы.
  static int? subgroupOf(String subject) {
    final m = RegExp(r'\((\d)\s*гр\.?\)').firstMatch(subject);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Расписание глазами студента подгруппы [n]: пары чужой подгруппы убраны.
  /// [n] == 0 — без фильтра.
  ScheduleData forSubgroup(int n) {
    if (n <= 0) return this;
    return ScheduleData(title, [
      for (final d in days)
        DaySchedule(d.title, d.date, [
          for (final l in d.lessons)
            Lesson(l.num, l.time, [
              for (final s in l.subgroups)
                if ((subgroupOf(s.subject) ?? n) == n) s
            ])
        ])
    ]);
  }

  factory ScheduleData.fromJson(Map<String, dynamic> j,
      {bool teacherMode = false}) {
    final title =
        teacherMode ? (j['teacher'] ?? '').toString() : (j['group_name'] ?? '').toString();
    final days = (j['days'] as List? ?? []).map((d) {
      final dm = d as Map<String, dynamic>;
      final lessons = (dm['lessons'] as List? ?? []).map((l) {
        final lm = l as Map<String, dynamic>;
        return teacherMode ? Lesson.fromTeacher(lm) : Lesson.fromGroup(lm);
      }).toList();
      return DaySchedule(
          (dm['title'] ?? '').toString(), dm['date'] as String?, lessons);
    }).toList();
    return ScheduleData(title, days);
  }

  /// Кабинет: в одну пару там может сидеть несколько групп/подгрупп —
  /// сворачиваем их в одну пару с несколькими подгруппами.
  factory ScheduleData.fromRoom(Map<String, dynamic> j) {
    final days = (j['days'] as List? ?? []).map((d) {
      final dm = d as Map<String, dynamic>;
      final byNum = <String, Lesson>{};
      for (final l in (dm['lessons'] as List? ?? [])) {
        final lm = l as Map<String, dynamic>;
        final num = (lm['num'] ?? '').toString();
        final lesson = byNum.putIfAbsent(
            num, () => Lesson(num, (lm['time'] ?? '').toString().trim(), []));
        lesson.subgroups.add(Subgroup(
          subject: (lm['subject'] ?? '').toString(),
          teacher: (lm['teacher'] ?? '').toString(),
          group: (lm['group'] ?? '').toString(),
        ));
      }
      return DaySchedule((dm['title'] ?? '').toString(), dm['date'] as String?,
          byNum.values.toList());
    }).toList();
    return ScheduleData((j['room'] ?? '').toString(), days);
  }
}

class RoomRef {
  final String name;
  final String short;
  final String floor; // '1' | '2' | '3' | 's' (СОШ №10) | 'o' (другое)
  final String floorLabel;
  RoomRef(this.name, this.short, this.floor, this.floorLabel);
  factory RoomRef.fromJson(Map<String, dynamic> j) => RoomRef(
      (j['name'] ?? '').toString(),
      (j['short'] ?? j['name'] ?? '').toString(),
      (j['floor'] ?? 'o').toString(),
      (j['floor_label'] ?? '').toString());
}

class PairSlot {
  final String num;
  final String start;
  final String end;
  PairSlot(this.num, this.start, this.end);
}

class FreeRooms {
  final String? title; // день, null — занятий нет
  final String? num; // выбранная пара, null — пары кончились
  final String? state; // 'now' | 'next' | 'over' | null
  final List<PairSlot> pairs;
  final List<String> free;
  final int busy;
  FreeRooms(this.title, this.num, this.state, this.pairs, this.free, this.busy);

  factory FreeRooms.fromJson(Map<String, dynamic> j) => FreeRooms(
        j['title'] as String?,
        j['num']?.toString(),
        j['state'] as String?,
        (j['pairs'] as List? ?? [])
            .map((p) => PairSlot((p['num'] ?? '').toString(),
                (p['start'] ?? '').toString(), (p['end'] ?? '').toString()))
            .toList(),
        (j['free'] as List? ?? []).map((e) => e.toString()).toList(),
        (j['busy'] as List? ?? []).length,
      );
}

int _asInt(Object? v) => v is int ? v : (v is double ? v.toInt() : 0);
double _asDouble(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// Одна строка «было → стало» внутри изменения.
class ChangeField {
  final String label; // «Время», «Кабинет», «Преподаватель», «Предмет»
  final String before; // пусто, если поле просто перечислено (добавлена/удалена пара)
  final String after;
  const ChangeField(this.label, this.before, this.after);
}

enum ChangeKind { edited, added, removed, other }

class ScheduleChange {
  final String ts; // ISO время обнаружения
  final String text; // сырой текст (как в Telegram-боте)
  final String groupName;
  ScheduleChange(this.ts, this.text, this.groupName);
  factory ScheduleChange.fromJson(Map<String, dynamic> j) => ScheduleChange(
        (j['ts'] ?? '').toString(),
        (j['text'] ?? '').toString(),
        (j['group_name'] ?? '').toString(),
      );

  static const _months = {
    'января': 1, 'февраля': 2, 'марта': 3, 'апреля': 4, 'мая': 5, 'июня': 6,
    'июля': 7, 'августа': 8, 'сентября': 9, 'октября': 10, 'ноября': 11,
    'декабря': 12,
  };

  late final List<String> _lines =
      text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  String _line(String emoji) {
    for (final l in _lines) {
      if (l.startsWith(emoji)) return l.substring(emoji.length).trim();
    }
    return '';
  }

  late final ChangeKind kind = () {
    final h = _lines.isEmpty ? '' : _lines.first.toLowerCase();
    if (h.contains('добавлен')) return ChangeKind.added;
    if (h.contains('удален') || h.contains('удалён') || h.contains('снят') || h.contains('отмен')) {
      return ChangeKind.removed;
    }
    if (h.contains('изменени')) return ChangeKind.edited;
    return ChangeKind.other;
  }();

  /// «12 ноября 2026, четверг» — как пришло с сервера ('' если строки нет).
  late final String dayTitle = _line('📅');

  /// Учебный день, которого касается изменение.
  late final DateTime? day = () {
    final m = RegExp(r'(\d{1,2})\s+([а-яё]+)\s+(\d{4})')
        .firstMatch(dayTitle.toLowerCase());
    if (m == null) return null;
    final mon = _months[m.group(2)!];
    if (mon == null) return null;
    return DateTime(int.parse(m.group(3)!), mon, int.parse(m.group(1)!));
  }();

  /// «среда», если есть в заголовке дня.
  late final String weekday = dayTitle.contains(',')
      ? dayTitle.split(',').last.trim().toLowerCase()
      : '';

  /// Номер пары: «5».
  late final String pairNum =
      RegExp(r'\d+').firstMatch(_line('🔢'))?.group(0) ?? '';

  /// Время пары, если указано в строке номера («8 пара | 12:40 - 13:10 …»).
  late final String pairTime = () {
    final l = _line('🔢');
    final i = l.indexOf('|');
    return i < 0 ? '' : l.substring(i + 1).trim();
  }();

  /// Группа из строки номера («3 пара, 👥 ЗЧС-26») — так пишет лента преподавателя.
  late final String pairGroup =
      RegExp(r'👥\s*(.+)$').firstMatch(_line('🔢'))?.group(1)?.trim() ?? '';

  /// Те же правки одной пары, сведённые к итогу: [fields] — «было в начале →
  /// стало сейчас». Текст собирается в формате сервера, чтобы разбор был один.
  ScheduleChange withFields(List<ChangeField> fields) {
    const emoji = {'Предмет': '📚', 'Кабинет': '🚪', 'Преподаватель': '👤', 'Время': '⏰', 'Группа': '👥'};
    final b = StringBuffer()
      ..writeln(_lines.isEmpty ? '✏️ Изменение в паре' : _lines.first)
      ..writeln('📅 $dayTitle')
      ..writeln('🔢 $pairNum пара${pairGroup.isEmpty ? '' : ', 👥 $pairGroup'}');
    for (final f in fields) {
      if (f.label == 'Группа' && f.before.isEmpty) continue;
      b.writeln('${emoji[f.label] ?? '📚'} ${f.label}: ${f.before} → ${f.after}');
    }
    return ScheduleChange(ts, b.toString().trim(), groupName);
  }

  /// Поля изменения: «Время: было → стало» либо просто значения пары.
  late final List<ChangeField> fields = () {
    const plain = {'📚': 'Предмет', '🚪': 'Кабинет', '👤': 'Преподаватель', '⏰': 'Время', '👥': 'Группа'};
    final out = <ChangeField>[
      if (pairGroup.isNotEmpty) ChangeField('Группа', '', pairGroup),
    ];
    for (final l in _lines.skip(1)) {
      if (l.startsWith('📅') || l.startsWith('🔢')) continue;
      String? label;
      var rest = l;
      for (final e in plain.entries) {
        if (l.startsWith(e.key)) {
          label = e.value;
          rest = l.substring(e.key.length).trim();
          break;
        }
      }
      final colon = rest.indexOf(':');
      // «Время: 08:00 → 09:00» — подпись до первого двоеточия, если она словом
      if (colon > 0 && RegExp(r'^[А-Яа-яЁё ]+$').hasMatch(rest.substring(0, colon))) {
        label = rest.substring(0, colon).trim();
        rest = rest.substring(colon + 1).trim();
      }
      final arrow = rest.indexOf('→');
      if (arrow >= 0) {
        out.add(ChangeField(label ?? '', rest.substring(0, arrow).trim(),
            rest.substring(arrow + 1).trim()));
      } else {
        out.add(ChangeField(label ?? '', '', rest));
      }
    }
    return out;
  }();
}

class BusRoute {
  final int id;
  final String number;
  final String type;
  final String from;
  final String to;
  BusRoute(this.id, this.number, this.type, this.from, this.to);
  factory BusRoute.fromJson(Map<String, dynamic> j) => BusRoute(
        _asInt(j['id']),
        (j['num'] ?? '').toString(),
        (j['type'] ?? '').toString(),
        (j['from'] ?? '').toString(),
        (j['to'] ?? '').toString(),
      );
}

class BusStation {
  final int id;
  final String name;
  final String descr;
  final double lat;
  final double lng;
  BusStation(this.id, this.name, this.descr, this.lat, this.lng);
  factory BusStation.fromJson(Map<String, dynamic> j) => BusStation(
        _asInt(j['id']),
        (j['name'] ?? '').toString(),
        (j['descr'] ?? '').toString(),
        _asDouble(j['lat']),
        _asDouble(j['lng']),
      );
}

class BusVehicle {
  final String id;
  final double lat;
  final double lng;
  final double dir;
  final String routeNum;
  final String gosnum;
  BusVehicle(this.id, this.lat, this.lng, this.dir, this.routeNum, this.gosnum);
  factory BusVehicle.fromJson(Map<String, dynamic> j) => BusVehicle(
        (j['id'] ?? '').toString(),
        _asDouble(j['lat']),
        _asDouble(j['lng']),
        _asDouble(j['dir']),
        (j['route_num'] ?? '').toString(),
        (j['gosnum'] ?? '').toString(),
      );
}

class BusForecast {
  final int minutes;
  final bool arriving;
  final String routeNum;
  final String routeType;
  final String lastStation;
  BusForecast(this.minutes, this.arriving, this.routeNum, this.routeType,
      this.lastStation);
  factory BusForecast.fromJson(Map<String, dynamic> j) => BusForecast(
        _asInt(j['minutes']),
        j['arriving'] == true,
        (j['route_num'] ?? '').toString(),
        (j['route_type'] ?? '').toString(),
        (j['last_station'] ?? '').toString(),
      );
}

class GradeEntry {
  final String date;
  final String attendance;
  final String grade;
  final String homework;
  GradeEntry(this.date, this.attendance, this.grade, this.homework);
  factory GradeEntry.fromJson(Map<String, dynamic> j) => GradeEntry(
      (j['date'] ?? '').toString(),
      (j['attendance'] ?? '').toString(),
      (j['grade'] ?? '').toString(),
      (j['homework'] ?? '').toString());
  bool get present => attendance == 'Да';

  /// Пропуск — только явная отметка «не был». Пустая отметка значит, что
  /// посещаемость за это занятие вообще не проставили: это не прогул.
  bool get absent => attendance.isNotEmpty && !present;

  /// Есть ли отметка о посещаемости (иначе занятие не учитываем в статистике).
  bool get marked => attendance.isNotEmpty;

  /// Дата без дня недели: «12.09.2026, пятница» -> «12.09.2026».
  String get shortDate => date.split(',').first.trim();
}

class SubjectGrades {
  final String subject;
  final List<GradeEntry> entries;
  final double avg;
  final int gradeCount;
  SubjectGrades(this.subject, this.entries, this.avg, this.gradeCount);

  List<GradeEntry> get misses => entries.where((e) => e.absent).toList();
  int get missed => misses.length;
  int get attended => entries.where((e) => e.present).length;

  /// Занятий с проставленной посещаемостью.
  int get marked => attended + missed;
  double get attendanceRate => marked == 0 ? 1 : attended / marked;
}

class JournalData {
  final String ticketId;
  final DateTime? cachedAt;
  final List<SubjectGrades> subjects;
  JournalData(this.ticketId, this.cachedAt, this.subjects);

  factory JournalData.fromJson(Map<String, dynamic> j) {
    final grades = (j['grades'] as Map<String, dynamic>? ?? {});
    final subjects = grades.entries.map((e) {
      final v = e.value as Map<String, dynamic>;
      final entries = (v['entries'] as List? ?? [])
          .map((x) => GradeEntry.fromJson(x as Map<String, dynamic>))
          .toList();
      return SubjectGrades(
        e.key,
        entries,
        (v['avg'] is num) ? (v['avg'] as num).toDouble() : 0.0,
        (v['grade_count'] is num) ? (v['grade_count'] as num).toInt() : 0,
      );
    }).toList();
    subjects.sort((a, b) => a.subject.compareTo(b.subject));
    DateTime? cached;
    try {
      cached = DateTime.parse(j['cached_at'].toString());
    } catch (_) {}
    return JournalData((j['ticket_id'] ?? '').toString(), cached, subjects);
  }

  /// Оценки из ячейки журнала: «5», «5/4», «4 5» -> [5], [5, 4], [4, 5].
  /// Нечисловые отметки («зач», «н/а») оценками не считаются.
  static List<int> gradesIn(String cell) {
    final c = cell.trim();
    if (c.isEmpty || !RegExp(r'^[\d\s/,;.+\-]+$').hasMatch(c)) return const [];
    return RegExp(r'\d+')
        .allMatches(c)
        .map((m) => int.parse(m.group(0)!))
        .where((g) => g >= 1 && g <= 5)
        .toList();
  }

  double get overallAvg {
    final nums = <int>[];
    for (final s in subjects) {
      for (final e in s.entries) {
        nums.addAll(gradesIn(e.grade));
      }
    }
    if (nums.isEmpty) return 0;
    return (nums.reduce((a, b) => a + b) / nums.length);
  }

  int get totalGrades => subjects.fold(0, (a, s) => a + s.gradeCount);
  int get totalMissed => subjects.fold(0, (a, s) => a + s.missed);
  int get totalAttended => subjects.fold(0, (a, s) => a + s.attended);
  int get totalMarked => totalAttended + totalMissed;
  double get attendanceRate => totalMarked == 0 ? 1 : totalAttended / totalMarked;

  /// Предметы с пропусками — сначала те, где пропусков больше.
  List<SubjectGrades> get byMisses {
    final list = subjects.where((s) => s.missed > 0).toList();
    list.sort((a, b) => b.missed.compareTo(a.missed));
    return list;
  }
}
