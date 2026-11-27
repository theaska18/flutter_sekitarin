import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import 'account_profile_screen.dart';
import 'profile_screen.dart';

/// Opens the appropriate profile for [accountId]: the owner's own Profile tab
/// when it is the active account, otherwise a read-only profile with the same
/// post grid.
Future<void> openAccountProfile(
  BuildContext context,
  int accountId, {
  String? initialName,
}) {
  final isOwnActive = accountId == context.read<AuthStore>().activeAccountId;
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => isOwnActive
          ? const ProfileScreen()
          : AccountProfileScreen(
              accountId: accountId,
              initialName: initialName,
            ),
    ),
  );
}
