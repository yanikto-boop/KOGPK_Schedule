import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../theme.dart';
import '../services/update_service.dart';
import '../services/update_flow.dart';
import '../services/native.dart';
import 'admin_screen.dart';
import 'transport_screen.dart';
import 'support_screen.dart';
import 'changes_screen.dart';
import 'rooms_screen.dart';
import '../services/notif_service.dart';
import '../services/profile.dart';
import '../games/games_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  int _tapCount = 0;
  bool _notif = true;
  String? _teacher; // режим преподавателя
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = '${i.version} (${i.buildNumber})');
    });
    NotifService.enabled().then((v) {
      if (mounted) setState(() => _notif = v);
    });
    Profile.changed.addListener(_loadRole);
    _loadRole();
  }

  @override
  void dispose() {
    Profile.changed.removeListener(_loadRole);
    super.dispose();
  }

  Future<void> _loadRole() async {
    final t = await Profile.teacher();
    if (mounted) setState(() => _teacher = t);
  }

  Future<void> _chooseRole() async {
    final teacher = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('Режим',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('Я студент'),
              subtitle: const Text('Расписание группы'),
              trailing: _teacher == null
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Я преподаватель'),
              subtitle: const Text('Свои пары и время до них везде в приложении'),
              trailing: _teacher != null
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (teacher == null || !mounted) return;
    if (!teacher) {
      if (_teacher != null) await Profile.setTeacher(null);
      return;
    }
    final name = await Profile.pickTeacher(context);
    if (name != null) await Profile.setTeacher(name);
  }

  void _onVersionTap() {
    final now = DateTime.now();
    if (now.difference(_lastTap) > const Duration(seconds: 2)) {
      _tapCount = 0;
    }
    _lastTap = now;
    _tapCount++;
    if (_tapCount >= 10) {
      _tapCount = 0;
      _askAdminPassword();
    }
  }

  Future<void> _askAdminPassword() async {
    final ctrl = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Доступ администратора'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Пароль'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Войти')),
        ],
      ),
    );
    if (pw == null || pw.isEmpty) return;
    final ok = await Api.adminLogin(pw);
    if (!mounted) return;
    if (ok) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => AdminScreen(password: pw)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Неверный пароль')));
    }
  }

  Future<void> _checkUpdate() async {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Проверяю обновления…')));
    final upd = await UpdateService.check();
    if (!mounted) return;
    if (upd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('У вас последняя версия')));
      return;
    }
    if (mounted) UpdateFlow.promptUpdate(context, upd);
  }

  Future<void> _addWidget() async {
    if (!await Native.canPinWidget()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Лаунчер не поддерживает добавление виджета. Добавьте вручную: долгий тап по рабочему столу → Виджеты')));
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text('Какой виджет добавить?',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.crop_square, color: AppColors.primary),
                title: const Text('Компактный 2×2'),
                subtitle: const Text('Пары на ближайший день'),
                onTap: () {
                  Navigator.pop(context);
                  Native.pinWidget('small');
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.crop_16_9, color: AppColors.primary),
                title: const Text('Широкий 4×2'),
                subtitle: const Text('Расширенный список пар'),
                onTap: () {
                  Navigator.pop(context);
                  Native.pinWidget('wide');
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined,
                    color: AppColors.primary),
                title: const Text('Таймер 2×1'),
                subtitle: const Text('Сколько до конца половины или перерыва'),
                onTap: () {
                  Navigator.pop(context);
                  Native.pinWidget('countdown_small');
                },
              ),
              ListTile(
                leading: const Icon(Icons.av_timer, color: AppColors.primary),
                title: const Text('Таймер 2×2'),
                subtitle: const Text('Отсчёт и текущая пара с кабинетом'),
                onTap: () {
                  Navigator.pop(context);
                  Native.pinWidget('countdown_medium');
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.directions_bus, color: AppColors.primary),
                title: const Text('Автобус 3×2'),
                subtitle: const Text('Прибытие на избранную остановку'),
                onTap: () {
                  Navigator.pop(context);
                  Native.pinWidget('bus');
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ещё')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _tile(_teacher != null ? Icons.person : Icons.school, 'Режим',
              subtitle: _teacher != null
                  ? 'Преподаватель · ${Profile.short(_teacher!)}'
                  : 'Студент · нажмите, если вы преподаватель',
              onTap: _chooseRole),
          _tile(Icons.sync_alt, 'Изменения расписания',
              subtitle: _teacher != null
                  ? 'Что поменялось в ваших парах'
                  : 'Что поменялось в расписании твоей группы',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ChangesScreen()))),
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
              secondary:
                  const Icon(Icons.notifications_active, color: AppColors.primary),
              title: const Text('Уведомления об изменениях',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Пуш, когда в расписании что-то поменялось',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              value: _notif,
              activeColor: AppColors.primary,
              onChanged: (v) async {
                await NotifService.setEnabled(v);
                setState(() => _notif = v);
              },
            ),
            ),
          ),
          _tile(Icons.videogame_asset_outlined, 'Игры',
              subtitle: 'Block Boom, дурак онлайн, таблица лидеров',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const GamesScreen()))),
          _tile(Icons.meeting_room, 'Кабинеты',
              subtitle: 'Расписание кабинетов и свободные на этой паре',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RoomsScreen()))),
          _tile(Icons.favorite, 'Поддержать проект',
              subtitle: 'Сбор на публикацию в App Store',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SupportScreen()))),
          _tile(Icons.directions_bus, 'Транспорт Когалыма',
              subtitle: 'Маршрутки: остановки и прибытие в реальном времени',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TransportScreen()))),
          _tile(Icons.dashboard_customize, 'Добавить виджет на рабочий стол',
              subtitle: 'Пары на ближайший день — 2×2 или 4×2',
              onTap: _addWidget),
          _tile(Icons.system_update, 'Проверить обновление',
              subtitle: 'Свежая версия приложения', onTap: _checkUpdate),
          _tile(Icons.smart_toy_outlined, 'Telegram-бот расписания',
              subtitle: '@Raspisanina_bot — уведомления об изменениях',
              onTap: () => launchUrl(Uri.parse('https://t.me/Raspisanina_bot'),
                  mode: LaunchMode.externalApplication)),
          _tile(Icons.campaign_outlined, 'Канал с расписанием',
              subtitle: '@Kpk_Raspisanina',
              onTap: () => launchUrl(Uri.parse('https://t.me/Kpk_Raspisanina'),
                  mode: LaunchMode.externalApplication)),
          const SizedBox(height: 24),
          Center(
            child: GestureDetector(
              onTap: _onVersionTap,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    const Icon(Icons.school, color: AppColors.textDim, size: 32),
                    const SizedBox(height: 8),
                    const Text('Расписание КОГПК',
                        style: TextStyle(color: AppColors.textDim)),
                    const SizedBox(height: 4),
                    Text('Версия $_version',
                        style: const TextStyle(
                            color: AppColors.textDim, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String title,
      {String? subtitle, VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      // своя Material — иначе фон контейнера перекрывает эффект нажатия
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          leading: Icon(icon, color: AppColors.primary),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: subtitle != null
              ? Text(subtitle,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12))
              : null,
          trailing: const Icon(Icons.chevron_right, color: AppColors.textDim),
          onTap: onTap,
        ),
      ),
    );
  }
}
