import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';
import 'screens/onboarding.dart';
import 'screens/home_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/teachers_screen.dart';
import 'screens/journal_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/casebattle_screen.dart';
import 'services/exact_alarm_prompt.dart';
import 'services/notif_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ScheduleApp());
  // уведомления об изменениях расписания (не блокируем запуск)
  NotifService.init().catchError((_) {});
}

class ScheduleApp extends StatelessWidget {
  const ScheduleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Расписание КОГПК',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const RootScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});
  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen>
    with WidgetsBindingObserver {
  int _index = 2; // стартуем на «Главной» (по центру)
  bool _showOnboarding = false;
  final _pages = const [
    ScheduleScreen(),
    TeachersScreen(),
    HomeScreen(),
    JournalScreen(),
    SettingsScreen(),
  ];
  // сайт грузим только при первом заходе на вкладку, а не при старте
  bool _cbOpened = false;

  Future<void> _maybeOnboard() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('onboarding_done') ?? false)) {
      if (mounted) setState(() => _showOnboarding = true);
    }
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (mounted) setState(() => _showOnboarding = false);
  }

  Timer? _alarmTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _maybeOnboard();
    // автопроверка обновления при запуске (с небольшой задержкой,
    // чтобы не мешать первой отрисовке)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // сборка для друга: автообновление на релиз выключено, иначе предложит
      // поставить обычное приложение без вкладки Case Battle
      // позже проверки обновлений, чтобы два диалога не всплыли разом
      _alarmTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) ExactAlarmPrompt.maybeAsk(context);
      });
    });
  }

  // виджет обычно добавляют через системное окно поверх приложения —
  // возвращаясь из него, и проверяем разрешение на точные будильники
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      ExactAlarmPrompt.maybeAsk(context);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarmTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      body: IndexedStack(index: _index, children: [
        ..._pages,
        _cbOpened ? const CaseBattleScreen() : const SizedBox.shrink(),
      ]),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.primary.withValues(alpha: 0.20),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, color: AppColors.textDim),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() {
            _index = i;
            if (i == _pages.length) _cbOpened = true;
          }),
          height: 64,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month, color: AppColors.primary),
                label: 'Расписание'),
            NavigationDestination(
                icon: Icon(Icons.person_search_outlined),
                selectedIcon: Icon(Icons.person_search, color: AppColors.primary),
                label: 'Преподы'),
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home, color: AppColors.primary),
                label: 'Главная'),
            NavigationDestination(
                icon: Icon(Icons.assignment_outlined),
                selectedIcon: Icon(Icons.assignment, color: AppColors.primary),
                label: 'Журнал'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings, color: AppColors.primary),
                label: 'Ещё'),
            NavigationDestination(
                icon: Icon(Icons.casino_outlined),
                selectedIcon: Icon(Icons.casino, color: AppColors.primary),
                label: 'Кейсы'),
          ],
        ),
      ),
    );

    if (!_showOnboarding) return scaffold;
    return Stack(
      children: [
        scaffold,
        OnboardingOverlay(
          onStep: (tab) => setState(() => _index = tab),
          onDone: _finishOnboarding,
        ),
      ],
    );
  }
}
