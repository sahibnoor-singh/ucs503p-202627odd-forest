import '../models/user.dart';
import '../services/api_client.dart';
import '../services/public_links.dart';

/// What `login` and `signup` hand back: a token to keep and the person it is for.
class AuthResult {
  const AuthResult({required this.token, required this.user});
  final String token;
  final User user;
}

/// Answer of the live username check.
class UsernameCheck {
  const UsernameCheck({required this.available, this.reason, this.suggestions = const []});
  final bool available;

  /// `TAKEN`, `INVALID` or `RESERVED` when not available.
  final String? reason;

  /// Free alternatives, only offered when the name is taken.
  final List<String> suggestions;
}

/// How this server checks that a new person owns what they typed: by a code in their inbox, or by SMS.
enum SignupChannel { email, phone }

/// What the server tells a signed-out app (`GET /api/auth/config`).
class AuthConfig {
  const AuthConfig({this.channel = SignupChannel.email, this.googleClientId});
  final SignupChannel channel;

  /// The Web OAuth client id to ask Google for a token with; null means "Continue with Google" is off.
  final String? googleClientId;
}

/// A person Google vouched for who has no FOREST account yet: they still pick a username and give a birth date.
class GoogleNewPerson {
  const GoogleNewPerson({required this.signupToken, required this.email, required this.fullName});
  final String signupToken;
  final String email;
  final String fullName;
}

/// Either the person had an account and is now logged in, or they are new and must finish a profile.
class GoogleOutcome {
  const GoogleOutcome({this.login, this.newPerson});
  final AuthResult? login;
  final GoogleNewPerson? newPerson;
}

class OtpSent {
  const OtpSent({required this.contact, required this.resendInSec, this.devCode});

  /// The number (`+91…`) or e-mail address as the server normalised it. Use this one from now on.
  final String contact;
  final int resendInSec;

  /// Only present when the server runs the development (console) provider.
  /// A real provider never sends it, so it is safe to auto-fill when non-null.
  final String? devCode;
}

/// The sign-up and login calls of `docs/api.md` ("Accounts").
///
/// Errors surface as [ApiException]. When the server says which input is at
/// fault it adds a `field`, available as [ApiException.field].
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  static Map<String, dynamic> _map(Object? json) {
    if (json is Map<String, dynamic>) return json;
    throw const ApiException('The server sent an answer the app does not understand.');
  }

  Future<UsernameCheck> usernameAvailable(String username) async {
    final json = _map(await _api.getJson('/api/auth/username-available', query: {'u': username}));
    return UsernameCheck(
      available: json['available'] == true,
      reason: json['reason'] as String?,
      suggestions: [
        for (final s in (json['suggestions'] as List<dynamic>? ?? const [])) s.toString(),
      ],
    );
  }

  /// What this server asks new people to verify, and whether Google sign-in is on (`GET /api/auth/config`).
  /// An older or unreachable server counts as e-mail with no Google button.
  Future<AuthConfig> config() async {
    try {
      final json = _map(await _api.getJson('/api/auth/config'));
      PublicLinks.learn(json['publicBaseUrl'] as String?);
      final client = json['googleClientId'];
      return AuthConfig(
        channel: json['signupChannel'] == 'phone' ? SignupChannel.phone : SignupChannel.email,
        googleClientId: client is String && client.isNotEmpty ? client : null,
      );
    } on ApiException {
      return const AuthConfig();
    }
  }

  /// Sends the ID token Google gave the app. A known person is logged in; a new one gets a sign-up token.
  Future<GoogleOutcome> googleSignIn(String idToken) async {
    final json = _map(await _api.sendJson('POST', '/api/auth/google', body: {'idToken': idToken}));
    if (json['needsProfile'] == true) {
      final token = json['signupToken'];
      if (token is! String || token.isEmpty) {
        throw const ApiException('The server sent an answer the app does not understand.');
      }
      return GoogleOutcome(
        newPerson: GoogleNewPerson(
          signupToken: token,
          email: json['email'] as String? ?? '',
          fullName: json['fullName'] as String? ?? '',
        ),
      );
    }
    return GoogleOutcome(login: _result(json));
  }

  /// Whether this account has a password (a Google-only account does not), so the delete dialog asks for the right proof.
  Future<bool> hasPassword() async {
    try {
      final json = _map(await _api.getJson('/api/me'));
      final account = json['account'];
      return account is Map<String, dynamic> ? account['hasPassword'] != false : true;
    } on ApiException {
      return true;
    }
  }

  Future<OtpSent> sendCode(String phone) async {
    final json = _map(await _api.sendJson('POST', '/api/auth/otp/send', body: {'phone': phone}));
    return OtpSent(
      contact: json['phone'] as String? ?? phone,
      resendInSec: (json['resendInSec'] as num?)?.toInt() ?? 30,
      devCode: json['devCode'] as String?,
    );
  }

  Future<OtpSent> sendEmailCode(String email) async {
    final json = _map(await _api.sendJson('POST', '/api/auth/email/send', body: {'email': email}));
    return OtpSent(
      contact: json['email'] as String? ?? email,
      resendInSec: (json['resendInSec'] as num?)?.toInt() ?? 30,
      devCode: json['devCode'] as String?,
    );
  }

  /// Returns the short-lived sign-up token. Keep it in memory only.
  Future<String> verifyCode(String phone, String code) => _verify('/api/auth/otp/verify', {'phone': phone, 'code': code});

  Future<String> verifyEmailCode(String email, String code) => _verify('/api/auth/email/verify', {'email': email, 'code': code});

  Future<String> _verify(String path, Map<String, String> body) async {
    final json = _map(await _api.sendJson('POST', path, body: body));
    final token = json['signupToken'];
    if (token is! String || token.isEmpty) {
      throw const ApiException('The server sent an answer the app does not understand.');
    }
    return token;
  }

  Future<AuthResult> signUp({
    required String signupToken,
    required String fullName,
    required String username,
    required String dob,
    String? password,
    String? email,
    String? inviteCode,
  }) async {
    final json = _map(await _api.sendJson('POST', '/api/auth/signup', body: {
      'signupToken': signupToken,
      'fullName': fullName,
      'username': username,
      'dob': dob,
      if (password != null && password.isNotEmpty) 'password': password,
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      if (inviteCode != null && inviteCode.trim().isNotEmpty) 'inviteCode': inviteCode.trim(),
    }));
    return _result(json);
  }

  Future<AuthResult> login(String identifier, String password) async {
    final json = _map(await _api.sendJson('POST', '/api/auth/login', body: {
      'identifier': identifier,
      'password': password,
    }));
    return _result(json);
  }

  /// Permanently deletes the signed-in account (docs/api.md `DELETE /api/me`). The password is
  /// asked for again so a phone left unlocked cannot erase an account.
  Future<void> deleteAccount(String password) async {
    await _api.sendJson('DELETE', '/api/me', body: {'password': password});
  }

  /// Deletes the account of someone who signed up with Google and has no password: a fresh Google token is the proof.
  Future<void> deleteAccountWithGoogle(String idToken) async {
    await _api.sendJson('DELETE', '/api/me', body: {'idToken': idToken});
  }

  static AuthResult _result(Map<String, dynamic> json) {
    final token = json['token'];
    if (token is! String || token.isEmpty) {
      throw const ApiException('The server sent an answer the app does not understand.');
    }
    return AuthResult(token: token, user: User.fromJson(_map(json['user'])));
  }
}
