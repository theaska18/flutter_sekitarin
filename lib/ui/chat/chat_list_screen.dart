import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import '../common.dart';
import '../widgets/account_avatar.dart';
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

  @override
  void initState() {
    super.initState();
    chatListRefreshTick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    chatListRefreshTick.removeListener(_load);
    super.dispose();
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
                      return Card(
                        color: hasUnread
                            ? scheme.primaryContainer.withValues(alpha: 0.35)
                            : null,
                        child: ListTile(
                          onTap: () => _openConversation(item),
                          leading: item['type'] == 'group'
                              ? AccountAvatar(
                                  account: {
                                    'avatar_media_id': item['avatar_media_id'],
                                  },
                                  radius: 20,
                                  token:
                                      context.read<AuthStore>().api.accessToken,
                                  fallbackIcon: Icons.groups,
                                  backgroundColor: scheme.tertiaryContainer,
                                  foregroundColor: scheme.onTertiaryContainer,
                                )
                              : CircleAvatar(
                                  backgroundColor: scheme.primaryContainer,
                                  child: const Icon(Icons.person),
                                ),
                          title: Text(
                            peerName(item),
                            style: TextStyle(
                              fontWeight:
                                  hasUnread ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            messagePreview(
                              item['last_message'] is Map
                                  ? Map<String, dynamic>.from(
                                      item['last_message'] as Map)
                                  : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  hasUnread ? FontWeight.w600 : FontWeight.w400,
                              color: hasUnread ? scheme.onSurface : null,
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
