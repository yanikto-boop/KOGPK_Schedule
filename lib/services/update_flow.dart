import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import 'update_service.dart';

/// Общий поток обновления приложения: диалог + загрузка + установка.
class UpdateFlow {
  /// Проверка при запуске: тихо проверяет и, если есть новее — предлагает.
  static Future<void> checkOnLaunch(BuildContext context) async {
    final upd = await UpdateService.check();
    if (upd == null || !context.mounted) return;
    promptUpdate(context, upd);
  }

  static Future<void> promptUpdate(BuildContext context, AppUpdate upd) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Доступна версия ${upd.version}'),
        content: SingleChildScrollView(
          child: Text(upd.notes.isEmpty ? 'Обновить приложение?' : upd.notes),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Позже')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Обновить')),
        ],
      ),
    );
    if (go == true && context.mounted) downloadAndInstall(context, upd);
  }

  static Future<void> downloadAndInstall(
      BuildContext context, AppUpdate upd) async {
    final progress = ValueNotifier<double>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Загрузка обновления'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                  value: v > 0 ? v : null, color: AppColors.primary),
              const SizedBox(height: 12),
              Text(v > 0 ? '${(v * 100).toStringAsFixed(0)}%' : 'Подключение…',
                  style: const TextStyle(color: AppColors.textDim)),
            ],
          ),
        ),
      ),
    );
    final path = await UpdateService.downloadApk(
        upd.downloadUrl, (p) => progress.value = p);
    if (!context.mounted) return;
    Navigator.pop(context); // закрыть прогресс
    if (path == null) {
      launchUrl(Uri.parse(UpdateService.releasesPage),
          mode: LaunchMode.externalApplication);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Не удалось скачать — открыл страницу релиза')));
      return;
    }
    await UpdateService.install(path);
  }
}
