import 'dart:async';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/auth_repository.dart';
import '../data/feed_repository.dart';
import '../features/discover/friend_taste_switch.dart';
import '../features/growth/growth_tiles.dart';
import '../features/legal/legal_screens.dart';
import '../features/profile/profile_screen.dart';
import '../features/safety/blocked_accounts_screen.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/google_identity.dart';
import '../services/session.dart';
import '../theme/forest_theme.dart';

/// The 4th tab in the bottom navigation bar: displays the signed-in user's
/// full Profile Page (ProfileScreen). Settings and management actions are
/// accessible via the gear icon in the profile header.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  User? _me;
  String? _meError;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMe());
  }

  Future<void> _loadMe() async {
    final session = context.read<Session>();
    final repo = context.read<FeedRepository>();
    if (session.user != null) {
      if (mounted) setState(() => _me = session.user);
      return;
    }
    setState(() {
      _loading = true;
      _meError = null;
    });
    try {
      final me = await repo.me();
      session.setUser(me);
      if (mounted) {
        setState(() {
          _me = me;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _meError = e.message;
          _loading = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _meError = 'Could not load your account. Check your connection and try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final me = context.watch<Session>().user ?? _me;

    // When the user is known, render the full Profile Page directly
    if (me != null) {
      return ProfileScreen(userId: me.id);
    }

    // Loading state
    if (_loading) {
      return Scaffold(
        backgroundColor: t.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Error / retry state
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: t.bg,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: t.border),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_off_outlined, size: 48, color: t.fg2),
              const SizedBox(height: 16),
              Text(
                _meError ?? 'Could not load profile.',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.fg, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Make sure the backend is running at ${context.read<ApiClient>().baseUrl}',
                textAlign: TextAlign.center,
                style: TextStyle(color: t.fg2, fontSize: 13),
              ),
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: _loadMe,
                child: const Text('Retry'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.read<Session>().signOut(),
                child: const Text('Log out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Settings screen opened via the gear icon on the user's own profile page.
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  late final ApiClient _api = context.read<ApiClient>();
  late Future<bool> _healthFuture;

  @override
  void initState() {
    super.initState();
    _healthFuture = _api.health();
  }

  Future<void> _confirmLogOut() async {
    final session = context.read<Session>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You can log back in any time with your username and password.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok == true) {
      if (mounted) Navigator.of(context).pop();
      await session.signOut();
    }
  }

  Future<void> _confirmDelete() async {
    final session = context.read<Session>();
    final deleted = await showDialog<bool>(context: context, builder: (_) => const _DeleteAccountDialog());
    if (deleted == true) {
      if (mounted) Navigator.of(context).pop();
      await session.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.forest;
    final me = context.watch<Session>().user;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: const Text('Settings & Account', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        backgroundColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: t.border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (me != null) ...[
              Text('SIGNED IN AS', style: TextStyle(color: t.fg2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: t.raised,
                      child: Icon(Icons.person_outline, size: 22, color: t.fg),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('@${me.username}', style: TextStyle(color: t.fg, fontSize: 15, fontWeight: FontWeight.w700)),
                          Text(me.fullName, style: TextStyle(color: t.fg2, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            Text('COMMUNITY', style: TextStyle(color: t.fg2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            const GrowthTiles(),
            const SizedBox(height: 24),

            Text('PREFERENCES & DISCOVERY', style: TextStyle(color: t.fg2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            FriendTasteSwitch(api: _api),
            const BlockedAccountsTile(),
            const SizedBox(height: 24),

            Text('LEGAL & PRIVACY', style: TextStyle(color: t.fg2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            const LegalLinks(),
            const SizedBox(height: 24),

            Text('CONNECTION', style: TextStyle(color: t.fg2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            FutureBuilder<bool>(
              future: _healthFuture,
              builder: (context, snapshot) {
                final ok = snapshot.data == true;
                final waiting = snapshot.connectionState == ConnectionState.waiting;
                final color = waiting ? t.fg2 : (ok ? t.forStance : t.like);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.border),
                  ),
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          waiting
                              ? 'Checking the connection…'
                              // The address is for the people building the app; a release build only says whether it works.
                              : (ok ? (kReleaseMode ? 'Connected' : 'Connected (${_api.baseUrl})') : (kReleaseMode ? 'Cannot reach FOREST right now' : 'Server offline (${_api.baseUrl})')),
                          style: TextStyle(color: t.fg, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('log-out'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: t.border),
                  foregroundColor: t.fg,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _confirmLogOut,
                child: const Text('Log out', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const Key('delete-account'),
                onPressed: _confirmDelete,
                child: Text('Delete account', style: TextStyle(color: t.like, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Password prompt for account deletion.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _hasPassword = true;

  @override
  void initState() {
    super.initState();
    _askWhichProof();
  }

  Future<void> _askWhichProof() async {
    final has = await context.read<AuthRepository>().hasPassword();
    if (mounted && has != _hasPassword) setState(() => _hasPassword = has);
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final auth = context.read<AuthRepository>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_hasPassword) {
        await auth.deleteAccount(_password.text);
      } else {
        final identity = context.read<GoogleIdentity>();
        final clientId = (await auth.config()).googleClientId;
        if (clientId == null) throw const ApiException('Google sign-in is not available right now.');
        final token = await identity.idToken(clientId);
        if (token == null) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        await auth.deleteAccountWithGoogle(token);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This cannot be undone. Your profile and videos are removed; replies other people wrote stay.'),
          const SizedBox(height: 12),
          if (_hasPassword)
            TextField(
              key: const Key('delete-password'),
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(labelText: 'Password', errorText: _error),
            )
          else ...[
            const Text('You signed up with Google, so you will be asked to confirm with that Google account.'),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(
          key: const Key('confirm-delete'),
          onPressed: _busy ? null : _delete,
          child: const Text('Delete forever'),
        ),
      ],
    );
  }
}
