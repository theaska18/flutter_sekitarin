import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../core/ws_client.dart';
import '../../state/auth_store.dart';
import '../common.dart';
import '../widgets/account_avatar.dart';
import 'group_info_screen.dart';
import 'group_map_screen.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({super.key, required this.conversation});

  final Map<String, dynamic> conversation;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  late final int _conversationId =
      widget.conversation['conversation_id'] as int;
  final _message = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  StreamSubscription? _wsSubscription;
  late final WsClient _ws;
  Timer? _poll;
  bool _loading = true;
  bool _sending = false;
  int _lastId = 0;
  String? _groupTitle;
  final Map<int, String> _memberNames = {};
  final Map<int, String> _typingNames = {};
  final Map<int, Timer> _typingTimers = {};
  Timer? _typingStop;
  DateTime? _lastTypingSent;

  @override
  void initState() {
    super.initState();
    _ws = context.read<AuthStore>().ws;
    _ws.subscribe(_conversationId);
    _wsSubscription = _ws.events.listen((event) {
      if (!mounted || event['conversation_id'] != _conversationId) return;
      final payload = event['payload'];
      if (payload is! Map) return;
      final message = Map<String, dynamic>.from(payload);
      final name = '${event['event']}';
      if (name == 'message.created' || name == 'message.updated') {
        _upsert(message);
        if (name == 'message.created') _markRead(message);
      } else if (name == 'typing') {
        final userId = payload['user_id'] as int?;
        if (userId != null &&
            userId != context.read<AuthStore>().user?['user_id']) {
          final typingName = '${payload['display_name'] ?? 'Seseorang'}';
          _typingTimers[userId]?.cancel();
          if (payload['is_typing'] == true) {
            setState(() => _typingNames[userId] = typingName);
            _typingTimers[userId] = Timer(const Duration(seconds: 4), () {
              if (mounted) setState(() => _typingNames.remove(userId));
            });
          } else {
            setState(() => _typingNames.remove(userId));
          }
        }
      } else if (name == 'message.deleted') {
        final index = _messages
            .indexWhere((item) => item['message_id'] == message['message_id']);
        if (index >= 0) {
          setState(() {
            _messages[index]['deleted_at'] = message['deleted_at'];
            _messages[index]['body'] = null;
            _messages[index]['media_id'] = null;
          });
        }
      }
    });
    _load();
    if (widget.conversation['type'] == 'group') {
      _loadConversation();
    }
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _pollNew());
  }

  @override
  void dispose() {
    _ws.unsubscribe(_conversationId);
    _wsSubscription?.cancel();
    _poll?.cancel();
    _typingStop?.cancel();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await context.read<AuthStore>().api.get(
        'conversations/$_conversationId/messages',
        query: {'limit': '50'},
      );
      if (!mounted) return;
      final items = data is Map && data['data'] is List
          ? (data['data'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _messages
          ..clear()
          ..addAll(items);
        _lastId = items.isEmpty ? 0 : items.last['message_id'] as int;
      });
      if (items.isNotEmpty) _markRead(items.last);
      _scrollToBottom();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadConversation() async {
    try {
      final data = await context.read<AuthStore>().api.get(
            'conversations/$_conversationId',
          );
      if (!mounted || data is! Map || data['conversation'] is! Map) return;
      final conversation = Map<String, dynamic>.from(
        data['conversation'] as Map,
      );
      setState(() {
        _groupTitle = '${conversation['title'] ?? ''}';
        widget.conversation['avatar_media_id'] =
            conversation['avatar_media_id'];
        _memberNames.clear();
        final members = conversation['members'];
        if (members is List) {
          for (final member in members) {
            if (member is Map) {
              _memberNames[member['user_id'] as int] =
                  '${member['display_name'] ?? ''}';
            }
          }
        }
      });
    } catch (_) {
      // Group details are best-effort.
    }
  }

  Future<void> _openGroupInfo() async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => GroupInfoScreen(
          conversationId: _conversationId,
          initial: widget.conversation,
        ),
      ),
    );
    if (!mounted) return;
    if (result == 'left') {
      Navigator.of(context).pop();
      return;
    }
    await _loadConversation();
  }

  void _onTypingChanged(String value) {
    _typingStop?.cancel();
    if (value.trim().isEmpty) {
      _sendTyping(false);
      return;
    }
    final now = DateTime.now();
    if (_lastTypingSent == null ||
        now.difference(_lastTypingSent!) > const Duration(seconds: 2)) {
      _lastTypingSent = now;
      _sendTyping(true);
    }
    _typingStop = Timer(const Duration(seconds: 3), () => _sendTyping(false));
  }

  Future<void> _sendTyping(bool isTyping) async {
    try {
      await context.read<AuthStore>().api.post(
        'conversations/$_conversationId/typing',
        {'is_typing': isTyping},
      );
    } catch (_) {
      // Typing is best-effort.
    }
  }

  Future<void> _pollNew() async {
    if (_lastId <= 0) return;
    try {
      final data = await context.read<AuthStore>().api.get(
        'conversations/$_conversationId/messages',
        query: {'after_id': '$_lastId', 'limit': '50'},
      );
      if (!mounted || data is! Map || data['data'] is! List) return;
      for (final raw in data['data'] as List) {
        if (raw is Map) _upsert(Map<String, dynamic>.from(raw));
      }
    } catch (_) {
      // Polling is best-effort.
    }
  }

  void _upsert(Map<String, dynamic> message) {
    final id = message['message_id'];
    if (id == null || !mounted) return;
    setState(() {
      final index = _messages.indexWhere((item) => item['message_id'] == id);
      if (index >= 0) {
        _messages[index] = message;
      } else {
        _messages.add(message);
        _messages.sort((a, b) =>
            (a['message_id'] as int).compareTo(b['message_id'] as int));
      }
      if (id is int && id > _lastId) _lastId = id;
    });
    _scrollToBottom();
  }

  Future<void> _markRead(Map<String, dynamic> message) async {
    final id = message['message_id'];
    if (id == null || !mounted) return;
    try {
      await context
          .read<AuthStore>()
          .api
          .post('conversations/$_conversationId/read', {'message_id': id});
    } catch (_) {
      // Read state can be retried on the next poll.
    }
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) return;
    _typingStop?.cancel();
    _sendTyping(false);
    setState(() => _sending = true);
    try {
      final data = await context.read<AuthStore>().api.post(
        'conversations/$_conversationId/messages',
        {'type': 'text', 'body': text},
      );
      if (data['message'] is Map) {
        final message = Map<String, dynamic>.from(data['message'] as Map);
        _upsert(message);
        await _markRead(message);
      }
      _message.clear();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openGroupMap() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupMapScreen(
          conversationId: _conversationId,
          title: _groupTitle ?? 'Peta grup',
        ),
      ),
    );
    if (mounted) _loadConversation();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    final isGroup = widget.conversation['type'] == 'group';
    final peer = widget.conversation['peer'];
    final title = isGroup
        ? (_groupTitle?.isNotEmpty == true
            ? _groupTitle!
            : '${widget.conversation['title'] ?? 'Grup'}')
        : (peer is Map
            ? '${peer['display_name'] ?? ''}'
            : '${widget.conversation['title'] ?? 'Percakapan'}');
    final myId = auth.user?['user_id'];
    final typingLabel = _typingNames.isEmpty
        ? null
        : '${_typingNames.values.join(', ')} sedang mengetik…';
    final subtitle = typingLabel ??
        (isGroup
            ? '${widget.conversation['member_count'] ?? ''} anggota'
            : null);
    final groupAvatarId = widget.conversation['avatar_media_id'];
    return Scaffold(
      appBar: AppBar(
        leading: isGroup
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: AccountAvatar(
                  account: {'avatar_media_id': groupAvatarId},
                  radius: 18,
                  token: auth.api.accessToken,
                  fallbackIcon: Icons.groups,
                ),
              )
            : null,
        title: GestureDetector(
          onTap: isGroup ? _openGroupInfo : null,
          child: Row(
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: typingLabel != null
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                      ),
                  ],
                ),
              ),
              if (isGroup)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.chevron_right, size: 18),
                ),
            ],
          ),
        ),
        actions: [
          if (isGroup)
            IconButton(
              onPressed: _openGroupMap,
              icon: const Icon(Icons.map_outlined),
              tooltip: 'Peta anggota',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final mine = message['sender_user_id'] == myId;
                      return _MessageBubble(
                        message: message,
                        mine: mine,
                        token: auth.api.accessToken,
                        senderName: mine
                            ? null
                            : _memberNames[message['sender_user_id'] as int?],
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _message,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Tulis pesan…',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onChanged: _onTypingChanged,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.token,
    this.senderName,
  });

  final Map<String, dynamic> message;
  final bool mine;
  final String? token;
  final String? senderName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final deleted = message['deleted_at'] != null;
    final type = '${message['type'] ?? 'text'}';
    final mediaId = message['media_id'];
    final location = message['location'];
    final headers = token == null || token!.isEmpty
        ? null
        : {'Authorization': 'Bearer $token'};

    Widget content;
    if (deleted) {
      content = const Text('Pesan dihapus',
          style: TextStyle(fontStyle: FontStyle.italic));
    } else if (type == 'image' && mediaId != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          AppConfig.absoluteUrl('/api/v1/media/$mediaId'),
          headers: headers,
          width: 220,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Text('Gambar tidak tersedia'),
        ),
      );
    } else if (type == 'location' && location is Map) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on, size: 16),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${location['label'] ?? '${location['lat']}, ${location['lng']}'}',
            ),
          ),
        ],
      );
    } else {
      content = Text(
        '${message['body'] ?? ''}',
        style: TextStyle(color: mine ? Colors.white : scheme.onSurface),
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
        decoration: BoxDecoration(
          color: mine ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (senderName != null && senderName!.isNotEmpty) ...[
              Text(
                senderName!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 2),
            ],
            content,
            const SizedBox(height: 3),
            Text(
              formatWhen(message['created_at']),
              style: TextStyle(
                fontSize: 10,
                color: mine ? Colors.white70 : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
