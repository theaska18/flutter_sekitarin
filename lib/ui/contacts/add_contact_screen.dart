import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import '../widgets/account_avatar.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _username = TextEditingController();
  List<Map<String, dynamic>> _results = [];
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
        _results = [];
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _results = [];
    });
    try {
      final data = await context.read<AuthStore>().api.get(
        'accounts/lookup',
        query: {'handle': handle},
      );
      if (!mounted) return;
      final raw = data is Map ? data['accounts'] : null;
      final results = raw is List
          ? raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _results = results;
        if (_results.isEmpty) _error = 'Akun tidak ditemukan.';
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(Map<String, dynamic> account) async {
    if (_adding) return;
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
          for (final account in _results) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    AccountAvatar(
                      account: account,
                      radius: 24,
                      token: context.read<AuthStore>().api.accessToken,
                      fallbackIcon: typeIcon(account['type_code'] as String?),
                      backgroundColor:
                          typeColor(account['type_code'] as String?)
                              .withValues(alpha: 0.15),
                      foregroundColor:
                          typeColor(account['type_code'] as String?),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${account['display_name'] ?? ''}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            '@${account['handle'] ?? ''} • ${account['type_label'] ?? ''}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: _adding ? null : () => _add(account),
                      child: const Text('Tambah'),
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
