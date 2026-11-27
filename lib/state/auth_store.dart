import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/token_store.dart';
import '../core/ws_client.dart';
import '../services/location_service.dart';
import '../services/push_service.dart';
import 'chat_cache.dart';

class AuthStore extends ChangeNotifier {
  AuthStore(this.api, this.store, this.ws) {
    api.onUnauthorized = _refreshSession;
    _wsEventsSub = ws.events.listen(_onWsEvent);
    _pushForegroundSub = PushService.foregroundMessages.listen(
      (_) => _scheduleBadgeRefresh(),
    );
    _pushTokenSub = PushService.tokenRefreshes.listen(_savePushToken);
  }

  final ApiClient api;
  final TokenStore store;
  final WsClient ws;

  Map<String, dynamic>? user;
  List<Map<String, dynamic>> accounts = <Map<String, dynamic>>[];
  int? activeAccountId;
  int unreadNotifications = 0;
  int unreadChatNotifications = 0;
  bool loading = true;
  String? lastError;

  String? _accessToken;
  String? _refreshToken;
  Future<bool>? _refreshFuture;
  StreamSubscription? _wsEventsSub;
  StreamSubscription? _pushForegroundSub;
  StreamSubscription? _pushTokenSub;
  Timer? _badgeRefreshDebounce;
  Timer? _pushRetryTimer;
  int _pushRetryCount = 0;
  Timer? _realtimeTimer;
  bool _realtimeBusy = false;
  bool _locationConsent = false;

  bool get signedIn => _accessToken != null && user != null;

  bool get hasStoredToken => _accessToken != null && _accessToken!.isNotEmpty;

  bool get locationConsent => _locationConsent;

  void _onWsEvent(Map<String, dynamic> event) {
    final name = '${event['event']}';
    if (name != 'message.created' && name != 'notification.created') return;
    _scheduleBadgeRefresh();
  }

  void _scheduleBadgeRefresh() {
    _badgeRefreshDebounce?.cancel();
    _badgeRefreshDebounce = Timer(const Duration(milliseconds: 700), () {
      refresh();
    });
  }

  Future<bool> registerPushToken() async {
    if (!signedIn) return false;
    final token = await PushService.getToken();
    if (token == null || token.isEmpty) return false;
    try {
      await api.post('me/push-token', {'push_token': token});
      _pushRetryCount = 0;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resetPushToken() async {
    if (!signedIn) return false;
    final token = await PushService.refreshToken();
    if (token == null || token.isEmpty) return false;
    try {
      await api.post('me/push-token', {'push_token': token});
      _pushRetryCount = 0;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _registerPushToken() async {
    final registered = await registerPushToken();
    if (registered || !signedIn) return;
    // Firebase may not be ready on the first frame; retry briefly.
    _pushRetryTimer?.cancel();
    if (_pushRetryCount >= 5) return;
    _pushRetryCount++;
    _pushRetryTimer = Timer(const Duration(seconds: 10), () {
      _registerPushToken();
    });
  }

  Future<void> _savePushToken(String token) async {
    if (!signedIn || token.isEmpty) return;
    try {
      await api.post('me/push-token', {'push_token': token});
    } catch (_) {
      // Push registration is best-effort.
    }
  }

  /// Reconnects the realtime socket after the app returns to the foreground or
  /// the connection was dropped.
  Future<void> reconnectRealtime() async {
    if (_accessToken == null || _accessToken!.isEmpty) return;
    await ws.reconnect();
  }

  void clearChatBadge() {
    if (unreadChatNotifications == 0) return;
    unreadChatNotifications = 0;
    notifyListeners();
  }

  Future<void> markChatNotificationsRead({bool force = false}) async {
    if (!signedIn) return;
    if (unreadChatNotifications == 0 && !force) return;
    unreadChatNotifications = 0;
    notifyListeners();
    try {
      await api.post('notifications/read-chat');
    } catch (_) {
      // Next refresh may restore the count; try again when leaving the tab.
    }
  }

  Map<String, dynamic>? get activeAccount {
    for (final account in accounts) {
      if (account['account_id'] == activeAccountId) return account;
    }
    return accounts.isEmpty ? null : accounts.first;
  }

  String get devicePlatform => Platform.isIOS ? 'ios' : 'android';

  Future<void> bootstrap() async {
    loading = true;
    notifyListeners();
    try {
      _accessToken = await store.readAccessToken();
      _refreshToken = await store.readRefreshToken();
      activeAccountId = store.activeAccountId;
      if (_accessToken != null && _accessToken!.isNotEmpty) {
        api.accessToken = _accessToken;
        api.activeAccountId = activeAccountId;
        await _loadMe();
        ws.connect(_accessToken!);
        _startRealtimeTracking();
        _registerPushToken();
      }
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await _clearSession();
      } else {
        lastError =
            'Tidak dapat terhubung ke server. Periksa koneksi lalu coba lagi.';
      }
    } catch (_) {
      lastError =
          'Tidak dapat terhubung ke server. Periksa koneksi lalu coba lagi.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> retryBootstrap() async {
    lastError = null;
    await bootstrap();
  }

  Future<void> login(String email, String password) async {
    loading = true;
    lastError = null;
    notifyListeners();
    try {
      final data = await api.post('auth/login', {
        'email': email.trim(),
        'password': password,
        'device': await _devicePayload(),
      });
      await _applySession(data);
    } on ApiException catch (error) {
      lastError = error.message;
      rethrow;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String passwordConfirmation,
    required String displayName,
    required String username,
  }) async {
    loading = true;
    lastError = null;
    notifyListeners();
    try {
      final data = await api.post('auth/register', {
        'email': email.trim(),
        'password': password,
        'password_confirmation': passwordConfirmation,
        'display_name': displayName.trim(),
        'username': username.trim().toLowerCase(),
        'device': await _devicePayload(),
      });
      await _applySession(data);
    } on ApiException catch (error) {
      lastError = error.message;
      rethrow;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (!signedIn) return;
    try {
      await _loadMe();
      notifyListeners();
    } on ApiException {
      // Keep the last known state; the next authorized call may refresh.
    }
  }

  Future<void> switchAccount(int accountId) async {
    await api.post('accounts/$accountId/activate');
    activeAccountId = accountId;
    api.activeAccountId = accountId;
    await store.saveActiveAccount(accountId);
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.delete('me/push-token');
    } catch (_) {
      // Token cleanup is best-effort.
    }
    try {
      await api.post('auth/logout');
    } catch (_) {
      // Local logout still proceeds.
    }
    await _clearSession();
    notifyListeners();
  }

  Future<void> _applySession(Map<String, dynamic> data) async {
    _accessToken = '${data['access_token'] ?? ''}';
    _refreshToken = '${data['refresh_token'] ?? ''}';
    api.accessToken = _accessToken;
    activeAccountId = data['active_account_id'] is int
        ? data['active_account_id'] as int
        : int.tryParse('${data['active_account_id']}');
    api.activeAccountId = activeAccountId;
    user = data['user'] is Map
        ? Map<String, dynamic>.from(data['user'] as Map)
        : null;
    accounts = _accountList(data['accounts']);
    unreadNotifications = 0;
    await store.saveTokens(
      accessToken: _accessToken ?? '',
      refreshToken: _refreshToken,
    );
    await store.saveActiveAccount(activeAccountId);
    ws.connect(_accessToken ?? '');
    await _loadMe();
    _startRealtimeTracking();
    await _registerPushToken();
  }

  Future<void> _loadMe() async {
    final data = await api.get('me');
    if (data is! Map) return;
    user = data['user'] is Map
        ? Map<String, dynamic>.from(data['user'] as Map)
        : user;
    accounts = _accountList(data['accounts']);
    final active = data['active_account_id'];
    activeAccountId = active is int ? active : int.tryParse('$active');
    api.activeAccountId = activeAccountId;
    unreadNotifications = data['unread_notifications'] is int
        ? data['unread_notifications'] as int
        : 0;
    unreadChatNotifications = data['unread_chat_notifications'] is int
        ? data['unread_chat_notifications'] as int
        : 0;
    final consents = data['consents'];
    _locationConsent = consents is Map &&
        consents['location'] is Map &&
        consents['location']['granted'] == true;
    await store.saveActiveAccount(activeAccountId);
    if (_locationConsent) {
      _syncRealtimeLocations();
    }
  }

  @override
  void dispose() {
    _wsEventsSub?.cancel();
    _pushForegroundSub?.cancel();
    _pushTokenSub?.cancel();
    _badgeRefreshDebounce?.cancel();
    _pushRetryTimer?.cancel();
    _realtimeTimer?.cancel();
    super.dispose();
  }

  void _startRealtimeTracking() {
    _realtimeTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => _syncRealtimeLocations(),
    );
  }

  Future<void> _syncRealtimeLocations() async {
    if (!signedIn || !_locationConsent || _realtimeBusy) return;
    final targets = accounts.where((account) {
      final allowsPresence = account['allows_presence'] == true;
      if (allowsPresence) return account['location_mode'] == 'realtime';
      // Personal accounts follow the phone so nearby posts can find them.
      // Business pins stay where the owner placed them.
      return account['type_code'] == 'personal';
    }).toList();
    if (targets.isEmpty) return;
    _realtimeBusy = true;
    try {
      final position = await LocationService.current();
      if (position == null) return;
      for (final account in targets) {
        final accountId = account['account_id'];
        if (accountId == null) continue;
        final allowsPresence = account['allows_presence'] == true;
        final path = allowsPresence
            ? 'accounts/$accountId/presence'
            : 'accounts/$accountId/location';
        try {
          await api.put(path, {
            'lat': position.latitude,
            'lng': position.longitude,
            if (!allowsPresence) 'source': 'gps',
          });
        } catch (_) {
          // One account failing should not stop the others.
        }
      }
    } finally {
      _realtimeBusy = false;
    }
  }

  Future<bool> _refreshSession() {
    // Refresh tokens rotate on the server, so concurrent 401s must share one
    // refresh. Otherwise the second request sends an already-rotated token and
    // the whole session gets cleared.
    final inFlight = _refreshFuture;
    if (inFlight != null) return inFlight;
    final future = _performRefresh();
    _refreshFuture = future;
    future.whenComplete(() {
      if (identical(_refreshFuture, future)) _refreshFuture = null;
    });
    return future;
  }

  Future<bool> _performRefresh() async {
    final refreshToken = _refreshToken ?? await store.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final data = await api.post('auth/refresh', {
        'refresh_token': refreshToken,
        'device_uuid': store.deviceUuid,
      });
      _accessToken = '${data['access_token'] ?? ''}';
      _refreshToken = '${data['refresh_token'] ?? refreshToken}';
      api.accessToken = _accessToken;
      final active = data['active_account_id'];
      if (active != null) {
        activeAccountId = active is int ? active : int.tryParse('$active');
        api.activeAccountId = activeAccountId;
      }
      await store.saveTokens(
        accessToken: _accessToken ?? '',
        refreshToken: _refreshToken,
      );
      return _accessToken != null && _accessToken!.isNotEmpty;
    } on ApiException catch (error) {
      // Only a rejected refresh token ends the session. Network errors,
      // timeouts, rate limits, and server errors keep the stored session so a
      // later attempt can recover without logging the user out.
      if (error.statusCode == 401 || error.statusCode == 422) {
        await _clearSession();
        notifyListeners();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _clearSession() async {
    ChatCache.clearAll();
    _accessToken = null;
    _refreshToken = null;
    api.accessToken = null;
    api.activeAccountId = null;
    user = null;
    accounts = [];
    activeAccountId = null;
    unreadNotifications = 0;
    unreadChatNotifications = 0;
    _locationConsent = false;
    _realtimeTimer?.cancel();
    _realtimeTimer = null;
    await store.clear();
    await ws.disconnect();
  }

  Future<Map<String, dynamic>> _devicePayload() async {
    String version = '';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      // Keep an empty version when package info is unavailable.
    }
    return {
      'device_uuid': store.deviceUuid,
      'platform': devicePlatform,
      'app_version': version,
    };
  }

  List<Map<String, dynamic>> _accountList(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}
