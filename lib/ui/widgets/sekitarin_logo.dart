import 'package:flutter/material.dart';

/// Sekitarin wordmark: the blue app icon next to the app name.
/// Uses the launcher icon asset so the in-app logo matches the home-screen icon.
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
    final radius = height * 0.24;
    final mark = Container(
      width: height,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: height * 0.16,
            offset: Offset(0, height * 0.06),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/brand/app_icon.png',
          width: height,
          height: height,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
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
