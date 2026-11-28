import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
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

  // Inline update state, shown on the "Cek update" row.
  bool _updateChecking = false;
  bool _updateDownloading = false;
  bool _updateReady = false;
  bool _updateCancelled = false;
  String? _updateError;
  String? _updateVersion;
  double? _updateProgress;
  int _updateReceived = 0;
  int _updateTotal = 0;
  String _updateStatus = '';
  File? _updateFile;
  http.Client? _updateClient;

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
    _updateCancelled = true;
    _updateClient?.close();
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

  String get _updateSizeLabel {
    final received = (_updateReceived / (1024 * 1024)).toStringAsFixed(1);
    if (_updateTotal <= 0) return '$received MB terunduh';
    final total = (_updateTotal / (1024 * 1024)).toStringAsFixed(1);
    final percent = ((_updateProgress ?? 0) * 100).round();
    return '$percent% • $received / $total MB';
  }

  String get _updateSubtitle {
    if (_updateDownloading) return 'Mengunduh ${_updateSizeLabel.trim()}';
    if (_updateError != null) return _updateError!;
    if (_updateReady) {
      final version = _updateVersion == null ? '' : ' • v$_updateVersion';
      return '${_updateStatus.isEmpty ? 'Siap dipasang' : _updateStatus}$version';
    }
    if (_updateChecking) return 'Memeriksa update…';
    return 'Unduh dan pasang APK terbaru';
  }

  Widget? _updateTrailing() {
    if (_updateDownloading) {
      return TextButton(
        onPressed: _cancelUpdateDownload,
        child: const Text('Batal'),
      );
    }
    if (_updateReady) {
      return FilledButton.tonal(
        onPressed: _openInstaller,
        child: const Text('Pasang'),
      );
    }
    if (_updateError != null) {
      return TextButton(
        onPressed: _checkUpdate,
        child: const Text('Coba lagi'),
      );
    }
    if (_updateChecking) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return const Icon(Icons.chevron_right, size: 18);
  }

  bool _isNewer(String remote, String current) {
    final a = remote.split('.').map(int.tryParse).toList();
    final b = current.split('.').map(int.tryParse).toList();
    for (var i = 0; i < 3; i++) {
      final left = i < a.length ? (a[i] ?? 0) : 0;
      final right = i < b.length ? (b[i] ?? 0) : 0;
      if (left != right) return left > right;
    }
    return false;
  }

  Future<void> _checkUpdate() async {
    if (_updateChecking || _updateDownloading) return;
    // A finished download stays on disk, so retrying the install (for example
    // after accidentally dismissing the installer) never downloads again.
    if (_updateReady && _updateFile != null) {
      await _openInstaller();
      return;
    }
    setState(() {
      _updateChecking = true;
      _updateError = null;
      _updateStatus = 'Memeriksa update…';
    });
    try {
      final data = await context.read<AuthStore>().api.get('app/latest');
      final app = data is Map ? data['app'] : null;
      if (app is! Map) throw Exception('Informasi update tidak tersedia.');
      final info = await PackageInfo.fromPlatform();
      final remoteVersion = '${app['version'] ?? '0.0.0'}';
      if (!_isNewer(remoteVersion, info.version)) {
        if (!mounted) return;
        setState(() {
          _updateChecking = false;
          _updateStatus = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Aplikasi sudah terbaru (${info.version}).'),
          ),
        );
        return;
      }
      if (!mounted) return;
      if (!Platform.isAndroid) {
        setState(() => _updateChecking = false);
        showErrorSnack(context, 'Update APK hanya tersedia di Android.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/sekitar-update-$remoteVersion.apk');
      final cached = await file.exists() && (await file.length()) > 100000;
      setState(() {
        _updateChecking = false;
        _updateVersion = remoteVersion;
        _updateFile = file;
      });
      if (cached) {
        setState(() {
          _updateReady = true;
          _updateProgress = 1;
          _updateStatus = 'File update sudah terunduh.';
        });
        await _openInstaller();
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Update $remoteVersion tersedia'),
          content: Text(
            '${app['notes'] ?? 'Perbaikan dan fitur baru.'}\n\n'
            'Versi terpasang: ${info.version}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Nanti'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Update'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final url = AppConfig.absoluteUrl(
        '${app['url'] ?? '/api/v1/app/download'}',
      );
      await _downloadUpdate(url, file);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _updateChecking = false;
        _updateDownloading = false;
        _updateError = 'Gagal memeriksa update: $error';
      });
    }
  }

  Future<void> _downloadUpdate(String url, File file) async {
    final client = http.Client();
    _updateClient = client;
    _updateCancelled = false;
    setState(() {
      _updateDownloading = true;
      _updateReady = false;
      _updateError = null;
      _updateProgress = null;
      _updateReceived = 0;
      _updateTotal = 0;
      _updateStatus = 'Mengunduh update…';
    });
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('Server membalas ${response.statusCode}.');
      }
      if (!mounted) return;
      setState(() => _updateTotal = response.contentLength ?? 0);
      final sink = file.openWrite();
      await for (final chunk in response.stream) {
        if (_updateCancelled) break;
        sink.add(chunk);
        _updateReceived += chunk.length;
        if (mounted) {
          setState(() {
            _updateProgress =
                _updateTotal > 0 ? _updateReceived / _updateTotal : null;
          });
        }
      }
      await sink.flush();
      await sink.close();
      if (_updateCancelled) {
        if (await file.exists()) await file.delete();
        return;
      }
      if (!mounted) return;
      setState(() {
        _updateDownloading = false;
        _updateReady = true;
        _updateProgress = 1;
        _updateStatus = 'Selesai diunduh.';
      });
      await _openInstaller();
    } catch (error) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Ignore cleanup failures.
      }
      if (_updateCancelled) return;
      if (!mounted) return;
      setState(() {
        _updateDownloading = false;
        _updateReady = false;
        _updateError = 'Unduhan gagal. Periksa koneksi lalu coba lagi.';
      });
    } finally {
      client.close();
      _updateClient = null;
    }
  }

  void _cancelUpdateDownload() {
    if (!_updateDownloading) return;
    _updateCancelled = true;
    _updateClient?.close();
    setState(() {
      _updateDownloading = false;
      _updateProgress = null;
      _updateStatus = 'Unduhan dibatalkan.';
    });
  }

  Future<void> _openInstaller() async {
    final file = _updateFile;
    if (file == null) return;
    if (!await file.exists()) {
      if (!mounted) return;
      setState(() {
        _updateReady = false;
        _updateError = 'File update sudah tidak ada. Unduh ulang.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _updateStatus = 'Membuka installer…';
      _updateError = null;
    });
    final result = await OpenFilex.open(file.path);
    if (!mounted) return;
    setState(() {
      _updateReady = true;
      _updateStatus = result.type == ResultType.done
          ? 'Installer dibuka. Jika terlewat, tekan Pasang lagi.'
          : 'File siap dipasang. Tekan Pasang untuk membuka installer.';
      if (result.type != ResultType.done) {
        _updateError = 'Installer tidak dapat dibuka otomatis.';
      }
    });
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
      await SystemNavigator.pop();
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
              // Custom row instead of ListTile: the "Pasang" button used to
              // squeeze the title and push "Cek update" downwards on narrow
              // screens.
              InkWell(
                onTap:
                    _updateDownloading || _updateChecking ? null : _checkUpdate,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      if (_updateDownloading)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            value: _updateProgress,
                          ),
                        )
                      else
                        const Icon(Icons.system_update_alt, size: 20),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Cek update',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13),
                            ),
                            Text(
                              _updateSubtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: _updateError != null
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_updateTrailing() case final trailing?) trailing,
                    ],
                  ),
                ),
              ),
              if (_updateDownloading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: LinearProgressIndicator(value: _updateProgress),
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
