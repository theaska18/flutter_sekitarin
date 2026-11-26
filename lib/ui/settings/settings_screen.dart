import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import '../notifications/notifications_screen.dart';
import '../profile/create_account_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<String, bool> _consents = {
    'location': false,
    'notifications': false,
  };
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadConsents();
  }

  Future<void> _loadConsents() async {
    try {
      final data = await context.read<AuthStore>().api.get('me/consents');
      final latest = data is Map ? data['latest'] : null;
      if (latest is Map) {
        setState(() {
          _consents['location'] = latest['location'] is Map &&
              latest['location']['granted'] == true;
          _consents['notifications'] = latest['notifications'] is Map &&
              latest['notifications']['granted'] == true;
        });
      }
    } catch (_) {
      // Consent defaults stay off.
    }
  }

  Future<void> _setConsent(String scope, bool value) async {
    setState(() => _consents[scope] = value);
    try {
      await context.read<AuthStore>().api.put('me/consents/$scope', {
        'granted': value,
        'policy_version': '1.0',
      });
    } catch (error) {
      if (mounted) {
        setState(() => _consents[scope] = !value);
        showErrorSnack(context, error);
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar?'),
        content: const Text('Sesi di perangkat ini akan dicabut.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AuthStore>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    final displayName = '${auth.user?['display_name'] ?? '?'}';
    final initial =
        displayName.isEmpty ? '?' : displayName.substring(0, 1).toUpperCase();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  child: Text(initial),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${auth.user?['display_name'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${auth.user?['email'] ?? ''}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (auth.user?['email_verified'] != true)
                  const Chip(label: Text('Belum verifikasi')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text('Akun',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final account in auth.accounts)
                ListTile(
                  leading: Icon(typeIcon(account['type_code'] as String?)),
                  title: Text('${account['display_name'] ?? ''}'),
                  subtitle: Text(
                      '@${account['handle'] ?? ''} • ${account['type_label'] ?? ''}'),
                  trailing: account['account_id'] == auth.activeAccountId
                      ? Icon(Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await auth
                                .switchAccount(account['account_id'] as int);
                          } catch (error) {
                            if (context.mounted) showErrorSnack(context, error);
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                ),
              ListTile(
                leading: const Icon(Icons.add_business_outlined),
                title: const Text('Tambah akun usaha'),
                onTap: () async {
                  final created = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => const CreateAccountScreen(),
                    ),
                  );
                  if (created == true && context.mounted) {
                    await context.read<AuthStore>().refresh();
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text('Privasi & izin',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: _consents['location'] ?? false,
                onChanged: (value) => _setConsent('location', value),
                secondary: const Icon(Icons.location_on_outlined),
                title: const Text('Bagikan lokasi'),
                subtitle: const Text(
                    'Diperlukan untuk peta, presence, dan live location grup.'),
              ),
              SwitchListTile(
                value: _consents['notifications'] ?? false,
                onChanged: (value) => _setConsent('notifications', value),
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('Notifikasi'),
                subtitle:
                    const Text('Pesan, like, komentar, dan update order.'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_none),
                title: const Text('Feed notifikasi'),
                trailing: auth.unreadNotifications > 0
                    ? Text('${auth.unreadNotifications}')
                    : null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Server API'),
                subtitle: Text(AppConfig.apiBaseUrl),
              ),
              ListTile(
                leading: Icon(Icons.logout,
                    color: Theme.of(context).colorScheme.error),
                title: Text('Keluar',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: _logout,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
