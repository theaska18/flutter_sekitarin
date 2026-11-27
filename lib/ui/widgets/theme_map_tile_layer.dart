import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Shared OSM tile layer for all maps.
///
/// Dark tiles are intentionally deferred (CARTO now requires an API key), so
/// maps stay light even in dark mode until a tile provider is chosen.
class ThemeMapTileLayer extends StatelessWidget {
  const ThemeMapTileLayer({super.key});

  static const _lightUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: _lightUrl,
      userAgentPackageName: 'net.emetrotel.sekitar_app',
    );
  }
}
