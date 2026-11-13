const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const { passwordProblem, hashPassword, verifyPassword } = require('../src/auth/password');
const { normalizePhone } = require('../src/auth/phone');
const { usernameProblem, suggestUsernames } = require('../src/auth/username');
const { checkDob } = require('../src/auth/dob');
const { createTokens } = require('../src/auth/tokens');
const { openDb } = require('../src/db');

const SECRET = 'unit-test-secret-0123456789abcdef';

test('passwords: round trip, salted, wrong one rejected, garbage hashes never match', async () => {
  const a = await hashPassword('correct horse battery');
  const b = await hashPassword('correct horse battery');
  assert.notEqual(a, b, 'every hash gets its own salt');
  assert.match(a, /^scrypt\$16384\$8\$1\$/);
  assert.equal(await verifyPassword('correct horse battery', a), true);
  assert.equal(await verifyPassword('correct horse batterz', a), false);
  assert.equal(await verifyPassword('anything', 'not-a-hash'), false);
  assert.equal(await verifyPassword('anything', null), false);
  assert.equal(await verifyPassword('anything', 'scrypt$1$1$1$AA$AA'), false);
  assert.ok(!a.includes('correct horse'), 'plaintext is not in the hash');
});

test('password rules', () => {
  assert.match(passwordProblem('short'), /at least 8/);
  assert.match(passwordProblem('x'.repeat(129)), /at most 128/);
  assert.match(passwordProblem('Password123'), /too common/);
  assert.match(passwordProblem('aman_singh', { username: 'Aman_Singh' }), /username/);
  assert.match(passwordProblem(undefined), /required/);
  assert.equal(passwordProblem('a decent passphrase'), null);
  assert.equal(passwordProblem('x'.repeat(128)), null);
});

test('phone numbers normalise to E.164, India first', () => {
  assert.equal(normalizePhone('+91 98765-43210'), '+919876543210');
  assert.equal(normalizePhone('9876543210'), '+919876543210');
  assert.equal(normalizePhone('09876543210'), '+919876543210');
  assert.equal(normalizePhone('(+44) 7700 900123'), '+447700900123');
  for (const bad of ['', '12345', '5876543210', '+0123456789', '98765432101234', 'abc', null, 42, '+91987654321012345']) {
    assert.equal(normalizePhone(bad), null, String(bad));
  }
});

test('usernames: format, reserved words and look-alikes of us', async () => {
  for (const ok of ['abc', 'aman_s', 'riya.k', 'a1.b2_c3', 'x'.repeat(30), 'ABC']) assert.equal(usernameProblem(ok), null, ok);
  for (const bad of ['ab', 'x'.repeat(31), 'has space', '.start', 'end.', 'dou..ble', 'emoji😀', 'semi;colon', '', null, ['a'], 'a/b']) {
    assert.equal(usernameProblem(bad), 'INVALID', String(bad));
  }
  for (const r of ['admin', 'Support', 'forest', 'forest_official', 'forestfan', 'administrator2', 'official_news', 'login']) {
    assert.equal(usernameProblem(r), 'RESERVED', r);
  }

  const db = await openDb();
  db.run("INSERT INTO users (id, username, full_name, created_at) VALUES ('1', 'aman', 'a', 'now')");
  const tips = suggestUsernames(db, 'Aman', 3);
  assert.equal(tips.length, 3);
  for (const t of tips) {
    assert.equal(usernameProblem(t), null, `${t} must itself be valid`);
    assert.notEqual(t, 'aman');
    assert.equal(db.get('SELECT 1 AS x FROM users WHERE username = ?', [t]), null, `${t} must be free`);
  }
  db.close();
});

test('age gate is exact on the 18th birthday, handles leap days, and rejects nonsense', () => {
  const today = new Date(Date.UTC(2026, 9, 17)); // 17 Oct 2026
  assert.equal(checkDob('2008-10-17', { today }).age, 18, 'turns 18 today: allowed');
  assert.equal(checkDob('2008-10-18', { today }).tooYoung, true, 'turns 18 tomorrow: not yet');
  assert.equal(checkDob('2008-10-16', { today }).age, 18);
  assert.equal(checkDob('2000-02-29', { today }).age, 26);
  assert.equal(checkDob('2010-02-28', { today }).tooYoung, true);
  assert.equal(checkDob('1990-01-01', { today }).age, 36);
  assert.equal(checkDob('1990-01-01', { today, minAge: 13 }).age, 36);
  assert.equal(checkDob('2012-10-17', { today, minAge: 13 }).age, 14);
  for (const bad of ['2026-10-18', '2030-01-01', '1890-01-01', '2001-02-29', '2001-13-01', '2001-00-10', '01/02/2000', '2000-1-1', '', null, 20000101]) {
    assert.ok(checkDob(bad, { today }).error, `${bad} should be rejected`);
  }
});

test('tokens: a signup token is not a login token, and forged, expired or foreign tokens fail', () => {
  const t = createTokens(SECRET);
  assert.equal(t.verifyAccess(t.signAccess('user-1')).sub, 'user-1');
  assert.equal(t.verifySignup(t.signSignup('+919876543210')).phone, '+919876543210');

  assert.throws(() => t.verifyAccess(t.signSignup('+919876543210')), /wrong token type/);
  assert.throws(() => t.verifySignup(t.signAccess('user-1')), /wrong token type/);

  const other = createTokens('a-completely-different-secret-9999');
  assert.throws(() => t.verifyAccess(other.signAccess('user-1')), /invalid signature/);

  const expired = jwt.sign({ typ: 'access', sub: 'u' }, SECRET, { algorithm: 'HS256', expiresIn: -10 });
  assert.throws(() => t.verifyAccess(expired), /expired/);

  // "alg: none" forgery (a classic): header says unsigned, signature empty
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const unsigned = `${b64({ alg: 'none', typ: 'JWT' })}.${b64({ typ: 'access', sub: 'admin' })}.`;
  assert.throws(() => t.verifyAccess(unsigned));
  // signed with a different algorithm than we allow
  const hs512 = jwt.sign({ typ: 'access', sub: 'u' }, SECRET, { algorithm: 'HS512' });
  assert.throws(() => t.verifyAccess(hs512), /invalid algorithm/);
  assert.throws(() => t.verifyAccess('garbage'));
  assert.throws(() => createTokens('short'), /at least 16/);
});
