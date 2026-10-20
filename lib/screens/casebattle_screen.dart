// Вкладка с case-battle.moe — только для сборки friend/casebattle, в релиз не идёт.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme.dart';

const _home = 'https://case-battle.moe/';

class CaseBattleScreen extends StatefulWidget {
  const CaseBattleScreen({super.key});
  @override
  State<CaseBattleScreen> createState() => _CaseBattleScreenState();
}

class _CaseBattleScreenState extends State<CaseBattleScreen> {
  late final WebViewController _web;
  int _progress = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.surface)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onPageStarted: (_) => setState(() => _failed = false),
        onWebResourceError: (e) {
          // ошибки картинок/скриптов не считаем — только саму страницу
          if (e.isForMainFrame ?? false) setState(() => _failed = true);
        },
        // вход через Steam и т.п. уводит на чужие схемы — отдаём системе
        onNavigationRequest: (req) {
          final uri = Uri.tryParse(req.url);
          if (uri != null && uri.scheme != 'http' && uri.scheme != 'https') {
            launchUrl(uri, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(_home));
  }

  Future<void> _back() async {
    if (await _web.canGoBack()) await _web.goBack();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Case Battle'),
        actions: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
          IconButton(
              icon: const Icon(Icons.home_outlined),
              onPressed: () => _web.loadRequest(Uri.parse(_home))),
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: () => _web.reload()),
        ],
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
      ),
      body: _failed
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Сайт не открылся',
                    style: TextStyle(color: AppColors.textDim)),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: () => _web.reload(),
                    child: const Text('Повторить')),
              ]),
            )
          : WebViewWidget(controller: _web),
    );
  }
}
