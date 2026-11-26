import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class TokenStore {
  TokenStore(this._secure, this._prefs);

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  static const _accessKey = 'sekitar_access_token';
  static const _refreshKey = 'sekitar_refresh_token';
  static const _accountKey = 'sekitar_active_account';
  static const _deviceKey = 'sekitar_device_uuid';

  static Future<TokenStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return TokenStore(const FlutterSecureStorage(), prefs);
  }

  Future<String?> readAccessToken() => _secure.read(key: _accessKey);
  Future<String?> readRefreshToken() => _secure.read(key: _refreshKey);

  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _secure.write(key: _accessKey, value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _secure.write(key: _refreshKey, value: refreshToken);
    }
  }

  int? get activeAccountId {
    final value = _prefs.getInt(_accountKey);
    return value;
  }

  Future<void> saveActiveAccount(int? accountId) async {
    if (accountId == null) {
      await _prefs.remove(_accountKey);
    } else {
      await _prefs.setInt(_accountKey, accountId);
    }
  }

  String get deviceUuid {
    final existing = _prefs.getString(_deviceKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final generated = const Uuid().v4();
    _prefs.setString(_deviceKey, generated);
    return generated;
  }

  Future<void> clear() async {
    await _secure.delete(key: _accessKey);
    await _secure.delete(key: _refreshKey);
    await _prefs.remove(_accountKey);
  }
}
