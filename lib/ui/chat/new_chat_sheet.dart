import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import '../common.dart';
import '../widgets/account_avatar.dart';
import 'group_create_screen.dart';

class NewChatSheet extends StatefulWidget {
  const NewChatSheet({super.key});

  @override
  State<NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<NewChatSheet> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      final data = await context.read<AuthStore>().api.get('contacts');
      if (!mounted) return;
      setState(() {
        _items = data is Map && data['data'] is List
            ? (data['data'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
      });
    } catch (_) {
      // A search can still be used when contacts fail.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runSearch(String query) async {
    if (query.trim().length < 2) {
      setState(() => _searching = false);
      await _loadContacts();
      return;
    }
    setState(() => _searching = true);
    try {
      final data = await context.read<AuthStore>().api.get(
        'accounts/search',
        query: {'q': query.trim()},
      );
      if (!mounted) return;
      setState(() {
        _items = data is Map && data['data'] is List
            ? (data['data'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
      });
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _start(Map<String, dynamic> item) async {
    final account = item['account'] is Map
        ? Map<String, dynamic>.from(item['account'] as Map)
        : item;
    final accountId = account['account_id'];
    if (accountId == null) return;
    try {
      final data = await context.read<AuthStore>().api.post('conversations', {
        'type': 'direct',
        'account_id': accountId,
      });
      final conversation = data['conversation'];
      if (!mounted) return;
      if (conversation is Map) {
        Navigator.of(context).pop(Map<String, dynamic>.from(conversation));
      }
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 16),
      child: SizedBox(
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Chat baru',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final conversation =
                        await Navigator.of(context).push<Map<String, dynamic>>(
                      MaterialPageRoute(
                        builder: (_) => const GroupCreateScreen(),
                      ),
                    );
                    if (conversation != null && context.mounted) {
                      Navigator.of(context).pop(conversation);
                    }
                  },
                  icon: const Icon(Icons.group_add_outlined, size: 18),
                  label: const Text('Buat grup'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Cari kontak atau akun…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                if (value.trim().isEmpty) {
                  _runSearch('');
                }
              },
              onSubmitted: _runSearch,
            ),
            const SizedBox(height: 12),
            if (_loading || _searching)
              const Center(child: CircularProgressIndicator())
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(
                    'Belum ada kontak.\nCari akun lewat kolom di atas.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final account = item['account'] is Map
                        ? Map<String, dynamic>.from(item['account'] as Map)
                        : item;
                    final type = account['type_code'] as String?;
                    return ListTile(
                      onTap: () => _start(item),
                      leading: AccountAvatar(
                        account: account,
                        radius: 22,
                        token: context.read<AuthStore>().api.accessToken,
                        fallbackIcon: typeIcon(type),
                        backgroundColor:
                            typeColor(type).withValues(alpha: 0.15),
                        foregroundColor: typeColor(type),
                      ),
                      title: Text(
                        '${item['alias'] ?? account['display_name'] ?? ''}',
                      ),
                      subtitle: Text('@${account['handle'] ?? ''}'),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
