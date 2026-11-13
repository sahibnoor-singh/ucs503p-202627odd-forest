import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:forest_app/data/fake_feed_repository.dart';
import 'package:forest_app/features/home/feed_controller.dart';
import 'package:forest_app/features/reels/reels_repository.dart';
import 'package:forest_app/main.dart';
import 'package:forest_app/models/user.dart';
import 'package:forest_app/services/api_client.dart';
import 'package:forest_app/services/google_identity.dart';
import 'package:forest_app/services/session.dart';
import 'package:forest_app/ui/forest_nav_bar.dart';

import 'support/fake_server.dart';

const _user = {'id': 'u1', 'username': 'riya_k', 'fullName': 'Riya K', 'avatarUrl': null, 'isBot': false};

/// Answers "Continue with Google" without a Google window: the same token every time, or null for "closed the window".
class _FakeGoogle implements GoogleIdentity {
  _FakeGoogle([this.token = 'google-id-token']);
  final String? token;
  int asked = 0;

  @override
  Future<String?> idToken(String serverClientId) async {
    asked++;
    return token;
  }
}

/// The whole app, signed out, against a scripted server.
Future<(Session, FakeServer)> _boot(WidgetTester tester, {void Function(FakeServer)? script, TokenStore? store, GoogleIdentity? google}) async {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final server = FakeServer()
    ..json('POST /api/auth/login', {'token': 'tok-1', 'user': _user})
    ..json('GET /api/auth/config', {'signupChannel': 'email', 'channels': ['email']})
    ..json('POST /api/auth/email/send', {'sent': true, 'email': 'riya@example.com', 'resendInSec': 30, 'devCode': '123456'})
    ..json('POST /api/auth/email/verify', {'verified': true, 'signupToken': 'su-1'})
    ..json('POST /api/auth/otp/send', {'sent': true, 'phone': '+919876543210', 'resendInSec': 30, 'devCode': '123456'})
    ..json('POST /api/auth/otp/verify', {'verified': true, 'signupToken': 'su-1'})
    ..json('GET /api/auth/username-available', {'available': true})
    ..json('POST /api/auth/signup', {'token': 'tok-2', 'user': _user}, status: 201)
    ..json('GET /api/onboarding/topics', {'topics': [{'id': 'politics', 'label': 'Politics'}], 'min': 3, 'max': 8})
    ..json('POST /api/me/onboarding', {'topics': []})
    ..json('GET /api/users/suggested', {'users': []})
    ..json('GET /api/me', {'user': _user})
    ..json('GET /api/users/u1/profile', {
      'user': _user,
      'bio': null,
      'followerCount': 0,
      'followingCount': 0,
      'postCount': 0,
      'followedByMe': false,
      'blockedByMe': false,
      'isMe': true,
      'personality': {'keywords': [], 'summary': null, 'summaryApproved': false, 'interests': []},
      'credibility': {'score': null, 'analyzedVideos': 0, 'totalClaims': 0, 'verdictDistribution': {}, 'sufficient': false},
      'contributions': {'totalPosts': 0, 'analyzedPosts': 0, 'totalReplies': 0, 'debatesStarted': 0},
    })
    ..json('GET /api/users/u1/videos', {'posts': [], 'nextCursor': null})
    ..json('GET /api/me/bookmarks', {'bookmarks': []})
    ..json('GET /api/health', {'ok': true});
  script?.call(server);
  final session = Session(store: store ?? MemoryTokenStore());
  await session.restore();
  await tester.pumpWidget(ForestApp(
    repository: FakeFeedRepository.sample(),
    session: session,
    googleIdentity: google,
    apiClient: server.client(token: () => session.token, onUnauthorized: () => session.expire()),
  ));
  await tester.pump();
  return (session, server);
}

/// The Account tab shows the person's own profile; settings (log out, delete, blocked accounts...) are behind its gear.
Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Account'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
}

/// A new account lands on the first-run pages before the app: skip both, as someone in a hurry would.
Future<void> _throughOnboarding(WidgetTester tester, Session session) async {
  await tester.pumpAndSettle();
  expect(session.needsOnboarding, isTrue);
  expect(find.byKey(const Key('onboarding-topics')), findsOneWidget);
  await tester.tap(find.byKey(const Key('onboarding-skip')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('onboarding-done')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('guide-skip')));
  await tester.pumpAndSettle();
  expect(session.needsOnboarding, isFalse);
}

void main() {
  testWidgets('login: wrong password shows the server wording and stays on the login screen', (tester) async {
    final (session, server) = await _boot(tester, script: (s) {
      s.json('POST /api/auth/login', {'error': 'Wrong username or password'}, status: 401);
    });
    await tester.enterText(find.byKey(const Key('login-identifier')), 'riya_k');
    await tester.enterText(find.byKey(const Key('login-password')), 'nope');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Wrong username or password'), findsOneWidget);
    expect(session.isSignedIn, isFalse, reason: 'a failed login must not look like an expired session or sign anyone in');
    expect(server.count('POST /api/auth/login'), 1);
  });

  testWidgets('login: empty form asks for input without calling the server', (tester) async {
    final (_, server) = await _boot(tester);
    await tester.tap(find.text('Log in'));
    await tester.pump();
    expect(find.textContaining('Enter your username'), findsOneWidget);
    expect(server.count('POST /api/auth/login'), 0);
  });

  testWidgets('login: success shows the app, keeps the token, sends what was typed', (tester) async {
    final store = MemoryTokenStore();
    final (session, server) = await _boot(tester, store: store);
    await tester.enterText(find.byKey(const Key('login-identifier')), '  riya_k ');
    await tester.enterText(find.byKey(const Key('login-password')), 'my-password');
    await tester.tap(find.text('Log in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(server.last('POST /api/auth/login').json, {'identifier': 'riya_k', 'password': 'my-password'});
    expect(session.token, 'tok-1');
    expect(await store.read(), 'tok-1');
    expect(find.byType(ForestNavBar), findsOneWidget);
    expect(find.byKey(const Key('login-identifier')), findsNothing);
  });

  testWidgets('sign-up: e-mail → code (auto-filled in dev) → profile → in the app', (tester) async {
    final (session, server) = await _boot(tester);
    await tester.tap(find.byKey(const Key('go-signup')));
    await tester.pumpAndSettle();

    expect(find.text('Your e-mail'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('signup-contact')), 'Riya@Example.com');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(server.last('POST /api/auth/email/send').json, {'email': 'Riya@Example.com'});
    expect(find.textContaining('riya@example.com'), findsOneWidget); // as the server normalised it
    expect(tester.widget<TextField>(find.byKey(const Key('signup-code'))).controller!.text, '123456'); // dev auto-fill

    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(find.text('Create your profile'), findsOneWidget);
    expect(find.byKey(const Key('signup-email')), findsNothing, reason: 'the address was verified in step 1');

    await tester.enterText(find.byKey(const Key('signup-name')), 'Riya K');
    await tester.enterText(find.byKey(const Key('signup-username')), 'riya_k');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('Available'), findsOneWidget);
    await tester.tap(find.byKey(const Key('signup-dob')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dob-done')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('signup-password')), 'long-enough-pw');
    await tester.tap(find.text('Create account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final sent = server.last('POST /api/auth/signup').json;
    expect(sent['signupToken'], 'su-1');
    expect(sent['username'], 'riya_k');
    expect(sent.containsKey('email'), isFalse);
    expect(session.token, 'tok-2');
    await _throughOnboarding(tester, session);
    expect(find.byType(ForestNavBar), findsOneWidget);
  });

  testWidgets('sign-up: a server set up for SMS asks for the mobile number and offers the optional e-mail', (tester) async {
    final (_, server) = await _boot(tester, script: (s) {
      s.json('GET /api/auth/config', {'signupChannel': 'phone', 'channels': ['phone']});
    });
    await tester.tap(find.byKey(const Key('go-signup')));
    await tester.pumpAndSettle();

    expect(find.text('Your mobile number'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('signup-contact')), '9876543210');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(server.count('POST /api/auth/email/send'), 0);
    expect(find.textContaining('+919876543210'), findsOneWidget);
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('signup-email')), findsOneWidget);
  });

  testWidgets('Google: no button unless the server has Google sign-in on', (tester) async {
    await _boot(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('google-button')), findsNothing);
  });

  testWidgets('Google on the login screen: a known person is simply logged in', (tester) async {
    final google = _FakeGoogle();
    final (session, server) = await _boot(tester, google: google, script: (s) {
      s.json('GET /api/auth/config', {'signupChannel': 'email', 'channels': ['email'], 'googleClientId': 'web-1'});
      s.json('POST /api/auth/google', {'token': 'tok-g', 'user': _user});
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('google-button')));
    await tester.pumpAndSettle();
    expect(server.last('POST /api/auth/google').json, {'idToken': 'google-id-token'});
    expect(session.token, 'tok-g');
    expect(find.byType(ForestNavBar), findsOneWidget);
  });

  testWidgets('Google on the login screen: closing the Google window leaves everything as it was', (tester) async {
    final (session, server) = await _boot(tester, google: _FakeGoogle(null), script: (s) {
      s.json('GET /api/auth/config', {'signupChannel': 'email', 'channels': ['email'], 'googleClientId': 'web-1'});
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('google-button')));
    await tester.pumpAndSettle();
    expect(server.count('POST /api/auth/google'), 0);
    expect(session.isSignedIn, isFalse);
    expect(find.byKey(const Key('login-identifier')), findsOneWidget);
  });

  testWidgets('Google, new person: name offered, no password asked, account created without one', (tester) async {
    final (session, server) = await _boot(tester, google: _FakeGoogle(), script: (s) {
      s.json('GET /api/auth/config', {'signupChannel': 'email', 'channels': ['email'], 'googleClientId': 'web-1'});
      s.json('POST /api/auth/google', {'needsProfile': true, 'signupToken': 'su-g', 'email': 'riya@gmail.com', 'fullName': 'Riya Kapoor'});
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('google-button')));
    await tester.pumpAndSettle();

    expect(find.text('Create your profile'), findsOneWidget);
    expect(find.textContaining('riya@gmail.com'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('signup-name'))).controller!.text, 'Riya Kapoor');
    expect(find.byKey(const Key('signup-password')), findsNothing);

    await tester.enterText(find.byKey(const Key('signup-username')), 'riya_k');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.tap(find.byKey(const Key('signup-dob')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dob-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final sent = server.last('POST /api/auth/signup').json;
    expect(sent['signupToken'], 'su-g');
    expect(sent.containsKey('password'), isFalse);
    expect(session.token, 'tok-2');
    await _throughOnboarding(tester, session);
    expect(find.byType(ForestNavBar), findsOneWidget);
  });

  testWidgets('Google on the sign-up screen: the button is there too and a known person is logged in', (tester) async {
    final (session, _) = await _boot(tester, google: _FakeGoogle(), script: (s) {
      s.json('GET /api/auth/config', {'signupChannel': 'email', 'channels': ['email'], 'googleClientId': 'web-1'});
      s.json('POST /api/auth/google', {'token': 'tok-g', 'user': _user});
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('go-signup')));
    await tester.pumpAndSettle();
    expect(find.text('Your e-mail'), findsOneWidget);
    await tester.tap(find.byKey(const Key('google-button')));
    await tester.pumpAndSettle();
    expect(session.token, 'tok-g');
    expect(find.byType(ForestNavBar), findsOneWidget);
  });

  testWidgets('delete account without a password: confirms with Google instead and logs out', (tester) async {
    final store = MemoryTokenStore();
    final (session, server) = await _boot(tester, store: store, google: _FakeGoogle(), script: (s) {
      s.json('GET /api/auth/config', {'signupChannel': 'email', 'channels': ['email'], 'googleClientId': 'web-1'});
      s.json('GET /api/me', {'user': _user, 'account': {'hasPassword': false, 'google': true}});
      s.json('DELETE /api/me', {'deleted': true});
    });
    await session.signIn(token: 'tok', user: _userObj);
    await tester.pumpAndSettle();
    await _openSettings(tester);
    await tester.ensureVisible(find.byKey(const Key('delete-account')));
    await tester.tap(find.byKey(const Key('delete-account')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delete-password')), findsNothing);
    expect(find.textContaining('signed up with Google'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(server.last('DELETE /api/me').json, {'idToken': 'google-id-token'});
    expect(find.byKey(const Key('login-identifier')), findsOneWidget);
    expect(await store.read(), isNull);
  });

  testWidgets('sign-up: an address the server refuses is explained under the e-mail box', (tester) async {
    await _boot(tester, script: (s) {
      s.json('POST /api/auth/email/send', {'error': 'Temporary e-mail addresses cannot be used. Use your own e-mail', 'field': 'email'}, status: 400);
    });
    await tester.tap(find.byKey(const Key('go-signup')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('signup-contact')), 'x@mailinator.com');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Temporary e-mail'), findsOneWidget);
    expect(find.text('Your e-mail'), findsOneWidget, reason: 'still on the first step');
  });

  testWidgets('sign-up: an unavailable username shows the reason and suggestions', (tester) async {
    await _boot(tester, script: (s) {
      s.json('GET /api/auth/username-available', {'available': false, 'reason': 'TAKEN', 'suggestions': ['riya_k42', 'riya_k7']});
    });
    await tester.tap(find.byKey(const Key('go-signup')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('signup-contact')), 'riya@example.com');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('signup-username')), 'riya_k');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.textContaining('That username is taken.'), findsOneWidget);
    expect(find.textContaining('riya_k42'), findsOneWidget);
  });

  testWidgets('a rejected token signs the person out at once, from any screen', (tester) async {
    final (session, server) = await _boot(tester, script: (s) {
      s.json('GET /api/some-call', {'error': 'Invalid or expired token'}, status: 401);
    });
    await session.signIn(token: 'old', user: _userObj);
    await tester.pumpAndSettle();
    expect(find.byType(ForestNavBar), findsOneWidget);

    // Any request made with the old token comes back 401 (it expired, or the account is gone).
    final api = tester.element(find.byType(ForestNavBar)).read<ApiClient>();
    await tester.runAsync(() => api.getJson('/api/some-call').catchError((_) => null));
    await tester.pumpAndSettle();
    expect(server.last('GET /api/some-call').headers['Authorization'], 'Bearer old');
    expect(session.status, SessionStatus.signedOut);
    expect(find.byKey(const Key('login-identifier')), findsOneWidget);
  });

  testWidgets('log out: asks first, then returns to the login screen and forgets the token', (tester) async {
    final store = MemoryTokenStore();
    final (session, _) = await _boot(tester, store: store);
    await session.signIn(token: 'tok', user: _userObj);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('riya_k'), findsWidgets, reason: 'the Account tab is the person\'s own profile');
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('log-out')));
    await tester.tap(find.byKey(const Key('log-out')));
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(session.isSignedIn, isTrue);

    await tester.tap(find.byKey(const Key('log-out')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Log out')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-identifier')), findsOneWidget);
    expect(await store.read(), isNull);
  });

  testWidgets('delete account: wrong password is reported, right password erases and logs out', (tester) async {
    final store = MemoryTokenStore();
    var attempts = 0;
    final (session, server) = await _boot(tester, store: store, script: (s) {
      s.on('DELETE /api/me', (req) {
        attempts++;
        return req.json['password'] == 'right-password'
            ? http.Response('{"deleted":true}', 200, headers: {'content-type': 'application/json'})
            : http.Response('{"error":"Wrong password"}', 403, headers: {'content-type': 'application/json'});
      });
    });
    await session.signIn(token: 'tok', user: _userObj);
    await tester.pumpAndSettle();
    await _openSettings(tester);
    await tester.ensureVisible(find.byKey(const Key('delete-account')));
    await tester.tap(find.byKey(const Key('delete-account')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('delete-password')), 'wrong');
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Wrong password'), findsOneWidget);
    expect(session.isSignedIn, isTrue, reason: 'a wrong password must not log anyone out');

    await tester.enterText(find.byKey(const Key('delete-password')), 'right-password');
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(server.last('DELETE /api/me').headers['Authorization'], 'Bearer tok');
    expect(find.byKey(const Key('login-identifier')), findsOneWidget);
    expect(await store.read(), isNull);
  });

  testWidgets('logging in as someone else never shows the previous person\'s feed objects', (tester) async {
    final (session, _) = await _boot(tester);
    await session.signIn(token: 'token-A', user: _userObj);
    await tester.pumpAndSettle();
    final first = tester.element(find.byType(ForestNavBar)).read<FeedController>();
    final firstReels = tester.element(find.byType(ForestNavBar)).read<ReelsRepository>();

    await session.signOut();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-identifier')), findsOneWidget);

    await session.signIn(token: 'token-B', user: _userObj);
    await tester.pumpAndSettle();
    final second = tester.element(find.byType(ForestNavBar)).read<FeedController>();
    final secondReels = tester.element(find.byType(ForestNavBar)).read<ReelsRepository>();
    expect(identical(first, second), isFalse, reason: 'a reused feed controller would still hold A\'s posts');
    expect(identical(firstReels, secondReels), isFalse);
  });
}

final _userObj = User.fromJson(_user);
