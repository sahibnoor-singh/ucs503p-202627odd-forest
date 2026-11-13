import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/data/auth_repository.dart';
import 'package:forest_app/services/api_client.dart';

import 'support/fake_server.dart';

const _userJson = {'id': 'u1', 'username': 'riya_k', 'fullName': 'Riya K', 'avatarUrl': null, 'isBot': false};

void main() {
  test('username check: sends the name, reads reason and suggestions', () async {
    final server = FakeServer()
      ..json('GET /api/auth/username-available', {'available': false, 'reason': 'TAKEN', 'suggestions': ['riya_k42']});
    final check = await AuthRepository(server.client()).usernameAvailable('riya_k');
    expect(server.last('GET /api/auth/username-available').uri.queryParameters['u'], 'riya_k');
    expect(check.available, isFalse);
    expect(check.reason, 'TAKEN');
    expect(check.suggestions, ['riya_k42']);
  });

  test('send code: normalised phone and cool-down come from the server; devCode only when given', () async {
    final server = FakeServer()
      ..json('POST /api/auth/otp/send', {'sent': true, 'phone': '+919876543210', 'resendInSec': 30, 'devCode': '123456'});
    final sent = await AuthRepository(server.client()).sendCode('9876543210');
    expect(server.last('POST /api/auth/otp/send').json, {'phone': '9876543210'});
    expect(sent.contact, '+919876543210');
    expect(sent.resendInSec, 30);
    expect(sent.devCode, '123456');

    final prod = FakeServer()..json('POST /api/auth/otp/send', {'sent': true, 'phone': '+91x', 'resendInSec': 30});
    expect((await AuthRepository(prod.client()).sendCode('9')).devCode, isNull);
  });

  test('e-mail: the address goes to the e-mail routes and comes back normalised', () async {
    final server = FakeServer()
      ..json('POST /api/auth/email/send', {'sent': true, 'email': 'riya@gmail.com', 'resendInSec': 30, 'devCode': '654321'})
      ..json('POST /api/auth/email/verify', {'verified': true, 'email': 'riya@gmail.com', 'signupToken': 'su-e'});
    final auth = AuthRepository(server.client());
    final sent = await auth.sendEmailCode('Riya@Gmail.com');
    expect(server.last('POST /api/auth/email/send').json, {'email': 'Riya@Gmail.com'});
    expect(sent.contact, 'riya@gmail.com');
    expect(sent.devCode, '654321');
    expect(await auth.verifyEmailCode('riya@gmail.com', '654321'), 'su-e');
    expect(server.last('POST /api/auth/email/verify').json, {'email': 'riya@gmail.com', 'code': '654321'});
  });

  test('config: channel and Google client id from the server; anything unexpected means e-mail and no Google', () async {
    final phone = await AuthRepository((FakeServer()..json('GET /api/auth/config', {'signupChannel': 'phone'})).client()).config();
    expect(phone.channel, SignupChannel.phone);
    expect(phone.googleClientId, isNull);
    final google = await AuthRepository((FakeServer()..json('GET /api/auth/config', {'signupChannel': 'email', 'googleClientId': 'web-1'})).client()).config();
    expect(google.channel, SignupChannel.email);
    expect(google.googleClientId, 'web-1');
    final down = await AuthRepository((FakeServer()..json('GET /api/auth/config', {'error': 'x'}, status: 500)).client()).config();
    expect(down.channel, SignupChannel.email);
    expect(down.googleClientId, isNull);
  });

  test('google: a known person is logged in, a new one gets a sign-up token and a name to offer', () async {
    final known = FakeServer()..json('POST /api/auth/google', {'token': 'tok', 'user': {'id': 'u1', 'username': 'riya_k', 'fullName': 'Riya K', 'avatarUrl': null, 'isBot': false}});
    final a = await AuthRepository(known.client()).googleSignIn('id-token');
    expect(known.last('POST /api/auth/google').json, {'idToken': 'id-token'});
    expect(a.login!.token, 'tok');
    expect(a.newPerson, isNull);

    final fresh = FakeServer()..json('POST /api/auth/google', {'needsProfile': true, 'signupToken': 'su-g', 'email': 'riya@gmail.com', 'fullName': 'Riya Kapoor'});
    final b = await AuthRepository(fresh.client()).googleSignIn('id-token');
    expect(b.login, isNull);
    expect(b.newPerson!.signupToken, 'su-g');
    expect(b.newPerson!.email, 'riya@gmail.com');
    expect(b.newPerson!.fullName, 'Riya Kapoor');

    final broken = FakeServer()..json('POST /api/auth/google', {'needsProfile': true});
    await expectLater(AuthRepository(broken.client()).googleSignIn('x'), throwsA(isA<ApiException>()));
  });

  test('hasPassword: false only when the server says so; a failed call keeps the password box', () async {
    expect(await AuthRepository((FakeServer()..json('GET /api/me', {'account': {'hasPassword': false}})).client()).hasPassword(), isFalse);
    expect(await AuthRepository((FakeServer()..json('GET /api/me', {'account': {'hasPassword': true}})).client()).hasPassword(), isTrue);
    expect(await AuthRepository((FakeServer()..json('GET /api/me', {'user': {}})).client()).hasPassword(), isTrue);
    expect(await AuthRepository(FakeServer().client()).hasPassword(), isTrue);
  });

  test('delete with Google sends the token, not a password', () async {
    final s = FakeServer()..json('DELETE /api/me', {'deleted': true});
    await AuthRepository(s.client()).deleteAccountWithGoogle('id-token');
    expect(s.last('DELETE /api/me').json, {'idToken': 'id-token'});
  });

  test('verify code returns the sign-up token; a reply without one is an error', () async {
    final server = FakeServer()..json('POST /api/auth/otp/verify', {'verified': true, 'signupToken': 'su-1'});
    expect(await AuthRepository(server.client()).verifyCode('+91x', '123456'), 'su-1');
    expect(server.last('POST /api/auth/otp/verify').json, {'phone': '+91x', 'code': '123456'});

    final bad = FakeServer()..json('POST /api/auth/otp/verify', {'verified': true});
    await expectLater(AuthRepository(bad.client()).verifyCode('+91x', '1'), throwsA(isA<ApiException>()));
  });

  test('sign up sends the profile (blank e-mail left out) and returns token + user', () async {
    final server = FakeServer()..json('POST /api/auth/signup', {'token': 'login-1', 'user': _userJson}, status: 201);
    final result = await AuthRepository(server.client()).signUp(
      signupToken: 'su-1', fullName: 'Riya K', username: 'riya_k', dob: '2000-05-20', password: 'pw-123456', email: '  ',
    );
    expect(server.last('POST /api/auth/signup').json, {
      'signupToken': 'su-1', 'fullName': 'Riya K', 'username': 'riya_k', 'dob': '2000-05-20', 'password': 'pw-123456',
    });
    expect(result.token, 'login-1');
    expect(result.user.username, 'riya_k');
  });

  test('login sends the identifier and password; failures keep the server wording', () async {
    final server = FakeServer()
      ..on('POST /api/auth/login', (s) => s.json['password'] == 'right'
          ? _ok({'token': 't', 'user': _userJson})
          : _no('Wrong username or password'));
    final repo = AuthRepository(server.client());
    expect((await repo.login('riya_k', 'right')).token, 't');
    await expectLater(
      repo.login('riya_k', 'wrong'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Wrong username or password')),
    );
  });
}

http.Response _ok(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
http.Response _no(String message) => http.Response(jsonEncode({'error': message}), 401, headers: {'content-type': 'application/json'});
