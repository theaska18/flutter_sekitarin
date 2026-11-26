import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/location_service.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import '../orders/location_picker_screen.dart';

class BusinessLocationScreen extends StatefulWidget {
  const BusinessLocationScreen({
    super.key,
    required this.accountId,
  });

  final int accountId;

  @override
  State<BusinessLocationScreen> createState() => _BusinessLocationScreenState();
}

class _BusinessLocationScreenState extends State<BusinessLocationScreen> {
  final _addressController = TextEditingController();
  String _mode = 'fixed';
  LatLng? _location;
  bool _allowsPresence = false;
  bool _active = true;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AuthStore>().api.get(
            'accounts/${widget.accountId}',
          );
      final account = data is Map ? data['account'] : null;
      if (account is Map) {
        final location = account['location'];
        setState(() {
          _mode = '${account['location_mode'] ?? 'fixed'}';
          _allowsPresence = account['allows_presence'] == true;
          _active = account['is_active'] != false;
          _addressController.text = '${account['address'] ?? ''}';
          if (location is Map) {
            _location = LatLng(
              (location['lat'] as num).toDouble(),
              (location['lng'] as num).toDouble(),
            );
          }
        });
      }
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickLocation() async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initial: _location),
      ),
    );
    if (picked != null && mounted) setState(() => _location = picked);
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final auth = context.read<AuthStore>();
    try {
      if (_mode == 'realtime') {
        await auth.api.put('me/consents/location', {
          'granted': true,
          'policy_version': '1.0',
        });
      }
      final position = _mode == 'fixed'
          ? _location
          : (_location ?? await LocationService.current());
      final body = <String, dynamic>{
        'location_mode': _mode,
        'is_active': _active,
      };
      if (position != null) {
        body['location'] = {
          'lat': position.latitude,
          'lng': position.longitude,
          'source': _mode == 'realtime' ? 'gps' : 'manual',
          if (_addressController.text.trim().isNotEmpty)
            'address': _addressController.text.trim(),
        };
      } else if (_mode == 'fixed') {
        throw Exception('Pilih titik lokasi terlebih dahulu.');
      }
      if (_addressController.text.trim().isNotEmpty) {
        body['address'] = _addressController.text.trim();
      }
      await auth.api.patch('accounts/${widget.accountId}', body);
      await auth.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pengaturan lokasi disimpan.')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final realtime = _mode == 'realtime';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan usaha'),
        actions: [
          TextButton(
            onPressed: _loading || _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Simpan'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                  title: const Text('Akun aktif'),
                  subtitle: Text(
                    _active
                        ? 'Tampil sebagai buka/aktif di peta.'
                        : 'Tampil sebagai tutup/nonaktif di peta.',
                  ),
                  secondary: Icon(
                    _active ? Icons.storefront : Icons.storefront_outlined,
                    color: _active
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                ),
                const Divider(height: 24),
                Text(
                  'Pilih bagaimana akun usaha ini tampil di peta.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'fixed',
                      icon: Icon(Icons.push_pin_outlined),
                      label: Text('Freeze'),
                    ),
                    ButtonSegment(
                      value: 'realtime',
                      icon: Icon(Icons.gps_fixed),
                      label: Text('Realtime'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (value) =>
                      setState(() => _mode = value.first),
                ),
                const SizedBox(height: 16),
                if (realtime)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.gps_fixed,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              const Text('Realtime GPS',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _allowsPresence
                                ? 'Lokasi presence diperbarui tiap 15 detik selama aplikasi aktif, sehingga driver/layanan terlihat bergerak di peta.'
                                : 'Lokasi usaha diperbarui tiap 15 detik selama aplikasi aktif.',
                          ),
                          if (_location != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Posisi terakhir: ${_location!.latitude.toStringAsFixed(5)}, ${_location!.longitude.toStringAsFixed(5)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    child: ListTile(
                      onTap: _busy ? null : _pickLocation,
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
                const SizedBox(height: 14),
                TextField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Alamat tampilan (opsional)',
                    prefixIcon: Icon(Icons.home_outlined),
                  ),
                ),
              ],
            ),
    );
  }
}
