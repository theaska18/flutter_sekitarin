import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/call_service.dart';
import '../../state/auth_store.dart';
import '../calls/call_status_screen.dart';
import '../common.dart';
import '../widgets/account_type_avatar.dart';
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
  bool _calling = false;
  bool _showingSearch = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool _isOnline(Map<String, dynamic> account) {
    final type = account['type_code'];
    final business = type != null && type != 'personal';
    return business
        ? account['is_active'] == true
        : account['is_online'] == true;
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

  void _onQueryChanged(String value) {
    final query = value.trim();
    _debounce?.cancel();
    if (query.isEmpty) {
      setState(() => _showingSearch = false);
      _runSearch('');
      return;
    }
    if (query.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(query);
    });
  }

  Future<void> _runSearch(String query) async {
    if (query.trim().length < 2) {
      setState(() {
        _searching = false;
        _showingSearch = false;
      });
      await _loadContacts();
      return;
    }
    setState(() {
      _searching = true;
      _showingSearch = true;
    });
    try {
      final auth = context.read<AuthStore>();
      final data = await auth.api.get(
        'accounts/search',
        query: {'q': query.trim()},
      );
      if (!mounted) return;
      final ownIds = auth.accounts
          .map((account) => account['account_id'])
          .whereType<int>()
          .toSet();
      setState(() {
        // Username search works for any active account, not only contacts,
        // so a conversation can be started with someone new.
        _items = data is Map && data['data'] is List
            ? (data['data'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .where((item) => !ownIds.contains(item['account_id']))
                .toList()
            : [];
      });
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _call(Map<String, dynamic> item, String kind) async {
    if (_calling) return;
    final account = item['account'] is Map
        ? Map<String, dynamic>.from(item['account'] as Map)
        : item;
    final accountId = account['account_id'];
    if (accountId is! int) return;
    FocusScope.of(context).unfocus();
    setState(() => _calling = true);
    try {
      final api = context.read<AuthStore>().api;
      // The call API requires a saved contact or an existing conversation.
      // Starting the direct thread first lets a username search call anyone.
      final data = await api.post('conversations', {
        'type': 'direct',
        'account_id': accountId,
      });
      final conversation = data['conversation'];
      final conversationId =
          conversation is Map && conversation['conversation_id'] is int
              ? conversation['conversation_id'] as int
              : null;
      final result = await CallService.instance.startDirectCall(
        accountId: accountId,
        kind: kind,
        conversationId: conversationId,
      );
      if (result == null) {
        if (mounted) showErrorSnack(context, 'Panggilan tidak dapat dimulai.');
        return;
      }
      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).push(
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
      if (mounted) setState(() => _calling = false);
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
    final media = MediaQuery.of(context);
    final bottom = media.viewInsets.bottom;
    // Keep the sheet fully on screen when the keyboard is open so the search
    // results are not pushed below it.
    final available = media.size.height - media.padding.top - bottom - 24;
    final height = available.clamp(280.0, 480.0);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 16),
      child: SizedBox(
        height: height,
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
              onChanged: _onQueryChanged,
              onSubmitted: (value) {
                FocusScope.of(context).unfocus();
                _runSearch(value);
              },
            ),
            const SizedBox(height: 12),
            if (_loading || _searching)
              const Center(child: CircularProgressIndicator())
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(
                    _showingSearch
                        ? 'Username tidak ditemukan.\nCoba tulis username lengkap.'
                        : 'Belum ada kontak.\nCari username siapa pun lewat kolom di atas.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final account = item['account'] is Map
                        ? Map<String, dynamic>.from(item['account'] as Map)
                        : item;
                    final type = account['type_code'] as String?;
                    final online = _isOnline(account);
                    return ListTile(
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        _start(item);
                      },
                      leading: AccountTypeAvatar(
                        account: account,
                        radius: 22,
                        token: context.read<AuthStore>().api.accessToken,
                        showStatusDot: online,
                        backgroundColor:
                            typeColor(type).withValues(alpha: 0.15),
                        foregroundColor: typeColor(type),
                      ),
                      title: Text(
                        '${item['alias'] ?? account['display_name'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '@${account['handle'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Panggilan suara',
                            icon: const Icon(Icons.call_outlined, size: 20),
                            onPressed:
                                _calling ? null : () => _call(item, 'voice'),
                          ),
                          IconButton(
                            tooltip: 'Panggilan video',
                            icon: const Icon(Icons.videocam_outlined, size: 22),
                            onPressed:
                                _calling ? null : () => _call(item, 'video'),
                          ),
                        ],
                      ),
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
