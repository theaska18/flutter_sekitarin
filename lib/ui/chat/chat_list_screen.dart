import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ws_client.dart';
import '../../services/message_sound.dart';
import '../../services/call_service.dart';
import '../../state/auth_store.dart';
import '../../state/chat_cache.dart';
import '../../state/chat_presence.dart';
import '../common.dart';
import '../widgets/account_type_avatar.dart';
import '../widgets/group_avatar.dart';
import 'chat_room_screen.dart';
import 'new_chat_sheet.dart';

/// Bumped by the shell whenever the Chat tab is opened so the list reloads
/// unread counts after messages arrive in the background.
final ValueNotifier<int> chatListRefreshTick = ValueNotifier<int>(0);

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({
    super.key,
    this.active = true,
    this.onOpenConversation,
    this.selectedConversationId,
  });

  final bool active;

  /// When set (tablet two-pane layout) the room is shown beside the list
  /// instead of being pushed as a new route.
  final void Function(Map<String, dynamic> conversation)? onOpenConversation;

  /// Conversation currently shown in the right-hand pane (highlighted row).
  final int? selectedConversationId;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  final Map<int, Map<int, String>> _typingUsers = {};
  final Map<String, Timer> _typingTimers = {};
  final Set<int> _subscribed = {};
  final Set<int> _contactAccountIds = {};
  StreamSubscription? _wsSub;
  Timer? _reloadDebounce;
  Timer? _presencePoll;
  bool _paused = false;
  late final WsClient _ws;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    chatListRefreshTick.addListener(_load);
    _ws = context.read<AuthStore>().ws;
    _wsSub = _ws.events.listen(_onWsEvent);
    CallService.instance.addListener(_onCallStateChanged);
    if (widget.active) _startPresencePoll();
    _load();
  }

  void _onCallStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ChatListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _load();
      _startPresencePoll();
    } else {
      _presencePoll?.cancel();
      _presencePoll = null;
    }
  }

  void _startPresencePoll() {
    if (_paused) return;
    _presencePoll ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => _load(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _paused = true;
      _presencePoll?.cancel();
      _presencePoll = null;
    } else if (state == AppLifecycleState.resumed) {
      _paused = false;
      if (widget.active) {
        _load();
        _startPresencePoll();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    chatListRefreshTick.removeListener(_load);
    CallService.instance.removeListener(_onCallStateChanged);
    _wsSub?.cancel();
    _reloadDebounce?.cancel();
    _presencePoll?.cancel();
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
      if (_paused) return;
      if (ChatPresence.activeConversationId != conversationId) {
        MessageSound.play();
      }
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 350), _load);
      return;
    }
    if (name == 'conversation.updated') {
      if (!_paused) _load();
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
      final api = context.read<AuthStore>().api;
      final data = await api.get('conversations');
      final contacts = <int>{};
      try {
        final contactData = await api.get('contacts');
        if (contactData is Map && contactData['data'] is List) {
          for (final item in contactData['data'] as List) {
            if (item is Map && item['account_id'] is int) {
              contacts.add(item['account_id'] as int);
            }
          }
        }
      } catch (_) {
        // Contact status is best-effort.
      }
      if (!mounted) return;
      setState(() {
        _error = null;
        _contactAccountIds
          ..clear()
          ..addAll(contacts);
        _items = data is Map && data['data'] is List
            ? (data['data'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
      });
      _syncSubscriptions();
      CallService.instance.syncConversations(_items);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chatAction(Map<String, dynamic> item, String action) async {
    final conversationId = item['conversation_id'] as int?;
    if (conversationId == null) return;
    final isGroup = item['type'] == 'group';
    if (action == 'pin') {
      try {
        await context.read<AuthStore>().api.post(
          'conversations/$conversationId/pin',
          {'pinned': item['pinned'] != true},
        );
        await _load();
      } catch (error) {
        if (mounted) showErrorSnack(context, error);
      }
      return;
    }
    if (action == 'mute') {
      try {
        await context.read<AuthStore>().api.post(
          'conversations/$conversationId/mute',
          {'muted': item['muted'] != true},
        );
        await _load();
      } catch (error) {
        if (mounted) showErrorSnack(context, error);
      }
      return;
    }
    if (action == 'add_contact') {
      final accountId =
          item['peer'] is Map ? (item['peer'] as Map)['account_id'] : null;
      if (accountId is! int) return;
      try {
        await context.read<AuthStore>().api.post('contacts', {
          'account_id': accountId,
        });
        await _load();
      } catch (error) {
        if (mounted) showErrorSnack(context, error);
      }
      return;
    }
    final title = action == 'clear'
        ? 'Bersihkan pesan?'
        : isGroup
            ? 'Keluar dari grup?'
            : 'Hapus percakapan?';
    final message = action == 'clear'
        ? 'Pesan akan disembunyikan dari tampilan Anda saja. Anggota lain tidak terpengaruh.'
        : isGroup
            ? 'Anda akan keluar dari grup ini.'
            : 'Percakapan akan dihapus dari daftar Anda.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final api = context.read<AuthStore>().api;
    try {
      if (action == 'clear') {
        await api.post('conversations/$conversationId/clear');
      } else {
        await api.delete('conversations/$conversationId');
      }
      ChatCache.clear(conversationId);
      _typingUsers.remove(conversationId);
      await _load();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _openConversation(Map<String, dynamic> conversation) async {
    final embedded = widget.onOpenConversation;
    if (embedded != null) {
      embedded(conversation);
      return;
    }
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
      body: ReadableWidth(
        maxWidth: 680,
        child: RefreshIndicator(
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
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, thickness: 0.5),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final unread = item['unread_count'] ?? 0;
                        final hasUnread = unread is int && unread > 0;
                        final scheme = Theme.of(context).colorScheme;
                        final peer = item['peer'] is Map
                            ? Map<String, dynamic>.from(item['peer'] as Map)
                            : null;
                        final myAccount = item['my_account'] is Map
                            ? Map<String, dynamic>.from(
                                item['my_account'] as Map)
                            : null;
                        final isGroup = item['type'] == 'group';
                        final myType = myAccount?['type_code'] as String?;
                        final myBusiness =
                            myType != null && myType != 'personal';
                        final token = context.read<AuthStore>().api.accessToken;
                        final conversationId = item['conversation_id'] as int?;
                        final typing = conversationId == null
                            ? null
                            : _typingUsers[conversationId];
                        final typingLabel = typing == null || typing.isEmpty
                            ? null
                            : isGroup
                                ? '${typing.values.join(', ')} sedang mengetik…'
                                : 'sedang mengetik…';
                        final lastMessage = item['last_message'] is Map
                            ? Map<String, dynamic>.from(
                                item['last_message'] as Map)
                            : null;
                        final senderPrefix = isGroup &&
                                lastMessage?['sender_name'] != null &&
                                '${lastMessage?['sender_name']}'.isNotEmpty
                            ? '${lastMessage?['sender_name']}: '
                            : '';
                        final titleStyle = TextStyle(
                          fontWeight:
                              hasUnread ? FontWeight.w800 : FontWeight.w600,
                        );
                        Widget titleWidget;
                        if (isGroup) {
                          titleWidget = Text(peerName(item), style: titleStyle);
                        } else if (myBusiness) {
                          // Message arrived at our business account: show our
                          // business identity, then the sender.
                          titleWidget = Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${myAccount?['display_name'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4),
                                child: Text('<'),
                              ),
                              AccountTypeAvatar(
                                account: peer,
                                radius: 9,
                                token: token,
                                showBadge: false,
                                showStatusDot: true,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${peer?['display_name'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          );
                        } else {
                          // Sending to a business account (or a normal personal
                          // chat): show the target account.
                          titleWidget = Text(peerName(item), style: titleStyle);
                        }
                        return Container(
                          color: hasUnread
                              ? scheme.primaryContainer.withValues(alpha: 0.25)
                              : null,
                          child: ListTile(
                            selected: widget.selectedConversationId != null &&
                                item['conversation_id'] ==
                                    widget.selectedConversationId,
                            selectedTileColor:
                                scheme.primary.withValues(alpha: 0.08),
                            onTap: () => _openConversation(item),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 2,
                            ),
                            leading: isGroup
                                ? GroupAvatar(
                                    mediaId: item['avatar_media_id'] as int?,
                                    radius: 20,
                                    token: token,
                                  )
                                : AccountTypeAvatar(
                                    account: myBusiness ? myAccount : peer,
                                    radius: 20,
                                    token: token,
                                    showStatusDot: true,
                                  ),
                            title: Row(
                              children: [
                                Expanded(child: titleWidget),
                                if (isGroup &&
                                    CallService.instance.groupCall(
                                            item['conversation_id'] as int? ??
                                                -1) !=
                                        null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Icon(
                                      Icons.call,
                                      size: 13,
                                      color: scheme.primary,
                                    ),
                                  ),
                                if (item['pinned'] == true)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Icon(Icons.push_pin, size: 13),
                                  ),
                                if (item['muted'] == true)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child:
                                        Icon(Icons.notifications_off, size: 13),
                                  ),
                                if (hasUnread)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: scheme.primary,
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
                                  ),
                              ],
                            ),
                            subtitle: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    typingLabel ??
                                        (isGroup &&
                                                CallService.instance.groupCall(
                                                        item['conversation_id']
                                                                as int? ??
                                                            -1) !=
                                                    null
                                            ? 'Panggilan grup berlangsung'
                                            : '$senderPrefix${messagePreview(lastMessage)}'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight:
                                          typingLabel != null || hasUnread
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                      fontStyle: typingLabel != null
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                      color: typingLabel != null
                                          ? scheme.primary
                                          : (hasUnread
                                              ? scheme.onSurface
                                              : null),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  timeAgo(item['last_message_at']),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              iconSize: 18,
                              tooltip: 'Aksi chat',
                              onSelected: (action) => _chatAction(item, action),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'pin',
                                  child: Text(item['pinned'] == true
                                      ? 'Lepas pin'
                                      : 'Pin percakapan'),
                                ),
                                if (isGroup)
                                  PopupMenuItem(
                                    value: 'mute',
                                    child: Text(item['muted'] == true
                                        ? 'Aktifkan notifikasi'
                                        : 'Bisukan notifikasi'),
                                  ),
                                const PopupMenuItem(
                                  value: 'clear',
                                  child: Text('Bersihkan semua pesan'),
                                ),
                                if (!isGroup &&
                                    peer?['account_id'] is int &&
                                    !_contactAccountIds
                                        .contains(peer?['account_id']))
                                  const PopupMenuItem(
                                    value: 'add_contact',
                                    child: Text('Tambah ke kontak'),
                                  ),
                                if (isGroup)
                                  const PopupMenuItem(
                                    value: 'leave',
                                    child: Text('Keluar dari grup'),
                                  )
                                else
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Hapus pesan'),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}
