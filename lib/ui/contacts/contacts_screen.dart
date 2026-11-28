import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/call_service.dart';
import '../../state/auth_store.dart';
import '../calls/call_status_screen.dart';
import '../chat/chat_room_screen.dart';
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
  bool _busy = false;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AuthStore>().api.get('contacts');
      if (!mounted) return;
      setState(() {
        _error = null;
        _contacts = data is Map && data['data'] is List
            ? (data['data'] as List).whereType<Map>().map((item) {
                final account = item['account'] is Map
                    ? Map<String, dynamic>.from(item['account'] as Map)
                    : Map<String, dynamic>.from(item);
                account['contact_id'] = item['contact_id'];
                account['alias'] = item['alias'];
                return account;
              }).toList()
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

  bool _isOnline(Map<String, dynamic> account) {
    final type = account['type_code'];
    final business = type != null && type != 'personal';
    return business
        ? account['is_active'] == true
        : account['is_online'] == true;
  }

  List<Map<String, dynamic>> get _visibleContacts {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _contacts;
    return _contacts.where((account) {
      return '${account['alias'] ?? ''} '
              '${account['display_name'] ?? ''} '
              '${account['handle'] ?? ''}'
          .toLowerCase()
          .contains(query);
    }).toList();
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

  Future<void> _message(Map<String, dynamic> account) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = await context.read<AuthStore>().api.post('conversations', {
        'type': 'direct',
        'account_id': account['account_id'],
      });
      final conversation = data['conversation'];
      if (!mounted || conversation is! Map) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatRoomScreen(
            conversation: Map<String, dynamic>.from(conversation),
          ),
        ),
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _call(Map<String, dynamic> account, String kind) async {
    if (_busy) return;
    final accountId = account['account_id'];
    if (accountId is! int) return;
    setState(() => _busy = true);
    try {
      final result = await CallService.instance.startDirectCall(
        accountId: accountId,
        kind: kind,
      );
      if (result == null) {
        if (mounted) showErrorSnack(context, 'Panggilan tidak dapat dimulai.');
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CallStatusScreen(
            call: result['call'] as Map<String, dynamic>,
            jitsi: result['jitsi'] as Map<String, dynamic>,
          ),
        ),
      );
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteContact(Map<String, dynamic> account) async {
    final contactId = account['contact_id'];
    if (contactId is! int) return;
    final name =
        '${account['alias'] ?? account['display_name'] ?? 'kontak ini'}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus kontak?'),
        content: Text('$name akan dihapus dari daftar kontak.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<AuthStore>().api.delete('contacts/$contactId');
      if (mounted) await _load();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Widget _compactAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    );
  }

  @override
  Widget build(BuildContext context) {
    final token = context.read<AuthStore>().api.accessToken;
    final contacts = _visibleContacts;
    return Scaffold(
      appBar: AppBar(title: const Text('Kontak')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addContact,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Tambah'),
      ),
      body: ReadableWidth(
        maxWidth: 680,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Cari nama atau username…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Hapus pencarian',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
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
                        : contacts.isEmpty
                            ? ListView(
                                children: [
                                  const SizedBox(height: 90),
                                  const Icon(Icons.contacts_outlined, size: 48),
                                  const SizedBox(height: 12),
                                  Center(
                                    child: Text(_contacts.isEmpty
                                        ? 'Belum ada kontak'
                                        : 'Tidak ada kontak yang cocok'),
                                  ),
                                  const SizedBox(height: 4),
                                  Center(
                                    child: Text(
                                      _contacts.isEmpty
                                          ? 'Tambahkan kontak lewat username.'
                                          : 'Ubah filter atau tambah kontak baru.',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 8, 12, 96),
                                itemCount: contacts.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (context, index) {
                                  final account = contacts[index];
                                  final type = account['type_code'] as String?;
                                  final alias = '${account['alias'] ?? ''}';
                                  return Card(
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.only(
                                        left: 12,
                                        right: 4,
                                      ),
                                      onTap: () => _open(account),
                                      leading: AccountTypeAvatar(
                                        account: account,
                                        radius: 22,
                                        token: token,
                                        showStatusDot: _isOnline(account),
                                        backgroundColor: typeColor(type)
                                            .withValues(alpha: 0.15),
                                        foregroundColor: typeColor(type),
                                      ),
                                      title: Text(
                                        alias.isEmpty
                                            ? '${account['display_name'] ?? ''}'
                                            : alias,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      subtitle: Text(
                                        alias.isEmpty
                                            ? '@${account['handle'] ?? ''}'
                                            : '@${account['handle'] ?? ''} • '
                                                '${account['display_name'] ?? ''}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _compactAction(
                                            icon: Icons.chat_bubble_outline,
                                            tooltip: 'Kirim pesan',
                                            onPressed: _busy
                                                ? null
                                                : () => _message(account),
                                          ),
                                          _compactAction(
                                            icon: Icons.call_outlined,
                                            tooltip: 'Panggilan suara',
                                            onPressed: _busy
                                                ? null
                                                : () => _call(account, 'voice'),
                                          ),
                                          _compactAction(
                                            icon: Icons.videocam_outlined,
                                            tooltip: 'Panggilan video',
                                            onPressed: _busy
                                                ? null
                                                : () => _call(account, 'video'),
                                          ),
                                          PopupMenuButton<String>(
                                            padding: EdgeInsets.zero,
                                            iconSize: 20,
                                            tooltip: 'Menu kontak',
                                            onSelected: (action) {
                                              if (action == 'delete') {
                                                _deleteContact(account);
                                              }
                                            },
                                            itemBuilder: (_) => [
                                              const PopupMenuItem<String>(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.person_remove_alt_1,
                                                      size: 18,
                                                    ),
                                                    SizedBox(width: 10),
                                                    Text('Hapus kontak'),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
