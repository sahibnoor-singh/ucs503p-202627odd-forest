import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

/// Any non-2xx answer, or a network failure, from the app API. [message] is
/// safe to show to the user.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.retryAfterSec, this.details});

  final String message;
  final int? statusCode;

  /// How long the server asked us to wait (`Retry-After` header or the
  /// `retryAfterSec` field), on a 429 or 503.
  final int? retryAfterSec;

  /// The whole error body (`{error, field?, reason?, tooYoung?, …}`) when the
  /// server sent JSON; null for network errors.
  final Map<String, dynamic>? details;

  /// Which input is at fault (`phone`, `username`, `dob`, …), when the server says.
  String? get field => details?['field'] as String?;

  /// `dob` rejected because the person is under 18.
  bool get tooYoung => details?['tooYoung'] == true;

  bool get isUnauthorized => statusCode == 401;

  /// 429: too many requests, too many unfinished videos, or a login lock-out.
  bool get isRateLimited => statusCode == 429;

  /// 503: the server's video queue is full.
  bool get isBusy => statusCode == 503;

  /// "Come back later" answers: never retry these in a loop.
  bool get shouldBackOff => isRateLimited || isBusy;

  /// How long to leave the server alone after this error: what it asked for,
  /// else [fallback]; never less than a second, never more than a minute.
  Duration backOff({Duration fallback = const Duration(seconds: 15)}) {
    final secs = retryAfterSec ?? fallback.inSeconds;
    return Duration(seconds: secs.clamp(1, 60));
  }

  @override
  String toString() => message;
}

/// What the server's upload check expects in the file's type (`package:http` would send `application/octet-stream`, which the
/// server refuses for photos). Judged by the file name's ending; anything else is sent as plain bytes.
MediaType uploadTypeOf(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 || dot < path.lastIndexOf(RegExp(r'[\\/]')) ? '' : path.substring(dot + 1).toLowerCase();
  const types = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    'mkv': 'video/x-matroska',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
  };
  return MediaType.parse(types[ext] ?? 'application/octet-stream');
}

/// HTTP client for the app API in `app/backend` (contract: `docs/api.md`).
///
/// Run-time settings, passed with `--dart-define`:
///  * `API_BASE_URL`: default `http://10.0.2.2:3000` (the Android emulator's
///    address for your PC). On a USB phone run `adb reverse tcp:3000 tcp:3000`
///    and pass `--dart-define=API_BASE_URL=http://localhost:3000`.
///  * `DEV_USER`: DEVELOPMENT ONLY shortcut that skips the login screen and
///    sends `X-Dev-User: <name>` (see docs/api.md). Empty by default, so a normal
///    run shows the real login. Ignored in release builds; the server also
///    ignores the header in production.
///
/// Who the request is from:
///  * a signed-in person: `Authorization: Bearer <token>` (from [tokenProvider]);
///  * otherwise the dev shortcut above, when it is set;
///  * otherwise nobody (public endpoints only).
/// If the server answers 401 to a request that carried a token, the token is
/// dead (expired, or the account is gone): [onUnauthorized] fires so the app
/// can go back to the login screen. It never fires for a request without one.
class ApiClient {
  ApiClient({
    String? baseUrl,
    String? devUser,
    http.Client? client,
    this.tokenProvider,
    this.onUnauthorized,
  })  : baseUrl = _withoutTrailingSlash(baseUrl ?? defaultBaseUrl),
        devUser = devUser ?? defaultDevUser,
        _client = client ?? http.Client();

  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  /// Only honoured in debug and profile builds (profile is for measuring speed, never shipped), so a release build
  /// can never carry it.
  static const defaultDevUser = kReleaseMode
      ? ''
      : String.fromEnvironment('DEV_USER');

  static const _readTimeout = Duration(seconds: 20);
  static const _uploadTimeout = Duration(minutes: 3);

  final String baseUrl;
  final String devUser;
  final http.Client _client;

  /// Returns the current login token, or null when signed out. Called for every
  /// request, so a new login is picked up without rebuilding the client.
  final String? Function()? tokenProvider;

  /// Called after a 401 on a request that had sent a token.
  final void Function()? onUnauthorized;

  static String _withoutTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  Map<String, String> get _headers {
    final token = tokenProvider?.call();
    return {
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty)
        'Authorization': 'Bearer $token'
      else if (devUser.isNotEmpty)
        'X-Dev-User': devUser,
    };
  }

  /// True when a signed-in person (not the dev shortcut) is making requests.
  bool get hasToken => (tokenProvider?.call() ?? '').isNotEmpty;

  /// Media URLs in the API are relative (`/uploads/x.mp4`).
  String resolveUrl(String pathOrUrl) =>
      pathOrUrl.startsWith('http') ? pathOrUrl : '$baseUrl$pathOrUrl';

  // ---- JSON helpers used by the repository (docs/api.md endpoints) ----

  Future<Object?> getJson(String path, {Map<String, String>? query}) {
    return _send(http.Request('GET', _uri(path, query)));
  }

  Future<Object?> sendJson(String method, String path, {Object? body}) {
    final request = http.Request(method, _uri(path));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    return _send(request);
  }

  Future<Object?> postMultipart(
    String path, {
    required Map<String, String> fields,
    String? filePath,
    String fileField = 'video',
  }) async {
    final request = http.MultipartRequest('POST', _uri(path))
      ..fields.addAll(fields);
    if (filePath != null) {
      request.files.add(await http.MultipartFile.fromPath(fileField, filePath));
    }
    return _send(request, timeout: _uploadTimeout);
  }

  /// Like [postMultipart] but with several files, each under its own form field (the editor sends `photos` once per
  /// photo, plus `music` and `video`).
  Future<Object?> postMultipartFiles(
    String path, {
    required Map<String, String> fields,
    List<({String field, String path})> files = const [],
  }) async {
    final request = http.MultipartRequest('POST', _uri(path))..fields.addAll(fields);
    for (final f in files) {
      request.files.add(await http.MultipartFile.fromPath(f.field, f.path, contentType: uploadTypeOf(f.path)));
    }
    return _send(request, timeout: _uploadTimeout);
  }

  /// In a debug build the person running it is a developer: say what usually fixes this.
  String get _unreachable => kDebugMode
      ? "Can't reach the server at $baseUrl. Is the backend running? (see docs/RUN_LOCALLY.md)"
      : "Can't reach FOREST. Check your internet connection and try again.";

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$baseUrl$path');
    return (query == null || query.isEmpty)
        ? uri
        : uri.replace(queryParameters: query);
  }

  Future<Object?> _send(
    http.BaseRequest request, {
    Duration timeout = _readTimeout,
  }) async {
    request.headers.addAll(_headers);
    final sentToken = request.headers.containsKey('Authorization');
    try {
      final streamed = await _client.send(request).timeout(timeout);
      final response =
          await http.Response.fromStream(streamed).timeout(timeout);
      Object? decoded;
      if (response.body.isNotEmpty) {
        try {
          decoded = jsonDecode(response.body);
        } on FormatException {
          decoded = null;
        }
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }
      final serverMessage =
          decoded is Map && decoded['error'] is String ? decoded['error'] as String : null;
      final status = response.statusCode;
      if (status == 401 && sentToken) onUnauthorized?.call();
      final retryAfter = _retryAfterSec(decoded, response.headers['retry-after']);
      throw ApiException(
        // The server's own words first; these only cover an answer with no body
        // (for example from a proxy in front of it).
        serverMessage ??
            switch (status) {
              429 => 'You are going too fast. Wait a moment and try again.',
              503 => 'The server is busy right now. Try again in a moment.',
              _ => 'Something went wrong (HTTP $status).',
            },
        statusCode: status,
        retryAfterSec: retryAfter,
        details: decoded is Map<String, dynamic> ? decoded : null,
      );
    } on TimeoutException {
      throw const ApiException('The server took too long to answer.');
    } on SocketException {
      throw ApiException(_unreachable);
    } on http.ClientException {
      throw ApiException(_unreachable);
    }
  }

  /// `retryAfterSec` in the body, else the `Retry-After` header (seconds).
  static int? _retryAfterSec(Object? body, String? header) {
    final fromBody = body is Map ? body['retryAfterSec'] : null;
    if (fromBody is num && fromBody > 0) return fromBody.ceil();
    final fromHeader = int.tryParse(header?.trim() ?? '');
    return (fromHeader != null && fromHeader > 0) ? fromHeader : null;
  }

  /// Fast "is the server up" check for the Account screen. Never throws.
  Future<bool> health() async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } on Object {
      return false;
    }
  }
}
