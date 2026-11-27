import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import '../common.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthStore>().api;
    try {
      final data = await api.get(
        'notifications',
        query: {'include_chat': 'false'},
      );
      if (!mounted) return;
      setState(() {
        _items = data is Map && data['data'] is List
            ? (data['data'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
      });
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAll() async {
    await context.read<AuthStore>().api.post('notifications/read-all');
    await _load();
    if (mounted) await context.read<AuthStore>().refresh();
  }

  Future<void> _open(Map<String, dynamic> item) async {
    if (item['read'] != true) {
      try {
        await context
            .read<AuthStore>()
            .api
            .post('notifications/${item['notification_id']}/read');
      } catch (_) {}
    }
    if (!mounted) return;
    final data = item['data'];
    if (data is Map && data['conversation_id'] != null) {
      Navigator.of(context).pop();
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi'),
        actions: [
          TextButton(
            onPressed: _items.isEmpty ? null : _markAll,
            child: const Text('Baca semua'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('Belum ada notifikasi')),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final unread = item['read'] != true;
                        return Card(
                          child: ListTile(
                            onTap: () => _open(item),
                            leading: CircleAvatar(
                              backgroundColor: unread
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : Colors.black12,
                              child: const Icon(Icons.notifications),
                            ),
                            title: Text('${item['title'] ?? ''}',
                                style: TextStyle(
                                  fontWeight: unread
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                )),
                            subtitle: Text('${item['body'] ?? ''}'),
                            trailing: Text(
                              formatWhen(item['created_at']),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
