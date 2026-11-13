import 'api_client.dart';

/// The addresses people outside the app use: a link to a debate. The server says what its public address is
/// (`publicBaseUrl` in `GET /api/auth/config`); until we have heard, the server we talk to is used.
class PublicLinks {
  PublicLinks._();

  static String? _base;

  /// Called when the server's config arrives.
  static void learn(String? publicBaseUrl) {
    final v = publicBaseUrl?.trim();
    if (v != null && v.isNotEmpty) _base = v.replaceAll(RegExp(r'/+$'), '');
  }

  static bool get known => _base != null;

  /// For tests: forget what was learnt.
  static void forget() => _base = null;

  /// The public page of one debate.
  static String debate(String postId) => '${_base ?? ApiClient.defaultBaseUrl}/p/$postId';
}
