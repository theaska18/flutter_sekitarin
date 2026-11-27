import 'dart:math' as math;

/// In-memory message cache so opening a conversation only fetches messages
/// newer than the last cached one.
class ChatCache {
  static final Map<int, List<Map<String, dynamic>>> _messages = {};
  static final Map<int, int> _lastIds = {};
  static final Set<int> _present = {};

  static bool has(int conversationId) => _present.contains(conversationId);

  static List<Map<String, dynamic>> messages(int conversationId) {
    return (_messages[conversationId] ?? const [])
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static int lastId(int conversationId) => _lastIds[conversationId] ?? 0;

  static void save(int conversationId, List<Map<String, dynamic>> messages) {
    final trimmed = messages.length > 200
        ? messages.sublist(messages.length - 200)
        : messages;
    _messages[conversationId] =
        trimmed.map((item) => Map<String, dynamic>.from(item)).toList();
    _lastIds[conversationId] = trimmed.fold<int>(
      0,
      (value, item) => math.max(value, (item['message_id'] as int?) ?? 0),
    );
    _present.add(conversationId);
  }

  static void upsert(int conversationId, Map<String, dynamic> message) {
    final id = message['message_id'];
    if (id is! int) return;
    final list = _messages.putIfAbsent(conversationId, () => []);
    final index = list.indexWhere((item) => item['message_id'] == id);
    if (index >= 0) {
      list[index] = Map<String, dynamic>.from(message);
    } else {
      list.add(Map<String, dynamic>.from(message));
      list.sort(
          (a, b) => (a['message_id'] as int).compareTo(b['message_id'] as int));
    }
    _lastIds[conversationId] = math.max(_lastIds[conversationId] ?? 0, id);
    _present.add(conversationId);
  }

  static void markDeleted(int conversationId, Map<String, dynamic> message) {
    final id = message['message_id'];
    if (id is! int) return;
    final list = _messages[conversationId];
    if (list == null) return;
    final index = list.indexWhere((item) => item['message_id'] == id);
    if (index < 0) return;
    list[index]['deleted_at'] = message['deleted_at'];
    list[index]['body'] = null;
    list[index]['media_id'] = null;
  }

  static void clear(int conversationId) {
    _messages.remove(conversationId);
    _lastIds.remove(conversationId);
    _present.remove(conversationId);
  }

  static void clearAll() {
    _messages.clear();
    _lastIds.clear();
    _present.clear();
  }
}
