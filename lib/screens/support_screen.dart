import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../theme.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen>
    with WidgetsBindingObserver {
  double _raised = 0;
  double _goal = 9000;
  bool _loading = true;
  final _ctrl = TextEditingController(text: '100');
  String? _pendingPayment;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProgress();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // вернулись из браузера после оплаты — проверяем статус
    if (state == AppLifecycleState.resumed && _pendingPayment != null) {
      _checkPayment();
    }
  }

  Future<void> _loadProgress() async {
    try {
      final p = await Api.donateProgress();
      if (mounted) {
        setState(() {
          _raised = p.raised;
          _goal = p.goal;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pay() async {
    final amount = int.tryParse(_ctrl.text.trim()) ?? 0;
    if (amount < 80) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Минимальная сумма — 80 ₽')));
      return;
    }
    setState(() => _paying = true);
    try {
      final p = await Api.donateCreate(amount);
      _pendingPayment = p.paymentId;
      await launchUrl(Uri.parse(p.url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _checkPayment() async {
    final pid = _pendingPayment;
    if (pid == null) return;
    // несколько попыток — оплата подтверждается не мгновенно
    for (var i = 0; i < 5; i++) {
      try {
        final r = await Api.donateCheck(pid);
        if (mounted) {
          setState(() {
            _raised = r.raised;
            _goal = r.goal;
          });
        }
        if (r.status == 'succeeded') {
          _pendingPayment = null;
          if (mounted) {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppColors.surface,
                title: const Text('Спасибо! 💙'),
                content: const Text('Платёж получен, прогресс обновлён.'),
                actions: [
                  FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Класс'))
                ],
              ),
            );
          }
          return;
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = _goal > 0 ? (_raised / _goal).clamp(0.0, 1.0) : 0.0;
    return Scaffold(
      appBar: AppBar(title: const Text('Поддержать проект')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      AppColors.primaryDim.withValues(alpha: 0.55),
                      AppColors.surface
                    ]),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Сбор на публикацию в App Store',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      const Text(
                          'Чтобы приложение появилось у студентов на iPhone, '
                          'нужен платный аккаунт разработчика Apple. Поможешь — будет круто 💙',
                          style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                      const SizedBox(height: 18),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 14,
                          backgroundColor: AppColors.surface2,
                          color: AppColors.green,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Собрано ${_raised.toStringAsFixed(0)} ₽',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.green)),
                          Text('Цель ${_goal.toStringAsFixed(0)} ₽',
                              style: const TextStyle(color: AppColors.textDim)),
                        ],
                      ),
                      Text('${(pct * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                              color: AppColors.textDim, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Сумма поддержки',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [100, 200, 300, 500]
                      .map((v) => ActionChip(
                            label: Text('$v ₽'),
                            backgroundColor: AppColors.surface,
                            side: const BorderSide(color: AppColors.border),
                            onPressed: () =>
                                setState(() => _ctrl.text = v.toString()),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _ctrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.currency_ruble),
                    hintText: 'Своя сумма (от 80 ₽)',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border)),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _paying ? null : _pay,
                    icon: const Icon(Icons.favorite),
                    label: Text(_paying ? 'Создаём платёж…' : 'Поддержать'),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                    'Оплата через ЮKassa (карта, СБП). После оплаты вернись в '
                    'приложение — прогресс обновится сам.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ],
            ),
    );
  }
}
