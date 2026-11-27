import 'package:flutter/material.dart';

import 'account_avatar.dart';

/// Group avatar with a small group badge so group chats are visually marked,
/// even when the group has a custom photo.
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({
    super.key,
    required this.mediaId,
    this.token,
    this.radius = 20,
    this.showBadge = true,
  });

  final int? mediaId;
  final String? token;
  final double radius;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AccountAvatar(
          account: {'avatar_media_id': mediaId},
          radius: radius,
          token: token,
          fallbackIcon: Icons.groups,
          backgroundColor: scheme.tertiaryContainer,
          foregroundColor: scheme.onTertiaryContainer,
        ),
        if (showBadge)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              padding: EdgeInsets.all(radius * 0.12),
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.surface,
                  width: radius * 0.08,
                ),
              ),
              child: Icon(
                Icons.groups,
                size: radius * 0.44,
                color: scheme.onPrimary,
              ),
            ),
          ),
      ],
    );
  }
}
