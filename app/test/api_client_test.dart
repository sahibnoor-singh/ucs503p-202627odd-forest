import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:forest_app/services/api_client.dart';

import 'support/fake_server.dart';

void main() {
  test('a logged-in person sends their token and never the dev header', () async {
    final server = FakeServer()..json('GET /api/x', {'ok': true});
    final api = server.client(token: () => 'secret-token', devUser: 'me_dev');
    await api.getJson('/api/x');
    final headers = server.last('GET /api/x').headers;
    expect(headers['Authorization'], 'Bearer secret-token');
    expect(headers.containsKey('X-Dev-User'), isFalse);
  });

  test('without a token the dev shortcut is used, and with neither nothing is sent', () async {
    final server = FakeServer()..json('GET /api/x', {});
    await server.client(devUser: 'me_dev').getJson('/api/x');
    expect(server.last('GET /api/x').headers['X-Dev-User'], 'me_dev');
    expect(server.last('GET /api/x').headers.containsKey('Authorization'), isFalse);

    final anon = FakeServer()..json('GET /api/x', {});
    await anon.client().getJson('/api/x');
    expect(anon.last('GET /api/x').headers.containsKey('Authorization'), isFalse);
    expect(anon.last('GET /api/x').headers.containsKey('X-Dev-User'), isFalse);
  });

  test('the token is read per request, so a new login is used immediately', () async {
    final server = FakeServer()..json('GET /api/x', {});
    String? token;
    final api = server.client(token: () => token);
    await api.getJson('/api/x');
    token = 'later';
    await api.getJson('/api/x');
    expect(server.seen.first.headers.containsKey('Authorization'), isFalse);
    expect(server.seen.last.headers['Authorization'], 'Bearer later');
  });

  test('401 on a request that carried a token fires onUnauthorized; without a token it does not', () async {
    var fired = 0;
    final server = FakeServer()..json('GET /api/me', {'error': 'Invalid or expired token'}, status: 401);
    final withToken = server.client(token: () => 't', onUnauthorized: () => fired++);
    await expectLater(withToken.getJson('/api/me'), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, '401', true)));
    expect(fired, 1);

    final anon = server.client(onUnauthorized: () => fired++);
    await expectLater(anon.getJson('/api/me'), throwsA(isA<ApiException>()));
    expect(fired, 1, reason: 'a wrong password at login must not look like an expired session');
  });

  test('errors carry the server message, field, flags and wait time', () async {
    final server = FakeServer()
      ..json('POST /a', {'error': 'You must be 18 or older.', 'field': 'dob', 'tooYoung': true}, status: 400)
      ..json('POST /b', {'error': 'Slow down', 'retryAfterSec': 12}, status: 429)
      ..on('POST /c', (_) => http.Response('<html>bad gateway</html>', 502));
    final api = server.client();

    final a = await _failure(api.sendJson('POST', '/a'));
    expect(a.message, 'You must be 18 or older.');
    expect(a.field, 'dob');
    expect(a.tooYoung, isTrue);

    final b = await _failure(api.sendJson('POST', '/b'));
    expect(b.isRateLimited, isTrue);
    expect(b.shouldBackOff, isTrue);
    expect(b.backOff(), const Duration(seconds: 12));

    final c = await _failure(api.sendJson('POST', '/c'));
    expect(c.message, contains('502')); // never shows HTML to the person
    expect(c.field, isNull);
  });

  test('backOff is clamped to between 1 and 60 seconds', () {
    expect(const ApiException('x', retryAfterSec: 9999).backOff(), const Duration(seconds: 60));
    expect(const ApiException('x', retryAfterSec: 0).backOff(), const Duration(seconds: 1));
    expect(const ApiException('x').backOff(), const Duration(seconds: 15));
  });

  test('relative media urls are resolved against the server, absolute ones are left alone', () {
    final api = FakeServer().client();
    expect(api.resolveUrl('/uploads/a.mp4'), 'http://test.invalid/uploads/a.mp4');
    expect(api.resolveUrl('https://cdn.example/a.mp4'), 'https://cdn.example/a.mp4');
  });

  test('a down server becomes a readable error', () async {
    final api = ApiClient(
      baseUrl: 'http://test.invalid/',
      devUser: '',
      client: _Throwing(),
    );
    expect(api.baseUrl, 'http://test.invalid'); // trailing slash removed
    await expectLater(api.getJson('/api/x'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains("Can't reach"))));
    expect(await api.health(), isFalse);
  });
}

class _Throwing extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => throw http.ClientException('no route');
}

/// The ApiException a call fails with (the test fails if it succeeds).
Future<ApiException> _failure(Future<Object?> call) async {
  try {
    await call;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected the call to fail');
}
