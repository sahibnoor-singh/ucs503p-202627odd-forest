#!/usr/bin/env node
// Checks the server's settings BEFORE it is started on a machine other people can reach.
//
//   npm run preflight                    # reads .env (and the real environment), prints what is wrong, exits 1 on a blocking problem
//   npm run preflight -- --env-file /etc/forest/api.env
//
// Two kinds of finding:
//   ERROR    the server would refuse to start, or would be unsafe or unusable for real people (a weak secret, dev mode, no way to send
//            sign-up codes, a plain-http address). Fix these before the first start.
//   WARNING  something works but you probably want it set (the AI key, the review token, the privacy contacts).
//
// `checkConfig(env, options)` is a pure function so it can be tested without touching the machine (test/preflight.test.js).

const fs = require('fs');
const path = require('path');

const MIN_SECRET = 32;

/** Weak or placeholder values people paste from an example file. */
const PLACEHOLDER = /^(changeme|change-me|secret|password|a-long-random-string|test|dev|example|xxx+)$/i;

function isWeak(value, min) {
  return !value || value.length < min || PLACEHOLDER.test(value) || /^(.)\1+$/.test(value);
}

/**
 * @param {Record<string, string|undefined>} env
 * @param {object} [o]
 * @param {(p: string) => boolean} [o.writable]   can this folder be written (and does it exist or can it be made)?
 * @param {(p: string) => number|null} [o.freeGb] free disk space for a path, or null when unknown
 * @param {boolean} [o.ffmpegFound]               the bundled ffmpeg is there
 * @returns {{ errors: string[], warnings: string[], ok: string[] }}
 */
function checkConfig(env, { writable = () => true, freeGb = () => null, ffmpegFound = true } = {}) {
  const errors = [];
  const warnings = [];
  const ok = [];
  const need = (cond, good, bad) => (cond ? ok.push(good) : errors.push(bad));
  const want = (cond, good, bad) => (cond ? ok.push(good) : warnings.push(bad));

  need(env.NODE_ENV === 'production', 'NODE_ENV=production', 'NODE_ENV must be "production" on a server people can reach (otherwise the dev-user shortcut and console e-mail codes are possible).');
  need(env.ALLOW_DEV_USER !== '1', 'dev-user shortcut is not requested', 'ALLOW_DEV_USER=1 must not be set on a real server (anyone could pretend to be anyone). It is ignored in production, but remove it.');
  need(!isWeak(env.JWT_SECRET, MIN_SECRET), 'JWT_SECRET is long and not a placeholder', `JWT_SECRET must be a random string of at least ${MIN_SECRET} characters (not a placeholder). Make one with: node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`);
  need(!isWeak(env.MODERATION_TOKEN, 16), 'MODERATION_TOKEN is set', 'MODERATION_TOKEN must be set to a random string of at least 16 characters: it guards the review page (/admin) and the founders\' numbers (/admin/insights).');

  // Sign-up codes
  const channel = env.SIGNUP_CHANNEL === 'phone' ? 'phone' : 'email';
  if (channel === 'email') {
    const provider = env.MAIL_PROVIDER || 'console';
    need(provider === 'smtp', 'MAIL_PROVIDER=smtp', `MAIL_PROVIDER is "${provider}": production needs "smtp" (the server refuses to print codes in a log). Use Brevo, Resend or Amazon SES SMTP.`);
    if (provider === 'smtp') {
      const missing = ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASS', 'MAIL_FROM'].filter((k) => !env[k]);
      need(!missing.length, 'SMTP login and sender are set', `MAIL_PROVIDER=smtp but these are empty: ${missing.join(', ')}.`);
    }
  } else {
    errors.push('SIGNUP_CHANNEL=phone needs a registered SMS sender that this project has never run live. Use the e-mail channel for the pilot.');
  }

  // Addresses and proxy
  const base = env.PUBLIC_BASE_URL || '';
  need(/^https:\/\/[^/\s]+/.test(base), 'PUBLIC_BASE_URL is an https address', 'PUBLIC_BASE_URL must be the https address people reach the server on, e.g. https://api.forestapp.in (shared links and invite links are built from it).');
  need(!!env.TRUST_PROXY, 'TRUST_PROXY is set', 'TRUST_PROXY must be set (1 behind Caddy or nginx), otherwise every request looks like it comes from the proxy and the per-person limits and the sign-up code budget break.');
  if (env.CORS_ORIGINS === '*') errors.push('CORS_ORIGINS=* lets any web page call the API. The phone app does not need CORS: leave it empty.');

  // Things on disk
  const dbFile = env.DB_FILE || 'data/forest-app.db';
  const uploads = env.UPLOADS_DIR || 'uploads';
  need(writable(path.dirname(dbFile)), 'the database folder is writable', `The folder for the database (${path.dirname(dbFile)}) cannot be written. Mount a volume there.`);
  need(writable(uploads), 'the uploads folder is writable', `The uploads folder (${uploads}) cannot be written. Mount a volume there.`);
  need(ffmpegFound, 'ffmpeg is present', 'The bundled ffmpeg is missing (run npm install again, or set FFMPEG_PATH). Without it no video can be processed.');
  const free = freeGb(uploads);
  if (free !== null) want(free >= 5, `${free.toFixed(0)} GB free for videos`, `Only ${free.toFixed(1)} GB free where videos are stored. A 60-second phone video can be 20 MB or more.`);

  // Worth setting
  want(!!(env.GEMINI_API_KEY || env.GEMINI_API_KEYS), 'a Gemini key is set', 'No GEMINI_API_KEY: videos are stored but get no transcript, no FOR/AGAINST label and no fact-check.');
  want(!!env.MODERATION_BLOCKLIST, 'a word list for automatic holds is set', 'MODERATION_BLOCKLIST is empty: no post is held for review automatically (reports still work).');
  want(!!(env.GRIEVANCE_OFFICER_NAME && env.GRIEVANCE_OFFICER_EMAIL), 'the complaints contact is set', 'GRIEVANCE_OFFICER_NAME / _EMAIL are empty: /api/legal/contact answers "not set yet".');
  want(!!env.GOOGLE_CLIENT_IDS, 'Google sign-in is switched on', 'GOOGLE_CLIENT_IDS is empty: the "Continue with Google" button stays hidden (e-mail sign-up still works).');
  want(!(env.WEBSITE_SYNC_URL && !env.WEBSITE_SYNC_TOKEN), 'website sync is consistent', 'WEBSITE_SYNC_URL is set without WEBSITE_SYNC_TOKEN: the sync stays off.');
  const budget = Number(env.OTP_DAILY_BUDGET);
  want(env.OTP_DAILY_BUDGET === undefined || (budget > 0 && budget <= 5000), 'the sign-up code budget is sane', 'OTP_DAILY_BUDGET should be just under your mail service\'s daily allowance (a free plan is about 300 a day).');

  return { errors, warnings, ok };
}

function realWritable(dir) {
  try {
    fs.mkdirSync(dir, { recursive: true });
    fs.accessSync(dir, fs.constants.W_OK);
    return true;
  } catch {
    return false;
  }
}

function realFreeGb(dir) {
  try {
    fs.mkdirSync(dir, { recursive: true });
    const s = fs.statfsSync(dir);
    return (s.bavail * s.bsize) / 1024 ** 3;
  } catch {
    return null;
  }
}

function ffmpegPresent(env) {
  if (env.FFMPEG_PATH) return fs.existsSync(env.FFMPEG_PATH);
  try {
    const p = require('ffmpeg-static');
    return !!p && fs.existsSync(p);
  } catch {
    return false;
  }
}

function main() {
  const argv = process.argv.slice(2);
  const i = argv.indexOf('--env-file');
  require('dotenv').config(i >= 0 ? { path: argv[i + 1] } : undefined);
  process.chdir(path.join(__dirname, '..'));
  const r = checkConfig(process.env, { writable: realWritable, freeGb: realFreeGb, ffmpegFound: ffmpegPresent(process.env) });
  for (const line of r.ok) console.log(`  ok       ${line}`);
  for (const line of r.warnings) console.log(`  WARNING  ${line}`);
  for (const line of r.errors) console.log(`  ERROR    ${line}`);
  console.log(`\n${r.errors.length} blocking, ${r.warnings.length} to consider, ${r.ok.length} fine.`);
  process.exit(r.errors.length ? 1 : 0);
}

if (require.main === module) main();

module.exports = { checkConfig };
