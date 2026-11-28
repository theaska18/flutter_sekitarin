import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import '../widgets/account_type_avatar.dart';

/// Picks a group member from saved contacts or by username search (including
/// accounts that are not in the contacts list yet). Returns the handle.
class AddMemberSheet extends StatefulWidget {
  const AddMemberSheet({super.key, this.excludeHandles = const {}});

  final Set<String> excludeHandles;

  @override
  State<AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<AddMemberSheet> {
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _accounts = [];
  bool _loading = true;
  bool _searching = false;
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AuthStore>().api.get('contacts');
      if (!mounted) return;
      setState(() {
        _contacts = data is Map && data['data'] is List
            ? (data['data'] as List)
                .whereType<Map>()
                .map((item) => item['account'] is Map
                    ? Map<String, dynamic>.from(item['account'] as Map)
                    : Map<String, dynamic>.from(item))
                .toList()
            : [];
      });
    } catch (_) {
      // Username search still works.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String value) {
    final query = value.trim();
    setState(() {
      _query = query;
      if (query.length < 2) _accounts = [];
    });
    _debounce?.cancel();
    if (query.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _searchAccounts();
    });
  }

  Future<void> _searchAccounts() async {
    final query = _query;
    if (query.length < 2) return;
    setState(() => _searching = true);
    try {
      final data = await context.read<AuthStore>().api.get(
        'accounts/search',
        query: {'q': query},
      );
      if (!mounted) return;
      setState(() {
        _accounts = data is Map && data['data'] is List
            ? (data['data'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
      });
    } catch (_) {
      if (mounted) setState(() => _accounts = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  bool _excluded(Map<String, dynamic> account) {
    final handle = '${account['handle'] ?? ''}'.toLowerCase();
    return widget.excludeHandles.contains(handle);
  }

  bool _matches(Map<String, dynamic> account, String query) {
    if (query.isEmpty) return true;
    return '${account['display_name'] ?? ''} ${account['handle'] ?? ''}'
        .toLowerCase()
        .contains(query);
  }

  Widget _tile(Map<String, dynamic> account, String label) {
    final token = context.read<AuthStore>().api.accessToken;
    return ListTile(
      onTap: () => Navigator.of(context).pop('${account['handle'] ?? ''}'),
      leading: AccountTypeAvatar(
        account: account,
        radius: 21,
        token: token,
        showStatusDot: true,
      ),
      title: Text(
        '${account['display_name'] ?? account['handle'] ?? ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.person_add_alt_1, size: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final available = media.size.height - media.padding.top - 80;
    final height = available.clamp(320.0, 620.0);
    final query = _query.toLowerCase();
    final contacts = _contacts
        .where((account) => !_excluded(account) && _matches(account, query))
        .toList();
    final accounts = _accounts
        .where((account) =>
            !_excluded(account) &&
            !contacts
                .any((item) => item['account_id'] == account['account_id']))
        .toList();
    final children = <Widget>[
      if (contacts.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Kontak', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        for (final account in contacts)
          _tile(account, '@${account['handle'] ?? ''}'),
      ],
      if (query.length >= 2) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Hasil pencarian username',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        for (final account in accounts)
          _tile(
            account,
            '@${account['handle'] ?? ''}'
            '${account['type_label'] != null ? ' • ${account['type_label']}' : ''}',
          ),
      ],
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, media.viewInsets.bottom + 16),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Tambah anggota',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              onChanged: _onQueryChanged,
              decoration: const InputDecoration(
                hintText: 'Cari kontak atau username…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            if (_loading || _searching)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (children.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'Belum ada kontak. Ketik username lengkap untuk menambah siapa pun.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: children,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
