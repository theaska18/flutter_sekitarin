import 'package:flutter/material.dart';

/// Sekitarin wordmark: a gradient map-pin tile next to the app name.
/// Drawn in Flutter so it stays crisp and follows the active theme.
class SekitarinLogo extends StatelessWidget {
  const SekitarinLogo({
    super.key,
    this.height = 26,
    this.showWordmark = true,
  });

  final double height;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mark = Container(
      width: height,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
        ),
        borderRadius: BorderRadius.circular(height * 0.3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withValues(alpha: 0.25),
            blurRadius: height * 0.18,
            offset: Offset(0, height * 0.08),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.place,
            color: Colors.white,
            size: height * 0.66,
          ),
          Positioned(
            right: height * 0.16,
            bottom: height * 0.14,
            child: Container(
              width: height * 0.22,
              height: height * 0.22,
              decoration: const BoxDecoration(
                color: Color(0xFFFFC857),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );

    if (!showWordmark) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: height * 0.3),
        Text(
          'Sekitarin',
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: height * 0.72,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
