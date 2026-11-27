import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import '../state/auth_store.dart';
import '../ui/calls/webrtc_call_screen.dart';
import 'push_service.dart';

/// Voice/video calls: direct calls ring through CallKit, group calls are only
/// advertised inside their conversation.
class CallService extends ChangeNotifier {
  CallService._();

  static final CallService instance = CallService._();

  AuthStore? _auth;
  bool _attached = false;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Map<String, dynamic>? _incoming;
  Map<String, dynamic>? _outgoing;
  Map<String, dynamic>? _active;
  final Map<int, Map<String, dynamic>> _groupCalls = {};
  Map<String, dynamic>? _pendingAccept;
  bool _joining = false;
  final Set<int> _acceptedCalls = {};
  int? _activeMeetCallId;
  Timer? _heartbeat;
  bool _clearedStaleCallkit = false;

  /// Navigation handle so calls can be opened from background events.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Signals the open call screen that the remote side ended the call.
  final ValueNotifier<int?> endSignal = ValueNotifier(null);

  Map<String, dynamic>? get incomingCall => _incoming;
  Map<String, dynamic>? get outgoingCall => _outgoing;
  Map<String, dynamic>? get activeCall => _active;

  Map<String, dynamic>? groupCall(int conversationId) =>
      _groupCalls[conversationId];

  bool get ringing => _incoming != null || _outgoing != null;

  void attach(AuthStore auth) {
    if (_attached && identical(_auth, auth)) return;
    _auth = auth;
    if (_attached) return;
    _attached = true;
    _subscriptions.add(auth.ws.events.listen(_onWsEvent));
    _subscriptions.add(PushService.foregroundMessages.listen(_onPushMessage));
    _subscriptions.add(FlutterCallkitIncoming.onEvent.listen(_onCallKitEvent));
    _prepareCallKit();
    if (_pendingAccept != null) {
      final pending = _pendingAccept!;
      _pendingAccept = null;
      _acceptIncoming(pending);
    }
  }

  Future<void> _prepareCallKit() async {
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Izin notifikasi',
        'rationaleMessagePermission':
            'Notifikasi dibutuhkan untuk menampilkan panggilan masuk.',
        'postNotificationMessageRequired':
            'Izinkan notifikasi agar panggilan masuk terlihat.',
      });
      final allowed = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (!allowed) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
      await _resumeAcceptedCall();
      await _clearStaleCallkit();
    } catch (error) {
      debugPrint('CallKit setup failed: $error');
    }
  }

  /// Dismiss call UI left behind by a previous crashed/killed call.
  Future<void> _clearStaleCallkit() async {
    if (_clearedStaleCallkit) return;
    _clearedStaleCallkit = true;
    if (_incoming != null || _active != null || _outgoing != null || _joining) {
      return;
    }
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      if (calls.any((call) => call.isAccepted == true)) return;
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  }

  /// The app may have been killed when the user accepted a call. Resume it.
  Future<void> _resumeAcceptedCall() async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final call in calls) {
        if (call.isAccepted != true) continue;
        final extra = Map<String, dynamic>.from(call.extra ?? {});
        if ('${extra['outgoing']}' == '1') continue;
        final callId = _asInt(extra['call_id']);
        if (callId == null) continue;
        _acceptIncoming(extra);
        return;
      }
    } catch (_) {}
  }

  void syncConversations(List<Map<String, dynamic>> items) {
    var changed = false;
    for (final item in items) {
      if (item['type'] != 'group') continue;
      final conversationId = item['conversation_id'];
      if (conversationId is! int) continue;
      final active = item['active_call'];
      if (active is Map) {
        final next = Map<String, dynamic>.from(active);
        if (!mapEquals(_groupCalls[conversationId], next)) {
          _groupCalls[conversationId] = next;
          changed = true;
        }
      } else if (_groupCalls.remove(conversationId) != null) {
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void setGroupCallFromConversation(Map<String, dynamic> conversation) {
    if (conversation['type'] != 'group') return;
    final conversationId = conversation['conversation_id'];
    if (conversationId is! int) return;
    final active = conversation['active_call'];
    if (active is Map) {
      _groupCalls[conversationId] = Map<String, dynamic>.from(active);
    } else {
      _groupCalls.remove(conversationId);
    }
    notifyListeners();
  }

  void _onWsEvent(Map<String, dynamic> event) {
    final name = '${event['event']}';
    final payload = event['payload'];
    if (payload is! Map) return;
    final data = Map<String, dynamic>.from(payload);
    switch (name) {
      case 'call.incoming':
        _presentIncoming(data);
      case 'call.answered':
        _outgoing = data;
        _active = data;
        _incoming = null;
        notifyListeners();
      case 'call.ended':
      case 'call.canceled':
        _handleRemoteEnd(data);
      case 'call.started':
      case 'call.updated':
        final conversationId = data['conversation_id'];
        if (conversationId is int) {
          _groupCalls[conversationId] = data;
          notifyListeners();
        }
    }
  }

  void _handleRemoteEnd(Map<String, dynamic> data) {
    final callId = _asInt(data['call_id']);
    if (callId != null && _incoming?['call_id'] == callId) {
      _incoming = null;
      _endCallKit(callId);
    }
    if (callId != null && _outgoing?['call_id'] == callId) {
      _outgoing = null;
      _endCallKit(callId);
    }
    if (callId != null && _active?['call_id'] == callId) {
      _active = null;
    }
    if (callId != null && _activeMeetCallId == callId) {
      _heartbeat?.cancel();
      _activeMeetCallId = null;
      endSignal.value = callId;
    }
    if (data['active_call'] == null) {
      final conversationId = _asInt(data['conversation_id']);
      if (conversationId != null) _groupCalls.remove(conversationId);
    }
    notifyListeners();
  }

  void _onPushMessage(RemoteMessage message) {
    final data = message.data;
    if (data['call_event'] == 'incoming') {
      _presentFromData(data);
    } else if (data['call_event'] == 'cancel') {
      final callId = _asInt(data['call_id']);
      if (callId != null) _endCallKit(callId);
    }
  }

  Future<void> _presentFromData(Map<String, dynamic> data) async {
    final call = _callFromPushData(data);
    if (call == null) return;
    _incoming = call;
    notifyListeners();
    await _showCallKit(call);
  }

  Future<void> _presentIncoming(Map<String, dynamic> call) async {
    if (_incoming?['call_id'] == call['call_id']) return;
    _incoming = call;
    notifyListeners();
    await _showCallKit(call);
  }

  Map<String, dynamic>? _callFromPushData(Map<String, dynamic> data) {
    final callId = _asInt(data['call_id']);
    if (callId == null) return null;
    final avatarId = _asInt(data['caller_avatar_media_id']);
    return {
      'call_id': callId,
      'scope': 'direct',
      'kind': data['kind'] ?? 'voice',
      'status': 'ringing',
      'direction': 'incoming',
      'room': data['room'],
      'server_url': data['server_url'],
      'conversation_id': _asInt(data['conversation_id']),
      'caller': {
        'user_id': _asInt(data['caller_user_id']),
        'account_id': _asInt(data['caller_account_id']),
        'display_name': data['caller_name'] ?? 'Panggilan',
        'handle': data['caller_handle'],
        'avatar_media_id': avatarId,
        'type_code': data['caller_type_code'] ?? 'personal',
      },
      'token': data['token'],
      'ring_timeout': _asInt(data['ring_timeout']) ?? 45,
    };
  }

  Future<void> _showCallKit(Map<String, dynamic> call) async {
    final callId = call['call_id'];
    final caller = call['caller'] is Map
        ? Map<String, dynamic>.from(call['caller'] as Map)
        : <String, dynamic>{};
    final avatarId = _asInt(caller['avatar_media_id']);
    final extra = <String, dynamic>{
      'call_id': '$callId',
      'conversation_id': '${call['conversation_id'] ?? 0}',
      'kind': '${call['kind'] ?? 'voice'}',
      'room': '${call['room'] ?? ''}',
      'server_url': '${call['server_url'] ?? ''}',
      'token': '${call['token'] ?? ''}',
      'caller_name': '${caller['display_name'] ?? 'Panggilan'}',
    };
    final params = CallKitParams(
      id: 'call-$callId',
      nameCaller: '${caller['display_name'] ?? 'Panggilan'}',
      appName: 'Sekitarin',
      avatar: avatarId != null
          ? AppConfig.absoluteUrl('/api/v1/media/$avatarId')
          : null,
      handle: caller['handle'] != null ? '@${caller['handle']}' : null,
      type: call['kind'] == 'video' ? 1 : 0,
      duration: ((_asInt(call['ring_timeout']) ?? 45) * 1000),
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Panggilan tak terjawab',
        callbackText: 'Hubungi lagi',
      ),
      extra: extra,
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0F6B57',
        actionColor: '#0F6B57',
        textAccept: 'Terima',
        textDecline: 'Tolak',
        incomingCallNotificationChannelName: 'Panggilan masuk',
        missedCallNotificationChannelName: 'Panggilan tak terjawab',
      ),
      ios: const IOSParams(
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        supportsHolding: false,
        supportsGrouping: false,
      ),
    );
    try {
      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (error) {
      debugPrint('CallKit incoming failed: $error');
    }
  }

  Future<void> _endCallKit(int callId) async {
    try {
      await FlutterCallkitIncoming.endCall('call-$callId');
    } catch (_) {
      // Ignore: the call may already be gone.
    }
  }

  void _onCallKitEvent(CallEvent? event) {
    switch (event) {
      case CallEventActionCallAccept(:final callKitParams):
        _acceptIncoming(
          Map<String, dynamic>.from(callKitParams.extra ?? {}),
        );
      case CallEventActionCallDecline(:final callKitParams):
        _declineIncoming(
          Map<String, dynamic>.from(callKitParams.extra ?? {}),
        );
      case CallEventActionCallEnded(:final callKitParams):
        _endIncoming(
          Map<String, dynamic>.from(callKitParams.extra ?? {}),
        );
      case CallEventActionCallTimeout(:final id):
        final callId = _callIdFromCallKitId(id);
        if (callId != null) _declineCallId(callId);
      default:
        break;
    }
  }

  int? _callIdFromCallKitId(String id) {
    if (id.startsWith('call-')) return int.tryParse(id.substring(5));
    return int.tryParse(id);
  }

  Future<void> _acceptIncoming(Map<String, dynamic> extra) async {
    final callId = _asInt(extra['call_id']);
    if (callId == null) return;
    if (_acceptedCalls.contains(callId)) return;
    final auth = _auth;
    if (auth == null || !auth.signedIn) {
      _pendingAccept = extra;
      return;
    }
    if (_joining) return;
    _joining = true;
    _acceptedCalls.add(callId);
    try {
      final data = await auth.api.post('calls/$callId/answer');
      final call = data['call'] is Map
          ? Map<String, dynamic>.from(data['call'] as Map)
          : null;
      final jitsi = data['jitsi'] is Map
          ? Map<String, dynamic>.from(data['jitsi'] as Map)
          : null;
      _incoming = null;
      _active = call;
      notifyListeners();
      if (jitsi != null && call != null) {
        await joinJitsi(
          jitsi,
          kind: '${call['kind'] ?? 'voice'}',
          callId: callId,
        );
      }
    } catch (error) {
      debugPrint('Answer call failed: $error');
      await _endCallKit(callId);
    } finally {
      _joining = false;
    }
  }

  Future<void> _declineIncoming(Map<String, dynamic> extra) async {
    final callId = _asInt(extra['call_id']);
    if (callId != null) await _declineCallId(callId);
  }

  Future<void> _declineCallId(int callId) async {
    _incoming = null;
    notifyListeners();
    try {
      await _auth?.api.post('calls/$callId/decline');
    } catch (_) {
      // Best effort: the call may already have ended.
    }
  }

  Future<void> _endIncoming(Map<String, dynamic> extra) async {
    final callId = _asInt(extra['call_id']);
    if (callId != null) await _declineCallId(callId);
  }

  Future<void> _sendHeartbeat(int callId) async {
    try {
      final data = await _auth?.api.post('calls/$callId/heartbeat');
      final status = '${data?['status']}';
      if (status == 'ended' ||
          status == 'missed' ||
          status == 'declined' ||
          status == 'canceled') {
        _heartbeat?.cancel();
        if (_activeMeetCallId == callId) {
          endSignal.value = callId;
        }
      }
    } catch (_) {
      // Transient failures are fine; the backend only expires silent calls.
    }
  }

  // ----- Public actions ---------------------------------------------------

  Future<Map<String, dynamic>?> startDirectCall({
    required int accountId,
    required String kind,
    int? conversationId,
  }) async {
    final auth = _auth;
    if (auth == null) return null;
    final data = await auth.api.post('calls', {
      'account_id': accountId,
      'kind': kind,
      if (conversationId != null) 'conversation_id': conversationId,
    });
    final call = data['call'] is Map
        ? Map<String, dynamic>.from(data['call'] as Map)
        : null;
    final jitsi = data['jitsi'] is Map
        ? Map<String, dynamic>.from(data['jitsi'] as Map)
        : null;
    if (call == null || jitsi == null) return null;
    _outgoing = call;
    notifyListeners();
    final callId = _asInt(call['call_id']);
    if (callId != null) {
      final peer = call['peer'] is Map
          ? Map<String, dynamic>.from(call['peer'] as Map)
          : <String, dynamic>{};
      try {
        await FlutterCallkitIncoming.startCall(
          CallKitParams(
            id: 'call-$callId',
            nameCaller: '${peer['display_name'] ?? 'Panggilan'}',
            appName: 'Sekitarin',
            type: kind == 'video' ? 1 : 0,
            extra: {'call_id': '$callId', 'outgoing': '1'},
            callingNotification: const NotificationParams(
              showNotification: true,
              isShowCallback: false,
              subtitle: 'Memanggil…',
            ),
            android: const AndroidParams(
              isCustomNotification: true,
              isShowLogo: false,
            ),
          ),
        );
      } catch (_) {}
    }
    return {'call': call, 'jitsi': jitsi};
  }

  Future<void> cancelOutgoing(int callId) async {
    _outgoing = null;
    _active = null;
    notifyListeners();
    await _endCallKit(callId);
    try {
      await _auth?.api.post('calls/$callId/end');
    } catch (_) {}
  }

  /// Fallback for a missed WebSocket event while an outgoing call rings.
  Future<void> refreshCall(int callId) async {
    if (_auth == null) return;
    try {
      final data = await _auth!.api.get('calls/$callId');
      if (data is! Map || data['call'] is! Map) return;
      final call = Map<String, dynamic>.from(data['call'] as Map);
      final status = '${call['status']}';
      if (status == 'answered') {
        _outgoing = call;
        _active = call;
        _incoming = null;
      } else if (status == 'ended' ||
          status == 'missed' ||
          status == 'canceled' ||
          status == 'declined') {
        _outgoing = null;
        _active = null;
        _incoming = null;
      } else {
        return;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> startGroupCall(
    int conversationId, {
    String kind = 'voice',
  }) async {
    final auth = _auth;
    if (auth == null) return null;
    final data = await auth.api.post(
      'conversations/$conversationId/call',
      {'kind': kind},
    );
    final jitsi = data['jitsi'] is Map
        ? Map<String, dynamic>.from(data['jitsi'] as Map)
        : null;
    final active = data['active_call'] is Map
        ? Map<String, dynamic>.from(data['active_call'] as Map)
        : null;
    if (active != null) {
      _groupCalls[conversationId] = active;
      notifyListeners();
    }
    if (jitsi == null || active == null) return null;
    final callId = _asInt(active['call_id']);
    await joinJitsi(
      jitsi,
      kind: '${active['kind'] ?? kind}',
      callId: callId,
      group: true,
    );
    return active;
  }

  Future<void> joinGroupCall(int conversationId, int callId) async {
    final auth = _auth;
    if (auth == null) return;
    final data = await auth.api.post('calls/$callId/join');
    final jitsi = data['jitsi'] is Map
        ? Map<String, dynamic>.from(data['jitsi'] as Map)
        : null;
    final active = data['active_call'] is Map
        ? Map<String, dynamic>.from(data['active_call'] as Map)
        : null;
    if (active != null) {
      _groupCalls[conversationId] = active;
      notifyListeners();
    }
    if (jitsi != null && active != null) {
      await joinJitsi(
        jitsi,
        kind: '${active['kind'] ?? 'voice'}',
        callId: callId,
        group: true,
      );
    }
  }

  Future<void> joinActiveCall(Map<String, dynamic> call) async {
    final callId = _asInt(call['call_id']);
    if (callId == null) return;
    try {
      final data = await _auth?.api.get('calls/$callId');
      final jitsi = data is Map && data['jitsi'] is Map
          ? Map<String, dynamic>.from(data['jitsi'] as Map)
          : null;
      if (jitsi != null) {
        await joinJitsi(
          jitsi,
          kind: '${call['kind'] ?? 'voice'}',
          callId: callId,
        );
      }
    } catch (_) {}
  }

  Future<void> joinJitsi(
    Map<String, dynamic> jitsi, {
    required String kind,
    int? callId,
    bool group = false,
  }) async {
    final serverUrl = '${jitsi['server_url'] ?? ''}';
    final room = '${jitsi['room'] ?? ''}';
    final token = '${jitsi['token'] ?? ''}';
    if (room.isEmpty) return;
    _activeMeetCallId = callId;
    _heartbeat?.cancel();
    if (!group && callId != null) {
      _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
        _sendHeartbeat(callId);
      });
    }
    if (callId != null) {
      try {
        await FlutterCallkitIncoming.setCallConnected('call-$callId');
      } catch (_) {}
    }
    try {
      // The native SDK starts a microphone foreground service, so the runtime
      // permissions must be granted before joining.
      await [Permission.microphone, Permission.camera].request();
      // Prefer the official Jitsi SDK (same UI as the Jitsi app). Fall back to
      // the in-app web view when this server/SDK combination cannot connect.
      final host = Uri.tryParse(serverUrl)?.host ?? '';
      final handled = await _joinWebrtc(
        serverUrl: serverUrl,
        host: host,
        room: room,
        token: token,
        kind: kind,
        callId: callId,
      );
      if (!handled) {
        messengerKey.currentState?.showSnackBar(
          const SnackBar(
              content: Text('Panggilan gagal tersambung ke server.')),
        );
      }
    } finally {
      _heartbeat?.cancel();
      _heartbeat = null;
      if (_activeMeetCallId == callId) _activeMeetCallId = null;
      if (callId != null) {
        try {
          await FlutterCallkitIncoming.endCall('call-$callId');
        } catch (_) {}
      }
      if (group && callId != null) {
        try {
          await _auth?.api.post('calls/$callId/leave');
        } catch (_) {}
        for (final entry in _groupCalls.entries) {
          if (_asInt(entry.value['call_id']) == callId) {
            entry.value['joined'] = false;
            final count = _asInt(entry.value['participant_count']) ?? 1;
            entry.value['participant_count'] = count > 0 ? count - 1 : 0;
          }
        }
      } else if (callId != null) {
        try {
          await _auth?.api.post('calls/$callId/end');
        } catch (_) {}
      }
      if (_active != null && _asInt(_active!['call_id']) == callId) {
        _active = null;
      }
      if (_outgoing != null && _asInt(_outgoing!['call_id']) == callId) {
        _outgoing = null;
      }
      notifyListeners();
    }
  }

  /// Opens the custom WebRTC call screen. Returns false when the connection
  /// could not be established so the caller can fall back to the Jitsi web view.
  Future<bool> _joinWebrtc({
    required String serverUrl,
    required String host,
    required String room,
    required String token,
    required String kind,
    int? callId,
  }) async {
    final nav = navigatorKey.currentState;
    if (nav == null || host.isEmpty) return false;
    final auth = _auth;
    final displayName =
        '${auth?.user?['display_name'] ?? auth?.user?['username'] ?? 'Sekitarin'}';
    final result = await nav.push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => WebrtcCallScreen(
          serverUrl: serverUrl,
          host: host,
          xmppDomain: 'meet.jitsi',
          room: room,
          token: token,
          displayName: displayName,
          title: kind == 'video' ? 'Panggilan video' : 'Panggilan suara',
          video: kind == 'video',
          callId: callId,
          onDebug: (stage, payload) {
            unawaited(() async {
              try {
                await _auth?.api.post(
                  'me/call-debug',
                  {'stage': stage, 'room': room, 'payload': payload},
                );
              } catch (_) {}
            }());
          },
        ),
        fullscreenDialog: true,
      ),
    );
    return result ?? false;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value');
  }
}
