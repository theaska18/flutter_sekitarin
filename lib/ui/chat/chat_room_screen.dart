import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../core/ws_client.dart';
import '../../services/media_opener.dart';
import '../../services/message_sound.dart';
import '../../state/auth_store.dart';
import '../../state/chat_cache.dart';
import '../../state/chat_presence.dart';
import '../common.dart';
import '../profile/account_profile_route.dart';
import '../widgets/account_type_avatar.dart';
import '../widgets/group_avatar.dart';
import 'group_info_screen.dart';
import 'group_map_screen.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({super.key, required this.conversation});

  final Map<String, dynamic> conversation;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen>
    with WidgetsBindingObserver {
  late final int _conversationId =
      widget.conversation['conversation_id'] as int;
  final _message = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  final Set<int> _incomingIds = {};
  final Map<int, Timer> _incomingTimers = {};
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
  int? _peerAccountId;
  int? _sendAccountId;
  int _nextLocalId = -1;
  bool _peerIsContact = true;
  bool _contactBusy = false;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ChatPresence.activeConversationId = _conversationId;
    _inputFocus.addListener(_onInputFocus);
    _ws = context.read<AuthStore>().ws;
    _sendAccountId = widget.conversation['my_account_id'] as int?;
    _ws.subscribe(_conversationId);
    _wsSubscription = _ws.events.listen((event) {
      if (!mounted || event['conversation_id'] != _conversationId) return;
      final payload = event['payload'];
      if (payload is! Map) return;
      final message = Map<String, dynamic>.from(payload);
      final name = '${event['event']}';
      if (name == 'message.created' || name == 'message.updated') {
        _upsert(message);
        if (name == 'message.created') {
          _markRead(message);
          context.read<AuthStore>().markChatNotificationsRead(
                conversationId: _conversationId,
              );
        }
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
      } else if (name == 'conversation.updated') {
        setState(() {
          if (payload['title'] != null) {
            _groupTitle = '${payload['title']}';
          }
          widget.conversation['avatar_media_id'] = payload['avatar_media_id'];
        });
      } else if (name == 'message.reaction') {
        final messageId = payload['message_id'];
        final reactions = payload['reactions'];
        final userId = payload['user_id'];
        final reaction = payload['reaction'];
        final myId = context.read<AuthStore>().user?['user_id'];
        if (messageId is int && reactions is Map) {
          setState(() {
            final index =
                _messages.indexWhere((item) => item['message_id'] == messageId);
            if (index >= 0) {
              _messages[index]['reactions'] =
                  Map<String, dynamic>.from(reactions);
              if (userId == myId) {
                _messages[index]['my_reaction'] =
                    reaction is String && reaction.isNotEmpty ? reaction : null;
              }
            }
          });
          final index =
              _messages.indexWhere((item) => item['message_id'] == messageId);
          if (index >= 0) {
            ChatCache.upsert(_conversationId, _messages[index]);
          }
        }
      } else if (name == 'messages.delivered') {
        final ids = payload['message_ids'];
        final myId = context.read<AuthStore>().user?['user_id'];
        if (ids is List) {
          setState(() {
            for (final item in _messages) {
              if (item['sender_user_id'] != myId) continue;
              if (!ids.contains(item['message_id'])) continue;
              item['delivered_count'] =
                  ((item['delivered_count'] as int? ?? 0) < 1)
                      ? 1
                      : item['delivered_count'];
            }
          });
          for (final item in _messages) {
            if (item['sender_user_id'] == myId) {
              ChatCache.upsert(_conversationId, item);
            }
          }
        }
      } else if (name == 'read.updated') {
        final readId = payload['message_id'];
        final myId = context.read<AuthStore>().user?['user_id'];
        if (readId is int) {
          setState(() {
            for (final item in _messages) {
              if (item['sender_user_id'] != myId) continue;
              final id = item['message_id'];
              if (id is! int || id > readId) continue;
              item['delivered_count'] = 1;
              item['read_count'] = 1;
            }
          });
          for (final item in _messages) {
            if (item['sender_user_id'] == myId) {
              ChatCache.upsert(_conversationId, item);
            }
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
        ChatCache.markDeleted(_conversationId, message);
      }
    });
    final auth = context.read<AuthStore>();
    auth.markChatNotificationsRead(conversationId: _conversationId);
    if (ChatCache.has(_conversationId)) {
      _messages.addAll(ChatCache.messages(_conversationId));
      _lastId = ChatCache.lastId(_conversationId);
      _loading = false;
      _scrollToBottom();
      if (_messages.isNotEmpty) _markRead(_messages.last);
      _pollNew();
    } else {
      _load();
    }
    if (widget.conversation['type'] == 'group') {
      _loadConversation();
    } else {
      _loadContactState();
    }
    _startPoll();
  }

  void _onInputFocus() {
    if (!_inputFocus.hasFocus) return;
    Future.delayed(const Duration(milliseconds: 120), _scrollToBottom);
    Future.delayed(const Duration(milliseconds: 380), _scrollToBottom);
  }

  void _startPoll() {
    if (_paused) return;
    _poll ??= Timer.periodic(const Duration(seconds: 5), (_) {
      // Poll only as a fallback; WebSocket is the primary transport.
      if (!_ws.connected) _pollNew();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _paused = true;
      _poll?.cancel();
      _poll = null;
    } else if (state == AppLifecycleState.resumed) {
      _paused = false;
      _pollNew();
      _startPoll();
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted || MediaQuery.of(context).viewInsets.bottom <= 0) return;
    Future.delayed(const Duration(milliseconds: 120), _scrollToBottom);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (ChatPresence.activeConversationId == _conversationId) {
      ChatPresence.activeConversationId = null;
    }
    _inputFocus.dispose();
    _ws.unsubscribe(_conversationId);
    _wsSubscription?.cancel();
    _poll?.cancel();
    _typingStop?.cancel();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    for (final timer in _incomingTimers.values) {
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
      ChatCache.save(_conversationId, _messages);
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
      Map<String, dynamic>? newest;
      for (final raw in data['data'] as List) {
        if (raw is Map) {
          final message = Map<String, dynamic>.from(raw);
          _upsert(message);
          newest = message;
        }
      }
      if (newest != null) {
        _markRead(newest);
        context.read<AuthStore>().markChatNotificationsRead(
              conversationId: _conversationId,
            );
      }
    } catch (_) {
      // Polling is best-effort.
    }
  }

  void _upsert(Map<String, dynamic> message, {bool playSound = true}) {
    final id = message['message_id'];
    if (id == null || !mounted) return;
    var isNew = false;
    setState(() {
      final index = _messages.indexWhere((item) => item['message_id'] == id);
      if (index >= 0) {
        _messages[index] = message;
      } else {
        isNew = true;
        _messages.add(message);
        _messages.sort((a, b) =>
            (a['message_id'] as int).compareTo(b['message_id'] as int));
      }
      if (id is int && id > _lastId) _lastId = id;
    });
    ChatCache.upsert(_conversationId, message);
    if (isNew && id is int) {
      _incomingIds.add(id);
      _incomingTimers[id]?.cancel();
      _incomingTimers[id] = Timer(const Duration(milliseconds: 600), () {
        _incomingIds.remove(id);
      });
      final myId = context.read<AuthStore>().user?['user_id'];
      if (playSound && message['sender_user_id'] != myId) {
        MessageSound.play();
      }
    }
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

  void _addPending(Map<String, dynamic> pending) {
    setState(() => _messages.add(pending));
    MessageSound.play();
    _scrollToBottom();
  }

  void _removePending(int localId) {
    if (!mounted) return;
    setState(() {
      _messages.removeWhere((item) => item['message_id'] == localId);
    });
  }

  void _markPendingFailed(int localId) {
    if (!mounted) return;
    setState(() {
      final index =
          _messages.indexWhere((item) => item['message_id'] == localId);
      if (index >= 0) _messages[index]['failed'] = true;
    });
  }

  Map<String, dynamic> _pendingMessage({
    required String type,
    required String body,
    int? mediaId,
  }) {
    final myId = context.read<AuthStore>().user?['user_id'];
    return {
      'message_id': _nextLocalId--,
      'conversation_id': _conversationId,
      'sender_user_id': myId,
      'sender_account_id': _sendAccountId,
      'type': type,
      'body': body,
      'media_id': mediaId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'pending': true,
      'delivered_count': 0,
      'read_count': 0,
    };
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) return;
    _typingStop?.cancel();
    _sendTyping(false);
    final pending = _pendingMessage(type: 'text', body: text);
    final localId = pending['message_id'] as int;
    _addPending(pending);
    _message.clear();
    setState(() => _sending = true);
    try {
      final data = await context.read<AuthStore>().api.post(
            'conversations/$_conversationId/messages',
            {'type': 'text', 'body': text},
            _sendAccountId?.toString(),
          );
      _removePending(localId);
      if (data['message'] is Map) {
        final message = Map<String, dynamic>.from(data['message'] as Map);
        _upsert(message, playSound: false);
        await _markRead(message);
      }
    } catch (error) {
      _markPendingFailed(localId);
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showMessageMenu(Map<String, dynamic> message) async {
    final mine =
        message['sender_user_id'] == context.read<AuthStore>().user?['user_id'];
    final canCopy = '${message['type']}' == 'text' &&
        '${message['body'] ?? ''}'.isNotEmpty &&
        message['deleted_at'] == null;
    final reactions = const ['❤️', '👍', '😂', '😮', '😢', '🙏'];
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final emoji in reactions)
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () =>
                          Navigator.of(sheetContext).pop('react:$emoji'),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child:
                            Text(emoji, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                ],
              ),
            ),
            if (canCopy)
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Salin pesan'),
                onTap: () => Navigator.of(sheetContext).pop('copy'),
              ),
            if (mine)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: Text(
                  'Hapus pesan',
                  style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action.startsWith('react:')) {
      await _reactMessage(message, action.substring(6));
      return;
    }
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: '${message['body'] ?? ''}'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pesan disalin.')),
        );
      }
      return;
    }
    if (action != 'delete') return;
    final scope = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus pesan ini?'),
        content: const Text(
          'Pilih “Hapus untuk semua” agar semua orang melihat “Pesan ini dihapus”. '
          '“Hapus untuk saya” hanya menyembunyikan pesan dari tampilan Anda.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('me'),
            child: const Text('Hapus untuk saya'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('all'),
            child: const Text('Hapus untuk semua'),
          ),
        ],
      ),
    );
    if (scope == null || !mounted) return;
    await _deleteMessage(message, forEveryone: scope == 'all');
  }

  Future<void> _reactMessage(
    Map<String, dynamic> message,
    String emoji,
  ) async {
    final id = message['message_id'];
    if (id is! int || id <= 0) return;
    final current = message['my_reaction'];
    final next = current == emoji ? '' : emoji;
    try {
      final data = await context.read<AuthStore>().api.post(
        'messages/$id/reaction',
        {'reaction': next},
      );
      if (!mounted) return;
      setState(() {
        message['reactions'] = data['reactions'] is Map
            ? Map<String, dynamic>.from(data['reactions'] as Map)
            : <String, dynamic>{};
        message['my_reaction'] = data['my_reaction'];
      });
      ChatCache.upsert(_conversationId, message);
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _deleteMessage(
    Map<String, dynamic> message, {
    required bool forEveryone,
  }) async {
    final id = message['message_id'];
    if (id is! int || id <= 0) return;
    try {
      await context.read<AuthStore>().api.delete(
        'messages/$id',
        query: {'for_everyone': forEveryone ? '1' : '0'},
      );
      if (!mounted) return;
      if (forEveryone) {
        final deletedAt = DateTime.now().toUtc().toIso8601String();
        setState(() {
          final index =
              _messages.indexWhere((item) => item['message_id'] == id);
          if (index >= 0) {
            _messages[index]['deleted_at'] = deletedAt;
            _messages[index]['body'] = null;
            _messages[index]['media_id'] = null;
          }
        });
        ChatCache.markDeleted(_conversationId, {
          'message_id': id,
          'deleted_at': deletedAt,
        });
      } else {
        setState(() {
          _messages.removeWhere((item) => item['message_id'] == id);
        });
        ChatCache.removeMessage(_conversationId, id);
      }
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Foto'),
              subtitle: const Text('Pilih dari galeri'),
              onTap: () => Navigator.of(sheetContext).pop('photo'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('File'),
              subtitle: const Text('PDF, Word, Excel, TXT, atau ZIP'),
              onTap: () => Navigator.of(sheetContext).pop('file'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'photo') {
      await _sendPhoto();
    } else if (choice == 'file') {
      await _sendFile();
    }
  }

  Future<void> _sendPhoto() async {
    if (_sending) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1800,
    );
    if (picked == null || !mounted) return;
    await _sendAttachment(
      path: picked.path,
      name: picked.name,
      type: 'image',
    );
  }

  Future<void> _sendFile() async {
    if (_sending) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'txt',
        'zip',
      ],
    );
    final file = result?.files.single;
    if (file == null || file.path == null || !mounted) return;
    await _sendAttachment(
      path: file.path!,
      name: file.name,
      type: 'file',
    );
  }

  Future<void> _sendAttachment({
    required String path,
    required String name,
    required String type,
  }) async {
    if (_sending) return;
    _typingStop?.cancel();
    _sendTyping(false);
    final api = context.read<AuthStore>().api;
    final pending = _pendingMessage(type: type, body: name);
    final localId = pending['message_id'] as int;
    _addPending(pending);
    setState(() => _sending = true);
    try {
      final media = await api.uploadFile(
        'media',
        filePath: path,
        purpose: 'chat',
      );
      final payload = media['media'];
      if (payload is! Map || payload['media_id'] is! int) {
        throw Exception('Upload lampiran gagal.');
      }
      final data = await api.post(
        'conversations/$_conversationId/messages',
        {
          'type': type,
          'media_id': payload['media_id'],
          'body': name,
        },
        _sendAccountId?.toString(),
      );
      _removePending(localId);
      if (data['message'] is Map) {
        final message = Map<String, dynamic>.from(data['message'] as Map);
        _upsert(message, playSound: false);
        await _markRead(message);
      }
      _scrollToBottom();
    } catch (error) {
      _markPendingFailed(localId);
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

  Future<void> _loadContactState() async {
    final peer = widget.conversation['peer'];
    if (peer is! Map) return;
    final accountId = peer['account_id'];
    if (accountId is! int) return;
    try {
      final data = await context.read<AuthStore>().api.get('contacts');
      final contacts = data is Map && data['data'] is List
          ? (data['data'] as List).whereType<Map>()
          : const <Map>[];
      final isContact = contacts.any((item) => item['account_id'] == accountId);
      if (!mounted) return;
      setState(() {
        _peerAccountId = accountId;
        _peerIsContact = isContact;
      });
    } catch (_) {
      // Contact state is best-effort.
    }
  }

  Future<void> _addPeerContact() async {
    final accountId = _peerAccountId;
    if (accountId == null || _contactBusy) return;
    setState(() => _contactBusy = true);
    try {
      await context.read<AuthStore>().api.post('contacts', {
        'account_id': accountId,
      });
      if (!mounted) return;
      setState(() => _peerIsContact = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kontak ditambahkan.')),
      );
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _contactBusy = false);
    }
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

  List<Widget> _buildMessageSlivers(
    BuildContext context,
    dynamic myId,
    String? token,
  ) {
    final groups = <DateTime, List<Map<String, dynamic>>>{};
    for (final message in _messages) {
      final created = DateTime.tryParse('${message['created_at']}')?.toLocal();
      final day = created == null
          ? DateTime.now()
          : DateTime(created.year, created.month, created.day);
      groups.putIfAbsent(day, () => <Map<String, dynamic>>[]).add(message);
    }
    final scheme = Theme.of(context).colorScheme;
    final slivers = <Widget>[];
    groups.forEach((day, messages) {
      slivers.add(
        SliverPersistentHeader(
          pinned: true,
          delegate: _ChatDayHeaderDelegate(
            label: chatDateLabel(day.toIso8601String()),
            background: Theme.of(context).scaffoldBackgroundColor,
            foreground: scheme.onSurfaceVariant,
            chip: scheme.surfaceContainerHighest,
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final message = messages[index];
                final mine = message['sender_user_id'] == myId;
                final id = message['message_id'] as int?;
                final canInteract = id != null &&
                    id > 0 &&
                    message['deleted_at'] == null &&
                    message['pending'] != true;
                return _MessageBubble(
                  key: ValueKey(id),
                  message: message,
                  mine: mine,
                  token: token,
                  animate: id != null && _incomingIds.contains(id),
                  onLongPress:
                      canInteract ? () => _showMessageMenu(message) : null,
                  onReact: canInteract
                      ? (emoji) => _reactMessage(message, emoji)
                      : null,
                  senderName: mine
                      ? null
                      : _memberNames[message['sender_user_id'] as int?],
                );
              },
              childCount: messages.length,
            ),
          ),
        ),
      );
    });
    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    final isGroup = widget.conversation['type'] == 'group';
    final peer = widget.conversation['peer'];
    final peerMap = peer is Map ? Map<String, dynamic>.from(peer) : null;
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
        : isGroup
            ? '${_typingNames.values.join(', ')} sedang mengetik…'
            : 'sedang mengetik…';
    final subtitle = typingLabel ??
        (isGroup
            ? '${widget.conversation['member_count'] ?? ''} anggota'
            : null);
    final groupAvatarId = widget.conversation['avatar_media_id'];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () {
            if (isGroup) {
              _openGroupInfo();
              return;
            }
            final accountId = peerMap?['account_id'];
            if (accountId is! int) return;
            openAccountProfile(
              context,
              accountId,
              initialName: '${peerMap?['display_name'] ?? ''}',
            );
          },
          child: Row(
            children: [
              if (isGroup)
                GroupAvatar(
                  mediaId: groupAvatarId as int?,
                  token: auth.api.accessToken,
                  radius: 18,
                )
              else
                AccountTypeAvatar(
                  account: peerMap,
                  radius: 18,
                  token: auth.api.accessToken,
                  showStatusDot: true,
                ),
              const SizedBox(width: 8),
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
          if (isGroup) ...[
            IconButton(
              onPressed: _openGroupMap,
              icon: const Icon(Icons.map_outlined),
              tooltip: 'Peta anggota',
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.videocam_outlined),
              tooltip: 'Panggilan video',
            ),
          ] else ...[
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.call_outlined),
              tooltip: 'Panggilan suara',
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.videocam_outlined),
              tooltip: 'Panggilan video',
            ),
            if (_peerAccountId != null && !_peerIsContact)
              IconButton(
                onPressed: _contactBusy ? null : _addPeerContact,
                icon: const Icon(Icons.person_add_alt_1),
                tooltip: 'Tambah ke kontak',
              ),
          ],
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('Belum ada pesan'))
                    : CustomScrollView(
                        controller: _scroll,
                        slivers: _buildMessageSlivers(
                          context,
                          myId,
                          auth.api.accessToken,
                        ),
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _sending ? null : _pickAttachment,
                    icon: const Icon(Icons.attach_file),
                    tooltip: 'Kirim foto atau file',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _message,
                      focusNode: _inputFocus,
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
    super.key,
    required this.message,
    required this.mine,
    required this.token,
    this.senderName,
    this.animate = false,
    this.onLongPress,
    this.onReact,
  });

  final Map<String, dynamic> message;
  final bool mine;
  final String? token;
  final String? senderName;
  final bool animate;
  final VoidCallback? onLongPress;
  final ValueChanged<String>? onReact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bubbleColor = mine
        ? (dark ? scheme.primaryContainer : scheme.primary)
        : scheme.surfaceContainerHighest;
    final bubbleTextColor = mine
        ? (dark ? scheme.onPrimaryContainer : Colors.white)
        : scheme.onSurface;
    final bubbleMetaColor = mine
        ? (dark
            ? scheme.onPrimaryContainer.withValues(alpha: 0.7)
            : Colors.white70)
        : scheme.onSurfaceVariant;
    final deleted = message['deleted_at'] != null;
    final type = '${message['type'] ?? 'text'}';
    final mediaId = message['media_id'];
    final location = message['location'];
    final headers = token == null || token!.isEmpty
        ? null
        : {'Authorization': 'Bearer $token'};
    final pending = message['pending'] == true;
    final failed = message['failed'] == true;
    final delivered = (message['delivered_count'] as int? ?? 0) > 0;
    final read = (message['read_count'] as int? ?? 0) > 0;
    final reactions = message['reactions'] is Map
        ? Map<String, dynamic>.from(message['reactions'] as Map)
        : <String, dynamic>{};
    final myReaction = message['my_reaction'] as String?;

    Widget content;
    if (deleted) {
      content = Text(
        'Pesan ini dihapus',
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: bubbleTextColor.withValues(alpha: 0.45),
        ),
      );
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
    } else if (type == 'file' && mediaId is int) {
      content = InkWell(
        onTap: () => openChatMedia(
          context,
          mediaId,
          token,
          filename: '${message['body'] ?? ''}',
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined,
                size: 26, color: bubbleTextColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${message['body'] ?? 'File'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bubbleTextColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.download, size: 14, color: bubbleMetaColor),
          ],
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
        style: TextStyle(color: bubbleTextColor),
      );
    }

    final body = Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
        decoration: BoxDecoration(
          color: bubbleColor,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: content),
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chatMessageTime(message['created_at']),
                      style: TextStyle(
                        fontSize: 10,
                        color: bubbleMetaColor,
                      ),
                    ),
                    if (mine) ...[
                      const SizedBox(width: 3),
                      Icon(
                        failed
                            ? Icons.error_outline
                            : pending
                                ? Icons.schedule
                                : read || delivered
                                    ? Icons.done_all
                                    : Icons.done,
                        size: 12,
                        color: failed
                            ? Theme.of(context).colorScheme.error
                            : read
                                ? const Color(0xFF38BDF8)
                                : bubbleMetaColor,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (reactions.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 2,
                children: [
                  for (final entry in reactions.entries)
                    if ((entry.value as num? ?? 0) > 0)
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap:
                            onReact == null ? null : () => onReact!(entry.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: bubbleTextColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: myReaction == entry.key
                                ? Border.all(
                                    color: bubbleTextColor.withValues(
                                      alpha: 0.5,
                                    ),
                                  )
                                : null,
                          ),
                          child: Text(
                            '${entry.key} ${entry.value}',
                            style: TextStyle(
                              fontSize: 11,
                              color: bubbleTextColor,
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
    final interactive = onLongPress == null
        ? body
        : GestureDetector(onLongPress: onLongPress, child: body);
    if (!animate) return interactive;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      child: interactive,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 12),
          child: child,
        ),
      ),
    );
  }
}

class _ChatDayHeaderDelegate extends SliverPersistentHeaderDelegate {
  _ChatDayHeaderDelegate({
    required this.label,
    required this.background,
    required this.foreground,
    required this.chip,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color chip;

  @override
  double get minExtent => 38;

  @override
  double get maxExtent => 38;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: background,
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: chip,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ChatDayHeaderDelegate oldDelegate) {
    return oldDelegate.label != label ||
        oldDelegate.background != background ||
        oldDelegate.foreground != foreground ||
        oldDelegate.chip != chip;
  }
}
