import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sekitar_app/core/api_client.dart';
import 'package:sekitar_app/core/api_exception.dart';

void main() {
  test('ApiClient sends bearer and active account headers', () async {
    late http.BaseRequest captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({'ok': true}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = ApiClient(client: client)
      ..accessToken = 'token-123'
      ..activeAccountId = 7;

    final result = await api.get('me');

    expect(result, isA<Map>());
    expect(captured.headers['Authorization'], 'Bearer token-123');
    expect(captured.headers['X-Account-Id'], '7');
  });

  test('ApiClient maps error envelopes to ApiException', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {
            'code': 'validation_error',
            'message': 'Data tidak valid.',
            'fields': {'email': 'Email sudah terdaftar.'},
          },
        }),
        422,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = ApiClient(client: client);

    await expectLater(
      api.post('auth/register', {'email': 'x'}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 422)
            .having((e) => e.code, 'code', 'validation_error')
            .having(
                (e) => e.fields?['email'], 'field', 'Email sudah terdaftar.'),
      ),
    );
  });

  test('ApiClient retries once after a successful token refresh', () async {
    var attempts = 0;
    final client = MockClient((request) async {
      attempts++;
      if (attempts == 1) {
        return http.Response(
          jsonEncode({
            'error': {'code': 'unauthenticated', 'message': 'expired'},
          }),
          401,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'ok': true}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    late ApiClient api;
    api = ApiClient(client: client)
      ..accessToken = 'old'
      ..onUnauthorized = () async {
        api.accessToken = 'new';
        return true;
      };

    final result = await api.get('me');

    expect(result['ok'], true);
    expect(attempts, 2);
  });
}
