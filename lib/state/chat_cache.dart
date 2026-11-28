import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

/// Disk-backed message cache so opening a conversation paints instantly, even
/// after the app process was restarted (like a messenger app).
class ChatCache {
  static const int _maxMessages = 200;

  static final Map<int, List<Map<String, dynamic>>> _messages = {};
  static final Map<int, int> _lastIds = {};
  static final Set<int> _present = {};
  static final Map<int, Timer> _writeTimers = {};

  static Directory? _dir;

  static Future<void> init() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/chat_cache');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _dir = dir;
    } catch (_) {
      // Disk cache is best-effort; the API still loads messages.
    }
  }

  static File? _file(int conversationId) {
    final dir = _dir;
    if (dir == null) return null;
    return File('${dir.path}/$conversationId.json');
  }

  /// Loads a conversation from disk into memory. Synchronous so the first
  /// frame of the chat room can already show the cached messages.
  static void hydrate(int conversationId) {
    if (_present.contains(conversationId)) return;
    final file = _file(conversationId);
    if (file == null || !file.existsSync()) return;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! List) return;
      final messages = decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      _messages[conversationId] = messages;
      _lastIds[conversationId] = messages.fold<int>(
        0,
        (value, item) => math.max(value, (item['message_id'] as int?) ?? 0),
      );
      _present.add(conversationId);
    } catch (_) {
      // Corrupt cache: ignore and let the API fill it.
    }
  }

  static bool has(int conversationId) => _present.contains(conversationId);

  static List<Map<String, dynamic>> messages(int conversationId) {
    return (_messages[conversationId] ?? const [])
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static int lastId(int conversationId) => _lastIds[conversationId] ?? 0;

  static void save(int conversationId, List<Map<String, dynamic>> messages) {
    final trimmed = messages.length > _maxMessages
        ? messages.sublist(messages.length - _maxMessages)
        : messages;
    _messages[conversationId] =
        trimmed.map((item) => Map<String, dynamic>.from(item)).toList();
    _lastIds[conversationId] = trimmed.fold<int>(
      0,
      (value, item) => math.max(value, (item['message_id'] as int?) ?? 0),
    );
    _present.add(conversationId);
    _persist(conversationId);
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
      if (list.length > _maxMessages) {
        list.removeRange(0, list.length - _maxMessages);
      }
    }
    _lastIds[conversationId] = math.max(_lastIds[conversationId] ?? 0, id);
    _present.add(conversationId);
    _persist(conversationId);
  }

  static void removeMessage(int conversationId, int messageId) {
    final list = _messages[conversationId];
    if (list == null) return;
    list.removeWhere((item) => item['message_id'] == messageId);
    _persist(conversationId);
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
    _persist(conversationId);
  }

  /// Debounced so a burst of incoming messages does not block the UI thread.
  static void _persist(int conversationId) {
    if (_dir == null) return;
    _writeTimers[conversationId]?.cancel();
    _writeTimers[conversationId] = Timer(const Duration(milliseconds: 400), () {
      _writeTimers.remove(conversationId);
      final file = _file(conversationId);
      if (file == null) return;
      try {
        file.writeAsStringSync(jsonEncode(_messages[conversationId] ?? []));
      } catch (_) {
        // Ignore disk errors; the in-memory cache still works.
      }
    });
  }

  static void clear(int conversationId) {
    _writeTimers.remove(conversationId)?.cancel();
    _messages.remove(conversationId);
    _lastIds.remove(conversationId);
    _present.remove(conversationId);
    try {
      final file = _file(conversationId);
      if (file != null && file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  static void clearAll() {
    for (final timer in _writeTimers.values) {
      timer.cancel();
    }
    _writeTimers.clear();
    _messages.clear();
    _lastIds.clear();
    _present.clear();
    final dir = _dir;
    if (dir == null) return;
    try {
      for (final entity in dir.listSync()) {
        if (entity is File && entity.path.endsWith('.json')) {
          entity.deleteSync();
        }
      }
    } catch (_) {}
  }
}
