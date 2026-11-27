import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Shared OSM tile layer for all maps.
///
/// In dark mode the light OSM tiles are inverted with flutter_map's built-in
/// color matrix, so the map follows the system theme without a paid tile
/// provider or API key.
class ThemeMapTileLayer extends StatelessWidget {
  const ThemeMapTileLayer({super.key});

  static const _lightUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TileLayer(
      urlTemplate: _lightUrl,
      userAgentPackageName: 'net.emetrotel.sekitar_app',
      tileBuilder: dark ? darkModeTileBuilder : null,
    );
  }
}
