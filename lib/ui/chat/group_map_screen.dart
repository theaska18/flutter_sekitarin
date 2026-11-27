import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/location_service.dart';
import '../../state/auth_store.dart';
import '../common.dart';

class GroupMapScreen extends StatefulWidget {
  const GroupMapScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });

  final int conversationId;
  final String title;

  @override
  State<GroupMapScreen> createState() => _GroupMapScreenState();
}

class _GroupMapScreenState extends State<GroupMapScreen> {
  final _mapController = MapController();
  List<Map<String, dynamic>> _locations = [];
  bool _loading = true;
  bool _sharing = false;
  bool _busy = false;
  LatLng _center = const LatLng(-6.9147, 107.6098);
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AuthStore>().api.get(
            'conversations/${widget.conversationId}/live-location',
          );
      if (!mounted) return;
      final items = data is Map && data['data'] is List
          ? (data['data'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : <Map<String, dynamic>>[];
      final myId = context.read<AuthStore>().user?['user_id'];
      final mine = items.where((item) => item['user_id'] == myId).toList();
      setState(() {
        _locations = items;
        _sharing = mine.isNotEmpty;
        if (items.isNotEmpty) {
          _center = LatLng(
            (items.first['lat'] as num).toDouble(),
            (items.first['lng'] as num).toDouble(),
          );
        }
      });
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleShare() async {
    if (_busy) return;
    final auth = context.read<AuthStore>();
    if (!auth.locationConsent) {
      showErrorSnack(
        context,
        'Aktifkan “Bagikan lokasi” di Profil/Setelan terlebih dahulu.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      if (_sharing) {
        await auth.api.delete(
          'conversations/${widget.conversationId}/live-location',
        );
      } else {
        final position = await LocationService.current();
        if (position == null) {
          throw Exception('Lokasi GPS tidak tersedia.');
        }
        await auth.api.put(
          'conversations/${widget.conversationId}/live-location',
          {
            'lat': position.latitude,
            'lng': position.longitude,
            'expires_in': 600,
          },
        );
      }
      await _load();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.read<AuthStore>().user?['user_id'];
    return Scaffold(
      appBar: AppBar(title: Text('Peta • ${widget.title}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'net.emetrotel.sekitar_app',
                    ),
                    MarkerLayer(
                      markers: [
                        for (final item in _locations)
                          Marker(
                            point: LatLng(
                              (item['lat'] as num).toDouble(),
                              (item['lng'] as num).toDouble(),
                            ),
                            width: 110,
                            height: 56,
                            alignment: Alignment.topCenter,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(7),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Colors.black26, blurRadius: 4),
                                    ],
                                  ),
                                  child: Text(
                                    item['user_id'] == myId
                                        ? 'Kamu'
                                        : '${item['display_name'] ?? ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.location_on,
                                  size: 34,
                                  color: item['user_id'] == myId
                                      ? const Color(0xFF1D4ED8)
                                      : const Color(0xFF047857),
                                ),
                              ],
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
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          const Icon(Icons.people_outline, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_locations.length} anggota membagikan lokasi. '
                              'Hanya anggota yang menyetujui share lokasi yang tampil.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 20,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _toggleShare,
                    icon: Icon(
                      _sharing ? Icons.location_off : Icons.my_location,
                    ),
                    label: Text(
                      _sharing
                          ? 'Berhenti bagikan lokasi'
                          : 'Bagikan lokasi saya (10 menit)',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
