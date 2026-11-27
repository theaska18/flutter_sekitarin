import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ws_client.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import '../widgets/account_avatar.dart';
import '../widgets/group_avatar.dart';
import 'chat_room_screen.dart';
import 'new_chat_sheet.dart';

/// Bumped by the shell whenever the Chat tab is opened so the list reloads
/// unread counts after messages arrive in the background.
final ValueNotifier<int> chatListRefreshTick = ValueNotifier<int>(0);

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  final Map<int, Map<int, String>> _typingUsers = {};
  final Map<String, Timer> _typingTimers = {};
  final Set<int> _subscribed = {};
  StreamSubscription? _wsSub;
  late final WsClient _ws;

  @override
  void initState() {
    super.initState();
    chatListRefreshTick.addListener(_load);
    _ws = context.read<AuthStore>().ws;
    _wsSub = _ws.events.listen(_onWsEvent);
    _load();
  }

  @override
  void dispose() {
    chatListRefreshTick.removeListener(_load);
    _wsSub?.cancel();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    for (final id in _subscribed) {
      _ws.unsubscribe(id);
    }
    super.dispose();
  }

  void _syncSubscriptions() {
    final ids =
        _items.map((item) => item['conversation_id']).whereType<int>().toSet();
    for (final id in _subscribed.difference(ids).toList()) {
      _ws.unsubscribe(id);
      _subscribed.remove(id);
      _typingUsers.remove(id);
    }
    for (final id in ids.difference(_subscribed).toList()) {
      _ws.subscribe(id);
      _subscribed.add(id);
    }
  }

  void _clearTyping(int conversationId, [int? userId]) {
    if (userId == null) {
      _typingUsers.remove(conversationId);
      _typingTimers.removeWhere((key, timer) {
        if (!key.startsWith('$conversationId:')) return false;
        timer.cancel();
        return true;
      });
    } else {
      _typingUsers[conversationId]?.remove(userId);
      if (_typingUsers[conversationId]?.isEmpty == true) {
        _typingUsers.remove(conversationId);
      }
    }
    if (mounted) setState(() {});
  }

  void _onWsEvent(Map<String, dynamic> event) {
    final conversationId = event['conversation_id'];
    if (conversationId is! int) return;
    final name = '${event['event']}';
    if (name == 'message.created') {
      _clearTyping(conversationId);
      return;
    }
    if (name == 'conversation.updated') {
      _load();
      return;
    }
    if (name != 'typing') return;
    final payload = event['payload'];
    if (payload is! Map) return;
    final userId = payload['user_id'];
    if (userId is! int) return;
    if (userId == context.read<AuthStore>().user?['user_id']) return;
    final typing = payload['is_typing'] == true;
    final displayName = '${payload['display_name'] ?? 'Seseorang'}';
    final key = '$conversationId:$userId';
    _typingTimers[key]?.cancel();
    if (!typing) {
      _typingTimers.remove(key);
      _clearTyping(conversationId, userId);
      return;
    }
    _typingUsers.putIfAbsent(conversationId, () => {})[userId] = displayName;
    _typingTimers[key] = Timer(const Duration(seconds: 4), () {
      _typingTimers.remove(key);
      _clearTyping(conversationId, userId);
    });
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AuthStore>().api.get('conversations');
      if (!mounted) return;
      setState(() {
        _error = null;
        _items = data is Map && data['data'] is List
            ? (data['data'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
      });
      _syncSubscriptions();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openConversation(Map<String, dynamic> conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatRoomScreen(conversation: conversation),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _newChat() async {
    final created = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const NewChatSheet(),
    );
    if (created != null && mounted) {
      await _openConversation(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _newChat,
        tooltip: 'Chat baru',
        child: const Icon(Icons.add_comment_outlined),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null
            ? ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(child: Text(_error!)),
                ],
              )
            : _items.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 140),
                      Icon(Icons.chat_bubble_outline, size: 48),
                      SizedBox(height: 12),
                      Center(child: Text('Belum ada percakapan')),
                      SizedBox(height: 4),
                      Center(
                        child: Text(
                          'Mulai chat dari kontak atau peta.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final unread = item['unread_count'] ?? 0;
                      final hasUnread = unread is int && unread > 0;
                      final scheme = Theme.of(context).colorScheme;
                      final peer = item['peer'] is Map
                          ? Map<String, dynamic>.from(item['peer'] as Map)
                          : null;
                      final conversationId = item['conversation_id'] as int?;
                      final typing = conversationId == null
                          ? null
                          : _typingUsers[conversationId];
                      final typingLabel = typing == null || typing.isEmpty
                          ? null
                          : '${typing.values.join(', ')} sedang mengetik…';
                      return Card(
                        color: hasUnread
                            ? scheme.primaryContainer.withValues(alpha: 0.35)
                            : null,
                        child: ListTile(
                          onTap: () => _openConversation(item),
                          leading: item['type'] == 'group'
                              ? GroupAvatar(
                                  mediaId: item['avatar_media_id'] as int?,
                                  radius: 20,
                                  token:
                                      context.read<AuthStore>().api.accessToken,
                                )
                              : AccountAvatar(
                                  account: peer,
                                  radius: 20,
                                  token:
                                      context.read<AuthStore>().api.accessToken,
                                  backgroundColor: scheme.primaryContainer,
                                ),
                          title: Text(
                            peerName(item),
                            style: TextStyle(
                              fontWeight:
                                  hasUnread ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            typingLabel ??
                                messagePreview(
                                  item['last_message'] is Map
                                      ? Map<String, dynamic>.from(
                                          item['last_message'] as Map)
                                      : null,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: typingLabel != null || hasUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              fontStyle: typingLabel != null
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              color: typingLabel != null
                                  ? scheme.primary
                                  : (hasUnread ? scheme.onSurface : null),
                            ),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                timeAgo(item['last_message_at']),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              if (unread > 0) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$unread',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
