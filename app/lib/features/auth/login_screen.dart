import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/auth_repository.dart';
import '../../services/api_client.dart';
import '../../services/google_identity.dart';
import '../../services/session.dart';
import '../../theme/forest_theme.dart';
import 'auth_widgets.dart';
import 'signup_screen.dart';

/// Log in with username, e-mail or phone number plus password.
///
/// The server answers every failure with the same words on purpose (it never
/// says which part was wrong); we show them as they come. After too many wrong
/// tries it answers 429 with how long to wait, which is shown the same way.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _googleClientId;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await context.read<AuthRepository>().config();
    if (mounted && config.googleClientId != _googleClientId) setState(() => _googleClientId = config.googleClientId);
  }

  /// Google window, then the server: a known person is in; a new one finishes a short profile first.
  Future<void> _google() async {
    final clientId = _googleClientId;
    if (clientId == null) return;
    final auth = context.read<AuthRepository>();
    final session = context.read<Session>();
    final identity = context.read<GoogleIdentity>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await identity.idToken(clientId);
      if (token == null) return; // the person closed the Google window
      final outcome = await auth.googleSignIn(token);
      final person = outcome.newPerson;
      final login = outcome.login;
      if (login != null) {
        await session.signIn(token: login.token, user: login.user);
      } else if (person != null && mounted) {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SignupScreen(google: person)));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final id = _identifier.text.trim();
    if (id.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your username (or phone) and password.');
      return;
    }
    final auth = context.read<AuthRepository>();
    final session = context.read<Session>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await auth.login(id, _password.text);
      // AuthGate swaps this screen for the app as soon as the session changes.
      await session.signIn(token: result.token, user: result.user);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    return AuthScaffold(
      brand: true,
      title: 'Welcome back',
      subtitle: 'Debate with video. Log in to continue.',
      children: [
        AuthField(
          fieldKey: const Key('login-identifier'),
          label: 'Username, e-mail or phone',
          controller: _identifier,
          autofillHints: const [AutofillHints.username],
          textInputAction: TextInputAction.next,
        ),
        AuthField(
          fieldKey: const Key('login-password'),
          label: 'Password',
          controller: _password,
          obscure: true,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        AuthError(_error),
        const SizedBox(height: 4),
        AuthButton(label: 'Log in', busy: _busy, onPressed: _submit),
        if (_googleClientId != null) ...[
          const AuthOrDivider(),
          GoogleButton(busy: _busy, onPressed: _google),
        ],
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('New here? ', style: TextStyle(color: t.fg2, fontSize: 15)),
            GestureDetector(
              key: const Key('go-signup'),
              onTap: _busy
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SignupScreen())),
              child: Text('Create an account', style: TextStyle(color: t.accent, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ],
        ),
      ],
    );
  }
}
