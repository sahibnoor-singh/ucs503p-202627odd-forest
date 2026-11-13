const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const { TEST_SECRET, startServer, addUser, addPost } = require('./helpers');
const { createTokens } = require('../src/auth/tokens');
const { createProvider } = require('../src/auth/providers');

const tokens = createTokens(TEST_SECRET);
let phoneCounter = 0;
const newPhone = () => `+9198${String(10000000 + ++phoneCounter)}`;
const post = (s, url, json, headers) => s.api('POST', url, { json }).then((r) => r);

/** A server with a clock the test controls. */
async function startWithClock(extra = {}) {
  const clock = { now: Date.UTC(2026, 9, 17, 12, 0, 0) };
  const s = await startServer({ appOptions: { clock: () => clock.now, ...extra } });
  return { s, clock };
}

async function verifyPhone(s, phone) {
  assert.equal((await post(s, '/api/auth/otp/send', { phone })).status, 200);
  const { code } = s.otpProvider.last(phone);
  const res = await post(s, '/api/auth/otp/verify', { phone, code });
  assert.equal(res.status, 200, JSON.stringify(res.data));
  return res.data.signupToken;
}

const goodSignup = (signupToken, over = {}) => ({
  signupToken, fullName: 'Riya  Kapoor ', username: 'Riya_K', dob: '2000-05-20', password: 'a decent passphrase', ...over
});

async function createAccount(s, over = {}, phone = newPhone()) {
  const signupToken = await verifyPhone(s, phone);
  const res = await post(s, '/api/auth/signup', goodSignup(signupToken, over));
  assert.equal(res.status, 201, JSON.stringify(res.data));
  return { ...res.data, phone };
}

// ---------------- username check ----------------

test('username check: free, taken (with free suggestions), invalid, reserved, case-insensitive', async () => {
  const { s } = await startWithClock();
  try {
    addUser(s.db, 'taken_name');
    const ask = (u) => s.api('GET', `/api/auth/username-available?u=${encodeURIComponent(u)}`);
    assert.deepEqual((await ask('brand_new')).data, { available: true });
    const taken = (await ask('TAKEN_name')).data;
    assert.equal(taken.available, false);
    assert.equal(taken.reason, 'TAKEN');
    assert.equal(taken.suggestions.length, 3);
    for (const t of taken.suggestions) assert.equal((await ask(t)).data.available, true, `${t} should really be free`);
    assert.deepEqual((await ask('a')).data, { available: false, reason: 'INVALID' });
    assert.deepEqual((await ask('forest_team')).data, { available: false, reason: 'RESERVED' });
    assert.equal((await s.api('GET', '/api/auth/username-available')).data.reason, 'INVALID');
    assert.equal((await s.api('GET', '/api/auth/username-available?u=a&u=b')).data.reason, 'INVALID'); // array input
    assert.equal((await ask('brand_new')).status, 200, 'never an error status while typing');
  } finally { await s.close(); }
});

// ---------------- OTP ----------------

test('otp send: validates the number, never returns the code, normalises a bare Indian number', async () => {
  const { s } = await startWithClock();
  try {
    assert.equal((await post(s, '/api/auth/otp/send', { phone: '12345' })).status, 400);
    assert.equal((await post(s, '/api/auth/otp/send', {})).status, 400);
    const res = await post(s, '/api/auth/otp/send', { phone: '98765 43210' });
    assert.equal(res.status, 200);
    assert.equal(res.data.phone, '+919876543210');
    assert.equal(res.data.resendInSec, 30);
    assert.equal(res.data.devCode, undefined, 'a real provider must never hand the code to the caller');
    assert.ok(!JSON.stringify(res.data).match(/\b\d{6}\b/));
    assert.equal(s.otpProvider.sent.length, 1);
    assert.match(s.otpProvider.sent[0].code, /^\d{6}$/);
    assert.equal(s.db.get('SELECT code_hash FROM otp_codes').code_hash.includes(s.otpProvider.sent[0].code), false, 'only a hash is stored');
  } finally { await s.close(); }
});

test('otp send: 30 s cooldown, then allowed; at most 5 a day; a provider failure costs nothing', async () => {
  const { s, clock } = await startWithClock();
  try {
    const phone = newPhone();
    assert.equal((await post(s, '/api/auth/otp/send', { phone })).status, 200);
    const early = await s.api('POST', '/api/auth/otp/send', { json: { phone } });
    assert.equal(early.status, 429);
    assert.equal(early.data.retryAfterSec, 30);
    assert.equal(early.headers.get('retry-after'), '30');
    assert.equal(s.otpProvider.sent.length, 1, 'no second SMS was sent');
    clock.now += 31000;
    assert.equal((await post(s, '/api/auth/otp/send', { phone })).status, 200);
    for (let i = 0; i < 3; i++) { clock.now += 31000; assert.equal((await post(s, '/api/auth/otp/send', { phone })).status, 200); }
    clock.now += 31000;
    const sixth = await post(s, '/api/auth/otp/send', { phone });
    assert.equal(sixth.status, 429);
    assert.match(sixth.data.error, /today/);
    clock.now += 24 * 3600 * 1000; // next day
    assert.equal((await post(s, '/api/auth/otp/send', { phone })).status, 200);

    // provider outage: 502, nothing stored, and the person can try again straight away
    const other = newPhone();
    const real = s.otpProvider.send;
    s.otpProvider.send = async () => { throw new Error('SMS gateway down'); };
    assert.equal((await post(s, '/api/auth/otp/send', { phone: other })).status, 502);
    assert.equal(s.db.get('SELECT 1 AS x FROM otp_codes WHERE phone = ?', [other]), null);
    s.otpProvider.send = real;
    assert.equal((await post(s, '/api/auth/otp/send', { phone: other })).status, 200);
  } finally { await s.close(); }
});

test('otp send: a number that already has an account is turned away before any SMS is paid for', async () => {
  const { s } = await startWithClock();
  try {
    const acct = await createAccount(s);
    const sentBefore = s.otpProvider.sent.length;
    const res = await post(s, '/api/auth/otp/send', { phone: acct.phone });
    assert.equal(res.status, 409);
    assert.equal(res.data.field, 'phone');
    assert.equal(s.otpProvider.sent.length, sentBefore);
  } finally { await s.close(); }
});

test('otp verify: wrong guesses are counted, 5 kill the code, expiry and single use are enforced', async () => {
  const { s, clock } = await startWithClock();
  try {
    const phone = newPhone();
    await post(s, '/api/auth/otp/send', { phone });
    const { code } = s.otpProvider.last(phone);
    const wrong = code === '000000' ? '111111' : '000000';

    const first = await post(s, '/api/auth/otp/verify', { phone, code: wrong });
    assert.equal(first.status, 400);
    assert.match(first.data.error, /4 tries left/);
    for (let i = 0; i < 4; i++) await post(s, '/api/auth/otp/verify', { phone, code: wrong });
    const locked = await post(s, '/api/auth/otp/verify', { phone, code });
    assert.equal(locked.status, 429, 'even the right code is refused after 5 wrong tries');

    clock.now += 31000;
    await post(s, '/api/auth/otp/send', { phone }); // a fresh code resets the tries
    const fresh = s.otpProvider.last(phone).code;
    assert.equal((await post(s, '/api/auth/otp/verify', { phone, code: fresh })).status, 200);
    const again = await post(s, '/api/auth/otp/verify', { phone, code: fresh });
    assert.equal(again.status, 400, 'a code works once');

    // expiry
    const p2 = newPhone();
    await post(s, '/api/auth/otp/send', { phone: p2 });
    const c2 = s.otpProvider.last(p2).code;
    clock.now += 5 * 60 * 1000 + 1000;
    const late = await post(s, '/api/auth/otp/verify', { phone: p2, code: c2 });
    assert.equal(late.status, 400);
    assert.match(late.data.error, /expired/);

    assert.equal((await post(s, '/api/auth/otp/verify', { phone: newPhone(), code: '123456' })).status, 400, 'no code was ever sent');
    assert.equal((await post(s, '/api/auth/otp/verify', { phone: 'nope', code: '123456' })).status, 400);
  } finally { await s.close(); }
});

test('the console provider hands the code back for development only, and refuses to run in production', async () => {
  const logs = [];
  const realLog = console.log;
  console.log = (...a) => logs.push(a.join(' '));
  const s = await startServer({ appOptions: { otpProvider: createProvider('console') } });
  try {
    const res = await post(s, '/api/auth/otp/send', { phone: newPhone() });
    assert.match(res.data.devCode, /^\d{6}$/);
    assert.ok(logs.some((l) => l.includes(res.data.devCode)));
  } finally { console.log = realLog; await s.close(); }
  assert.throws(() => createProvider('console', { production: true }), /cannot be used in production/);
  assert.throws(() => createProvider('carrier-pigeon'), /Unknown OTP_PROVIDER/);
});

// ---------------- sign up ----------------

test('sign up: the happy path creates a verified account and the token works straight away', async () => {
  const { s } = await startWithClock();
  try {
    const phone = newPhone();
    const signupToken = await verifyPhone(s, phone);
    const res = await post(s, '/api/auth/signup', goodSignup(signupToken, { email: ' Riya@Example.COM ' }));
    assert.equal(res.status, 201);
    assert.equal(res.data.user.username, 'riya_k', 'stored lowercase');
    assert.equal(res.data.user.fullName, 'Riya Kapoor', 'whitespace tidied');
    assert.equal(res.data.user.isBot, false);
    assert.equal(res.data.expiresInSec, 30 * 24 * 3600);
    // nothing private comes back in the user object or the response
    const body = JSON.stringify(res.data);
    for (const secret of ['password', 'passphrase', phone, 'example.com', '2000-05-20', 'hash', 'scrypt']) {
      assert.ok(!body.toLowerCase().includes(secret.toLowerCase()), `response must not contain ${secret}`);
    }
    const row = s.db.get('SELECT * FROM users WHERE username = ?', ['riya_k']);
    assert.equal(row.phone, phone);
    assert.equal(row.phone_verified, 1);
    assert.equal(row.email, 'riya@example.com');
    assert.equal(row.dob, '2000-05-20');
    assert.match(row.password_hash, /^scrypt\$/);
    assert.ok(!row.password_hash.includes('passphrase'));

    const me = await s.api('GET', '/api/me', { json: undefined });
    assert.equal(me.status, 401);
    const withToken = await fetch(`${s.base}/api/me`, { headers: { authorization: `Bearer ${res.data.token}` } });
    assert.equal(withToken.status, 200);
    const meBody = await withToken.json();
    assert.equal(meBody.user.username, 'riya_k');
    assert.ok(!JSON.stringify(meBody).includes('2000-05-20'));
  } finally { await s.close(); }
});

test('sign up: e-mail is optional, and a blank one counts as none', async () => {
  const { s } = await startWithClock();
  try {
    await createAccount(s, { username: 'no_email_1' });
    await createAccount(s, { username: 'no_email_2', email: '   ' });
    assert.equal(s.db.get("SELECT COUNT(*) AS n FROM users WHERE email IS NULL").n, 2, 'two people with no e-mail do not clash');
  } finally { await s.close(); }
});

test('sign up: every field is validated, and the error says which field', async () => {
  const { s } = await startWithClock();
  try {
    const bad = async (over, status, field, pattern) => {
      const token = await verifyPhone(s, newPhone());
      const res = await post(s, '/api/auth/signup', goodSignup(token, over));
      assert.equal(res.status, status, JSON.stringify({ over, got: res.data }));
      assert.equal(res.data.field, field, JSON.stringify(res.data));
      if (pattern) assert.match(res.data.error, pattern);
      return res;
    };
    await bad({ fullName: '' }, 400, 'fullName');
    await bad({ fullName: 'x'.repeat(61) }, 400, 'fullName');
    await bad({ fullName: 'Bad\u0000Name' }, 400, 'fullName');
    await bad({ username: 'no' }, 400, 'username');
    await bad({ username: 'forest_admin' }, 400, 'username', /isn't available/);
    await bad({ email: 'not-an-email' }, 400, 'email');
    await bad({ dob: '2000-02-31' }, 400, 'dob', /real date/);
    await bad({ dob: '2012-01-01' }, 400, 'dob', /at least 18/).then((r) => assert.equal(r.data.tooYoung, true));
    await bad({ dob: '2026-10-18' }, 400, 'dob');
    await bad({ password: 'short' }, 400, 'password');
    await bad({ password: 'password123' }, 400, 'password', /too common/);
    await bad({ username: 'same_as_pw', password: 'same_as_pw' }, 400, 'password', /username/);
    assert.equal(s.db.get('SELECT COUNT(*) AS n FROM users').n, 0, 'nothing was created by any rejected attempt');
  } finally { await s.close(); }
});

test('sign up: the age gate lets a 18th-birthday-today through and stops the day before', async () => {
  const { s } = await startWithClock(); // clock is 17 Oct 2026
  try {
    const t1 = await verifyPhone(s, newPhone());
    assert.equal((await post(s, '/api/auth/signup', goodSignup(t1, { username: 'just_18', dob: '2008-10-17' }))).status, 201);
    const t2 = await verifyPhone(s, newPhone());
    assert.equal((await post(s, '/api/auth/signup', goodSignup(t2, { username: 'almost_18', dob: '2008-10-18' }))).status, 400);
  } finally { await s.close(); }
});

test('sign up needs a real signup token: missing, forged, expired, or a login token all fail', async () => {
  const { s } = await startWithClock();
  try {
    const user = await createAccount(s, { username: 'owner' });
    const attempts = [
      undefined, '', 'garbage',
      user.token, // a LOGIN token must not work as a phone verification
      jwt.sign({ typ: 'signup', phone: newPhone() }, 'wrong-secret-wrong-secret-12345', { algorithm: 'HS256' }),
      jwt.sign({ typ: 'signup', phone: newPhone() }, TEST_SECRET, { algorithm: 'HS256', expiresIn: -5 })
    ];
    for (const signupToken of attempts) {
      const res = await post(s, '/api/auth/signup', goodSignup(signupToken, { username: 'sneaky' }));
      assert.equal(res.status, 401, String(signupToken).slice(0, 30));
      assert.equal(res.data.field, 'signupToken');
    }
    assert.equal(s.db.get("SELECT 1 AS x FROM users WHERE username = 'sneaky'"), null);
  } finally { await s.close(); }
});

test('sign up: a signup token cannot be replayed, and clashes on username, phone or e-mail say which', async () => {
  const { s } = await startWithClock();
  try {
    const first = await createAccount(s, { username: 'first_one', email: 'dup@example.com' });
    // same token again: the username is now taken
    const phone = newPhone();
    const token = await verifyPhone(s, phone);
    const clash = await post(s, '/api/auth/signup', goodSignup(token, { username: 'FIRST_ONE' }));
    assert.equal(clash.status, 409);
    assert.equal(clash.data.field, 'username');
    assert.equal(clash.data.reason, 'TAKEN');
    const mail = await post(s, '/api/auth/signup', goodSignup(token, { username: 'someone_else', email: 'DUP@example.com' }));
    assert.equal(mail.status, 409);
    assert.equal(mail.data.field, 'email');
    // the same verified token can still be used for a legitimate signup once the clash is fixed
    const ok = await post(s, '/api/auth/signup', goodSignup(token, { username: 'someone_else', email: 'other@example.com' }));
    assert.equal(ok.status, 201);
    // ...but not twice: the phone is now taken
    const replay = await post(s, '/api/auth/signup', goodSignup(token, { username: 'third_try' }));
    assert.equal(replay.status, 409);
    assert.equal(replay.data.field, 'phone');
    assert.ok(first);
  } finally { await s.close(); }
});

// ---------------- login ----------------

test('login by username, e-mail or phone; username is case-insensitive; the token then works', async () => {
  const { s } = await startWithClock();
  try {
    const acct = await createAccount(s, { username: 'log_in_me', email: 'log@in.me' }, '+919811122233');
    const attempt = (identifier) => post(s, '/api/auth/login', { identifier, password: 'a decent passphrase' });
    for (const id of ['log_in_me', 'LOG_IN_ME', ' log_in_me ', 'log@in.me', 'LOG@IN.ME', '+919811122233', '9811122233', '+91 98111-22233']) {
      const res = await attempt(id);
      assert.equal(res.status, 200, `identifier "${id}" -> ${JSON.stringify(res.data)}`);
      assert.equal(res.data.user.id, acct.user.id);
    }
    const res = await attempt('log_in_me');
    const home = await fetch(`${s.base}/api/home`, { headers: { authorization: `Bearer ${res.data.token}` } });
    assert.equal(home.status, 200);
    assert.ok(!JSON.stringify(res.data).includes('scrypt'));
  } finally { await s.close(); }
});

test('login failures all look the same, and accounts without a password cannot be logged into', async () => {
  const { s } = await startWithClock();
  try {
    await createAccount(s, { username: 'real_one' });
    addUser(s.db, 'a_bot', { bot: true }); // no password at all
    const wrongPassword = await post(s, '/api/auth/login', { identifier: 'real_one', password: 'not the password' });
    const noSuchUser = await post(s, '/api/auth/login', { identifier: 'ghost_user', password: 'not the password' });
    const botLogin = await post(s, '/api/auth/login', { identifier: 'a_bot', password: 'anything at all' });
    for (const r of [wrongPassword, noSuchUser, botLogin]) {
      assert.equal(r.status, 401);
      assert.equal(r.data.error, 'Wrong username or password');
    }
    assert.deepEqual(Object.keys(wrongPassword.data), Object.keys(noSuchUser.data), 'identical shape: no hint which part was wrong');
    for (const bad of [{}, { identifier: 'x' }, { password: 'x' }, { identifier: 5, password: 'x' }, { identifier: ' ', password: 'x' }]) {
      assert.equal((await post(s, '/api/auth/login', bad)).status, 400, JSON.stringify(bad));
    }
  } finally { await s.close(); }
});

test('login lockout: repeated wrong passwords lock that account from that place, then it recovers', async () => {
  const { s, clock } = await startWithClock();
  try {
    await createAccount(s, { username: 'target_a' });
    await createAccount(s, { username: 'target_b' });
    const login = (identifier, password) => s.api('POST', '/api/auth/login', { json: { identifier, password } });
    for (let i = 0; i < 8; i++) assert.equal((await login('target_a', `wrong-${i}`)).status, 401);
    const locked = await login('target_a', 'a decent passphrase'); // the RIGHT password is refused while locked
    assert.equal(locked.status, 429);
    assert.equal(locked.data.retryAfterSec, 900);
    assert.equal(locked.headers.get('retry-after'), '900');
    assert.equal((await login('target_b', 'a decent passphrase')).status, 200, 'other accounts are unaffected');
    clock.now += 15 * 60 * 1000 + 1000;
    assert.equal((await login('target_a', 'a decent passphrase')).status, 200, 'unlocked after 15 minutes');
    // a success clears the count
    for (let i = 0; i < 7; i++) await login('target_a', 'nope');
    assert.equal((await login('target_a', 'a decent passphrase')).status, 200);
    for (let i = 0; i < 7; i++) await login('target_a', 'nope');
    assert.equal((await login('target_a', 'a decent passphrase')).status, 200, 'the earlier success reset the counter');
  } finally { await s.close(); }
});

// ---------------- using tokens ----------------

test('access tokens: valid ones work, bad ones are 401 and NEVER fall back to the dev header', async () => {
  const { s } = await startWithClock();
  try {
    const acct = await createAccount(s, { username: 'token_user' });
    addUser(s.db, 'dev_person');
    const call = (headers) => fetch(`${s.base}/api/me`, { headers });
    assert.equal((await call({ authorization: `Bearer ${acct.token}` })).status, 200);

    const deleted = tokens.signAccess('a-user-id-that-no-longer-exists');
    const expired = jwt.sign({ typ: 'access', sub: acct.user.id }, TEST_SECRET, { algorithm: 'HS256', expiresIn: -5 });
    for (const bad of [`Bearer ${deleted}`, `Bearer ${expired}`, 'Bearer garbage', 'Bearer ', 'Basic abc',
      `Bearer ${tokens.signSignup('+919800000000')}`, acct.token /* missing the "Bearer " word */]) {
      assert.equal((await call({ authorization: bad })).status, 401, bad.slice(0, 40));
    }
    // a bad token plus a valid dev header: still 401, so a client can't hide an expired login behind the dev header
    assert.equal((await call({ authorization: 'Bearer garbage', 'x-dev-user': 'dev_person' })).status, 401);
    assert.equal((await call({ authorization: 'Basic abc', 'x-dev-user': 'dev_person' })).status, 401, 'malformed header too');
    assert.equal((await call({ authorization: `Bearer ${expired}`, 'x-dev-user': 'dev_person' })).status, 401, 'expired login too');
    assert.equal((await call({ authorization: `Bearer ${deleted}`, 'x-dev-user': 'dev_person' })).status, 401, 'deleted account too');
    // and the dev header alone still works while enabled (TEMP)
    assert.equal((await call({ 'x-dev-user': 'dev_person' })).status, 200);
  } finally { await s.close(); }
});

test('with the dev header off, only tokens identify people', async () => {
  const { s } = await startWithClock({ allowDevUser: false });
  try {
    addUser(s.db, 'dev_person');
    const acct = await createAccount(s, { username: 'real_token_user' });
    assert.equal((await fetch(`${s.base}/api/me`, { headers: { 'x-dev-user': 'dev_person' } })).status, 401);
    assert.equal((await fetch(`${s.base}/api/me`, { headers: { authorization: `Bearer ${acct.token}` } })).status, 200);
    // and a signed-in person can really do things
    const p = addPost(s.db, { userId: addUser(s.db, 'someone'), title: 't' });
    const like = await fetch(`${s.base}/api/posts/${p}/like`, { method: 'POST', headers: { authorization: `Bearer ${acct.token}` } });
    assert.equal(like.status, 200);
  } finally { await s.close(); }
});

test('auth endpoints are rate limited per minute when limits are on', async () => {
  const { s } = await startWithClock({ rateLimit: { login: { max: 3, windowMs: 5000 }, otpSend: { max: 2, windowMs: 5000 }, usernameCheck: { max: 4, windowMs: 5000 } } });
  try {
    const codes = [];
    for (let i = 0; i < 5; i++) codes.push((await s.api('POST', '/api/auth/login', { json: { identifier: `ghost${i}`, password: 'x' } })).status);
    assert.deepEqual(codes, [401, 401, 401, 429, 429]);
    const sends = [];
    for (let i = 0; i < 3; i++) sends.push((await post(s, '/api/auth/otp/send', { phone: newPhone() })).status);
    assert.deepEqual(sends, [200, 200, 429]);
    const checks = [];
    for (let i = 0; i < 5; i++) checks.push((await s.api('GET', '/api/auth/username-available?u=abc')).status);
    assert.deepEqual(checks, [200, 200, 200, 200, 429]);
  } finally { await s.close(); }
});
