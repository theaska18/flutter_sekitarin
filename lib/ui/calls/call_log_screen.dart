import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/call_service.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import '../widgets/account_type_avatar.dart';
import 'call_status_screen.dart';

/// Phone call history for direct (1:1) calls.
class CallLogScreen extends StatefulWidget {
  const CallLogScreen({super.key});

  @override
  State<CallLogScreen> createState() => _CallLogScreenState();
}

class _CallLogScreenState extends State<CallLogScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  int? _busyCallAccount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AuthStore>().api.get('calls');
      if (!mounted) return;
      setState(() {
        _error = null;
        _items = data is Map && data['data'] is List
            ? (data['data'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _callBack(Map<String, dynamic> item) async {
    final peer = item['peer'] is Map
        ? Map<String, dynamic>.from(item['peer'] as Map)
        : null;
    final accountId = peer?['account_id'];
    if (accountId is! int) return;
    setState(() => _busyCallAccount = accountId);
    try {
      final result = await CallService.instance.startDirectCall(
        accountId: accountId,
        kind: '${item['kind'] ?? 'voice'}',
        conversationId: item['conversation_id'] as int?,
      );
      if (!mounted) return;
      if (result == null) {
        showErrorSnack(context, 'Panggilan tidak dapat dimulai.');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CallStatusScreen(
            call: result['call'] as Map<String, dynamic>,
            jitsi: result['jitsi'] as Map<String, dynamic>,
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busyCallAccount = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Gagal memuat log panggilan'),
              const SizedBox(height: 8),
              TextButton(onPressed: _load, child: const Text('Coba lagi')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.3),
              Icon(Icons.phone_in_talk_outlined,
                  size: 48, color: scheme.outline),
              const SizedBox(height: 12),
              const Center(child: Text('Belum ada log panggilan')),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ReadableWidth(
        maxWidth: 720,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = _items[index];
              final peer = item['peer'] is Map
                  ? Map<String, dynamic>.from(item['peer'] as Map)
                  : <String, dynamic>{};
              final direction = '${item['direction'] ?? 'outgoing'}';
              final status = '${item['status'] ?? ''}';
              final missed = status == 'missed' ||
                  status == 'declined' ||
                  status == 'canceled';
              final icon = direction == 'incoming'
                  ? (missed ? Icons.call_missed : Icons.call_received)
                  : Icons.call_made;
              final color = missed ? scheme.error : scheme.primary;
              final busy = _busyCallAccount != null &&
                  _busyCallAccount == peer['account_id'];
              return ListTile(
                leading: AccountTypeAvatar(
                  account: peer,
                  radius: 22,
                  showStatusDot: true,
                ),
                title: Row(
                  children: [
                    Icon(icon, size: 15, color: color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${peer['display_name'] ?? 'Panggilan'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight:
                              missed ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  _describe(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        onPressed: () => _callBack(item),
                        icon: Icon(
                          item['kind'] == 'video'
                              ? Icons.videocam_outlined
                              : Icons.call_outlined,
                        ),
                        tooltip: 'Hubungi lagi',
                      ),
                onTap: () => _callBack(item),
              );
            },
          ),
        ),
      ),
    );
  }

  String _describe(Map<String, dynamic> item) {
    final status = '${item['status'] ?? ''}';
    final kind = item['kind'] == 'video' ? 'Video' : 'Suara';
    String label;
    switch (status) {
      case 'missed':
        label = 'Tidak dijawab';
        break;
      case 'declined':
        label = 'Ditolak';
        break;
      case 'canceled':
        label = 'Dibatalkan';
        break;
      case 'ringing':
        label = 'Berdering';
        break;
      case 'answered':
        label = 'Berlangsung';
        break;
      default:
        final seconds = item['duration_seconds'] as int? ?? 0;
        label = seconds > 0 ? _duration(seconds) : 'Selesai';
    }
    final prefix = item['direction'] == 'outgoing' ? 'Keluar' : 'Masuk';
    final when = timeAgo(item['created_at']);
    return '$prefix · $kind · $label · $when';
  }

  String _duration(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    if (minutes <= 0) return '${rest} dtk';
    return '$minutes mnt ${rest.toString().padLeft(2, '0')} dtk';
  }
}
