import 'dart:async';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets.dart';
import 'map_screen.dart';

class TransportScreen extends StatelessWidget {
  const TransportScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Транспорт'),
          actions: [
            IconButton(
              icon: const Icon(Icons.map_outlined),
              tooltip: 'Карта',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BusMapScreen())),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textDim,
            tabs: [Tab(text: 'Остановки'), Tab(text: 'Маршруты')],
          ),
        ),
        body: const TabBarView(
          children: [_StationsTab(), _RoutesTab()],
        ),
      ),
    );
  }
}

// ─── вкладка остановок (+ избранное, поиск) ──────────────────────────────────
class _StationsTab extends StatefulWidget {
  const _StationsTab();
  @override
  State<_StationsTab> createState() => _StationsTabState();
}

class _StationsTabState extends State<_StationsTab>
    with AutomaticKeepAliveClientMixin {
  List<BusStation> _all = [];
  List<int> _favIds = [];
  String _q = '';
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final st = await Api.busStations();
      final prefs = await SharedPreferences.getInstance();
      final fav = prefs.getStringList('fav_stops') ?? [];
      setState(() {
        _all = st;
        _favIds = fav.map(int.parse).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openStation(BusStation s) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => StationForecastScreen(station: s)));
    // обновить избранное по возвращении
    final prefs = await SharedPreferences.getInstance();
    final fav = prefs.getStringList('fav_stops') ?? [];
    if (mounted) setState(() => _favIds = fav.map(int.parse).toList());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const StatusView(message: 'Загрузка остановок…');
    if (_error != null) {
      return StatusView(message: _error!, isError: true, onRetry: _load);
    }
    final favs = _all.where((s) => _favIds.contains(s.id)).toList();
    final filtered = _q.isEmpty
        ? _all
        : _all
            .where((s) => s.name.toLowerCase().contains(_q.toLowerCase()))
            .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: 'Поиск остановки…',
              prefixIcon: const Icon(Icons.search),
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
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            children: [
              if (favs.isNotEmpty && _q.isEmpty) ...[
                const _SectionLabel('⭐ Избранные'),
                ...favs.map((s) => _stationTile(s, fav: true)),
                const _SectionLabel('Все остановки'),
              ],
              ...filtered.map((s) => _stationTile(s, fav: _favIds.contains(s.id))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stationTile(BusStation s, {bool fav = false}) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: ListTile(
          leading: Icon(fav ? Icons.star : Icons.directions_bus_outlined,
              color: fav ? AppColors.yellow : AppColors.primary),
          title: Text(s.name, style: const TextStyle(fontSize: 14.5)),
          subtitle: s.descr.isNotEmpty
              ? Text(s.descr,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12))
              : null,
          trailing: const Icon(Icons.chevron_right, color: AppColors.textDim),
          onTap: () => _openStation(s),
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
        child: Text(text,
            style: const TextStyle(
                color: AppColors.textDim,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
      );
}

// ─── вкладка маршрутов ───────────────────────────────────────────────────────
class _RoutesTab extends StatefulWidget {
  const _RoutesTab();
  @override
  State<_RoutesTab> createState() => _RoutesTabState();
}

class _RoutesTabState extends State<_RoutesTab>
    with AutomaticKeepAliveClientMixin {
  List<BusRoute> _routes = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.busRoutes();
      setState(() {
        _routes = r;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const StatusView(message: 'Загрузка маршрутов…');
    if (_error != null) {
      return StatusView(message: _error!, isError: true, onRetry: _load);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _routes.length,
      separatorBuilder: (_, i) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final r = _routes[i];
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: ListTile(
            leading: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(r.number,
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
            ),
            title: Text('${r.from} → ${r.to}',
                style: const TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textDim),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => RouteStationsScreen(route: r))),
          ),
        );
      },
    );
  }
}

// ─── остановки маршрута ──────────────────────────────────────────────────────
class RouteStationsScreen extends StatefulWidget {
  final BusRoute route;
  const RouteStationsScreen({super.key, required this.route});
  @override
  State<RouteStationsScreen> createState() => _RouteStationsScreenState();
}

class _RouteStationsScreenState extends State<RouteStationsScreen> {
  List<BusStation> _stations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await Api.busRouteStations(widget.route.id);
      setState(() {
        _stations = s;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Маршрут ${widget.route.number}',
            style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'На карте',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => BusMapScreen(route: widget.route))),
          ),
        ],
      ),
      body: _loading
          ? const StatusView(message: 'Загрузка…')
          : _error != null
              ? StatusView(message: _error!, isError: true, onRetry: _load)
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _stations.length,
                  itemBuilder: (_, i) {
                    final s = _stations[i];
                    final last = i == _stations.length - 1;
                    return InkWell(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  StationForecastScreen(station: s))),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            children: [
                              const Icon(Icons.circle,
                                  size: 12, color: AppColors.primary),
                              if (!last)
                                Container(
                                    width: 2,
                                    height: 34,
                                    color: AppColors.border),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14.5)),
                                  if (s.descr.isNotEmpty)
                                    Text(s.descr,
                                        style: const TextStyle(
                                            color: AppColors.textDim,
                                            fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              color: AppColors.textDim, size: 18),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

// ─── живые прибытия на остановку ─────────────────────────────────────────────
class StationForecastScreen extends StatefulWidget {
  final BusStation station;
  const StationForecastScreen({super.key, required this.station});
  @override
  State<StationForecastScreen> createState() => _StationForecastScreenState();
}

class _StationForecastScreenState extends State<StationForecastScreen> {
  List<BusForecast> _items = [];
  bool _loading = true;
  String? _error;
  bool _fav = false;
  Timer? _timer;
  DateTime? _updated;

  @override
  void initState() {
    super.initState();
    _checkFav();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkFav() async {
    final prefs = await SharedPreferences.getInstance();
    final fav = prefs.getStringList('fav_stops') ?? [];
    if (mounted) {
      setState(() => _fav = fav.contains(widget.station.id.toString()));
    }
  }

  Future<void> _toggleFav() async {
    final prefs = await SharedPreferences.getInstance();
    final fav = prefs.getStringList('fav_stops') ?? [];
    final id = widget.station.id.toString();
    if (fav.contains(id)) {
      fav.remove(id);
    } else {
      fav.add(id);
      // только что добавленная остановка становится целью виджета
      await HomeWidget.saveWidgetData<int>('bus_widget_sid', widget.station.id);
      await HomeWidget.saveWidgetData<String>(
          'bus_widget_name', widget.station.name);
      await HomeWidget.updateWidget(
          androidName: 'BusWidget', name: 'BusWidget');
    }
    await prefs.setStringList('fav_stops', fav);
    if (mounted) {
      setState(() => _fav = fav.contains(id));
      if (fav.contains(id)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Остановка в избранном и на виджете'),
            duration: Duration(seconds: 2)));
      }
    }
  }

  Future<void> _load() async {
    try {
      final f = await Api.busForecast(widget.station.id);
      if (!mounted) return;
      setState(() {
        _items = f;
        _loading = false;
        _error = null;
        _updated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.station.name, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            onPressed: _toggleFav,
            icon: Icon(_fav ? Icons.star : Icons.star_border,
                color: _fav ? AppColors.yellow : null),
            tooltip: _fav ? 'Убрать из избранного' : 'В избранное',
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: _load,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 120),
        StatusView(message: _error!, isError: true, onRetry: _load),
      ]);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (widget.station.descr.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(widget.station.descr,
                style: const TextStyle(color: AppColors.textDim)),
          ),
        if (_items.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              'Сейчас нет автобусов в пути к этой остановке.\n'
              'Возможно, рейсы закончились или ещё не вышли.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim),
            ),
          )
        else
          ..._items.map(_forecastCard),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _updated != null
                ? 'Обновляется автоматически • ${_hm(_updated!)}'
                : '',
            style: const TextStyle(color: AppColors.textDim, fontSize: 11),
          ),
        ),
      ],
    );
  }

  String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _forecastCard(BusForecast f) {
    final mins = f.arriving ? 'подъезжает' : '${f.minutes} мин';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: f.arriving ? AppColors.green : AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(f.routeNum,
                style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mins,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: f.arriving ? AppColors.green : AppColors.text)),
                if (f.lastStation.isNotEmpty)
                  Text('прошёл: ${f.lastStation}',
                      style: const TextStyle(
                          color: AppColors.textDim, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.directions_bus, color: AppColors.textDim),
        ],
      ),
    );
  }
}
