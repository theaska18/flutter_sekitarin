import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!AppConfig.firebaseConfigured) return;
  await Firebase.initializeApp(options: PushService.options);
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
    if (_initialized || !configured) return;
    try {
      await Firebase.initializeApp(options: options);
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
