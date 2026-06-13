import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../api.dart';
import '../theme.dart';

class BusMapScreen extends StatefulWidget {
  final BusRoute? route; // null = вся сеть города
  const BusMapScreen({super.key, this.route});
  @override
  State<BusMapScreen> createState() => _BusMapScreenState();
}

class _BusMapScreenState extends State<BusMapScreen> {
  final _map = MapController();
  List<BusStation> _stations = [];
  List<LatLng> _line = [];
  List<BusVehicle> _vehicles = [];
  bool _loading = true;
  String? _error;
  Timer? _timer;

  static final _center = LatLng(62.25848, 74.500784); // Когалым

  @override
  void initState() {
    super.initState();
    _init();
    _timer = Timer.periodic(const Duration(seconds: 12), (_) => _loadVehicles());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final r = widget.route;
      final stations =
          r != null ? await Api.busRouteStations(r.id) : await Api.busStations();
      List<LatLng> line = [];
      if (r != null) {
        final pts = await Api.busRouteNodes(r.id);
        line = pts.map((p) => LatLng(p[0], p[1])).toList();
      }
      setState(() {
        _stations = stations;
        _line = line;
        _loading = false;
      });
      _loadVehicles();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadVehicles() async {
    try {
      final v = await Api.busVehicles(
          rids: widget.route != null ? '${widget.route!.id}' : null);
      if (mounted) setState(() => _vehicles = v);
    } catch (_) {}
  }

  void _openForecast(BusStation s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _StationSheet(station: s),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.route != null
            ? 'Маршрут ${widget.route!.number} — карта'
            : 'Карта транспорта'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: AppColors.textDim)))
              : _buildMap(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.surface,
        onPressed: () => _map.move(_center, 13),
        child: const Icon(Icons.my_location, color: AppColors.primary),
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _line.isNotEmpty ? _line.first : _center,
        initialZoom: 13,
        minZoom: 10,
        maxZoom: 18,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.kogpk.schedule_app',
        ),
        if (_line.isNotEmpty)
          PolylineLayer(polylines: [
            Polyline(
                points: _line, color: AppColors.primary, strokeWidth: 4),
          ]),
        MarkerLayer(
          markers: [
            for (final s in _stations)
              Marker(
                point: LatLng(s.lat, s.lng),
                width: 22,
                height: 22,
                child: GestureDetector(
                  onTap: () => _openForecast(s),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                    child: const Icon(Icons.circle,
                        size: 6, color: AppColors.primary),
                  ),
                ),
              ),
            for (final v in _vehicles)
              Marker(
                point: LatLng(v.lat, v.lng),
                width: 40,
                height: 40,
                child: Tooltip(
                  message: 'Маршрут ${v.routeNum}'
                      '${v.gosnum.isNotEmpty ? '\n${v.gosnum}' : ''}',
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.rotate(
                        angle: (v.dir - 90) * 3.14159 / 180,
                        child: const Icon(Icons.navigation,
                            color: AppColors.green, size: 30),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: AppColors.green,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(v.routeNum,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _StationSheet extends StatefulWidget {
  final BusStation station;
  const _StationSheet({required this.station});
  @override
  State<_StationSheet> createState() => _StationSheetState();
}

class _StationSheetState extends State<_StationSheet> {
  List<BusForecast>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await Api.busForecast(widget.station.id);
      if (mounted) setState(() => _items = f);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 12),
          Text(widget.station.name,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          if (widget.station.descr.isNotEmpty)
            Text(widget.station.descr,
                style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
          const SizedBox(height: 12),
          if (_error != null)
            Text('Не удалось загрузить прибытия',
                style: const TextStyle(color: AppColors.textDim))
          else if (_items == null)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(color: AppColors.primary),
            ))
          else if (_items!.isEmpty)
            const Text('Сейчас автобусов в пути нет',
                style: TextStyle(color: AppColors.textDim))
          else
            ..._items!.map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(f.routeNum,
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 12),
                      Text(f.arriving ? 'подъезжает' : '${f.minutes} мин',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: f.arriving
                                  ? AppColors.green
                                  : AppColors.text)),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}
