// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';

/// Where the login token is kept between app launches.
///
/// The token is the key to the account, so it lives behind this small
/// interface: [SharedPrefsTokenStore] is what the app uses today (private to
/// the app on Android/iOS), and [MemoryTokenStore] is for tests. Before a
/// public launch, swap the first for one backed by the platform keystore
/// (`flutter_secure_storage`): nothing else in the app has to change.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();

  /// True from the moment someone creates an account until they finish (or skip) the first-run pages, so closing the app
  /// in the middle brings the pages back next time.
  Future<bool> readOnboardingPending();
  Future<void> writeOnboardingPending(bool pending);
}

class SharedPrefsTokenStore implements TokenStore {
  static const _key = 'forest.auth.token';

  @override
  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String token) async =>
      (await SharedPreferences.getInstance()).setString(_key, token);

  @override
  Future<void> clear() async => (await SharedPreferences.getInstance()).remove(_key);

  static const _pendingKey = 'forest.onboarding.pending';

  @override
  Future<bool> readOnboardingPending() async => (await SharedPreferences.getInstance()).getBool(_pendingKey) ?? false;

  @override
  Future<void> writeOnboardingPending(bool pending) async =>
      (await SharedPreferences.getInstance()).setBool(_pendingKey, pending);
}

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this._token]);
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;

  bool _pending = false;

  @override
  Future<bool> readOnboardingPending() async => _pending;

  @override
  Future<void> writeOnboardingPending(bool pending) async => _pending = pending;
}

enum SessionStatus {
  /// Looking for a saved token at app start. Show a splash, not the login.
  restoring,
  signedOut,
  signedIn,
}

/// "Who is using the app right now."
///
/// Owns the login token (see [ApiClient.tokenProvider]) and tells the UI when
/// to show the app or the login screen. [AuthGate] listens to it.
///
/// Rules worth knowing:
///  * a saved token is trusted until the server says otherwise: any 401 on a
///    request that carried it calls [expire], which signs out and forgets it;
///  * [signOut] only forgets the token on this phone (tokens are stateless on the
///    server, so there is nothing to call there yet).
class Session extends ChangeNotifier {
  Session({TokenStore? store, bool devBypass = false})
      : _store = store ?? SharedPrefsTokenStore(),
        _devBypass = devBypass {
    if (devBypass) _status = SessionStatus.signedIn;
  }

  /// A session that is already signed in (tests, and the DEV_USER shortcut).
  Session.signedIn({TokenStore? store, String token = 'test-token', User? user, bool needsOnboarding = false})
      : _store = store ?? MemoryTokenStore(),
        _devBypass = false,
        _status = SessionStatus.signedIn,
        _token = token,
        _user = user,
        _needsOnboarding = needsOnboarding;

  final TokenStore _store;
  final bool _devBypass;
  SessionStatus _status = SessionStatus.restoring;
  String? _token;
  User? _user;
  bool _needsOnboarding = false;

  /// A person who just made an account and has not yet been through the first-run pages (topics, people to follow).
  bool get needsOnboarding => _needsOnboarding;

  SessionStatus get status => _status;
  String? get token => _token;
  User? get user => _user;
  bool get isSignedIn => _status == SessionStatus.signedIn;

  /// Looks for a saved token. Call once at start.
  Future<void> restore() async {
    if (_devBypass) return;
    String? saved;
    try {
      saved = await _store.read();
    } on Object catch (error) {
      debugPrint('Could not read the saved login: $error'); // treat as signed out
    }
    _token = (saved == null || saved.isEmpty) ? null : saved;
    _status = _token == null ? SessionStatus.signedOut : SessionStatus.signedIn;
    if (_token != null) {
      try {
        _needsOnboarding = await _store.readOnboardingPending();
      } on Object catch (error) {
        debugPrint('Could not read the first-run flag: $error'); // skip the pages rather than block the app
      }
    }
    notifyListeners();
  }

  /// Called after a successful login or sign-up. [newAccount] is true only when the account was just created: it
  /// shows the first-run pages once.
  Future<void> signIn({required String token, required User user, bool newAccount = false}) async {
    _token = token;
    _user = user;
    _needsOnboarding = newAccount;
    _status = SessionStatus.signedIn;
    notifyListeners();
    try {
      await _store.write(token);
    } on Object catch (error) {
      // Still signed in for this run; they will just have to log in again next launch.
      debugPrint('Could not save the login: $error');
    }
    await _rememberPending(newAccount);
  }

  /// The first-run pages are done (or skipped): show the app, and do not show them again.
  Future<void> finishOnboarding() async {
    if (!_needsOnboarding) return;
    _needsOnboarding = false;
    notifyListeners();
    await _rememberPending(false);
  }

  Future<void> _rememberPending(bool pending) async {
    try {
      await _store.writeOnboardingPending(pending);
    } on Object catch (error) {
      debugPrint('Could not save the first-run flag: $error');
    }
  }

  /// The profile the server knows, once loaded (shown on the Account screen).
  void setUser(User user) {
    _user = user;
    notifyListeners();
  }

  Future<void> signOut() async {
    _token = null;
    _user = null;
    _needsOnboarding = false;
    _status = SessionStatus.signedOut;
    notifyListeners();
    try {
      await _store.clear();
    } on Object catch (error) {
      debugPrint('Could not clear the saved login: $error');
    }
    await _rememberPending(false);
  }

  /// The server rejected our token (expired, or the account was deleted).
  /// Safe to call many times, for example when several requests fail together.
  Future<void> expire() async {
    if (_status != SessionStatus.signedIn || _devBypass) return;
    await signOut();
  }
}
