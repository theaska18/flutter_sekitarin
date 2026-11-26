import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import '../notifications/notifications_screen.dart';
import '../orders/orders_screen.dart';
import '../profile/business_location_screen.dart';
import '../profile/create_account_screen.dart';
import '../widgets/account_avatar.dart';

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
  Timer? _timer;
  bool _expiryRefresh = false;

  @override
  void initState() {
    super.initState();
    _loadConsents();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      final now = DateTime.now();
      final expired = context.read<AuthStore>().accounts.any((account) {
        final until = account['active_until'];
        if (account['type_code'] == 'personal' ||
            account['is_active'] == false ||
            until == null) {
          return false;
        }
        final parsed = DateTime.tryParse('$until')?.toLocal();
        return parsed != null && !parsed.isAfter(now);
      });
      if (expired && !_expiryRefresh) {
        _expiryRefresh = true;
        context.read<AuthStore>().refresh().whenComplete(() {
          _expiryRefresh = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
      final auth = context.read<AuthStore>();
      await auth.api.put('me/consents/$scope', {
        'granted': value,
        'policy_version': '1.0',
      });
      await auth.refresh();
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 36),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                AccountAvatar(
                  account: auth.activeAccount,
                  radius: 22,
                  token: auth.api.accessToken,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${auth.user?['display_name'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${auth.user?['email'] ?? ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (auth.user?['email_verified'] != true)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: const Text('Belum verifikasi',
                        style: TextStyle(fontSize: 10)),
                    onPressed: () {},
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const _SectionTitle('Akun'),
        Card(
          child: Column(
            children: [
              for (final account in auth.accounts)
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: AccountAvatar(
                    account: account,
                    radius: 20,
                    token: auth.api.accessToken,
                    fallbackIcon: typeIcon(account['type_code'] as String?),
                    backgroundColor: typeColor(account['type_code'] as String?)
                        .withValues(alpha: 0.15),
                    foregroundColor: typeColor(account['type_code'] as String?),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${account['display_name'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _ActiveBadge(active: account['is_active'] != false),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@${account['handle'] ?? ''} • ${account['type_label'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      if (account['type_code'] != 'personal' &&
                          account['is_active'] != false &&
                          account['active_until'] != null)
                        Text(
                          timeRemaining(account['active_until']),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (account['type_code'] != 'personal' &&
                          account['location_mode'] == 'realtime')
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 2),
                          child: Tooltip(
                            message: 'Live GPS',
                            child: Icon(
                              Icons.gps_fixed,
                              size: 16,
                              color: Color(0xFF047857),
                            ),
                          ),
                        ),
                      if (account['type_code'] != 'personal')
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Pengaturan usaha',
                          icon: const Icon(Icons.settings_outlined, size: 19),
                          onPressed: () async {
                            final changed =
                                await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => BusinessLocationScreen(
                                  accountId: account['account_id'] as int,
                                ),
                              ),
                            );
                            if (changed == true && context.mounted) {
                              await context.read<AuthStore>().refresh();
                            }
                          },
                        ),
                      if (account['account_id'] == auth.activeAccountId)
                        Icon(
                          Icons.check_circle,
                          size: 19,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                  onTap: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await auth
                                .switchAccount(account['account_id'] as int);
                          } catch (error) {
                            if (context.mounted) {
                              showErrorSnack(context, error);
                            }
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                ),
              const Divider(height: 1),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                dense: true,
                leading: const Icon(Icons.add_business_outlined, size: 20),
                title: const Text('Tambah akun usaha',
                    style: TextStyle(fontSize: 13)),
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
        const SizedBox(height: 14),
        const _SectionTitle('Privasi & izin'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                value: _consents['location'] ?? false,
                onChanged: (value) => _setConsent('location', value),
                secondary: const Icon(Icons.location_on_outlined, size: 20),
                title: const Text('Bagikan lokasi',
                    style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                  'Peta, presence, dan live location grup.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                value: _consents['notifications'] ?? false,
                onChanged: (value) => _setConsent('notifications', value),
                secondary: const Icon(Icons.notifications_outlined, size: 20),
                title: const Text('Notifikasi', style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                  'Pesan, like, komentar, dan update order.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _SectionTitle('Lainnya'),
        Card(
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                dense: true,
                leading: const Icon(Icons.receipt_long_outlined, size: 20),
                title: const Text('Pesanan', style: TextStyle(fontSize: 13)),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const OrdersScreen(),
                  ),
                ),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                dense: true,
                leading: const Icon(Icons.notifications_none, size: 20),
                title: const Text('Feed notifikasi',
                    style: TextStyle(fontSize: 13)),
                trailing: auth.unreadNotifications > 0
                    ? Badge(
                        label: Text('${auth.unreadNotifications}'),
                      )
                    : null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                dense: true,
                leading: const Icon(Icons.info_outline, size: 20),
                title: const Text('Server API', style: TextStyle(fontSize: 13)),
                subtitle: Text(
                  AppConfig.apiBaseUrl,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                dense: true,
                leading: Icon(
                  Icons.logout,
                  size: 20,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Keluar',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                onTap: _logout,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF047857) : Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        active ? 'Aktif' : 'Nonaktif',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
