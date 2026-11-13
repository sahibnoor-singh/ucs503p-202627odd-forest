const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createProvider, mask } = require('../src/auth/providers');
const { createOtpService } = require('../src/auth/otp');
const { openDb } = require('../src/db');

const env = { MSG91_AUTHKEY: 'KEY123', MSG91_TEMPLATE_ID: 'TPL1' };
const okResponse = (body, status = 200) => ({ ok: status < 400, status, json: async () => body });

test('msg91 refuses to start without its settings', () => {
  assert.throws(() => createProvider('msg91', { env: {} }), /MSG91_AUTHKEY/);
  assert.throws(() => createProvider('msg91', { env: { MSG91_AUTHKEY: 'x' } }), /MSG91_TEMPLATE_ID/);
});

test('msg91 sends the code through the OTP API and never exposes it to the caller', async () => {
  const calls = [];
  const p = createProvider('msg91', { env, fetchImpl: async (url, init) => { calls.push({ url, init }); return okResponse({ type: 'success' }); } });
  assert.equal(p.exposeCode, false);
  await p.send('+919876543210', '482913');
  assert.equal(calls[0].url, 'https://control.msg91.com/api/v5/otp');
  assert.equal(calls[0].init.method, 'POST');
  assert.equal(calls[0].init.headers.authkey, 'KEY123');
  assert.deepEqual(JSON.parse(calls[0].init.body), { template_id: 'TPL1', mobile: '919876543210', otp: '482913' });
});

test('msg91 failures throw an error that names neither the code nor the full number', async () => {
  const bad = [
    okResponse({ type: 'error', message: 'Template not approved' }, 200),
    okResponse({ type: 'error', message: 'Invalid authkey' }, 401),
    { ok: true, status: 200, json: async () => { throw new Error('html'); } }
  ];
  for (const res of bad) {
    const p = createProvider('msg91', { env, fetchImpl: async () => res });
    await assert.rejects(p.send('+919876543210', '482913'), (err) => {
      assert.match(err.message, /msg91 refused/);
      assert.ok(!err.message.includes('482913'));
      assert.ok(!err.message.includes('9876543210'));
      return true;
    });
  }
});

test('a provider outage is a 502 for the app, spends no cool-down, and leaks nothing', async () => {
  const db = await openDb();
  const p = createProvider('msg91', { env, fetchImpl: async () => { throw new Error('socket hang up'); } });
  const otp = createOtpService({ db, provider: p, secret: 'secret-secret-secret' });
  await assert.rejects(otp.send('+919876543210'), (err) => err.status === 502 && !JSON.stringify(err).includes('KEY123'));
  assert.equal(db.get('SELECT COUNT(*) n FROM otp_codes').n, 0); // retry is allowed straight away
  db.close();
});

test('phone numbers are masked for logs', () => {
  assert.equal(mask('+919876543210'), '+91*******210');
  assert.ok(!mask('+919876543210').includes('9876543'));
});

test('unknown provider names and production safety', () => {
  assert.throws(() => createProvider('carrier-pigeon'), /Unknown OTP_PROVIDER/);
  assert.throws(() => createProvider('console', { production: true }), /production/);
});
