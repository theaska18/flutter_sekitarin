import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import '../chat/chat_room_screen.dart';
import '../common.dart';
import 'create_order_screen.dart';

class ProviderScreen extends StatefulWidget {
  const ProviderScreen({
    super.key,
    required this.accountId,
    this.initialName,
  });

  final int accountId;
  final String? initialName;

  @override
  State<ProviderScreen> createState() => _ProviderScreenState();
}

class _ProviderScreenState extends State<ProviderScreen> {
  Map<String, dynamic>? _account;
  List<Map<String, dynamic>> _services = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthStore>().api;
    try {
      final results = await Future.wait([
        api.get('accounts/${widget.accountId}'),
        api.get('accounts/${widget.accountId}/services'),
      ]);
      final accountData = results[0];
      final serviceData = results[1];
      if (!mounted) return;
      setState(() {
        _account = accountData is Map && accountData['account'] is Map
            ? Map<String, dynamic>.from(accountData['account'] as Map)
            : null;
        _services = serviceData is Map && serviceData['data'] is List
            ? (serviceData['data'] as List)
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

  Future<void> _chat() async {
    try {
      final data = await context.read<AuthStore>().api.post('conversations', {
        'type': 'direct',
        'account_id': widget.accountId,
      });
      final conversation = data['conversation'];
      if (!mounted || conversation is! Map) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatRoomScreen(
            conversation: Map<String, dynamic>.from(conversation),
          ),
        ),
      );
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _order() async {
    final account = _account;
    if (account == null) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateOrderScreen(
          account: account,
          services: _services,
        ),
      ),
    );
    if (created == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    final type = account?['type_code'] as String?;
    final orderType = orderTypeForAccount(type);
    final orderServices = _services
        .where((service) =>
            service['kind'] == (orderType == 'food' ? 'product' : orderType))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(account?['display_name'] as String? ??
            widget.initialName ??
            'Akun'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (account == null)
                  const Center(child: Text('Akun tidak ditemukan'))
                else ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 34,
                            backgroundColor:
                                typeColor(type).withValues(alpha: 0.15),
                            child: Icon(typeIcon(type),
                                size: 34, color: typeColor(type)),
                          ),
                          const SizedBox(height: 12),
                          Text('${account['display_name'] ?? ''}',
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w800)),
                          Text('@${account['handle'] ?? ''}'),
                          const SizedBox(height: 4),
                          Text('${account['type_label'] ?? ''}',
                              style: Theme.of(context).textTheme.bodySmall),
                          if ('${account['bio'] ?? ''}'.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text('${account['bio']}',
                                textAlign: TextAlign.center),
                          ],
                          if ('${account['address'] ?? ''}'.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.place_outlined, size: 16),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text('${account['address']}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                ),
                              ],
                            ),
                          ],
                          if (account['hours'] is List &&
                              (account['hours'] as List).isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              alignment: WrapAlignment.center,
                              children: [
                                for (final hour in account['hours'] as List)
                                  if (hour is Map && hour['is_closed'] != true)
                                    Chip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text(
                                        '${[
                                          'Min',
                                          'Sen',
                                          'Sel',
                                          'Rab',
                                          'Kam',
                                          'Jum',
                                          'Sab'
                                        ][hour['weekday'] as int? ?? 0]} '
                                        '${hour['open_time']}-${hour['close_time']}',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Layanan',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (_services.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('Akun ini belum menambahkan layanan.'),
                      ),
                    )
                  else
                    Card(
                      child: Column(
                        children: [
                          for (final service in _services)
                            ListTile(
                              leading: Icon(
                                service['kind'] == 'ride'
                                    ? Icons.two_wheeler
                                    : service['kind'] == 'product'
                                        ? Icons.fastfood
                                        : Icons.handyman,
                              ),
                              title: Text('${service['name'] ?? ''}'),
                              subtitle: service['description'] == null
                                  ? null
                                  : Text('${service['description']}'),
                              trailing: Text(
                                rupiah((service['price'] as num?) ?? 0),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _chat,
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Chat'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: orderServices.isEmpty ? null : _order,
                          icon: const Icon(Icons.shopping_bag_outlined),
                          label: const Text('Pesan'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}
