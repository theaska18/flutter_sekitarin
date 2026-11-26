import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/location_service.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import '../orders/location_picker_screen.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _address = TextEditingController();
  List<Map<String, dynamic>> _types = [];
  String? _type;
  LatLng? _location;
  bool _realtime = false;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initial: _location),
      ),
    );
    if (picked != null && mounted) setState(() => _location = picked);
  }

  Future<void> _loadTypes() async {
    final current = await LocationService.current();
    if (current != null && mounted) {
      setState(() => _location = current);
    }
    try {
      final data = await context.read<AuthStore>().api.get('account-types');
      if (!mounted) return;
      setState(() {
        _types = data is Map && data['data'] is List
            ? (data['data'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .where((item) => item['type_code'] != 'personal')
                .toList()
            : [];
        _type = _types.isEmpty ? null : _types.first['type_code'] as String?;
      });
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _type == null) return;
    setState(() => _busy = true);
    final auth = context.read<AuthStore>();
    try {
      if (_realtime) {
        await auth.api.put('me/consents/location', {
          'granted': true,
          'policy_version': '1.0',
        });
      }
      final position = _location ?? await LocationService.current();
      final body = <String, dynamic>{
        'type_code': _type,
        'display_name': _name.text.trim(),
        'location_mode': _realtime ? 'realtime' : 'fixed',
      };
      if (_handle.text.trim().isNotEmpty) {
        body['handle'] = _handle.text.trim().toLowerCase();
      }
      if (_address.text.trim().isNotEmpty) {
        body['address'] = _address.text.trim();
      }
      body['location'] = position == null
          ? {'lat': -6.9147, 'lng': 107.6098}
          : {'lat': position.latitude, 'lng': position.longitude};
      final data = await auth.api.post('accounts', body);
      final account = data['account'];
      if (account is Map && account['account_id'] != null) {
        await auth.switchAccount(account['account_id'] as int);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Akun usaha baru')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'Tipe akun'),
                    items: [
                      for (final type in _types)
                        DropdownMenuItem(
                          value: '${type['type_code']}',
                          child: Text('${type['label']}'),
                        ),
                    ],
                    onChanged: (value) => setState(() => _type = value),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        const InputDecoration(labelText: 'Nama usaha/layanan'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Nama wajib diisi'
                            : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _handle,
                    decoration: const InputDecoration(
                      labelText: 'Handle (opsional)',
                      prefixText: '@',
                      helperText:
                          'Huruf kecil, angka, titik, atau garis bawah.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _address,
                    decoration: const InputDecoration(labelText: 'Alamat'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _realtime,
                    onChanged: (value) => setState(() => _realtime = value),
                    title: const Text('Realtime GPS'),
                    subtitle: const Text(
                      'Lokasi diperbarui otomatis selama aplikasi aktif. '
                      'Jika nonaktif, titik lokasi dibekukan (freeze).',
                    ),
                    secondary: const Icon(Icons.gps_fixed),
                  ),
                  if (_realtime)
                    Text(
                      'Izin lokasi akan diaktifkan untuk akun ini.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    Card(
                      child: ListTile(
                        onTap: _pickLocation,
                        leading: const Icon(Icons.place_outlined),
                        title: const Text('Titik lokasi tetap'),
                        subtitle: Text(
                          _location == null
                              ? 'Ketuk untuk memilih di peta'
                              : '${_location!.latitude.toStringAsFixed(5)}, ${_location!.longitude.toStringAsFixed(5)}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Jika izin GPS belum aktif dan Anda memilih freeze, pilih titik di peta.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Buat akun usaha'),
                  ),
                ],
              ),
            ),
    );
  }
}
