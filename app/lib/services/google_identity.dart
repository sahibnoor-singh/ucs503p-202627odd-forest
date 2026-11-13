import 'package:google_sign_in/google_sign_in.dart';

import 'api_client.dart';

/// Gets a Google ID token for our server ("Continue with Google"). The server checks the token with Google, so the
/// app never decides who someone is by itself. Behind an interface so tests can answer without a Google window.
abstract class GoogleIdentity {
  /// An ID token whose audience is [serverClientId] (the Web client id from `GET /api/auth/config`),
  /// or null when the person closes the Google window. Failures are [ApiException]s with words for the person.
  Future<String?> idToken(String serverClientId);
}

class RealGoogleIdentity implements GoogleIdentity {
  bool _ready = false;

  @override
  Future<String?> idToken(String serverClientId) async {
    final google = GoogleSignIn.instance;
    try {
      if (!_ready) {
        await google.initialize(serverClientId: serverClientId);
        _ready = true;
      }
      final account = await google.authenticate();
      final token = account.authentication.idToken;
      // Forget the choice, so the next sign-in lets the person pick the account again.
      await google.signOut();
      if (token == null || token.isEmpty) {
        throw const ApiException('Google did not return a sign-in token. Try again.');
      }
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw ApiException('Google sign-in did not work (${e.code.name}). Try again.');
    }
  }
}
