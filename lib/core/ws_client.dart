import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';

class WsClient {
  WsClient();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final Map<int, int> _subscriptions = <int, int>{};
  bool _ready = false;

  Stream<Map<String, dynamic>> get events => _events.stream;
  bool get connected => _ready;

  Future<void> connect(String token) async {
    if (_ready) return;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(AppConfig.wsUrl));
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 8));
      channel.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      _subscription = channel.stream.listen(
        (raw) {
          try {
            final event = jsonDecode('$raw');
            if (event is! Map) return;
            final map = Map<String, dynamic>.from(event);
            if (map['event'] == 'ready') {
              _ready = true;
              for (final id in _subscriptions.keys) {
                _sendSubscribe(id);
              }
            }
            _events.add(map);
          } catch (_) {
            // Ignore malformed frames.
          }
        },
        onDone: _onClosed,
        onError: (_) => _onClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      _onClosed();
    }
  }

  void subscribe(int conversationId) {
    final count = (_subscriptions[conversationId] ?? 0) + 1;
    _subscriptions[conversationId] = count;
    if (count == 1 && _ready) _sendSubscribe(conversationId);
  }

  void unsubscribe(int conversationId) {
    final count = (_subscriptions[conversationId] ?? 0) - 1;
    if (count > 0) {
      _subscriptions[conversationId] = count;
      return;
    }
    _subscriptions.remove(conversationId);
    _channel?.sink.add(jsonEncode({
      'type': 'unsubscribe',
      'conversation_id': conversationId,
    }));
  }

  void _sendSubscribe(int conversationId) {
    _channel?.sink.add(jsonEncode({
      'type': 'subscribe',
      'conversation_id': conversationId,
    }));
  }

  void _onClosed() {
    _ready = false;
    _channel = null;
    _subscription = null;
  }

  Future<void> disconnect() async {
    _subscriptions.clear();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _subscription = null;
    _channel = null;
    _ready = false;
  }
}
