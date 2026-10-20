import 'dart:io';

import 'package:flutter/material.dart';
import '../theme.dart';
import 'update_service.dart';

enum UpdatePhase { idle, downloading, ready, failed }

/// Строгое обновление: при каждом открытии приложения проверяем релиз,
/// новую версию сразу качаем (полоса снизу) и открываем установку.
/// «Позже» нет — пока не обновишься, полоса с кнопкой «Установить» висит.
class UpdateController extends ChangeNotifier {
  UpdateController._();
  static final instance = UpdateController._();

  UpdatePhase phase = UpdatePhase.idle;
  double progress = 0;
  AppUpdate? update;
  String? _path;
  bool _busy = false;
  DateTime? _lastCheck, _lastInstall;

  /// [manual] — из настроек: без паузы между проверками.
  /// Возвращает найденное обновление (или null — последняя версия).
  Future<AppUpdate?> check({bool manual = false}) async {
    if (!Platform.isAndroid || _busy) return update;
    if (phase == UpdatePhase.ready) {
      // установщик закрыли — открываем снова, но не по кругу сразу же
      final last = _lastInstall;
      if (manual || last == null || DateTime.now().difference(last).inSeconds > 60) install();
      return update;
    }
    final last = _lastCheck;
    if (!manual && phase == UpdatePhase.idle && last != null &&
        DateTime.now().difference(last).inMinutes < 3) {
      return null;
    }
    _busy = true;
    _lastCheck = DateTime.now();
    try {
      final u = await UpdateService.check();
      if (u == null) return null;
      update = u;
      await _download(u);
      return u;
    } finally {
      _busy = false;
    }
  }

  Future<void> _download(AppUpdate u) async {
    phase = UpdatePhase.downloading;
    progress = 0;
    notifyListeners();
    var shown = 0;
    final path = await UpdateService.downloadApk(u.downloadUrl, u.version, (p) {
      progress = p;
      final pct = (p * 100).floor();
      if (pct != shown) {
        shown = pct;
        notifyListeners();
      }
    });
    if (path == null) {
      phase = UpdatePhase.failed;
      notifyListeners();
      return;
    }
    _path = path;
    phase = UpdatePhase.ready;
    notifyListeners();
    install();
  }

  void install() {
    final p = _path;
    if (p == null) return;
    _lastInstall = DateTime.now();
    UpdateService.install(p);
  }

  void retry() {
    final u = update;
    if (u == null || _busy) return;
    _busy = true;
    _download(u).whenComplete(() => _busy = false);
  }
}

/// Полоса обновления над нижней панелью.
class UpdateBar extends StatelessWidget {
  const UpdateBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = UpdateController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        if (c.phase == UpdatePhase.idle) return const SizedBox.shrink();
        final v = c.update?.version ?? '';
        final (String text, String? action, VoidCallback? onTap) = switch (c.phase) {
          UpdatePhase.downloading =>
            ('Скачиваю обновление $v · ${(c.progress * 100).floor()}%', null, null),
          UpdatePhase.ready => ('Обновление $v скачано', 'Установить', c.install),
          _ => ('Не удалось скачать обновление $v', 'Повторить', c.retry),
        };
        return Material(
          color: AppColors.surface,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(
              value: c.phase == UpdatePhase.downloading
                  ? (c.progress > 0 ? c.progress : null)
                  : 1,
              minHeight: 3,
              color: c.phase == UpdatePhase.failed ? Colors.redAccent : AppColors.primary,
              backgroundColor: Colors.transparent,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: Row(children: [
                const Icon(Icons.system_update, size: 18, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
                if (action != null)
                  TextButton(onPressed: onTap, child: Text(action))
                else
                  const SizedBox(height: 40),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
