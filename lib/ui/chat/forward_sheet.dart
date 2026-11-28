import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import '../common.dart';
import '../widgets/account_type_avatar.dart';
import '../widgets/group_avatar.dart';

/// Picks a conversation to forward a message to: recent chats, saved contacts,
/// or any account found by username. Returns the target conversation.
class ForwardSheet extends StatefulWidget {
  const ForwardSheet({super.key});

  @override
  State<ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<ForwardSheet> {
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _accounts = [];
  bool _loading = true;
  bool _searching = false;
  bool _busy = false;
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
    final api = context.read<AuthStore>().api;
    try {
      final results = await Future.wait([
        api.get('conversations'),
        api.get('contacts'),
      ]);
      if (!mounted) return;
      setState(() {
        _conversations = results[0] is Map && results[0]['data'] is List
            ? (results[0]['data'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
        _contacts = results[1] is Map && results[1]['data'] is List
            ? (results[1]['data'] as List)
                .whereType<Map>()
                .map((item) => item['account'] is Map
                    ? Map<String, dynamic>.from(item['account'] as Map)
                    : Map<String, dynamic>.from(item))
                .toList()
            : [];
      });
    } catch (_) {
      // Search by username still works.
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
    _debounce =
        Timer(const Duration(milliseconds: 350), () => _searchAccounts());
  }

  Future<void> _searchAccounts() async {
    final query = _query;
    if (query.length < 2) return;
    setState(() => _searching = true);
    try {
      final auth = context.read<AuthStore>();
      final data = await auth.api.get('accounts/search', query: {'q': query});
      if (!mounted) return;
      final ownIds = auth.accounts
          .map((account) => account['account_id'])
          .whereType<int>()
          .toSet();
      setState(() {
        _accounts = data is Map && data['data'] is List
            ? (data['data'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .where((item) => !ownIds.contains(item['account_id']))
                .toList()
            : [];
      });
    } catch (_) {
      if (mounted) setState(() => _accounts = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pickConversation(Map<String, dynamic> conversation) async {
    if (_busy) return;
    setState(() => _busy = true);
    if (mounted) Navigator.of(context).pop(conversation);
  }

  Future<void> _pickAccount(Map<String, dynamic> account) async {
    if (_busy) return;
    final accountId = account['account_id'];
    if (accountId is! int) return;
    setState(() => _busy = true);
    try {
      final data = await context.read<AuthStore>().api.post('conversations', {
        'type': 'direct',
        'account_id': accountId,
      });
      final conversation = data['conversation'];
      if (!mounted) return;
      Navigator.of(context).pop(
        conversation is Map ? Map<String, dynamic>.from(conversation) : null,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        showErrorSnack(context, error);
      }
    }
  }

  bool _matchesConversation(Map<String, dynamic> item, String query) {
    if (query.isEmpty) return true;
    final peer = item['peer'];
    final title = item['title'];
    final haystack = [
      peerName(item),
      if (peer is Map) '${peer['handle'] ?? ''}',
      if (title != null) '$title',
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }

  bool _matchesAccount(Map<String, dynamic> account, String query) {
    if (query.isEmpty) return true;
    return '${account['display_name'] ?? ''} ${account['handle'] ?? ''}'
        .toLowerCase()
        .contains(query);
  }

  Widget _accountTile(Map<String, dynamic> account, {String? label}) {
    final token = context.read<AuthStore>().api.accessToken;
    return ListTile(
      onTap: _busy ? null : () => _pickAccount(account),
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
      subtitle: Text(
        label ?? '@${account['handle'] ?? ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _conversationTile(Map<String, dynamic> item) {
    final token = context.read<AuthStore>().api.accessToken;
    final isGroup = item['type'] == 'group';
    final peer = item['peer'] is Map
        ? Map<String, dynamic>.from(item['peer'] as Map)
        : null;
    return ListTile(
      onTap: _busy ? null : () => _pickConversation(item),
      leading: isGroup
          ? GroupAvatar(
              mediaId: item['avatar_media_id'] as int?,
              radius: 21,
              token: token,
            )
          : AccountTypeAvatar(
              account: peer ??
                  (item['my_account'] is Map
                      ? Map<String, dynamic>.from(item['my_account'] as Map)
                      : null),
              radius: 21,
              token: token,
              showStatusDot: true,
            ),
      title: Text(
        peerName(item),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        isGroup ? 'Grup' : 'Chat',
        maxLines: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final available = media.size.height - media.padding.top - 80;
    final height = available.clamp(320.0, 640.0);
    final query = _query.toLowerCase();
    final conversations = _conversations
        .where((item) => _matchesConversation(item, query))
        .toList();
    final contacts =
        _contacts.where((account) => _matchesAccount(account, query)).toList();
    final children = <Widget>[
      if (conversations.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Chat terakhir',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        for (final item in conversations) _conversationTile(item),
      ],
      if (contacts.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Kontak', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        for (final account in contacts) _accountTile(account),
      ],
      if (_query.length >= 2 && _accounts.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child:
              Text('Akun lain', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        for (final account in _accounts)
          if (!contacts
              .any((item) => item['account_id'] == account['account_id']))
            _accountTile(account),
      ],
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        media.viewInsets.bottom + 16,
      ),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Teruskan ke',
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
                hintText: 'Cari chat, kontak, atau username…',
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
                    'Tidak ada tujuan. Cari username lengkap untuk mengirim ke akun baru.',
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
