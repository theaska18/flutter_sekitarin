import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import 'account_profile_screen.dart';
import 'profile_screen.dart';

/// Opens the appropriate profile for [accountId]: the existing Profile page
/// for any account owned by the signed-in user (switching to it when needed),
/// otherwise a read-only profile with the same post grid.
Future<void> openAccountProfile(
  BuildContext context,
  int accountId, {
  String? initialName,
}) async {
  final auth = context.read<AuthStore>();
  final owned = auth.accounts.any(
    (account) => account['account_id'] == accountId,
  );
  if (owned) {
    if (auth.activeAccountId != accountId) {
      try {
        await auth.switchAccount(accountId);
      } catch (_) {
        // Keep the current account if switching fails.
      }
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
    );
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AccountProfileScreen(
        accountId: accountId,
        initialName: initialName,
      ),
    ),
  );
}
