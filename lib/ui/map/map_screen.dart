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
                                '${place['type_label'] ?? ''} • ${place['distance_m'] ?? 0} m',
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
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'net.emetrotel.sekitar_app',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _center,
                  width: 34,
                  height: 34,
                  child:
                      const Icon(Icons.my_location, color: Color(0xFF1D4ED8)),
                ),
                for (final place in _places)
                  Marker(
                    point: LatLng(
                      (place['lat'] as num).toDouble(),
                      (place['lng'] as num).toDouble(),
                    ),
                    width: 52,
                    height: 52,
                    child: GestureDetector(
                      onTap: () => _openPlace(place),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: place['is_active'] == false
                                  ? Colors.blueGrey
                                  : typeColor(place['type_code'] as String?),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: place['is_own'] == true
                                    ? const Color(0xFFF59E0B)
                                    : Colors.white,
                                width: place['is_own'] == true ? 3 : 2,
                              ),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 6),
                              ],
                            ),
                            child: Icon(
                              typeIcon(place['type_code'] as String?),
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          if (place['is_own'] == true)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF59E0B),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.star,
                                    size: 13, color: Colors.white),
                              ),
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
