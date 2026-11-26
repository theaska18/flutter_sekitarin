import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/location_service.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import 'location_picker_screen.dart';
import 'order_detail_screen.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({
    super.key,
    required this.account,
    required this.services,
  });

  final Map<String, dynamic> account;
  final List<Map<String, dynamic>> services;

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _notes = TextEditingController();
  final _address = TextEditingController();
  final Map<int, int> _quantity = {};
  String _payment = 'cash';
  LatLng? _pickup;
  LatLng? _dropoff;
  bool _busy = false;

  String get _type =>
      orderTypeForAccount(widget.account['type_code'] as String?);

  List<Map<String, dynamic>> get _available {
    final expected = _type == 'food' ? 'product' : _type;
    return widget.services
        .where((service) => service['kind'] == expected)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    for (final service in _available) {
      _quantity[service['service_id'] as int] = 1;
    }
    if (_type == 'ride') {
      _loadPickup();
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _loadPickup() async {
    final position = await LocationService.current();
    if (position != null && mounted) {
      setState(() => _pickup = position);
    }
  }

  num get _total {
    var total = 0.0;
    for (final service in _available) {
      final id = service['service_id'] as int;
      final qty = _quantity[id] ?? 0;
      total += ((service['price'] as num?)?.toDouble() ?? 0) * qty;
    }
    return total;
  }

  Future<void> _pickDropoff() async {
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initial: _pickup),
      ),
    );
    if (point != null && mounted) setState(() => _dropoff = point);
  }

  Future<void> _submit() async {
    final items = <Map<String, dynamic>>[];
    for (final service in _available) {
      final id = service['service_id'] as int;
      final qty = _quantity[id] ?? 0;
      if (qty > 0) {
        items.add({'service_id': id, 'quantity': qty});
      }
    }
    if (items.isEmpty) {
      showErrorSnack(context, 'Pilih minimal satu layanan.');
      return;
    }
    if (_type == 'ride' &&
        (items.length != 1 || items.first['quantity'] != 1)) {
      showErrorSnack(context, 'Pilih satu layanan ride.');
      return;
    }
    if (_type == 'ride' && _dropoff == null) {
      showErrorSnack(context, 'Pilih titik tujuan.');
      return;
    }

    setState(() => _busy = true);
    final api = context.read<AuthStore>().api;
    try {
      LatLng? pickup = _pickup;
      LatLng? delivery;
      if (_type == 'ride' && pickup == null) {
        pickup = await LocationService.current();
      }
      if (_type == 'food') {
        delivery = await LocationService.current();
      }
      final body = <String, dynamic>{
        'type': _type,
        'provider_account_id': widget.account['account_id'],
        'items': items,
        'payment_method': _payment,
      };
      if (_notes.text.trim().isNotEmpty) body['notes'] = _notes.text.trim();
      if (_type == 'food') {
        if (_address.text.trim().isNotEmpty) {
          body['delivery_address'] = _address.text.trim();
        }
        if (delivery != null) {
          body['delivery'] = {
            'lat': delivery.latitude,
            'lng': delivery.longitude,
          };
        }
      }
      if (_type == 'ride') {
        if (pickup == null) {
          throw Exception('Lokasi pickup tidak tersedia. Aktifkan GPS.');
        }
        body['pickup'] = {'lat': pickup.latitude, 'lng': pickup.longitude};
        body['dropoff'] = {
          'lat': _dropoff!.latitude,
          'lng': _dropoff!.longitude,
        };
        if (_address.text.trim().isNotEmpty) {
          body['dropoff_address'] = _address.text.trim();
        }
      }
      final data = await api.post('orders', body);
      final order = data['order'];
      if (!mounted) return;
      if (order is Map) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(
              orderId: order['order_id'] as int,
              initial: Map<String, dynamic>.from(order),
            ),
          ),
        );
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return Scaffold(
      appBar: AppBar(title: Text('Pesan • ${account['display_name']}')),
      body: _available.isEmpty
          ? const Center(
              child: Text('Belum ada layanan yang bisa dipesan.'),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(orderTypeLabel(_type),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Card(
                  child: Column(
                    children: [
                      for (final service in _available)
                        _ServiceRow(
                          service: service,
                          quantity: _quantity[service['service_id']] ?? 0,
                          onChanged: (value) => setState(
                            () =>
                                _quantity[service['service_id'] as int] = value,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_type == 'food') ...[
                  TextField(
                    controller: _address,
                    decoration: const InputDecoration(
                      labelText: 'Alamat pengantaran',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Titik antar memakai GPS saat ini bila tersedia.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_type == 'ride') ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.my_location),
                      title: const Text('Titik jemput'),
                      subtitle: Text(_pickup == null
                          ? 'Menggunakan GPS saat ini'
                          : '${_pickup!.latitude.toStringAsFixed(5)}, ${_pickup!.longitude.toStringAsFixed(5)}'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      onTap: _pickDropoff,
                      leading: const Icon(Icons.place),
                      title: const Text('Titik tujuan'),
                      subtitle: Text(_dropoff == null
                          ? 'Ketuk untuk memilih di peta'
                          : '${_dropoff!.latitude.toStringAsFixed(5)}, ${_dropoff!.longitude.toStringAsFixed(5)}'),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _address,
                    decoration: const InputDecoration(
                      labelText: 'Alamat tujuan (opsional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Catatan untuk penyedia',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _payment,
                  decoration: const InputDecoration(
                    labelText: 'Pembayaran',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Tunai')),
                    DropdownMenuItem(
                        value: 'transfer', child: Text('Transfer')),
                  ],
                  onChanged: (value) => setState(() => _payment = value!),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    Text(rupiah(_total),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Buat order'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pembayaran tunai/transfer dikonfirmasi manual oleh penyedia.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.service,
    required this.quantity,
    required this.onChanged,
  });

  final Map<String, dynamic> service;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${service['name'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  rupiah((service['price'] as num?) ?? 0),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: quantity <= 0 ? null : () => onChanged(quantity - 1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('$quantity'),
          IconButton(
            onPressed: () => onChanged(quantity + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}
