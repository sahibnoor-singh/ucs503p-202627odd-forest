const { test } = require('node:test');
const assert = require('node:assert/strict');
const { startServer } = require('./helpers');
const { createGoogleVerifier } = require('../src/auth/google');

const post = (s, url, json, user) => s.api('POST', url, { json, user });

/** Google's side, scripted: the token string is the key. */
function fakeGoogle() {
  const people = {
    'tok-riya': { sub: 'g-riya', email: 'Riya.Kapoor@gmail.com', emailVerified: true, name: '  Riya   Kapoor ' },
    'tok-riya-again': { sub: 'g-riya', email: 'riyakapoor@gmail.com', emailVerified: true, name: 'Riya Kapoor' },
    'tok-other': { sub: 'g-other', email: 'other@example.com', emailVerified: true, name: 'Other' },
    'tok-unverified': { sub: 'g-u', email: 'u@example.com', emailVerified: false, name: 'U' },
    'tok-burner': { sub: 'g-b', email: 'x@mailinator.com', emailVerified: true, name: 'B' }
  };
  return { verify: async (t) => { if (!people[t]) throw new Error('bad token'); return people[t]; } };
}

const start = (extra = {}) => startServer({ appOptions: { googleVerifier: fakeGoogle(), ...extra } });
const profile = (signupToken, over = {}) => ({ signupToken, fullName: 'Riya Kapoor', username: 'riya_k', dob: '2000-05-20', ...over });

test('config: the app is told the Google client id only when Google sign-in is on', async () => {
  const off = await startServer();
  try { assert.equal((await off.api('GET', '/api/auth/config')).data.googleClientId, null); } finally { await off.close(); }
  const on = await startServer({ appOptions: { googleClientIds: ['web-client.apps.googleusercontent.com'] } });
  try { assert.equal((await on.api('GET', '/api/auth/config')).data.googleClientId, 'web-client.apps.googleusercontent.com'); } finally { await on.close(); }
});

test('off by default: the route answers 404', async () => {
  const s = await startServer();
  try { assert.equal((await post(s, '/api/auth/google', { idToken: 'x' })).status, 404); } finally { await s.close(); }
});

test('a new person: Google gives a sign-up token, the profile needs no password, the account has the verified e-mail', async () => {
  const s = await start();
  try {
    const first = await post(s, '/api/auth/google', { idToken: 'tok-riya' });
    assert.equal(first.status, 200, JSON.stringify(first.data));
    assert.equal(first.data.needsProfile, true);
    assert.equal(first.data.email, 'riyakapoor@gmail.com');
    assert.equal(first.data.fullName, 'Riya Kapoor');

    const done = await post(s, '/api/auth/signup', profile(first.data.signupToken));
    assert.equal(done.status, 201, JSON.stringify(done.data));
    const row = s.db.get('SELECT * FROM users WHERE id = ?', [done.data.user.id]);
    assert.equal(row.email, 'riyakapoor@gmail.com');
    assert.equal(row.email_verified, 1);
    assert.equal(row.google_sub, 'g-riya');
    assert.equal(row.password_hash, null);
    assert.equal(row.phone, null);

    // the next time, Google logs them straight in (whichever way Google spells the address)
    const again = await post(s, '/api/auth/google', { idToken: 'tok-riya-again' });
    assert.equal(again.status, 200);
    assert.ok(again.data.token);
    assert.equal(again.data.user.username, 'riya_k');
    assert.equal(again.data.needsProfile, undefined);

    // no password exists, so password login says the usual thing and does not crash
    const pw = await post(s, '/api/auth/login', { identifier: 'riya_k', password: 'anything at all' });
    assert.equal(pw.status, 401);
  } finally { await s.close(); }
});

test('Google sign-up still enforces the age gate and the username rules', async () => {
  const s = await start();
  try {
    const { signupToken } = (await post(s, '/api/auth/google', { idToken: 'tok-other' })).data;
    const young = await post(s, '/api/auth/signup', profile(signupToken, { dob: '2015-01-01' }));
    assert.equal(young.status, 400);
    assert.equal(young.data.field, 'dob');
    const reserved = await post(s, '/api/auth/signup', profile(signupToken, { username: 'admin_x' }));
    assert.equal(reserved.status, 400);
    assert.equal(reserved.data.field, 'username');
  } finally { await s.close(); }
});

test('a password given on a Google sign-up is checked and kept', async () => {
  const s = await start();
  try {
    const { signupToken } = (await post(s, '/api/auth/google', { idToken: 'tok-other' })).data;
    const weak = await post(s, '/api/auth/signup', profile(signupToken, { password: '123' }));
    assert.equal(weak.status, 400);
    assert.equal(weak.data.field, 'password');
    const ok = await post(s, '/api/auth/signup', profile(signupToken, { password: 'a decent passphrase' }));
    assert.equal(ok.status, 201);
    const login = await post(s, '/api/auth/login', { identifier: 'other@example.com', password: 'a decent passphrase' });
    assert.equal(login.status, 200);
  } finally { await s.close(); }
});

test('a bad token, an unverified e-mail and a throw-away domain are refused', async () => {
  const s = await start();
  try {
    assert.equal((await post(s, '/api/auth/google', { idToken: 'nonsense' })).status, 401);
    assert.equal((await post(s, '/api/auth/google', {})).status, 401);
    assert.equal((await post(s, '/api/auth/google', { idToken: 'tok-unverified' })).status, 400);
    const burner = await post(s, '/api/auth/google', { idToken: 'tok-burner' });
    assert.equal(burner.status, 400);
    assert.equal(burner.data.field, 'email');
  } finally { await s.close(); }
});

test('the campus allow-list applies to Google sign-in too', async () => {
  const s = await start({ signupEmailDomains: ['thapar.edu'] });
  try {
    const r = await post(s, '/api/auth/google', { idToken: 'tok-riya' });
    assert.equal(r.status, 400);
    assert.match(r.data.error, /thapar\.edu/);
  } finally { await s.close(); }
});

test('an account made with a verified e-mail is linked by Google; one with a typed, unverified e-mail is not', async () => {
  const s = await start();
  try {
    // verified by code first
    await post(s, '/api/auth/email/send', { email: 'riyakapoor@gmail.com' });
    const code = s.emailProvider.last('riyakapoor@gmail.com').code;
    const { signupToken } = (await post(s, '/api/auth/email/verify', { email: 'riyakapoor@gmail.com', code })).data;
    const made = await post(s, '/api/auth/signup', profile(signupToken, { password: 'a decent passphrase' }));
    assert.equal(made.status, 201);
    const g = await post(s, '/api/auth/google', { idToken: 'tok-riya' });
    assert.equal(g.status, 200);
    assert.equal(g.data.user.id, made.data.user.id, 'same account');
    assert.equal(s.db.get('SELECT google_sub FROM users WHERE id = ?', [made.data.user.id]).google_sub, 'g-riya');

    // typed, never verified (phone sign-up with an optional e-mail)
    const { tokens } = { tokens: require('../src/auth/tokens').createTokens(require('./helpers').TEST_SECRET) };
    const typed = await post(s, '/api/auth/signup', profile(tokens.signSignup('+919800000009'), { username: 'typed_one', password: 'a decent passphrase', email: 'other@example.com' }));
    assert.equal(typed.status, 201, JSON.stringify(typed.data));
    const clash = await post(s, '/api/auth/google', { idToken: 'tok-other' });
    assert.equal(clash.status, 409);
    assert.equal(clash.data.field, 'email');
  } finally { await s.close(); }
});

test('a suspended account cannot get in through Google', async () => {
  const s = await start();
  try {
    const { signupToken } = (await post(s, '/api/auth/google', { idToken: 'tok-riya' })).data;
    const made = await post(s, '/api/auth/signup', profile(signupToken));
    s.db.run("UPDATE users SET suspended_at = '2026-10-01T00:00:00Z' WHERE id = ?", [made.data.user.id]);
    assert.equal((await post(s, '/api/auth/google', { idToken: 'tok-riya' })).status, 403);
  } finally { await s.close(); }
});

test('/api/me says whether there is a password; deleting a Google-only account needs a fresh Google proof', async () => {
  const s = await start();
  try {
    const { signupToken } = (await post(s, '/api/auth/google', { idToken: 'tok-riya' })).data;
    const made = await post(s, '/api/auth/signup', profile(signupToken));
    const auth = { authorization: `Bearer ${made.data.token}` };
    const call = async (method, url, json) => {
      const res = await fetch(s.base + url, { method, headers: { ...auth, 'content-type': 'application/json' }, body: json ? JSON.stringify(json) : undefined });
      return { status: res.status, data: await res.json() };
    };
    assert.deepEqual((await call('GET', '/api/me')).data.account, { hasPassword: false, google: true, onboarded: false });

    assert.equal((await call('DELETE', '/api/me', { password: 'x' })).status, 403);
    assert.equal((await call('DELETE', '/api/me', {})).status, 403);
    assert.equal((await call('DELETE', '/api/me', { idToken: 'tok-other' })).status, 403, "someone else's Google account");
    assert.equal((await call('DELETE', '/api/me', { idToken: 'nonsense' })).status, 403);
    const ok = await call('DELETE', '/api/me', { idToken: 'tok-riya' });
    assert.equal(ok.status, 200, JSON.stringify(ok.data));
    const row = s.db.get('SELECT * FROM users WHERE id = ?', [made.data.user.id]);
    assert.equal(row.google_sub, null);
    assert.equal(row.email, null);

    // the same Google account can start again as a brand-new person
    assert.equal((await post(s, '/api/auth/google', { idToken: 'tok-riya' })).data.needsProfile, true);
  } finally { await s.close(); }
});

test('the real verifier: needs a client id, asks Google with our audience, and refuses tokens without a subject', async () => {
  assert.equal(createGoogleVerifier({ clientIds: [] }), null);
  assert.equal(createGoogleVerifier({ clientIds: ['  '] }), null);
  const calls = [];
  const v = createGoogleVerifier({
    clientIds: ['web-1', 'web-2'],
    clientFactory: () => ({ verifyIdToken: async (a) => { calls.push(a); return { getPayload: () => (a.idToken === 'good' ? { sub: '42', email: 'a@b.co', email_verified: true, name: 'A' } : {}) }; } })
  });
  assert.deepEqual(await v.verify('good'), { sub: '42', email: 'a@b.co', emailVerified: true, name: 'A' });
  assert.deepEqual(calls[0], { idToken: 'good', audience: ['web-1', 'web-2'] });
  await assert.rejects(() => v.verify('empty'), /no subject/);
});
