import 'package:flutter/material.dart';

import '../../config.dart';

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.account,
    this.radius = 24,
    this.token,
    this.fallbackIcon = Icons.person,
    this.backgroundColor,
    this.foregroundColor,
  });

  final Map<String, dynamic>? account;
  final double radius;
  final String? token;
  final IconData fallbackIcon;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final mediaId = account?['avatar_media_id'];
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor:
          backgroundColor ?? Theme.of(context).colorScheme.primaryContainer,
      child: Icon(
        fallbackIcon,
        size: radius * 1.05,
        color:
            foregroundColor ?? Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
    if (mediaId is! int) return fallback;
    final headers = token == null || token!.isEmpty
        ? null
        : <String, String>{'Authorization': 'Bearer $token'};
    return ClipOval(
      child: Image.network(
        AppConfig.absoluteUrl('/api/v1/media/$mediaId'),
        headers: headers,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
