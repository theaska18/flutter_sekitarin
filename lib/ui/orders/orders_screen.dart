import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import '../common.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.initialRole = 'customer'});

  final String initialRole;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late String _role = widget.initialRole;
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<AuthStore>().api.get(
        'orders',
        query: {'role': _role, 'limit': '30'},
      );
      if (!mounted) return;
      setState(() {
        _error = null;
        _orders = data is Map && data['data'] is List
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

  Future<void> _open(Map<String, dynamic> order) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailScreen(
          orderId: order['order_id'] as int,
          initial: order,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    final providerAccount = auth.activeAccount;
    return Scaffold(
      appBar: AppBar(title: const Text('Pesanan')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'customer',
                  icon: Icon(Icons.person_outline),
                  label: Text('Saya pesan'),
                ),
                ButtonSegment(
                  value: 'provider',
                  icon: Icon(Icons.storefront),
                  label: Text('Pesanan masuk'),
                ),
              ],
              selected: {_role},
              onSelectionChanged: (value) {
                setState(() => _role = value.first);
                _load();
              },
            ),
          ),
          if (_role == 'provider')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.store, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      providerAccount == null
                          ? 'Pilih akun terlebih dahulu.'
                          : 'Akun aktif: ${providerAccount['display_name']}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _error != null
                        ? ListView(
                            children: [
                              const SizedBox(height: 120),
                              Center(child: Text(_error!)),
                            ],
                          )
                        : _orders.isEmpty
                            ? ListView(
                                children: const [
                                  SizedBox(height: 140),
                                  Icon(Icons.receipt_long_outlined, size: 48),
                                  SizedBox(height: 12),
                                  Center(child: Text('Belum ada pesanan')),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(12),
                                itemCount: _orders.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final order = _orders[index];
                                  final counterpart = _role == 'customer'
                                      ? order['provider']
                                      : order['customer'];
                                  final name = counterpart is Map
                                      ? '${counterpart['display_name'] ?? ''}'
                                      : '';
                                  final status = '${order['status'] ?? ''}';
                                  return Card(
                                    child: ListTile(
                                      onTap: () => _open(order),
                                      leading: CircleAvatar(
                                        backgroundColor:
                                            orderStatusColor(status)
                                                .withValues(alpha: 0.15),
                                        child: Icon(
                                          order['type'] == 'ride'
                                              ? Icons.two_wheeler
                                              : order['type'] == 'food'
                                                  ? Icons.fastfood
                                                  : Icons.handyman,
                                          color: orderStatusColor(status),
                                        ),
                                      ),
                                      title: Text('${order['code'] ?? ''}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700)),
                                      subtitle: Text(
                                          '$name • ${orderTypeLabel(order['type'] as String?)}'),
                                      trailing: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(rupiah(
                                              (order['total'] as num?) ?? 0)),
                                          const SizedBox(height: 4),
                                          Text(
                                            orderStatusLabel(status),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: orderStatusColor(status),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
          ),
        ],
      ),
    );
  }
}
