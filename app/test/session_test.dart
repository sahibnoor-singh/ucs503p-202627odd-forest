import 'package:flutter_test/flutter_test.dart';

import 'package:forest_app/models/user.dart';
import 'package:forest_app/services/session.dart';

const _user = User(id: 'u1', username: 'riya_k', fullName: 'Riya K', avatarUrl: null, isBot: false);

class _BrokenStore implements TokenStore {
  @override
  Future<String?> read() async => throw Exception('disk gone');
  @override
  Future<void> write(String token) async => throw Exception('disk gone');
  @override
  Future<void> clear() async => throw Exception('disk gone');
  @override
  Future<bool> readOnboardingPending() async => throw Exception('disk gone');
  @override
  Future<void> writeOnboardingPending(bool pending) async => throw Exception('disk gone');
}

void main() {
  test('starts "restoring", then signed out when nothing is saved', () async {
    final s = Session(store: MemoryTokenStore());
    expect(s.status, SessionStatus.restoring);
    await s.restore();
    expect(s.status, SessionStatus.signedOut);
    expect(s.token, isNull);
  });

  test('a saved token means signed in after restore', () async {
    final s = Session(store: MemoryTokenStore('abc'));
    await s.restore();
    expect(s.isSignedIn, isTrue);
    expect(s.token, 'abc');
  });

  test('an empty saved token counts as signed out', () async {
    final s = Session(store: MemoryTokenStore(''));
    await s.restore();
    expect(s.status, SessionStatus.signedOut);
  });

  test('signIn keeps the token for next launch; signOut forgets it', () async {
    final store = MemoryTokenStore();
    final s = Session(store: store);
    await s.restore();
    await s.signIn(token: 'tok', user: _user);
    expect(s.isSignedIn, isTrue);
    expect(s.user, _user);
    expect(await store.read(), 'tok');

    await s.signOut();
    expect(s.status, SessionStatus.signedOut);
    expect(s.token, isNull);
    expect(s.user, isNull);
    expect(await store.read(), isNull);
  });

  test('expire (a 401) signs out once, however many requests fail together', () async {
    final store = MemoryTokenStore('tok');
    final s = Session(store: store);
    await s.restore();
    var notified = 0;
    s.addListener(() => notified++);
    await Future.wait([s.expire(), s.expire(), s.expire()]);
    expect(s.status, SessionStatus.signedOut);
    expect(notified, 1);
    expect(await store.read(), isNull);
  });

  test('a storage failure never crashes the app', () async {
    final s = Session(store: _BrokenStore());
    await s.restore();
    expect(s.status, SessionStatus.signedOut); // cannot read: treated as signed out
    await s.signIn(token: 'tok', user: _user);
    expect(s.isSignedIn, isTrue); // signed in for this run even though saving failed
    await s.signOut();
    expect(s.status, SessionStatus.signedOut);
  });

  test('the dev shortcut is signed in at once and cannot be expired', () async {
    final s = Session(store: MemoryTokenStore(), devBypass: true);
    expect(s.isSignedIn, isTrue);
    await s.restore();
    await s.expire();
    expect(s.isSignedIn, isTrue);
  });
}
