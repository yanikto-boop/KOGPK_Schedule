import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdate {
  final String version;
  final String notes;
  final String downloadUrl;
  AppUpdate({required this.version, required this.notes, required this.downloadUrl});
}

/// Проверка обновлений через GitHub Releases.
/// Репозиторий задаётся при релизе (см. README проекта).
class UpdateService {
  static const repo = 'yanikto-boop/KOGPK_Schedule';
  static const releasesPage =
      'https://github.com/yanikto-boop/KOGPK_Schedule/releases/latest';

  static Future<AppUpdate?> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version;
      final resp = await http.get(
        Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] ?? '').toString();
      final latest = _normalize(tag);
      if (latest.isEmpty || !_isNewer(latest, current)) return null;

      String url = releasesPage;
      final assets = data['assets'];
      if (assets is List) {
        for (final a in assets) {
          final name = (a['name'] ?? '').toString().toLowerCase();
          if (name.endsWith('.apk')) {
            url = (a['browser_download_url'] ?? url).toString();
            break;
          }
        }
      }
      return AppUpdate(
        version: latest,
        notes: (data['body'] ?? '').toString(),
        downloadUrl: url,
      );
    } catch (_) {
      return null;
    }
  }

  static String _normalize(String tag) =>
      tag.trim().replaceFirst(RegExp(r'^[vV]'), '');

  static bool _isNewer(String a, String b) {
    final pa = _parts(a), pb = _parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int> _parts(String v) =>
      v.split(RegExp(r'[.+\-]')).map((s) => int.tryParse(s) ?? 0).toList();
}
