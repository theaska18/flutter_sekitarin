import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import '../chat/chat_room_screen.dart';
import '../common.dart';

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.initial,
  });

  final int orderId;
  final Map<String, dynamic>? initial;

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _order = widget.initial;
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AuthStore>().api.get(
            'orders/${widget.orderId}',
          );
      if (!mounted) return;
      if (data is Map && data['order'] is Map) {
        setState(() {
          _order = Map<String, dynamic>.from(data['order'] as Map);
        });
      }
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _isCustomer {
    final order = _order;
    final userId = context.read<AuthStore>().user?['user_id'];
    final customer = order?['customer'];
    return customer is Map && customer['user_id'] == userId;
  }

  bool get _isProvider {
    final order = _order;
    final provider = order?['provider'];
    if (provider is! Map) return false;
    final auth = context.read<AuthStore>();
    return auth.accounts.any(
      (account) => account['account_id'] == provider['account_id'],
    );
  }

  String get _status => '${_order?['status'] ?? ''}';

  Future<void> _action(String action, [Map<String, dynamic>? body]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = await context.read<AuthStore>().api.post(
            'orders/${widget.orderId}/$action',
            body,
          );
      if (!mounted) return;
      if (data['order'] is Map) {
        setState(() {
          _order = Map<String, dynamic>.from(data['order'] as Map);
        });
      }
      await _load();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan order?'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Alasan (opsional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tidak'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Batalkan'),
          ),
        ],
      ),
    );
    if (reason != null) {
      await _action('cancel', {'reason': reason});
    }
  }

  Future<void> _chat() async {
    final order = _order;
    if (order == null) return;
    try {
      final body = _isCustomer
          ? {
              'type': 'direct',
              'account_id': (order['provider'] as Map)['account_id'],
            }
          : {
              'type': 'direct',
              'user_id': (order['customer'] as Map)['user_id'],
            };
      final data =
          await context.read<AuthStore>().api.post('conversations', body);
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

  @override
  Widget build(BuildContext context) {
    final order = _order;
    if (_loading && order == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order')),
        body: const Center(child: Text('Order tidak ditemukan')),
      );
    }
    final provider = order['provider'] is Map
        ? Map<String, dynamic>.from(order['provider'] as Map)
        : <String, dynamic>{};
    final items = order['items'] is List ? order['items'] as List : const [];
    final events = order['events'] is List ? order['events'] as List : const [];
    final paymentStatus = '${order['payment_status'] ?? 'unpaid'}';
    return Scaffold(
      appBar: AppBar(
        title: Text('${order['code'] ?? 'Order'}'),
        actions: [
          IconButton(
            onPressed: _chat,
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Chat',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: orderStatusColor(_status).withValues(alpha: 0.10),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    _status == 'completed'
                        ? Icons.check_circle
                        : _status == 'cancelled'
                            ? Icons.cancel
                            : Icons.local_shipping_outlined,
                    color: orderStatusColor(_status),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(orderStatusLabel(_status),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: orderStatusColor(_status),
                            )),
                        Text(
                            '${orderTypeLabel(order['type'] as String?)} • ${formatWhen(order['created_at'])}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Text(rupiah((order['total'] as num?) ?? 0),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(typeIcon(provider['type_code'] as String?)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${provider['display_name'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text('@${provider['handle'] ?? ''}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  const Divider(height: 22),
                  for (final item in items)
                    if (item is Map)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                  '${item['quantity']}× ${item['name'] ?? ''}'),
                            ),
                            Text(rupiah((item['subtotal'] as num?) ?? 0)),
                          ],
                        ),
                      ),
                  const Divider(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Pembayaran',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '${order['payment_method'] == 'cash' ? 'Tunai' : 'Transfer'} • $paymentStatus',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if ('${order['notes'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Catatan: ${order['notes']}'),
                  ],
                  if (order['delivery'] is Map) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Antar: ${(order['delivery'] as Map)['address'] ?? '${(order['delivery'] as Map)['lat']}, ${(order['delivery'] as Map)['lng']}'}',
                    ),
                  ],
                  if (order['dropoff'] is Map) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Tujuan: ${(order['dropoff'] as Map)['address'] ?? '${(order['dropoff'] as Map)['lat']}, ${(order['dropoff'] as Map)['lng']}'}',
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (events.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Riwayat status',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final event in events)
                    if (event is Map)
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.circle,
                            size: 10,
                            color:
                                orderStatusColor(event['status'] as String?)),
                        title:
                            Text(orderStatusLabel(event['status'] as String?)),
                        subtitle: Text(
                            '${event['note'] ?? ''} • ${formatWhen(event['created_at'])}'),
                      ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          ..._actions(),
        ],
      ),
    );
  }

  List<Widget> _actions() {
    final widgets = <Widget>[];
    if (_isProvider) {
      if (_status == 'pending') {
        widgets.add(FilledButton(
          onPressed: _busy ? null : () => _action('accept'),
          child: const Text('Terima order'),
        ));
      } else if (_status == 'accepted') {
        widgets.add(FilledButton(
          onPressed: _busy ? null : () => _action('progress'),
          child: const Text('Mulai proses'),
        ));
      } else if (_status == 'in_progress' && _order?['type'] == 'food') {
        widgets.add(FilledButton(
          onPressed: _busy ? null : () => _action('deliver'),
          child: const Text('Mulai antar'),
        ));
      }
      if (['accepted', 'in_progress', 'delivering'].contains(_status)) {
        widgets.add(const SizedBox(height: 8));
        widgets.add(OutlinedButton(
          onPressed: _busy ? null : () => _action('complete'),
          child: const Text('Selesaikan order'),
        ));
      }
      if (_status == 'completed' && _order?['payment_status'] != 'paid') {
        widgets.add(const SizedBox(height: 8));
        widgets.add(OutlinedButton(
          onPressed:
              _busy ? null : () => _action('payment', {'status': 'paid'}),
          child: const Text('Tandai sudah dibayar'),
        ));
      }
    }
    if (['pending', 'accepted'].contains(_status) &&
        (_isCustomer || _isProvider)) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(TextButton(
        onPressed: _busy ? null : _cancel,
        child: Text('Batalkan order',
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ));
    }
    return widgets;
  }
}
