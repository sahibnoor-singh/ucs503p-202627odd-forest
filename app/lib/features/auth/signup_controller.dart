import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/auth_repository.dart';
import '../../services/api_client.dart';
import '../../services/google_identity.dart';

enum SignupStep { contact, code, profile }

/// The logic of the three sign-up steps, with no widgets, so it can be tested
/// without a screen. The server (`docs/api.md` → Accounts) is always the judge;
/// the checks done here only save a round trip and give a friendlier message.
///
///   contact → [sendCode] → code → [verifyCode] → profile → [submit] → AuthResult
///
/// "Contact" is an e-mail address (the free default) or a mobile number, as the server's
/// config says ([loadChannel]); the code is checked the same way for both.
///
/// Rules this class keeps:
///  * the sign-up token (proof the address or number was verified) is held in memory
///    only, and dropped as soon as the server says it is no longer valid;
///  * a field error from the server (`field: "username"`) is shown under that
///    input, anything else goes to [error];
///  * a slow answer to an old username check never overwrites a newer one.
class SignupController extends ChangeNotifier {
  SignupController(
    this._auth, {
    this.channel = SignupChannel.email,
    DateTime Function()? now,
    this.usernameDebounce = const Duration(milliseconds: 400),
  }) : _now = now ?? DateTime.now;

  final AuthRepository _auth;
  final DateTime Function() _now;
  final Duration usernameDebounce;

  /// What the person is asked to verify. Starts as e-mail and follows the server's answer once [loadChannel] finishes.
  SignupChannel channel;

  /// Set when the server has "Continue with Google" on.
  String? googleClientId;

  /// True when Google vouched for this person: the profile step needs no password. [googleName] pre-fills the name.
  bool viaGoogle = false;
  String? googleName;

  SignupStep step = SignupStep.contact;
  bool busy = false;

  /// A problem that is not about one particular input.
  String? error;

  /// Server messages by input name (`contact`, `code`, `fullName`, `username`, `dob`, `password`, `email`).
  final Map<String, String> fieldErrors = {};

  /// The address or number as the server normalised it (`+91…`).
  String? contact;

  /// Only set by the development provider; the UI may auto-fill it.
  String? devCode;
  DateTime? _resendAt;

  UsernameCheck? usernameCheck;
  bool usernameChecking = false;

  String? _signupToken;
  Timer? _debounce;
  int _usernameSeq = 0;

  /// Seconds until a new code may be requested (0 = now).
  int get resendInSec {
    final at = _resendAt;
    if (at == null) return 0;
    final left = at.difference(_now()).inSeconds + 1;
    return left > 0 ? left : 0;
  }

  static const minAge = 18;
  static final _usernameShape = RegExp(r'^[a-z0-9._]{3,30}$');

  // ---- step 1 ----

  /// Asks the server how new people are verified and whether Google sign-in is on. Call once, when the sign-up opens.
  Future<void> loadConfig() async {
    final found = await _auth.config();
    if (found.channel == channel && found.googleClientId == googleClientId) return;
    channel = found.channel;
    googleClientId = found.googleClientId;
    notifyListeners();
  }

  /// Opens Google, then either logs a known person in (returns them) or moves a new one to the profile step.
  /// Returns null when the person closes the Google window or something failed (see [error]).
  Future<AuthResult?> continueWithGoogle(GoogleIdentity google) async {
    final clientId = googleClientId;
    if (clientId == null) return null;
    AuthResult? result;
    await _run(() async {
      final token = await google.idToken(clientId);
      if (token == null) return;
      final outcome = await _auth.googleSignIn(token);
      final person = outcome.newPerson;
      if (person != null) {
        startWithGoogle(person);
      } else {
        result = outcome.login;
      }
    });
    return result;
  }

  /// A new person Google vouched for: skip the code step, the e-mail is already verified.
  void startWithGoogle(GoogleNewPerson person) {
    _signupToken = person.signupToken;
    contact = person.email;
    googleName = person.fullName;
    viaGoogle = true;
    step = SignupStep.profile;
    _clearErrors();
    notifyListeners();
  }

  static final _emailShape = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  Future<void> sendCode(String raw) async {
    final email = channel == SignupChannel.email;
    final value = email ? raw.trim() : raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (email ? !_emailShape.hasMatch(value) : !RegExp(r'^\+?[0-9]{10,15}$').hasMatch(value)) {
      _fail({'contact': email ? 'Enter a valid e-mail address.' : 'Enter a valid mobile number.'});
      return;
    }
    await _run(() async {
      final sent = await (email ? _auth.sendEmailCode(value) : _auth.sendCode(value));
      contact = sent.contact;
      devCode = sent.devCode;
      _resendAt = _now().add(Duration(seconds: sent.resendInSec));
      step = SignupStep.code;
    }, field: 'contact');
  }

  // ---- step 2 ----

  Future<void> verifyCode(String code) async {
    final clean = code.trim();
    if (!RegExp(r'^[0-9]{6}$').hasMatch(clean)) {
      _fail({'code': 'The code has 6 digits.'});
      return;
    }
    await _run(() async {
      _signupToken = await (channel == SignupChannel.email ? _auth.verifyEmailCode(contact!, clean) : _auth.verifyCode(contact!, clean));
      step = SignupStep.profile;
    }, field: 'code');
  }

  /// Asks for a fresh code (same address or number). Does nothing during the cool-down.
  Future<void> resend() async {
    if (contact == null || resendInSec > 0) return;
    await sendCode(contact!);
  }

  void changeContact() {
    _signupToken = null;
    devCode = null;
    viaGoogle = false;
    step = SignupStep.contact;
    _clearErrors();
    notifyListeners();
  }

  // ---- step 3 ----

  /// Call on every keystroke in the username field; checks after a short pause.
  void onUsernameChanged(String raw) {
    final name = raw.trim().toLowerCase();
    _debounce?.cancel();
    final seq = ++_usernameSeq;
    fieldErrors.remove('username');
    usernameCheck = null;
    if (name.isEmpty) {
      usernameChecking = false;
      notifyListeners();
      return;
    }
    if (!_usernameShape.hasMatch(name)) {
      usernameChecking = false;
      usernameCheck = const UsernameCheck(available: false, reason: 'INVALID');
      notifyListeners();
      return;
    }
    usernameChecking = true;
    notifyListeners();
    _debounce = Timer(usernameDebounce, () async {
      try {
        final result = await _auth.usernameAvailable(name);
        if (seq != _usernameSeq) return; // the person kept typing
        usernameCheck = result;
      } on ApiException {
        if (seq != _usernameSeq) return;
        usernameCheck = null; // the real check happens again at sign-up
      }
      usernameChecking = false;
      notifyListeners();
    });
  }

  /// Human wording for a failed username check.
  static String usernameProblem(UsernameCheck check) => switch (check.reason) {
        'TAKEN' => 'That username is taken.',
        'RESERVED' => 'That username is not available.',
        _ => 'Use 3-30 letters, numbers, dots or underscores.',
      };

  /// Returns the new account on success, null otherwise (see [error]/[fieldErrors]).
  Future<AuthResult?> submit({
    required String fullName,
    required String username,
    required DateTime? dob,
    required String password,
    String email = '',
    String inviteCode = '',
  }) async {
    final problems = <String, String>{};
    if (fullName.trim().isEmpty) problems['fullName'] = 'Enter your name.';
    final name = username.trim().toLowerCase();
    if (!_usernameShape.hasMatch(name)) problems['username'] = usernameProblem(const UsernameCheck(available: false));
    if (dob == null) {
      problems['dob'] = 'Pick your date of birth.';
    } else if (!isAdult(dob)) {
      problems['dob'] = 'You must be 18 or older to use FOREST.';
    }
    // A person Google vouched for needs no password; if they type one it must still be long enough.
    if (password.length < 8 && !(viaGoogle && password.isEmpty)) problems['password'] = 'Use at least 8 characters.';
    // With e-mail sign-up the address was already verified in step 1, so the profile has no e-mail field.
    if (channel == SignupChannel.phone && !viaGoogle && email.trim().isNotEmpty && !email.contains('@')) problems['email'] = 'That e-mail does not look right.';
    if (problems.isNotEmpty) {
      _fail(problems);
      return null;
    }
    final token = _signupToken;
    if (token == null) {
      step = SignupStep.contact;
      _fail({'contact': channel == SignupChannel.email ? 'Verify your e-mail again.' : 'Verify your number again.'});
      return null;
    }

    AuthResult? result;
    await _run(() async {
      result = await _auth.signUp(
        signupToken: token,
        fullName: fullName.trim(),
        username: name,
        dob: formatDob(dob!),
        password: password,
        email: channel == SignupChannel.phone && !viaGoogle ? email : '',
        inviteCode: inviteCode,
      );
      _signupToken = null;
    });
    return result;
  }

  /// 18 or older today, to the exact day (same rule as the server).
  bool isAdult(DateTime dob) {
    final today = _now();
    var age = today.year - dob.year;
    if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) age--;
    return age >= minAge;
  }

  static String formatDob(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ---- plumbing ----

  /// Runs one server call with the busy flag and error mapping.
  Future<void> _run(Future<void> Function() body, {String? field}) async {
    if (busy) return;
    busy = true;
    _clearErrors();
    notifyListeners();
    try {
      await body();
    } on ApiException catch (e) {
      _onApiError(e, defaultField: field);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _onApiError(ApiException e, {String? defaultField}) {
    final retry = e.retryAfterSec;
    if (e.isRateLimited && retry != null) _resendAt = _now().add(Duration(seconds: retry));
    final field = e.field;
    if (field == 'signupToken') {
      // The check expired (15 minutes) or was never done.
      _signupToken = null;
      step = SignupStep.contact;
      fieldErrors['contact'] = 'Verification expired. Verify again.';
    } else if ((field == 'phone' || field == 'email') && step != SignupStep.profile) {
      // Wrong shape, already registered, refused domain: all about the thing typed in step 1.
      step = SignupStep.contact;
      fieldErrors['contact'] = e.message;
    } else if (field != null) {
      fieldErrors[field] = e.message;
    } else if (defaultField != null && !e.isRateLimited && e.statusCode != null && e.statusCode! < 500) {
      fieldErrors[defaultField] = e.message;
    } else {
      error = e.message;
    }
  }

  void _fail(Map<String, String> problems) {
    _clearErrors();
    fieldErrors.addAll(problems);
    notifyListeners();
  }

  void _clearErrors() {
    error = null;
    fieldErrors.clear();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
