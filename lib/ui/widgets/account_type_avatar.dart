import 'package:flutter/material.dart';

import '../common.dart';
import 'account_avatar.dart';

/// Account avatar with a small badge for non-personal accounts showing the
/// account type (driver car, warung, restaurant, etc.) and an optional
/// online/active status dot.
class AccountTypeAvatar extends StatelessWidget {
  const AccountTypeAvatar({
    super.key,
    required this.account,
    this.radius = 20,
    this.token,
    this.showBadge = true,
    this.showStatusDot = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  final Map<String, dynamic>? account;
  final double radius;
  final String? token;
  final bool showBadge;
  final bool showStatusDot;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final type = account?['type_code'] as String?;
    final isBusiness = type != null && type != 'personal';
    final active = isBusiness
        ? (account?['is_active'] ?? account?['is_online']) == true
        : account?['is_online'] == true;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AccountAvatar(
          account: account,
          radius: radius,
          token: token,
          fallbackIcon: typeIcon(type),
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
        ),
        if (showBadge && isBusiness)
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              padding: EdgeInsets.all(radius * 0.1 + 0.8),
              decoration: BoxDecoration(
                color: typeColor(type),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1.5,
                ),
              ),
              child: Icon(
                typeIcon(type),
                size: radius * 0.42,
                color: Colors.white,
              ),
            ),
          ),
        if (showStatusDot && account != null)
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: radius * 0.6,
              height: radius * 0.6,
              decoration: BoxDecoration(
                color:
                    active ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
