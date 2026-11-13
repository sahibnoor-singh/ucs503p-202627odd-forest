import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:forest_app/services/api_client.dart';

/// One request the app made, as the server would see it.
class Seen {
  Seen(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;

  String get path => uri.path;
  Map<String, dynamic> get json => body.isEmpty ? {} : jsonDecode(body) as Map<String, dynamic>;
}

/// A scripted backend for tests: register answers by "METHOD /path", read back
/// what the app sent. Unregistered routes answer 404 so a forgotten stub is loud.
class FakeServer {
  final List<Seen> seen = [];
  final Map<String, http.Response Function(Seen)> _routes = {};

  void on(String route, http.Response Function(Seen) answer) => _routes[route] = answer;

  /// Shortcut: JSON body with a status.
  void json(String route, Object body, {int status = 200, Map<String, String>? headers}) =>
      on(route, (_) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', ...?headers}));

  ApiClient client({String? Function()? token, void Function()? onUnauthorized, String devUser = ''}) => ApiClient(
        baseUrl: 'http://test.invalid',
        devUser: devUser,
        tokenProvider: token,
        onUnauthorized: onUnauthorized,
        client: MockClient((request) async {
          final s = Seen(request.method, request.url, request.headers, request.body);
          seen.add(s);
          final answer = _routes['${request.method} ${request.url.path}'];
          return answer == null ? http.Response('{"error":"no stub for ${request.method} ${request.url.path}"}', 404) : answer(s);
        }),
      );

  http.Response let200(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
  http.Response let401(String message) =>
      http.Response(jsonEncode({'error': message}), 401, headers: {'content-type': 'application/json'});

  Seen last(String route) => seen.lastWhere((s) => '${s.method} ${s.path}' == route);
  int count(String route) => seen.where((s) => '${s.method} ${s.path}' == route).length;
}
