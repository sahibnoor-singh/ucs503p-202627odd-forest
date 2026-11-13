import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/data/auth_repository.dart';
import 'package:forest_app/features/auth/signup_controller.dart';
import 'package:forest_app/services/google_identity.dart';

import 'support/fake_server.dart';

const _user = {'id': 'u1', 'username': 'riya_k', 'fullName': 'Riya K', 'avatarUrl': null, 'isBot': false};

/// A server that accepts the happy path; tests override single routes.
class _FakeGoogle implements GoogleIdentity {
  _FakeGoogle(this.token);
  final String? token;
  String? askedWith;

  @override
  Future<String?> idToken(String serverClientId) async {
    askedWith = serverClientId;
    return token;
  }
}

FakeServer _server() => FakeServer()
  ..json('POST /api/auth/otp/send', {'sent': true, 'phone': '+919876543210', 'resendInSec': 30})
  ..json('POST /api/auth/otp/verify', {'verified': true, 'signupToken': 'su-1'})
  ..json('POST /api/auth/signup', {'token': 'login-1', 'user': _user}, status: 201)
  ..json('GET /api/auth/username-available', {'available': true});

SignupController _controller(FakeServer s, {DateTime Function()? now, SignupChannel channel = SignupChannel.phone}) =>
    SignupController(AuthRepository(s.client()), channel: channel, now: now, usernameDebounce: const Duration(milliseconds: 5));

/// Walks a controller to the profile step.
Future<void> _toProfile(SignupController c) async {
  await c.sendCode('98765 43210');
  await c.verifyCode('123456');
  expect(c.step, SignupStep.profile);
}

Future<AuthResult?> _submit(SignupController c, {String name = 'Riya K', String username = 'riya_k', DateTime? dob, String password = 'long-enough-pw', String email = ''}) =>
    c.submit(fullName: name, username: username, dob: dob ?? DateTime(2000, 5, 20), password: password, email: email);

void main() {
  final today = DateTime(2026, 10, 12);

  group('Google', () {
    FakeServer googleServer({bool known = false}) => FakeServer()
      ..json('GET /api/auth/config', {'signupChannel': 'email', 'googleClientId': 'web-1'})
      ..json(
          'POST /api/auth/google',
          known
              ? {'token': 'tok-g', 'user': _user}
              : {'needsProfile': true, 'signupToken': 'su-g', 'email': 'riya@gmail.com', 'fullName': 'Riya Kapoor'})
      ..json('POST /api/auth/signup', {'token': 'login-1', 'user': _user}, status: 201);

    test('the Google client id comes from the config', () async {
      final c = _controller(googleServer(), channel: SignupChannel.email);
      expect(c.googleClientId, isNull);
      await c.loadConfig();
      expect(c.googleClientId, 'web-1');
    });

    test('a new person goes straight to the profile step; no password is needed and none is sent', () async {
      final s = googleServer();
      final c = _controller(s, channel: SignupChannel.email);
      await c.loadConfig();
      final google = _FakeGoogle('id-token');
      expect(await c.continueWithGoogle(google), isNull);
      expect(google.askedWith, 'web-1');
      expect(s.last('POST /api/auth/google').json, {'idToken': 'id-token'});
      expect(c.step, SignupStep.profile);
      expect(c.viaGoogle, isTrue);
      expect(c.googleName, 'Riya Kapoor');
      expect(c.contact, 'riya@gmail.com');

      final result = await _submit(c, password: '');
      expect(result, isNotNull);
      final body = s.last('POST /api/auth/signup').json;
      expect(body['signupToken'], 'su-g');
      expect(body.containsKey('password'), isFalse);
      expect(body.containsKey('email'), isFalse);
    });

    test('a password typed on a Google sign-up must still be long enough', () async {
      final c = _controller(googleServer(), channel: SignupChannel.email);
      await c.loadConfig();
      await c.continueWithGoogle(_FakeGoogle('t'));
      expect(await _submit(c, password: 'short'), isNull);
      expect(c.fieldErrors['password'], isNotNull);
    });

    test('a known person is returned logged in', () async {
      final c = _controller(googleServer(known: true), channel: SignupChannel.email);
      await c.loadConfig();
      final result = await c.continueWithGoogle(_FakeGoogle('t'));
      expect(result!.token, 'tok-g');
      expect(c.step, SignupStep.contact);
    });

    test('closing the Google window changes nothing and shows no error', () async {
      final s = googleServer();
      final c = _controller(s, channel: SignupChannel.email);
      await c.loadConfig();
      expect(await c.continueWithGoogle(_FakeGoogle(null)), isNull);
      expect(c.error, isNull);
      expect(c.step, SignupStep.contact);
      expect(s.count('POST /api/auth/google'), 0);
    });

    test('a server refusal is shown, and going back from the profile forgets Google', () async {
      final s = googleServer()..json('POST /api/auth/google', {'error': 'An account with this e-mail already exists. Log in with your password', 'field': 'email'}, status: 409);
      final c = _controller(s, channel: SignupChannel.email);
      await c.loadConfig();
      await c.continueWithGoogle(_FakeGoogle('t'));
      expect(c.fieldErrors['contact'] ?? c.error, contains('already exists'));

      final d = _controller(googleServer(), channel: SignupChannel.email);
      await d.loadConfig();
      await d.continueWithGoogle(_FakeGoogle('t'));
      d.changeContact();
      expect(d.viaGoogle, isFalse);
      expect(d.step, SignupStep.contact);
    });

    test('with no Google client id nothing is asked', () async {
      final c = _controller(FakeServer(), channel: SignupChannel.email);
      final google = _FakeGoogle('t');
      expect(await c.continueWithGoogle(google), isNull);
      expect(google.askedWith, isNull);
    });
  });

  group('e-mail channel', () {
    FakeServer emailServer() => FakeServer()
      ..json('GET /api/auth/config', {'signupChannel': 'email', 'channels': ['email']})
      ..json('POST /api/auth/email/send', {'sent': true, 'email': 'riya@example.com', 'resendInSec': 30})
      ..json('POST /api/auth/email/verify', {'verified': true, 'email': 'riya@example.com', 'signupToken': 'su-e'})
      ..json('POST /api/auth/signup', {'token': 'login-1', 'user': _user}, status: 201);

    test('the channel follows the server config; an unreachable server means e-mail', () async {
      final phone = FakeServer()..json('GET /api/auth/config', {'signupChannel': 'phone', 'channels': ['phone']});
      final c = _controller(phone, channel: SignupChannel.email);
      await c.loadConfig();
      expect(c.channel, SignupChannel.phone);

      final none = FakeServer();
      final d = _controller(none, channel: SignupChannel.phone);
      await d.loadConfig();
      expect(d.channel, SignupChannel.email);
      expect(d.googleClientId, isNull);
    });

    test('a badly shaped address is stopped before the server', () async {
      final s = emailServer();
      final c = _controller(s, channel: SignupChannel.email);
      for (final bad in ['', 'riya', 'riya@', 'riya@example', 'a b@example.com']) {
        await c.sendCode(bad);
        expect(c.fieldErrors['contact'], contains('e-mail'), reason: bad);
      }
      expect(s.count('POST /api/auth/email/send'), 0);
    });

    test('send, verify and sign up with the e-mail; the profile sends no e-mail of its own', () async {
      final s = emailServer();
      final c = _controller(s, channel: SignupChannel.email);
      await c.sendCode('  Riya@Example.com ');
      expect(s.last('POST /api/auth/email/send').json, {'email': 'Riya@Example.com'});
      expect(c.step, SignupStep.code);
      expect(c.contact, 'riya@example.com');
      await c.verifyCode('123456');
      expect(s.last('POST /api/auth/email/verify').json, {'email': 'riya@example.com', 'code': '123456'});
      expect(c.step, SignupStep.profile);
      final result = await _submit(c, email: 'typed@elsewhere.com');
      expect(result, isNotNull);
      final body = s.last('POST /api/auth/signup').json;
      expect(body['signupToken'], 'su-e');
      expect(body.containsKey('email'), isFalse);
    });

    test('a refused or already-used address goes back to step 1 with the reason under the box', () async {
      final s = emailServer()..json('POST /api/auth/email/send', {'error': 'An account with this e-mail already exists. Log in instead', 'field': 'email'}, status: 409);
      final c = _controller(s, channel: SignupChannel.email);
      await c.sendCode('riya@example.com');
      expect(c.step, SignupStep.contact);
      expect(c.fieldErrors['contact'], contains('already exists'));
    });
  });

  test('rejects a number that is obviously wrong without calling the server', () async {
    final s = _server();
    final c = _controller(s);
    await c.sendCode('12345');
    expect(c.fieldErrors['contact'], isNotNull);
    expect(c.step, SignupStep.contact);
    expect(s.count('POST /api/auth/otp/send'), 0);
  });

  test('send code moves to the code step with the normalised number and a cool-down', () async {
    final c = _controller(_server(), now: () => today);
    await c.sendCode('98765 43210');
    expect(c.step, SignupStep.code);
    expect(c.contact, '+919876543210');
    expect(c.resendInSec, inInclusiveRange(29, 31));
  });

  test('resend is blocked during the cool-down and allowed after it', () async {
    final s = _server();
    var clock = today;
    final c = _controller(s, now: () => clock);
    await c.sendCode('9876543210');
    await c.resend();
    expect(s.count('POST /api/auth/otp/send'), 1);
    clock = today.add(const Duration(seconds: 31));
    expect(c.resendInSec, 0);
    await c.resend();
    expect(s.count('POST /api/auth/otp/send'), 2);
  });

  test('a rate-limit answer starts a countdown instead of an error banner', () async {
    final s = _server()..json('POST /api/auth/otp/send', {'error': 'Wait', 'retryAfterSec': 25}, status: 429);
    final c = _controller(s, now: () => today);
    await c.sendCode('9876543210');
    expect(c.step, SignupStep.contact);
    expect(c.error, 'Wait');
    expect(c.resendInSec, inInclusiveRange(24, 26));
  });

  test('a number that already has an account is reported under the phone input', () async {
    final s = _server()..json('POST /api/auth/otp/send', {'error': 'Already registered. Log in instead.', 'field': 'phone'}, status: 409);
    final c = _controller(s);
    await c.sendCode('9876543210');
    expect(c.fieldErrors['contact'], contains('Already registered'));
    expect(c.error, isNull);
  });

  test('a server outage is a general error, not blamed on the phone input', () async {
    final s = _server()..json('POST /api/auth/otp/send', {'error': 'Could not send the code'}, status: 502);
    final c = _controller(s);
    await c.sendCode('9876543210');
    expect(c.error, 'Could not send the code');
    expect(c.fieldErrors, isEmpty);
  });

  test('the code must be 6 digits; a wrong code stays on the code step', () async {
    final s = _server()..json('POST /api/auth/otp/verify', {'error': 'Wrong code'}, status: 400);
    final c = _controller(s);
    await c.sendCode('9876543210');
    await c.verifyCode('12');
    expect(c.fieldErrors['code'], isNotNull);
    expect(s.count('POST /api/auth/otp/verify'), 0);
    await c.verifyCode('123456');
    expect(c.step, SignupStep.code);
    expect(c.fieldErrors['code'], 'Wrong code');
  });

  test('happy path: the account comes back and the token is used once', () async {
    final s = _server();
    final c = _controller(s, now: () => today);
    await _toProfile(c);
    final result = await _submit(c);
    expect(result!.token, 'login-1');
    expect(s.last('POST /api/auth/signup').json['signupToken'], 'su-1');
    expect(s.last('POST /api/auth/signup').json['dob'], '2000-05-20');
    // the proof of verification is spent: signing up again needs a fresh code
    expect(await _submit(c), isNull);
    expect(c.step, SignupStep.contact);
  });

  test('under 18 is refused before any request, to the exact day', () async {
    final s = _server();
    final c = _controller(s, now: () => today);
    await _toProfile(c);
    final tooYoung = await _submit(c, dob: DateTime(2008, 10, 13)); // turns 18 tomorrow
    expect(tooYoung, isNull);
    expect(c.fieldErrors['dob'], contains('18'));
    expect(s.count('POST /api/auth/signup'), 0);
    expect(await _submit(c, dob: DateTime(2008, 10, 12)), isNotNull); // turns 18 today
  });

  test('every field is checked and all problems are shown together', () async {
    final s = _server();
    final c = _controller(s, now: () => today);
    await _toProfile(c);
    final r = await c.submit(fullName: ' ', username: 'a', dob: null, password: 'short', email: 'nope');
    expect(r, isNull);
    expect(c.fieldErrors.keys, containsAll(['fullName', 'username', 'dob', 'password', 'email']));
    expect(s.count('POST /api/auth/signup'), 0);
  });

  test('a username taken in the meantime is shown under that input and keeps the form', () async {
    final s = _server()
      ..json('POST /api/auth/signup', {'error': 'Username taken', 'field': 'username', 'reason': 'TAKEN'}, status: 409);
    final c = _controller(s, now: () => today);
    await _toProfile(c);
    expect(await _submit(c), isNull);
    expect(c.step, SignupStep.profile);
    expect(c.fieldErrors['username'], 'Username taken');
  });

  test('an expired verification sends the person back to the phone step', () async {
    final s = _server()
      ..json('POST /api/auth/signup', {'error': 'Verify your phone number first', 'field': 'signupToken'}, status: 401);
    final c = _controller(s, now: () => today);
    await _toProfile(c);
    expect(await _submit(c), isNull);
    expect(c.step, SignupStep.contact);
    expect(c.fieldErrors['contact'], contains('Verify'));
  });

  test('going back to change the number drops the verification', () async {
    final s = _server();
    final c = _controller(s, now: () => today);
    await _toProfile(c);
    c.changeContact();
    expect(c.step, SignupStep.contact);
    expect(await _submit(c), isNull);
    expect(s.count('POST /api/auth/signup'), 0);
  });

  test('double taps send one request', () async {
    final s = _server();
    final gate = Completer<void>();
    s.on('POST /api/auth/otp/send', (_) => throw StateError('replaced below'));
    final slow = FakeServer()
      ..json('POST /api/auth/otp/send', {'sent': true, 'phone': '+91x', 'resendInSec': 30});
    final c = SignupController(AuthRepository(slow.client()), channel: SignupChannel.phone);
    final a = c.sendCode('9876543210');
    final b = c.sendCode('9876543210');
    await Future.wait([a, b]);
    gate.complete();
    expect(slow.count('POST /api/auth/otp/send'), 1);
  });

  group('live username check', () {
    test('checks after a pause, not on every key', () async {
      final s = _server();
      final c = _controller(s);
      c.onUsernameChanged('ri');
      c.onUsernameChanged('riy');
      c.onUsernameChanged('riya_k');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(s.count('GET /api/auth/username-available'), 1);
      expect(c.usernameCheck!.available, isTrue);
      expect(c.usernameChecking, isFalse);
    });

    test('a badly shaped name is rejected locally', () async {
      final s = _server();
      final c = _controller(s);
      c.onUsernameChanged('no spaces!');
      expect(c.usernameCheck!.available, isFalse);
      expect(SignupController.usernameProblem(c.usernameCheck!), contains('3-30'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(s.count('GET /api/auth/username-available'), 0);
    });

    test('a slow old answer never overwrites a newer one', () async {
      final slowFirst = Completer<void>();
      final s = FakeServer();
      s.on('GET /api/auth/username-available', (_) => throw UnimplementedError());
      // Hand-rolled client so the first request can be held back.
      var calls = 0;
      final repo = _ReorderingAuth(onCall: (name) async {
        calls++;
        if (name == 'first_name') {
          await slowFirst.future;
          return const UsernameCheck(available: false, reason: 'TAKEN');
        }
        return const UsernameCheck(available: true);
      });
      final c = SignupController(repo, usernameDebounce: const Duration(milliseconds: 1));
      c.onUsernameChanged('first_name');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      c.onUsernameChanged('second_name');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.usernameCheck!.available, isTrue);
      slowFirst.complete(); // the stale TAKEN answer arrives late
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.usernameCheck!.available, isTrue);
      expect(calls, 2);
    });

    test('clearing the field clears the result', () async {
      final c = _controller(_server());
      c.onUsernameChanged('riya_k');
      c.onUsernameChanged('');
      expect(c.usernameCheck, isNull);
      expect(c.usernameChecking, isFalse);
    });
  });
}

/// Auth repository whose username check is scripted by the test.
class _ReorderingAuth extends AuthRepository {
  _ReorderingAuth({required this.onCall}) : super(FakeServer().client());
  final Future<UsernameCheck> Function(String name) onCall;

  @override
  Future<UsernameCheck> usernameAvailable(String username) => onCall(username);
}
