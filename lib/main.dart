import 'package:flutter/material.dart';
import 'theme.dart';
import 'screens/schedule_screen.dart';
import 'screens/teachers_screen.dart';
import 'screens/journal_screen.dart';
import 'screens/settings_screen.dart';
import 'services/update_flow.dart';

void main() => runApp(const ScheduleApp());

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

class _RootScreenState extends State<RootScreen> {
  int _index = 0;
  final _pages = const [
    ScheduleScreen(),
    TeachersScreen(),
    JournalScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // автопроверка обновления при запуске (с небольшой задержкой,
    // чтобы не мешать первой отрисовке)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) UpdateFlow.checkOnLaunch(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
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
          onDestinationSelected: (i) => setState(() => _index = i),
          height: 64,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month, color: AppColors.primary),
                label: 'Расписание'),
            NavigationDestination(
                icon: Icon(Icons.person_search_outlined),
                selectedIcon: Icon(Icons.person_search, color: AppColors.primary),
                label: 'Преподаватели'),
            NavigationDestination(
                icon: Icon(Icons.assignment_outlined),
                selectedIcon: Icon(Icons.assignment, color: AppColors.primary),
                label: 'Журнал'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings, color: AppColors.primary),
                label: 'Ещё'),
          ],
        ),
      ),
    );
  }
}
