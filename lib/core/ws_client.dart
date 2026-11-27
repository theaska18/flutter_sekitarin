import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';

class WsClient {
  WsClient();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  String? _token;
  bool _manualClose = false;
  bool _connecting = false;
  int _attempt = 0;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final Map<int, int> _subscriptions = <int, int>{};
  bool _ready = false;

  Stream<Map<String, dynamic>> get events => _events.stream;
  bool get connected => _ready;

  Future<void> connect(String token) async {
    _token = token;
    _manualClose = false;
    if (_ready || _connecting) return;
    await _open();
  }

  Future<void> _open() async {
    final token = _token;
    if (token == null || token.isEmpty || _manualClose || _connecting) return;
    _connecting = true;
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
              _attempt = 0;
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
    } finally {
      _connecting = false;
    }
  }

  void _onClosed() {
    _ready = false;
    _channel = null;
    _subscription = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manualClose || _token == null || _token!.isEmpty) return;
    if (_reconnectTimer?.isActive == true) return;
    _attempt++;
    final seconds = (1 << (_attempt.clamp(1, 5))).clamp(2, 30);
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (!_manualClose) _open();
    });
  }

  /// Force an immediate reconnect, e.g. when the app returns to foreground.
  Future<void> reconnect() async {
    if (_manualClose || _token == null) return;
    if (_ready) return;
    _reconnectTimer?.cancel();
    await _open();
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

  Future<void> disconnect() async {
    _manualClose = true;
    _token = null;
    _reconnectTimer?.cancel();
    _subscriptions.clear();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _subscription = null;
    _channel = null;
    _ready = false;
  }
}
