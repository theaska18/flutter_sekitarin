import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_exception.dart';
import '../../state/auth_store.dart';
import '../common.dart';

class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  final _title = TextEditingController();
  final _username = TextEditingController();
  final Map<int, Map<String, dynamic>> _selected = {};
  List<Map<String, dynamic>> _contacts = [];
  bool _loading = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _title.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      final data = await context.read<AuthStore>().api.get('contacts');
      if (!mounted) return;
      setState(() {
        _contacts = data is Map && data['data'] is List
            ? (data['data'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
      });
    } catch (_) {
      // Search by username still works.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchUsername() async {
    final handle = normalizeUsername(_username.text);
    if (!validUsername(handle)) {
      showErrorSnack(context, 'Username tidak valid.');
      return;
    }
    try {
      final data = await context.read<AuthStore>().api.get(
        'accounts/lookup',
        query: {'handle': handle},
      );
      final account = data is Map ? data['account'] : null;
      if (account is! Map) return;
      final map = Map<String, dynamic>.from(account);
      final id = map['account_id'] as int;
      if (_selected.containsKey(id)) {
        if (mounted) showErrorSnack(context, 'Akun sudah dipilih.');
        return;
      }
      setState(() {
        _selected[id] = map;
        _username.clear();
      });
    } on ApiException catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showErrorSnack(context, 'Judul grup wajib diisi.');
      return;
    }
    if (_selected.isEmpty) {
      showErrorSnack(context, 'Pilih minimal satu anggota.');
      return;
    }
    setState(() => _creating = true);
    try {
      final data = await context.read<AuthStore>().api.post('conversations', {
        'type': 'group',
        'title': title,
        'member_account_ids': _selected.keys.toList(),
      });
      final conversation = data['conversation'];
      if (!mounted) return;
      if (conversation is Map) {
        Navigator.of(context).pop(Map<String, dynamic>.from(conversation));
      }
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = <Map<String, dynamic>>[];
    final seen = <int>{};
    for (final item in _contacts) {
      final account = item['account'] is Map
          ? Map<String, dynamic>.from(item['account'] as Map)
          : item;
      final id = account['account_id'];
      if (id is int && seen.add(id)) contacts.add(account);
    }
    for (final account in _selected.values) {
      final id = account['account_id'];
      if (id is int && seen.add(id)) contacts.add(account);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buat grup'),
        actions: [
          TextButton(
            onPressed: _creating ? null : _create,
            child: _creating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Buat'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nama grup',
                    prefixIcon: Icon(Icons.groups),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _username,
                        decoration: const InputDecoration(
                          labelText: 'Tambah lewat username',
                          prefixText: '@',
                        ),
                        onSubmitted: (_) => _searchUsername(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _searchUsername,
                      icon: const Icon(Icons.person_add_alt_1),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '${_selected.length} anggota dipilih',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                if (contacts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('Belum ada kontak. Tambah lewat username.'),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final account in contacts)
                          CheckboxListTile(
                            value: _selected.containsKey(account['account_id']),
                            onChanged: (checked) {
                              final id = account['account_id'] as int;
                              setState(() {
                                if (checked == true) {
                                  _selected[id] = account;
                                } else {
                                  _selected.remove(id);
                                }
                              });
                            },
                            secondary: CircleAvatar(
                              backgroundColor:
                                  typeColor(account['type_code'] as String?)
                                      .withValues(alpha: 0.15),
                              child: Icon(
                                typeIcon(account['type_code'] as String?),
                                color:
                                    typeColor(account['type_code'] as String?),
                              ),
                            ),
                            title: Text('${account['display_name'] ?? ''}'),
                            subtitle: Text('@${account['handle'] ?? ''}'),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
