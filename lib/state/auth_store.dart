import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/token_store.dart';
import '../core/ws_client.dart';
import '../services/location_service.dart';

class AuthStore extends ChangeNotifier {
  AuthStore(this.api, this.store, this.ws) {
    api.onUnauthorized = _refreshSession;
  }

  final ApiClient api;
  final TokenStore store;
  final WsClient ws;

  Map<String, dynamic>? user;
  List<Map<String, dynamic>> accounts = <Map<String, dynamic>>[];
  int? activeAccountId;
  int unreadNotifications = 0;
  bool loading = true;
  String? lastError;

  String? _accessToken;
  String? _refreshToken;
  Timer? _realtimeTimer;
  bool _realtimeBusy = false;
  bool _locationConsent = false;

  bool get signedIn => _accessToken != null && user != null;

  bool get locationConsent => _locationConsent;

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
      }
    } catch (_) {
      await _clearSession();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    loading = true;
    lastError = null;
    notifyListeners();
    try {
      final data = await api.post('auth/login', {
        'email': email.trim(),
        'password': password,
        'device': _devicePayload(),
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
        'device': _devicePayload(),
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
    final consents = data['consents'];
    _locationConsent = consents is Map &&
        consents['location'] is Map &&
        consents['location']['granted'] == true;
    await store.saveActiveAccount(activeAccountId);
    if (_locationConsent) {
      _syncRealtimeLocations();
    }
  }

  void _startRealtimeTracking() {
    _realtimeTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => _syncRealtimeLocations(),
    );
  }

  Future<void> _syncRealtimeLocations() async {
    if (!signedIn || !_locationConsent || _realtimeBusy) return;
    final realtimeAccounts = accounts.where((account) {
      return account['location_mode'] == 'realtime';
    }).toList();
    if (realtimeAccounts.isEmpty) return;
    _realtimeBusy = true;
    try {
      final position = await LocationService.current();
      if (position == null) return;
      for (final account in realtimeAccounts) {
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

  Future<bool> _refreshSession() async {
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
    } catch (_) {
      await _clearSession();
      notifyListeners();
      return false;
    }
  }

  Future<void> _clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    api.accessToken = null;
    api.activeAccountId = null;
    user = null;
    accounts = [];
    activeAccountId = null;
    unreadNotifications = 0;
    _locationConsent = false;
    _realtimeTimer?.cancel();
    _realtimeTimer = null;
    await store.clear();
    await ws.disconnect();
  }

  Map<String, dynamic> _devicePayload() => {
        'device_uuid': store.deviceUuid,
        'platform': devicePlatform,
        'app_version': '0.10.1',
      };

  List<Map<String, dynamic>> _accountList(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}
