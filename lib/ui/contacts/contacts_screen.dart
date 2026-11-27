import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import '../common.dart';
import '../orders/provider_screen.dart';
import '../profile/account_profile_route.dart';
import '../widgets/account_type_avatar.dart';
import 'add_contact_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Map<String, dynamic>> _contacts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AuthStore>().api.get('contacts');
      if (!mounted) return;
      setState(() {
        _error = null;
        _contacts = data is Map && data['data'] is List
            ? (data['data'] as List)
                .whereType<Map>()
                .map((item) => item['account'] is Map
                    ? Map<String, dynamic>.from(item['account'] as Map)
                    : Map<String, dynamic>.from(item))
                .toList()
            : [];
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addContact() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AddContactScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _open(Map<String, dynamic> account) async {
    final accountId = account['account_id'];
    if (accountId is! int) return;
    if (account['type_code'] == 'personal') {
      await openAccountProfile(
        context,
        accountId,
        initialName: '${account['display_name'] ?? ''}',
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProviderScreen(
            accountId: accountId,
            initialName: '${account['display_name'] ?? ''}',
          ),
        ),
      );
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final token = context.read<AuthStore>().api.accessToken;
    return Scaffold(
      appBar: AppBar(title: const Text('Kontak')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addContact,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Tambah'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      const SizedBox(height: 140),
                      Center(child: Text(_error!)),
                    ],
                  )
                : _contacts.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 140),
                          Icon(Icons.contacts_outlined, size: 48),
                          SizedBox(height: 12),
                          Center(child: Text('Belum ada kontak')),
                          SizedBox(height: 4),
                          Center(
                            child: Text(
                              'Tambahkan kontak lewat username.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                        itemCount: _contacts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final account = _contacts[index];
                          final type = account['type_code'] as String?;
                          return Card(
                            child: ListTile(
                              onTap: () => _open(account),
                              leading: AccountTypeAvatar(
                                account: account,
                                radius: 22,
                                token: token,
                                showStatusDot: true,
                                backgroundColor:
                                    typeColor(type).withValues(alpha: 0.15),
                                foregroundColor: typeColor(type),
                              ),
                              title: Text(
                                '${account['display_name'] ?? ''}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '@${account['handle'] ?? ''}'
                                '${account['type_label'] != null ? ' • ${account['type_label']}' : ''}',
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
