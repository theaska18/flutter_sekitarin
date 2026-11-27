import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  String? accessToken;
  int? activeAccountId;
  Future<bool> Function()? onUnauthorized;

  Map<String, String> _headers({bool json = true, String? accountId}) {
    final headers = <String, String>{'Accept': 'application/json'};
    if (json) {
      headers['Content-Type'] = 'application/json';
    }
    if (accessToken != null && accessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    final account = int.tryParse('${accountId ?? ''}') ?? activeAccountId;
    if (account != null) {
      headers['X-Account-Id'] = account.toString();
    }
    return headers;
  }

  Future<dynamic> get(
    String path, {
    Map<String, String>? query,
    String? accountId,
  }) {
    return _send('GET', path, query: query, accountId: accountId);
  }

  Future<Map<String, dynamic>> post(
    String path, [
    Object? body,
    String? accountId,
  ]) async {
    final result = await _send('POST', path, body: body, accountId: accountId);
    return _asMap(result);
  }

  Future<Map<String, dynamic>> patch(
    String path, [
    Object? body,
    String? accountId,
  ]) async {
    final result = await _send('PATCH', path, body: body, accountId: accountId);
    return _asMap(result);
  }

  Future<Map<String, dynamic>> put(
    String path, [
    Object? body,
    String? accountId,
  ]) async {
    final result = await _send('PUT', path, body: body, accountId: accountId);
    return _asMap(result);
  }

  Future<Map<String, dynamic>> delete(String path, {String? accountId}) async {
    final result = await _send('DELETE', path, accountId: accountId);
    return _asMap(result);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool retried = false,
    String? accountId,
  }) async {
    final uri = AppConfig.apiUri(path, query);
    late http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _http.get(
            uri,
            headers: _headers(json: false, accountId: accountId),
          );
          break;
        case 'POST':
          response = await _http.post(
            uri,
            headers: _headers(accountId: accountId),
            body: body == null ? null : jsonEncode(body),
          );
          break;
        case 'PATCH':
          response = await _http.patch(
            uri,
            headers: _headers(accountId: accountId),
            body: body == null ? null : jsonEncode(body),
          );
          break;
        case 'PUT':
          response = await _http.put(
            uri,
            headers: _headers(accountId: accountId),
            body: body == null ? null : jsonEncode(body),
          );
          break;
        case 'DELETE':
          response = await _http.delete(
            uri,
            headers: _headers(json: false, accountId: accountId),
          );
          break;
        default:
          throw ApiException(0, 'method_not_allowed', 'Metode tidak didukung.');
      }
    } on TimeoutException {
      throw ApiException(
        0,
        'timeout',
        'Server tidak merespons (timeout). Periksa koneksi lalu coba lagi.',
      );
    } on HandshakeException {
      throw ApiException(
        0,
        'tls_error',
        'Koneksi HTTPS gagal. Periksa tanggal & jam HP, lalu coba lagi.',
      );
    } on SocketException {
      throw ApiException(
        0,
        'network_error',
        'Tidak dapat terhubung ke server (jaringan/DNS). Periksa koneksi internet.',
      );
    } catch (error) {
      if (error is ApiException) rethrow;
      throw ApiException(
        0,
        'network_error',
        'Tidak dapat terhubung ke server: $error',
      );
    }

    final text = response.body.trim();
    dynamic decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        decoded = null;
      }
    }
    if (response.statusCode == 401 &&
        !retried &&
        !path.startsWith('auth/') &&
        onUnauthorized != null) {
      final refreshed = await onUnauthorized!();
      if (refreshed) {
        return _send(
          method,
          path,
          body: body,
          query: query,
          retried: true,
          accountId: accountId,
        );
      }
    }
    if (response.statusCode >= 400) {
      final error = decoded is Map ? decoded['error'] : null;
      throw ApiException(
        response.statusCode,
        error is Map ? '${error['code']}' : 'http_${response.statusCode}',
        error is Map ? '${error['message']}' : 'Permintaan gagal.',
        error is Map && error['fields'] is Map
            ? Map<String, dynamic>.from(error['fields'] as Map)
            : null,
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> uploadFile(
    String path, {
    required String filePath,
    required String purpose,
    String field = 'file',
  }) async {
    final request = http.MultipartRequest('POST', AppConfig.apiUri(path));
    request.headers.addAll(_headers(json: false));
    request.fields['purpose'] = purpose;
    request.files.add(await http.MultipartFile.fromPath(field, filePath));
    late http.StreamedResponse streamed;
    try {
      streamed = await request.send().timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw ApiException(0, 'timeout', 'Upload timeout.');
    } catch (_) {
      throw ApiException(0, 'network_error', 'Upload gagal.');
    }
    final response = await http.Response.fromStream(streamed);
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final error = decoded is Map ? decoded['error'] : null;
      throw ApiException(
        response.statusCode,
        error is Map ? '${error['code']}' : 'upload_failed',
        error is Map ? '${error['message']}' : 'Upload gagal.',
      );
    }
    return _asMap(decoded);
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }
}
