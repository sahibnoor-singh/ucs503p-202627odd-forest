import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/session.dart';
import '../onboarding/onboarding_screen.dart';
import '../../theme/forest_theme.dart';
import 'login_screen.dart';

/// Shows the app to people who are signed in and the login screen to everyone
/// else, switching the moment the [Session] changes (login, logout, or the
/// server rejecting an old token).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.app});

  /// What a signed-in person sees (the four-tab shell).
  final Widget app;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Session _session = context.read<Session>();
  SessionStatus? _last;

  @override
  void initState() {
    super.initState();
    _last = _session.status;
    _session.addListener(_onSession);
  }

  /// Signing out (or a dead token) while a viewer, sheet or thread is open must
  /// not leave that page on top of the login screen showing the old person's data.
  void _onSession() {
    final now = _session.status;
    if (_last == SessionStatus.signedIn && now == SessionStatus.signedOut && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    _last = now;
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = context.select<Session, SessionStatus>((s) => s.status);
    final onboarding = context.select<Session, bool>((s) => s.needsOnboarding);
    return switch (status) {
      SessionStatus.restoring => Scaffold(
          backgroundColor: context.forest.bg,
          body: const Center(child: CircularProgressIndicator()),
        ),
      SessionStatus.signedOut => const LoginScreen(),
      // Someone who has just made an account sees two short pages first (topics, people to follow), once.
      SessionStatus.signedIn => onboarding ? const OnboardingScreen() : widget.app,
    };
  }
}
