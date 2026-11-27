import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/location_service.dart';
import '../../state/auth_store.dart';
import '../chat/chat_room_screen.dart';
import '../common.dart';
import '../orders/provider_screen.dart';
import '../widgets/theme_map_tile_layer.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  final List<Map<String, dynamic>> _places = [];
  static const double _minDataZoom = 14.5;
  LatLng _center = const LatLng(-6.9147, 107.6098);
  LatLng? _userLocation;
  bool _loading = true;
  bool _hasLocation = false;
  bool _tooFar = false;
  bool? _lastConsent;
  double _zoom = 16;
  double _radius = 1000;
  Timer? _poll;
  Timer? _moveDebounce;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadPlaces(showLoading: false),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _moveDebounce?.cancel();
    super.dispose();
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _center = camera.center;
    _zoom = camera.zoom;
    _moveDebounce?.cancel();
    _moveDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      if (_zoom < _minDataZoom) {
        setState(() {
          _tooFar = true;
          _loading = false;
          _places.clear();
        });
        return;
      }
      _tooFar = false;
      _radius = _radiusForCamera(camera);
      _loadPlaces(showLoading: false);
    });
  }

  double _radiusForCamera(MapCamera camera) {
    final distance = const Distance().as(
      LengthUnit.Meter,
      camera.center,
      camera.visibleBounds.northEast,
    );
    return distance.clamp(150, 5000).toDouble();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final position = await LocationService.current();
    if (position != null) {
      if (mounted) {
        setState(() {
          _center = position;
          _userLocation = position;
          _hasLocation = true;
          _zoom = 16.5;
          _radius = 1000;
        });
      }
      try {
        _mapController.move(position, 16.5);
      } catch (_) {
        // The map may not be attached on the first frame.
      }
    }
    await _loadPlaces(showLoading: false);
  }

  Future<void> _loadPlaces({bool showLoading = true}) async {
    if (_zoom < _minDataZoom) {
      if (mounted) {
        setState(() {
          _tooFar = true;
          _loading = false;
          _places.clear();
        });
      }
      return;
    }
    if (showLoading) setState(() => _loading = true);
    final api = context.read<AuthStore>().api;
    try {
      final data = await api.get(
        'nearby',
        query: {
          'lat': '${_center.latitude}',
          'lng': '${_center.longitude}',
          'radius': '${_radius.round()}',
          'limit': '100',
        },
      );
      if (!mounted) return;
      setState(() {
        _places
          ..clear()
          ..addAll(data is Map && data['data'] is List
              ? (data['data'] as List)
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
              : const <Map<String, dynamic>>[]);
      });
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _distanceTo(Map<String, dynamic> place) {
    final from = _userLocation ?? _center;
    final point = LatLng(
      (place['lat'] as num).toDouble(),
      (place['lng'] as num).toDouble(),
    );
    return const Distance().as(LengthUnit.Meter, from, point).round();
  }

  bool _isDriverType(String? type) {
    return type == 'driver_mobil' ||
        type == 'driver_motor' ||
        type == 'kurir_makanan';
  }

  Widget _placeMarkerIcon(Map<String, dynamic> place) {
    final type = place['type_code'] as String?;
    final color =
        place['is_active'] == false ? Colors.blueGrey : typeColor(type);
    if (_isDriverType(type)) {
      // Drivers use a bare vehicle icon instead of a circular badge.
      return Icon(
        typeIcon(type),
        size: 38,
        color: color,
        shadows: const [
          Shadow(color: Colors.white, blurRadius: 4),
          Shadow(color: Colors.black45, blurRadius: 6),
        ],
      );
    }
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color:
              place['is_own'] == true ? const Color(0xFFF59E0B) : Colors.white,
          width: place['is_own'] == true ? 3 : 2,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6),
        ],
      ),
      child: Icon(typeIcon(type), color: Colors.white, size: 21),
    );
  }

  String _distanceLabel(int meters) {
    return meters >= 1000
        ? '${(meters / 1000).toStringAsFixed(1)} km'
        : '$meters m';
  }

  Future<void> _openPlace(Map<String, dynamic> place) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final type = place['type_code'] as String?;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: typeColor(type).withValues(alpha: 0.15),
                    child: Icon(typeIcon(type), color: typeColor(type)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${place['display_name'] ?? ''}',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${place['type_label'] ?? ''} • ${_distanceLabel(_distanceTo(place))}',
                                style:
                                    Theme.of(sheetContext).textTheme.bodySmall,
                              ),
                            ),
                            if (place['is_own'] == true) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Akunmu',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                            if (place['is_active'] == false) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Tutup',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (place['bio'] != null) ...[
                const SizedBox(height: 12),
                Text('${place['bio']}'),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  if (place['is_own'] != true) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(sheetContext).pop('chat'),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Chat'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(sheetContext).pop('view'),
                      icon: const Icon(Icons.storefront_outlined),
                      label: Text(place['is_own'] == true
                          ? 'Lihat akun'
                          : 'Lihat & pesan'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (result == 'view' && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProviderScreen(
            accountId: place['account_id'] as int,
            initialName: place['display_name'] as String?,
          ),
        ),
      );
      return;
    }
    if (result != 'chat' || !mounted) return;
    try {
      final data = await context.read<AuthStore>().api.post('conversations', {
        'type': 'direct',
        'account_id': place['account_id'],
      });
      final conversation = data['conversation'];
      if (!mounted || conversation is! Map) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatRoomScreen(
            conversation: Map<String, dynamic>.from(conversation),
          ),
        ),
      );
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final consent = context.watch<AuthStore>().locationConsent;
    if (_lastConsent != consent) {
      _lastConsent = consent;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadPlaces(showLoading: false);
      });
    }
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 16,
            minZoom: 12,
            maxZoom: 19,
            onPositionChanged: _onPositionChanged,
            onTap: (_, __) => FocusScope.of(context).unfocus(),
          ),
          children: [
            const ThemeMapTileLayer(),
            MarkerLayer(
              markers: [
                if (consent && _userLocation != null)
                  Marker(
                    point: _userLocation!,
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.location_on,
                      size: 42,
                      color: Color(0xFF1D4ED8),
                      shadows: [
                        Shadow(color: Colors.white, blurRadius: 3),
                        Shadow(color: Colors.black38, blurRadius: 6),
                      ],
                    ),
                  ),
                for (final place in _places)
                  Marker(
                    point: LatLng(
                      (place['lat'] as num).toDouble(),
                      (place['lng'] as num).toDouble(),
                    ),
                    width: 80,
                    height: 70,
                    alignment: Alignment.topCenter,
                    child: GestureDetector(
                      onTap: () => _openPlace(place),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 4),
                              ],
                            ),
                            child: Text(
                              _distanceLabel(_distanceTo(place)),
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _placeMarkerIcon(place),
                              if (place['is_own'] == true)
                                Positioned(
                                  right: -3,
                                  top: -3,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFF59E0B),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.star,
                                        size: 12, color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 10,
          child: Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _tooFar
                        ? Icons.zoom_in
                        : !consent
                            ? Icons.location_off
                            : (_hasLocation
                                ? Icons.near_me
                                : Icons.location_searching),
                    size: 18,
                    color: _tooFar
                        ? const Color(0xFFB45309)
                        : !consent
                            ? const Color(0xFFB45309)
                            : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _tooFar
                          ? 'Perbesar peta untuk memuat akun di sekitar.'
                          : !consent
                              ? 'Mode freeze. Aktifkan “Bagikan lokasi” di Setelan untuk melihat akun realtime.'
                              : _hasLocation
                                  ? '${_places.length} akun · ${_radius.round()} m'
                                  : 'Aktifkan GPS untuk melihat sekitar',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 14,
          bottom: 18,
          child: FloatingActionButton.small(
            onPressed: _refresh,
            tooltip: 'Muat ulang sekitar',
            child: const Icon(Icons.refresh),
          ),
        ),
        Positioned(
          left: 12,
          bottom: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            color: Colors.white70,
            child: const Text(
              '© OpenStreetMap contributors',
              style: TextStyle(fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }
}
