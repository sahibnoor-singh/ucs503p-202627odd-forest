const { test } = require('node:test');
const assert = require('node:assert/strict');
const { checkConfig } = require('../scripts/preflight');

/** A complete, good production setting. Each test spoils one thing. */
const GOOD = {
  NODE_ENV: 'production',
  JWT_SECRET: 'f3a9c1d27b6e48a0953c71ed2b84f60a1c5d9e3b7a2f4c8d6e1b0a39572c4d8e',
  MODERATION_TOKEN: 'a2c4e6f8a1b3c5d7e9f0',
  MAIL_PROVIDER: 'smtp',
  SMTP_HOST: 'smtp-relay.brevo.com',
  SMTP_USER: 'user',
  SMTP_PASS: 'pass',
  MAIL_FROM: 'FOREST <noreply@forestapp.in>',
  PUBLIC_BASE_URL: 'https://api.forestapp.in',
  TRUST_PROXY: '1',
  GEMINI_API_KEY: 'k',
  MODERATION_BLOCKLIST: 'word',
  GRIEVANCE_OFFICER_NAME: 'A Person',
  GRIEVANCE_OFFICER_EMAIL: 'p@example.com',
  GOOGLE_CLIENT_IDS: 'id.apps.googleusercontent.com'
};

const run = (env, opts) => checkConfig({ ...GOOD, ...env }, opts);
const text = (r) => [...r.errors, ...r.warnings].join('\n');

test('a complete production setting has nothing to fix', () => {
  const r = run({});
  assert.deepEqual(r.errors, []);
  assert.deepEqual(r.warnings, []);
  assert.ok(r.ok.length >= 8);
});

test('development mode, the dev-user shortcut and weak secrets are blocking', () => {
  assert.match(text(run({ NODE_ENV: 'development' })), /NODE_ENV must be "production"/);
  assert.match(text(run({ ALLOW_DEV_USER: '1' })), /ALLOW_DEV_USER/);
  for (const bad of [undefined, 'short', 'changeme', 'a'.repeat(40), 'a-long-random-string']) {
    assert.match(text(run({ JWT_SECRET: bad })), /JWT_SECRET/, String(bad));
  }
  for (const bad of [undefined, 'short', 'a-long-random-string']) {
    assert.match(text(run({ MODERATION_TOKEN: bad })), /MODERATION_TOKEN/, String(bad));
  }
});

test('sign-up codes need real e-mail: console is refused, smtp needs its login, phone is not for the pilot', () => {
  assert.match(text(run({ MAIL_PROVIDER: 'console' })), /MAIL_PROVIDER is "console"/);
  assert.match(text(run({ MAIL_PROVIDER: undefined })), /MAIL_PROVIDER is "console"/);
  const r = run({ SMTP_PASS: '', MAIL_FROM: '' });
  assert.match(text(r), /SMTP_PASS, MAIL_FROM/);
  assert.match(text(run({ SIGNUP_CHANNEL: 'phone' })), /SIGNUP_CHANNEL=phone/);
});

test('the public address must be https and the proxy must be declared', () => {
  for (const bad of [undefined, '', 'http://api.forestapp.in', 'api.forestapp.in', 'https://']) {
    assert.match(text(run({ PUBLIC_BASE_URL: bad })), /PUBLIC_BASE_URL/, String(bad));
  }
  assert.match(text(run({ TRUST_PROXY: undefined })), /TRUST_PROXY/);
  assert.match(text(run({ CORS_ORIGINS: '*' })), /CORS_ORIGINS/);
});

test('folders that cannot be written and a missing ffmpeg are blocking; low disk is a warning', () => {
  const noWrite = run({}, { writable: () => false });
  assert.equal(noWrite.errors.length, 2);
  assert.match(text(noWrite), /database/);
  assert.match(text(noWrite), /uploads/);
  assert.match(text(run({}, { ffmpegFound: false })), /ffmpeg/);
  const low = run({}, { freeGb: () => 1.2 });
  assert.deepEqual(low.errors, []);
  assert.match(low.warnings.join(), /1\.2 GB free/);
});

test('what is merely missing is a warning, never blocking', () => {
  const r = run({ GEMINI_API_KEY: undefined, MODERATION_BLOCKLIST: undefined, GRIEVANCE_OFFICER_NAME: undefined, GOOGLE_CLIENT_IDS: undefined });
  assert.deepEqual(r.errors, []);
  assert.equal(r.warnings.length, 4);
  assert.match(r.warnings.join('\n'), /GEMINI_API_KEY/);
  assert.equal(run({ GEMINI_API_KEYS: 'a,b', GEMINI_API_KEY: undefined }).warnings.length, 0, 'a list of keys counts');
});
