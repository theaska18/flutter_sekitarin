import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/location_service.dart';
import '../../state/auth_store.dart';
import '../chat/chat_room_screen.dart';
import '../common.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  final List<Map<String, dynamic>> _places = [];
  LatLng _center = const LatLng(-6.9147, 107.6098);
  bool _loading = true;
  bool _hasLocation = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final api = context.read<AuthStore>().api;
    final position = await LocationService.current();
    if (position != null) {
      if (mounted) {
        setState(() {
          _center = position;
          _hasLocation = true;
        });
      }
      try {
        _mapController.move(position, 15);
      } catch (_) {
        // The map may not be attached on the first frame.
      }
    }
    try {
      final data = await api.get(
        'nearby',
        query: {
          'lat': '${_center.latitude}',
          'lng': '${_center.longitude}',
          'radius': '2500',
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
    final result = await showModalBottomSheet<bool>(
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
                        Text(
                          '${place['type_label'] ?? ''} • ${place['distance_m'] ?? 0} m',
                          style: Theme.of(sheetContext).textTheme.bodySmall,
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
              FilledButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Chat akun ini'),
              ),
            ],
          ),
        );
      },
    );
    if (result != true || !mounted) return;
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
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 14,
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
                    width: 46,
                    height: 46,
                    child: GestureDetector(
                      onTap: () => _openPlace(place),
                      child: Container(
                        decoration: BoxDecoration(
                          color: typeColor(place['type_code'] as String?),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
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
                    _hasLocation ? Icons.near_me : Icons.location_off,
                    size: 18,
                    color: _hasLocation
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _hasLocation
                          ? '${_places.length} akun di sekitar Anda'
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
