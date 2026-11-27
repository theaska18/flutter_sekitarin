import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// OpenStreetMap in light mode, CARTO dark tiles in dark mode, so the map
/// follows the system/app theme.
class ThemeMapTileLayer extends StatelessWidget {
  const ThemeMapTileLayer({super.key});

  static const _lightUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const _darkUrl =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TileLayer(
      urlTemplate: dark ? _darkUrl : _lightUrl,
      subdomains: dark ? const ['a', 'b', 'c', 'd'] : const [],
      retinaMode: MediaQuery.devicePixelRatioOf(context) > 1.5,
      userAgentPackageName: 'net.emetrotel.sekitar_app',
    );
  }
}
