import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../state/auth_store.dart';
import '../common.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _username = TextEditingController();
  Map<String, dynamic>? _result;
  bool _searching = false;
  bool _adding = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final handle = normalizeUsername(_username.text);
    if (!validUsername(handle)) {
      setState(() {
        _error = 'Username tidak valid.';
        _result = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _result = null;
    });
    try {
      final data = await context.read<AuthStore>().api.get(
        'accounts/lookup',
        query: {'handle': handle},
      );
      if (!mounted) return;
      final account = data is Map ? data['account'] : null;
      setState(() {
        _result = account is Map ? Map<String, dynamic>.from(account) : null;
        if (_result == null) _error = 'Akun tidak ditemukan.';
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add() async {
    final account = _result;
    if (account == null || _adding) return;
    setState(() => _adding = true);
    try {
      await context.read<AuthStore>().api.post('contacts', {
        'account_id': account['account_id'],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${account['display_name']} ditambahkan ke kontak.')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = _result;
    final type = account?['type_code'] as String?;
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah kontak')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Cari akun menggunakan username, misalnya @aska.development.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _username,
            autocorrect: false,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixText: '@',
              prefixIcon: Icon(Icons.alternate_email),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _searching ? null : _search,
            icon: _searching
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: const Text('Cari akun'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (account != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: typeColor(type).withValues(alpha: 0.15),
                      child: Icon(typeIcon(type),
                          size: 30, color: typeColor(type)),
                    ),
                    const SizedBox(height: 10),
                    Text('${account['display_name'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    Text('@${account['handle'] ?? ''}'),
                    Text('${account['type_label'] ?? ''}',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _adding ? null : _add,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: Text(_adding ? 'Menambahkan…' : 'Tambah kontak'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
