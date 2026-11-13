import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/auth_repository.dart';
import '../../services/google_identity.dart';
import '../../services/session.dart';
import '../legal/legal_screens.dart';
import '../../theme/forest_theme.dart';
import 'auth_widgets.dart';
import 'dob_picker.dart';
import 'signup_controller.dart';

/// Create an account: e-mail (or mobile number, as the server is set up) → 6-digit code → profile.
/// All the rules live in [SignupController]; this file is only the three forms.
class SignupScreen extends StatefulWidget {
  /// [google] is set when the person arrives from "Continue with Google" on the login screen and is new here.
  const SignupScreen({super.key, this.google});

  final GoogleNewPerson? google;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  late final SignupController _c;
  final _contact = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _email = TextEditingController();
  final _invite = TextEditingController();
  DateTime? _dob;

  @override
  void initState() {
    super.initState();
    _c = SignupController(context.read<AuthRepository>())..addListener(_onChange);
    final google = widget.google;
    if (google != null) {
      _c.startWithGoogle(google);
    } else {
      _c.loadConfig();
    }
  }

  void _onChange() {
    // The development provider returns the code; fill it in so testing is quick.
    if (_c.step == SignupStep.code && _c.devCode != null && _code.text.isEmpty) {
      _code.text = _c.devCode!;
    }
    // Google already told us the name: offer it, the person can change it.
    if (_c.viaGoogle && _name.text.isEmpty && (_c.googleName ?? '').isNotEmpty) _name.text = _c.googleName!;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c
      ..removeListener(_onChange)
      ..dispose();
    for (final c in [_contact, _code, _name, _username, _password, _email, _invite]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDob() async {
    FocusScope.of(context).unfocus();
    final picked = await pickDateOfBirth(context, initial: _dob);
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    final result = await _c.submit(
      fullName: _name.text,
      username: _username.text,
      dob: _dob,
      password: _password.text,
      email: _email.text,
      inviteCode: _invite.text,
    );
    await _finish(result, newAccount: true);
  }

  Future<void> _google() async {
    final identity = context.read<GoogleIdentity>();
    await _finish(await _c.continueWithGoogle(identity)); // a person Google already knew: logged in, not new
  }

  Future<void> _finish(AuthResult? result, {bool newAccount = false}) async {
    if (result == null || !mounted) return;
    final session = context.read<Session>();
    // Leave the sign-up pages first; AuthGate then shows the app.
    Navigator.of(context).popUntil((r) => r.isFirst);
    await session.signIn(token: result.token, user: result.user, newAccount: newAccount);
  }

  @override
  Widget build(BuildContext context) {
    switch (_c.step) {
      case SignupStep.contact:
        return _contactStep();
      case SignupStep.code:
        return _codeStep();
      case SignupStep.profile:
        return _profileStep();
    }
  }

  Widget _contactStep() {
    final email = _c.channel == SignupChannel.email;
    return AuthScaffold(
      title: email ? 'Your e-mail' : 'Your mobile number',
      subtitle: 'We send a 6-digit code to check it is you. You must be 18 or older.',
      step: 0,
      onBack: () => Navigator.of(context).maybePop(),
      children: [
        AuthField(
          fieldKey: const Key('signup-contact'),
          label: email ? 'E-mail' : 'Mobile number',
          controller: _contact,
          keyboard: email ? TextInputType.emailAddress : TextInputType.phone,
          error: _c.fieldErrors['contact'],
          helper: email ? 'Your own address; temporary e-mail is not accepted' : '10 digits; +91 is added for you',
          onSubmitted: (_) => _c.sendCode(_contact.text),
        ),
        AuthError(_c.error),
        AuthButton(label: 'Send code', busy: _c.busy, onPressed: () => _c.sendCode(_contact.text)),
        if (_c.googleClientId != null) ...[
          const AuthOrDivider(),
          GoogleButton(busy: _c.busy, onPressed: _google),
        ],
      ],
    );
  }

  Widget _codeStep() {
    final wait = _c.resendInSec;
    final t = context.forest;
    return AuthScaffold(
      title: 'Enter the code',
      subtitle: _c.channel == SignupChannel.email
          ? 'Sent to ${_c.contact}. It works for 5 minutes. If you do not see it, look in spam.'
          : 'Sent to ${_c.contact}. It works for 5 minutes.',
      step: 1,
      onBack: _c.changeContact,
      children: [
        AuthField(
          fieldKey: const Key('signup-code'),
          label: '6-digit code',
          controller: _code,
          code: true,
          keyboard: TextInputType.number,
          maxLength: 6,
          error: _c.fieldErrors['code'],
          onSubmitted: (_) => _c.verifyCode(_code.text),
        ),
        AuthError(_c.error),
        AuthButton(label: 'Verify', busy: _c.busy, onPressed: () => _c.verifyCode(_code.text)),
        const SizedBox(height: 14),
        Center(
          child: wait > 0
              ? Text('Send a new code in ${wait}s', style: TextStyle(color: t.fg2))
              : GestureDetector(
                  key: const Key('resend-code'),
                  onTap: () {
                    _code.clear();
                    _c.resend();
                  },
                  child: Text('Send a new code', style: TextStyle(color: t.accent, fontWeight: FontWeight.w700)),
                ),
        ),
      ],
    );
  }

  Widget _profileStep() {
    final t = context.forest;
    final check = _c.usernameCheck;
    String? usernameError = _c.fieldErrors['username'];
    String? usernameHelper;
    Widget? usernameSuffix;
    if (usernameError == null && check != null && !check.available) {
      usernameError = SignupController.usernameProblem(check);
      // Material shows helperText only while there is no error, so the suggestions ride in the error text.
      if (check.suggestions.isNotEmpty) usernameError = '$usernameError Try: ${check.suggestions.take(3).join(', ')}';
    } else if (check != null && check.available) {
      usernameHelper = 'Available';
      usernameSuffix = Icon(Icons.check_circle, color: t.forStance, size: 20);
    }
    if (_c.usernameChecking) {
      usernameSuffix = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return AuthScaffold(
      title: 'Create your profile',
      step: _c.viaGoogle ? null : 2,
      subtitle: _c.viaGoogle ? 'Signed in with Google as ${_c.contact}. Pick a username and your birth date.' : null,
      onBack: _c.viaGoogle ? () => Navigator.of(context).maybePop() : _c.changeContact,
      children: [
        AuthField(fieldKey: const Key('signup-name'), label: 'Full name', controller: _name, error: _c.fieldErrors['fullName']),
        AuthField(
          fieldKey: const Key('signup-username'),
          label: 'Username',
          controller: _username,
          onChanged: _c.onUsernameChanged,
          error: usernameError,
          helper: usernameHelper,
          suffix: usernameSuffix,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: InkWell(
            key: const Key('signup-dob'),
            onTap: _pickDob,
            borderRadius: BorderRadius.circular(14),
            child: InputDecorator(
              isEmpty: _dob == null, // an empty field keeps its label inside, like the others
              decoration: InputDecoration(
                labelText: 'Date of birth',
                errorText: _c.fieldErrors['dob'],
                filled: true,
                fillColor: t.raised,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                labelStyle: TextStyle(color: t.fg2),
                floatingLabelStyle: TextStyle(color: t.fg2, fontWeight: FontWeight.w600),
                suffixIcon: Icon(Icons.calendar_month_rounded, color: t.fg2),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: t.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: t.border)),
                errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: t.like)),
              ),
              child: Text(_dob == null ? '' : friendlyDate(_dob!), style: TextStyle(color: t.fg, fontSize: 16)),
            ),
          ),
        ),
        // Someone Google vouched for signs in with Google next time: no password to invent or forget.
        if (!_c.viaGoogle)
          AuthField(
            fieldKey: const Key('signup-password'),
            label: 'Password',
            controller: _password,
            obscure: true,
            error: _c.fieldErrors['password'],
            helper: 'At least 8 characters',
          ),
        // With e-mail sign-up the address is already verified; only the SMS flow asks for an optional one.
        if (_c.channel == SignupChannel.phone)
          AuthField(
            fieldKey: const Key('signup-email'),
            label: 'E-mail (optional)',
            controller: _email,
            keyboard: TextInputType.emailAddress,
            error: _c.fieldErrors['email'],
          ),
        AuthField(
          fieldKey: const Key('signup-invite'),
          label: 'Invite code (optional)',
          controller: _invite,
          error: _c.fieldErrors['inviteCode'],
          helper: 'From a friend who already uses FOREST. You will follow each other.',
        ),
        AuthError(_c.error),
        const LegalConsentText(),
        AuthButton(label: 'Create account', busy: _c.busy, onPressed: _submit),
      ],
    );
  }
}
