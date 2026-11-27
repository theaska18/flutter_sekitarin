import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../config.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (AppConfig.firebaseConfigured) {
      await Firebase.initializeApp(options: PushService.options);
    } else {
      await Firebase.initializeApp();
    }
  } catch (_) {
    // No Firebase configuration on this build.
  }
  try {
    final data = message.data;
    final callEvent = data['call_event'];
    if (callEvent == 'incoming') {
      await _showBackgroundIncomingCall(data);
    } else if (callEvent == 'cancel') {
      final callId = data['call_id'];
      if (callId != null) {
        await FlutterCallkitIncoming.endCall('call-$callId');
      }
    }
  } catch (error) {
    debugPrint('Background call handling failed: $error');
  }
}

Future<void> _showBackgroundIncomingCall(Map<String, dynamic> data) async {
  final callId = data['call_id'];
  if (callId == null) return;
  final avatarId = int.tryParse('${data['caller_avatar_media_id'] ?? ''}');
  final params = CallKitParams(
    id: 'call-$callId',
    nameCaller: '${data['caller_name'] ?? 'Panggilan'}',
    appName: 'Sekitarin',
    avatar: avatarId != null
        ? AppConfig.absoluteUrl('/api/v1/media/$avatarId')
        : null,
    handle:
        data['caller_handle'] != null && '${data['caller_handle']}'.isNotEmpty
            ? '@${data['caller_handle']}'
            : null,
    type: data['kind'] == 'video' ? 1 : 0,
    duration: 45000,
    extra: {
      'call_id': '$callId',
      'conversation_id': '${data['conversation_id'] ?? 0}',
      'kind': '${data['kind'] ?? 'voice'}',
      'room': '${data['room'] ?? ''}',
      'server_url': '${data['server_url'] ?? ''}',
      'token': '${data['token'] ?? ''}',
      'caller_name': '${data['caller_name'] ?? 'Panggilan'}',
    },
    missedCallNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: true,
      subtitle: 'Panggilan tak terjawab',
      callbackText: 'Hubungi lagi',
    ),
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
      supportsHolding: false,
      supportsGrouping: false,
    ),
  );
  await FlutterCallkitIncoming.showCallkitIncoming(params);
}

/// FCM setup. When Firebase build-time values are absent the service is a
/// no-op so the app can still run without push credentials.
class PushService {
  static bool _initialized = false;
  static final _foreground = StreamController<RemoteMessage>.broadcast();
  static final _tokenRefreshes = StreamController<String>.broadcast();

  /// Conversation requested from a tapped system notification.
  static final ValueNotifier<int?> conversationToOpen = ValueNotifier(null);

  static bool get configured => AppConfig.firebaseConfigured;

  static bool get ready => _initialized;

  static Future<void> _initializeFirebase() async {
    if (AppConfig.firebaseConfigured) {
      await Firebase.initializeApp(options: options);
      return;
    }
    // Uses android/app/google-services.json (Android) or
    // GoogleService-Info.plist (iOS) when build-time values are absent.
    await Firebase.initializeApp();
  }

  static FirebaseOptions get options => FirebaseOptions(
        apiKey: AppConfig.firebaseApiKey,
        appId: AppConfig.firebaseAppId,
        messagingSenderId: AppConfig.firebaseMessagingSenderId,
        projectId: AppConfig.firebaseProjectId,
        storageBucket: AppConfig.firebaseStorageBucket.isEmpty
            ? null
            : AppConfig.firebaseStorageBucket,
        iosBundleId: AppConfig.firebaseIosBundleId,
      );

  static Stream<RemoteMessage> get foregroundMessages => _foreground.stream;
  static Stream<String> get tokenRefreshes => _tokenRefreshes.stream;

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _initializeFirebase();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler,
      );
      FirebaseMessaging.onMessage.listen(_foreground.add);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpened);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _handleOpened(initial);
      messaging.onTokenRefresh.listen(_tokenRefreshes.add);
      _initialized = true;
    } catch (error) {
      debugPrint('Push initialization failed: $error');
    }
  }

  /// Forces FCM to discard the cached token and issue a new one.
  static Future<String?> refreshToken() async {
    if (!_initialized) return null;
    try {
      await FirebaseMessaging.instance.deleteToken();
      return await FirebaseMessaging.instance.getToken();
    } catch (error) {
      debugPrint('FCM token refresh failed: $error');
      return null;
    }
  }

  static Future<String?> getToken() async {
    if (!_initialized) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (error) {
      debugPrint('FCM token unavailable: $error');
      return null;
    }
  }

  static void _handleOpened(RemoteMessage message) {
    final raw = message.data['conversation_id'];
    final conversationId = int.tryParse('$raw');
    if (conversationId != null && conversationId > 0) {
      conversationToOpen.value = conversationId;
    }
  }
}
