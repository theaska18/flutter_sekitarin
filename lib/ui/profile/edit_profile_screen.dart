import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import '../widgets/account_avatar.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _username;
  bool _busy = false;
  bool _avatarBusy = false;
  int? _avatarMediaId;

  Map<String, dynamic>? get _personalAccount {
    final accounts = context.read<AuthStore>().accounts;
    for (final account in accounts) {
      if (account['type_code'] == 'personal') return account;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthStore>();
    _name = TextEditingController(
      text: '${auth.user?['display_name'] ?? ''}',
    );
    final personal = auth.accounts
        .where((account) => account['type_code'] == 'personal')
        .toList();
    _username = TextEditingController(
      text: personal.isEmpty ? '' : '${personal.first['handle'] ?? ''}',
    );
    if (personal.isNotEmpty) {
      final avatar = personal.first['avatar_media_id'];
      _avatarMediaId = avatar is int ? avatar : null;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    final auth = context.read<AuthStore>();
    final api = auth.api;
    final personal = _personalAccount;
    try {
      final name = _name.text.trim();
      if (name != '${auth.user?['display_name'] ?? ''}') {
        await api.patch('me', {'display_name': name});
      }
      final username = normalizeUsername(_username.text);
      if (personal != null && username != '${personal['handle'] ?? ''}') {
        await api.patch('accounts/${personal['account_id']}', {
          'handle': username,
        });
      }
      await auth.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil diperbarui.')),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) showErrorSnack(context, error);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAvatar() async {
    final personal = _personalAccount;
    if (personal == null || _avatarBusy) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pilih dari galeri'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Ambil foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (picked == null || !mounted) return;
    setState(() => _avatarBusy = true);
    final auth = context.read<AuthStore>();
    try {
      final media = await auth.api.uploadFile(
        'media',
        filePath: picked.path,
        purpose: 'avatar',
      );
      final mediaData = media['media'];
      if (mediaData is! Map || mediaData['media_id'] is! int) {
        throw Exception('Upload foto gagal.');
      }
      final mediaId = mediaData['media_id'] as int;
      await auth.api.patch('accounts/${personal['account_id']}', {
        'avatar_media_id': mediaId,
      });
      await auth.refresh();
      if (!mounted) return;
      setState(() => _avatarMediaId = mediaId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto profil diperbarui.')),
      );
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _changePassword() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ChangePasswordSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profil'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: GestureDetector(
                onTap: _avatarBusy ? null : _pickAvatar,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    AccountAvatar(
                      account: {
                        'avatar_media_id': _avatarMediaId,
                      },
                      radius: 46,
                      token: auth.api.accessToken,
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: _avatarBusy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_camera,
                              size: 16, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _avatarBusy ? null : _pickAvatar,
                child: const Text('Ganti foto profil'),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama tampilan',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Nama wajib diisi'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _username,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixText: '@',
                prefixIcon: Icon(Icons.alternate_email),
                helperText:
                    'Username dipakai orang lain untuk menambah kontak.',
              ),
              validator: (value) =>
                  validUsername(value ?? '') ? null : 'Username tidak valid',
            ),
            const SizedBox(height: 14),
            TextFormField(
              enabled: false,
              initialValue: '${auth.user?['email'] ?? ''}',
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
                helperText: 'Email tidak dapat diubah dari aplikasi.',
              ),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: _changePassword,
              icon: const Icon(Icons.lock_reset),
              label: const Text('Ganti password'),
            ),
            const SizedBox(height: 10),
            Text(
              'Nama tampilan juga diperbarui pada akun personal.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    try {
      await context.read<AuthStore>().api.patch('me', {
        'current_password': _current.text,
        'password': _next.text,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password berhasil diganti.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Ganti password',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            TextFormField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password saat ini'),
              validator: (value) =>
                  (value == null || value.isEmpty) ? 'Wajib diisi' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password baru',
                helperText: 'Minimal 8 karakter',
              ),
              validator: (value) => (value == null || value.length < 8)
                  ? 'Minimal 8 karakter'
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Ulangi password baru',
              ),
              validator: (value) =>
                  value == _next.text ? null : 'Konfirmasi tidak sama',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Simpan password'),
            ),
          ],
        ),
      ),
    );
  }
}
