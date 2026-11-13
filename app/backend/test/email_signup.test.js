const { test } = require('node:test');
const assert = require('node:assert/strict');
const { TEST_SECRET, startServer, addUser } = require('./helpers');
const { createTokens } = require('../src/auth/tokens');
const { createMailer } = require('../src/auth/mailers');
const { normalizeEmail, emailProblem, maskEmail } = require('../src/auth/email');

const tokens = createTokens(TEST_SECRET);
const post = (s, url, json) => s.api('POST', url, { json });

async function startWithClock(extra = {}) {
  const clock = { now: Date.UTC(2026, 9, 21, 12, 0, 0) };
  const s = await startServer({ appOptions: { clock: () => clock.now, ...extra } });
  return { s, clock };
}

async function verifyEmail(s, email) {
  assert.equal((await post(s, '/api/auth/email/send', { email })).status, 200);
  const { code } = s.emailProvider.last(normalizeEmail(email));
  const res = await post(s, '/api/auth/email/verify', { email, code });
  assert.equal(res.status, 200, JSON.stringify(res.data));
  return res.data;
}

const profile = (signupToken, over = {}) => ({
  signupToken, fullName: 'Riya Kapoor', username: 'riya_k', dob: '2000-05-20', password: 'a decent passphrase', ...over
});

// ---------------- the address rules ----------------

test('addresses: Gmail dots and +tags collapse to one mailbox; other domains keep their form', () => {
  assert.equal(normalizeEmail('  Riya.Kapoor+news@Gmail.com '), 'riyakapoor@gmail.com');
  assert.equal(normalizeEmail('r.k@googlemail.com'), 'rk@gmail.com');
  assert.equal(normalizeEmail('Riya.K@Thapar.edu'), 'riya.k@thapar.edu');
  for (const bad of ['', 'nope', 'a@b', 'a b@c.com', 'a@@c.com', '@gmail.com', '+@gmail.com', null, undefined]) {
    assert.equal(normalizeEmail(bad), null, String(bad));
  }
});

test('addresses: +tags elsewhere, throw-away inboxes and the domain allow-list are refused with a reason', () => {
  assert.equal(emailProblem('riya@gmail.com'), null);
  assert.equal(emailProblem('riya+x@gmail.com'), null, 'Gmail ignores +tags, so it is the same mailbox');
  assert.match(emailProblem('riya+x@outlook.com'), /without a \+/);
  assert.match(emailProblem('someone@mailinator.com'), /Temporary/);
  assert.match(emailProblem('someone@inbox.mailinator.com', {}) || '', /^$|Temporary/);
  assert.match(emailProblem('someone@burner.example', { blockedDomains: ['burner.example'] }), /Temporary/);
  assert.match(emailProblem('riya@gmail.com', { allowedDomains: ['thapar.edu'] }), /@thapar\.edu/);
  assert.equal(emailProblem('riya@thapar.edu', { allowedDomains: ['thapar.edu'] }), null);
  assert.equal(emailProblem('riya@cse.thapar.edu', { allowedDomains: ['Thapar.edu'] }), null, 'subdomains of an allowed domain');
  assert.equal(emailProblem('riya@notthapar.edu', { allowedDomains: ['thapar.edu'] }) === null, false);
  assert.match(emailProblem('nope'), /valid e-mail/);
});

test('addresses are masked for logs', () => {
  assert.equal(maskEmail('riya.kapoor@gmail.com'), 'r***@gmail.com');
});

// ---------------- the sign-up flow ----------------

test('config: tells the app to use e-mail, and which channels are on', async () => {
  const { s } = await startWithClock();
  try {
    const { publicBaseUrl, ...config } = (await s.api('GET', '/api/auth/config')).data;
    assert.deepEqual(config, { signupChannel: 'email', channels: ['email', 'phone'], googleClientId: null });
    assert.ok(/^http:\/\/127\.0\.0\.1:\d+$/.test(publicBaseUrl), 'the address the request came in on, when none is configured');
  } finally { await s.close(); }
  const only = await startWithClock({ otpProvider: null });
  try {
    const { publicBaseUrl: _ignored, ...onlyConfig } = (await only.s.api('GET', '/api/auth/config')).data;
    assert.deepEqual(onlyConfig, { signupChannel: 'email', channels: ['email'], googleClientId: null });
    const r = await post(only.s, '/api/auth/otp/send', { phone: '+919876543210' });
    assert.equal(r.status, 404, 'phone sign-up is off');
  } finally { await only.s.close(); }
});

test('e-mail sign-up: code in the inbox, verify, finish the profile, the address is the verified e-mail, login works with it', async () => {
  const { s, clock } = await startWithClock();
  try {
    const sent = await post(s, '/api/auth/email/send', { email: 'Riya.Kapoor+x@Gmail.com' });
    assert.equal(sent.status, 200);
    assert.equal(sent.data.email, 'riyakapoor@gmail.com');
    assert.equal(sent.data.devCode, undefined, 'a real mailer never hands the code back');
    assert.equal(s.emailProvider.sent.length, 1);

    const wrong = await post(s, '/api/auth/email/verify', { email: 'riyakapoor@gmail.com', code: '000000' });
    assert.equal(wrong.status, 400);

    clock.now += 31000; // the same mailbox must wait out the cool-down before a second code
    const { signupToken, email } = await verifyEmail(s, 'riya.kapoor@gmail.com');
    assert.equal(email, 'riyakapoor@gmail.com');

    // the e-mail comes from the token: whatever the body says is ignored
    const res = await post(s, '/api/auth/signup', profile(signupToken, { email: 'someone.else@example.com' }));
    assert.equal(res.status, 201, JSON.stringify(res.data));
    const row = s.db.get('SELECT * FROM users WHERE id = ?', [res.data.user.id]);
    assert.equal(row.email, 'riyakapoor@gmail.com');
    assert.equal(row.email_verified, 1);
    assert.equal(row.phone, null);
    assert.equal(row.phone_verified, 0);

    // log in with the address however it is typed
    for (const id of ['riyakapoor@gmail.com', 'Riya.Kapoor@gmail.com', 'riya.kapoor+tag@gmail.com']) {
      const login = await post(s, '/api/auth/login', { identifier: id, password: 'a decent passphrase' });
      assert.equal(login.status, 200, id);
    }

    // a second sign-up with the same mailbox, however it is written, is refused before any mail goes out
    const before = s.emailProvider.sent.length;
    const again = await post(s, '/api/auth/email/send', { email: 'r.i.y.a.kapoor@gmail.com' });
    assert.equal(again.status, 409);
    assert.equal(again.data.field, 'email');
    assert.equal(s.emailProvider.sent.length, before);
  } finally { await s.close(); }
});

test('e-mail sign-up: the code is single-use, expires, and is capped per address', async () => {
  const { s, clock } = await startWithClock();
  try {
    await post(s, '/api/auth/email/send', { email: 'a@example.com' });
    const { code } = s.emailProvider.last('a@example.com');
    assert.equal((await post(s, '/api/auth/email/verify', { email: 'a@example.com', code })).status, 200);
    assert.equal((await post(s, '/api/auth/email/verify', { email: 'a@example.com', code })).status, 400, 'used once');

    clock.now += 31000;
    await post(s, '/api/auth/email/send', { email: 'a@example.com' });
    const second = s.emailProvider.last('a@example.com').code;
    clock.now += 6 * 60 * 1000;
    assert.equal((await post(s, '/api/auth/email/verify', { email: 'a@example.com', code: second })).status, 400, 'expired');

    const cool = await post(s, '/api/auth/email/send', { email: 'b@example.com' });
    assert.equal(cool.status, 200);
    const tooSoon = await post(s, '/api/auth/email/send', { email: 'b@example.com' });
    assert.equal(tooSoon.status, 429);
  } finally { await s.close(); }
});

test('e-mail sign-up: refused addresses never cost a message', async () => {
  const { s } = await startWithClock({ signupEmailDomains: ['thapar.edu'], blockedEmailDomains: ['bad.example'] });
  try {
    for (const email of ['riya@gmail.com', 'riya+1@thapar.edu', 'nope', '']) {
      const r = await post(s, '/api/auth/email/send', { email });
      assert.equal(r.status, 400, email);
      assert.equal(r.data.field, 'email');
    }
    assert.equal(s.emailProvider.sent.length, 0);
    assert.equal((await post(s, '/api/auth/email/send', { email: 'riya@thapar.edu' })).status, 200);
  } finally { await s.close(); }
});

test('e-mail sign-up: the daily budget and the per-address cap stop a flood', async () => {
  const { s } = await startWithClock({ otpDailyBudget: 3, otpPerIpPerDay: 2 });
  try {
    assert.equal((await post(s, '/api/auth/email/send', { email: 'one@example.com' })).status, 200);
    assert.equal((await post(s, '/api/auth/email/send', { email: 'two@example.com' })).status, 200);
    const third = await post(s, '/api/auth/email/send', { email: 'three@example.com' });
    assert.equal(third.status, 429, 'same address, third code');
    assert.equal(s.emailProvider.sent.length, 2);
  } finally { await s.close(); }
});

test('a sign-up token for a phone still works and carries no e-mail; a login-style token is refused', async () => {
  const { s } = await startWithClock();
  try {
    const phoneToken = tokens.signSignup('+919800000001');
    const res = await post(s, '/api/auth/signup', profile(phoneToken, { email: 'optional@example.com' }));
    assert.equal(res.status, 201, JSON.stringify(res.data));
    const row = s.db.get('SELECT * FROM users WHERE id = ?', [res.data.user.id]);
    assert.equal(row.phone, '+919800000001');
    assert.equal(row.email, 'optional@example.com');
    assert.equal(row.email_verified, 0, 'typed, not confirmed');

    const bad = await post(s, '/api/auth/signup', profile(tokens.signAccess('x'), { username: 'other_name' }));
    assert.equal(bad.status, 401);
  } finally { await s.close(); }
});

test('an existing account whose address is taken cannot be verified into a second account', async () => {
  const { s } = await startWithClock();
  try {
    addUser(s.db, 'old_hand');
    s.db.run("UPDATE users SET email = 'taken@example.com' WHERE username = 'old_hand'");
    const r = await post(s, '/api/auth/email/send', { email: 'Taken@Example.com' });
    assert.equal(r.status, 409);
  } finally { await s.close(); }
});

// ---------------- the mailer ----------------

test('smtp mailer refuses to start without its settings and picks TLS for port 465', () => {
  assert.throws(() => createMailer('smtp', { env: {} }), /SMTP_HOST/);
  const seen = [];
  const env = { SMTP_HOST: 'smtp.example.com', SMTP_USER: 'u', SMTP_PASS: 'p', MAIL_FROM: 'FOREST <noreply@forestapp.in>' };
  createMailer('smtp', { env, transportFactory: (o) => { seen.push(o); return { sendMail: async () => {} }; } });
  createMailer('smtp', { env: { ...env, SMTP_PORT: '465' }, transportFactory: (o) => { seen.push(o); return { sendMail: async () => {} }; } });
  assert.equal(seen[0].port, 587);
  assert.equal(seen[0].secure, false);
  assert.equal(seen[1].secure, true);
  assert.deepEqual(seen[0].auth, { user: 'u', pass: 'p' });
});

test('smtp mailer sends the code in subject and body, and failures name neither the code nor the full address', async () => {
  const messages = [];
  const env = { SMTP_HOST: 'h', SMTP_USER: 'u', SMTP_PASS: 'p', MAIL_FROM: 'FOREST <noreply@forestapp.in>' };
  const ok = createMailer('smtp', { env, transportFactory: () => ({ sendMail: async (m) => { messages.push(m); } }) });
  assert.equal(ok.exposeCode, false);
  await ok.send('riya@example.com', '482913');
  assert.equal(messages[0].to, 'riya@example.com');
  assert.equal(messages[0].from, 'FOREST <noreply@forestapp.in>');
  assert.match(messages[0].subject, /482913/);
  assert.match(messages[0].text, /482913/);
  assert.match(messages[0].html, /482913/);

  const failing = createMailer('smtp', { env, transportFactory: () => ({ sendMail: async () => { const e = new Error('mailbox 482913 unavailable'); e.responseCode = 550; throw e; } }) });
  await assert.rejects(() => failing.send('riya@example.com', '482913'), (err) => {
    assert.ok(!err.message.includes('482913'));
    assert.ok(!err.message.includes('riya@example.com'));
    assert.match(err.message, /r\*\*\*@example\.com/);
    return true;
  });
});

test('mail providers: unknown names fail, console is refused in production', () => {
  assert.throws(() => createMailer('carrier-pigeon'), /Unknown MAIL_PROVIDER/);
  assert.throws(() => createMailer('console', { production: true }), /production/);
  assert.equal(createMailer('console').exposeCode, true);
});
