import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/location_service.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import '../orders/location_picker_screen.dart';
import '../widgets/account_avatar.dart';

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
  final _nameController = TextEditingController();
  final _handleController = TextEditingController();
  int? _avatarMediaId;
  bool _avatarBusy = false;
  String _typeCode = 'warung';
  String _mode = 'fixed';
  LatLng? _location;
  bool _allowsPresence = false;
  bool _active = true;
  String? _activeUntil;
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
    _nameController.dispose();
    _handleController.dispose();
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
          _activeUntil = account['active_until'] as String?;
          _typeCode = '${account['type_code'] ?? 'warung'}';
          _avatarMediaId = account['avatar_media_id'] as int?;
          _nameController.text = '${account['display_name'] ?? ''}';
          _handleController.text = '${account['handle'] ?? ''}';
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

  Future<void> _pickAvatar() async {
    if (_avatarBusy) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (picked == null || !mounted) return;
    setState(() => _avatarBusy = true);
    try {
      final media = await context.read<AuthStore>().api.uploadFile(
            'media',
            filePath: picked.path,
            purpose: 'avatar',
          );
      final payload = media['media'];
      if (payload is Map && payload['media_id'] is int) {
        setState(() => _avatarMediaId = payload['media_id'] as int);
      }
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
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

  Future<void> _toggleActive(bool value) async {
    if (value && !_active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Aktifkan akun 24 jam?'),
          content: const Text(
            'Akun akan tampil aktif di peta selama 24 jam. Setelah itu akun '
            'mati otomatis dan harus diaktifkan kembali dari Setelan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Aktifkan'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _active = value);
  }

  Future<void> _save() async {
    if (_busy) return;
    final name = _nameController.text.trim();
    final handle = normalizeUsername(_handleController.text);
    if (name.isEmpty) {
      showErrorSnack(context, 'Nama usaha wajib diisi.');
      return;
    }
    if (!validUsername(handle)) {
      showErrorSnack(context, 'Username bisnis tidak valid.');
      return;
    }
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
        'display_name': name,
        'handle': handle,
        'avatar_media_id': _avatarMediaId,
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
        const SnackBar(content: Text('Pengaturan usaha disimpan.')),
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
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        AccountAvatar(
                          account: {'avatar_media_id': _avatarMediaId},
                          radius: 42,
                          token: context.read<AuthStore>().api.accessToken,
                          fallbackIcon: typeIcon(_typeCode),
                        ),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: _avatarBusy
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.photo_camera,
                                  size: 14, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _avatarBusy ? null : _pickAvatar,
                    child: const Text('Ganti foto usaha'),
                  ),
                ),
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nama usaha',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _handleController,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Username bisnis',
                    prefixText: '@',
                    prefixIcon: Icon(Icons.alternate_email),
                    helperText:
                        'Terpisah dari username personal dan tidak bisa dipakai login.',
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: _toggleActive,
                  title: const Text('Akun aktif'),
                  subtitle: Text(
                    _active
                        ? 'Aktif 24 jam${_activeUntil == null ? '' : ' hingga ${formatWhen(_activeUntil)}'}. '
                            'Setelah itu mati otomatis dan harus diaktifkan lagi dari Setelan.'
                        : 'Tampil sebagai tutup/nonaktif. Aktifkan untuk tampil 24 jam.',
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
