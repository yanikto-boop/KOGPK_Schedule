import 'dart:convert';
import 'package:http/http.dart' as http;

/// Клиент к Schedule API (бэкенд на германском сервере).
class Api {
  static const base = 'https://vpn-ornux.space/sapi';

  static Future<List<GroupRef>> groups() async {
    final r = await _get('/groups');
    final list = (r['groups'] as List).cast<Map<String, dynamic>>();
    return list.map(GroupRef.fromJson).toList();
  }

  static Future<ScheduleData> schedule(String group) async {
    final r = await _get('/schedule?group=${Uri.encodeQueryComponent(group)}');
    return ScheduleData.fromJson(r);
  }

  static Future<List<String>> teachers() async {
    final r = await _get('/teachers');
    return (r['teachers'] as List).cast<String>();
  }

  static Future<ScheduleData> teacher(String name) async {
    final r = await _get('/teacher?name=${Uri.encodeQueryComponent(name)}');
    return ScheduleData.fromJson(r, teacherMode: true);
  }

  static Future<JournalData> journal(String ticketId) async {
    final resp = await http
        .post(Uri.parse('$base/journal'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'ticket_id': ticketId}))
        .timeout(const Duration(seconds: 55));
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
    final resp = await http
        .post(Uri.parse('$base/donate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'amount': amount}))
        .timeout(const Duration(seconds: 25));
    if (resp.statusCode != 200) throw ApiException(_msg(resp));
    final m = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return (
      paymentId: m['payment_id'].toString(),
      url: m['confirmation_url'].toString()
    );
  }

  static Future<({String status, double raised, double goal})> donateCheck(
      String paymentId) async {
    final r = await _get('/donate/check?payment_id=$paymentId');
    return (
      status: r['status'].toString(),
      raised: (r['raised'] as num).toDouble(),
      goal: (r['goal'] as num).toDouble(),
    );
  }

  // ── admin ──
  static Future<bool> adminLogin(String password) async {
    final resp = await http.post(Uri.parse('$base/admin/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'password': password}));
    return resp.statusCode == 200;
  }

  static Future<Map<String, dynamic>> adminStatus(String password) async {
    final resp = await http.get(Uri.parse('$base/admin/status'),
        headers: {'X-Admin-Password': password});
    if (resp.statusCode != 200) throw ApiException(_msg(resp));
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<void> adminRefresh(String password, String target) async {
    final resp = await http.post(Uri.parse('$base/admin/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Password': password
        },
        body: jsonEncode({'target': target}));
    if (resp.statusCode != 200) throw ApiException(_msg(resp));
  }

  static Future<Map<String, dynamic>> _get(String path) async {
    final resp = await http
        .get(Uri.parse('$base$path'))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) throw ApiException(_msg(resp));
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
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
}

int _asInt(Object? v) => v is int ? v : (v is double ? v.toInt() : 0);
double _asDouble(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

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
}

class SubjectGrades {
  final String subject;
  final List<GradeEntry> entries;
  final double avg;
  final int gradeCount;
  SubjectGrades(this.subject, this.entries, this.avg, this.gradeCount);
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

  double get overallAvg {
    final nums = <int>[];
    for (final s in subjects) {
      for (final e in s.entries) {
        final g = int.tryParse(e.grade);
        if (g != null) nums.add(g);
      }
    }
    if (nums.isEmpty) return 0;
    return (nums.reduce((a, b) => a + b) / nums.length);
  }

  int get totalGrades => subjects.fold(0, (a, s) => a + s.gradeCount);
  int get totalMissed => subjects.fold(
      0, (a, s) => a + s.entries.where((e) => !e.present).length);
}
