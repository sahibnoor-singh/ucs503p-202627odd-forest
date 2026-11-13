require('dotenv').config();
const fs = require('fs');
const crypto = require('crypto');
const path = require('path');
const { createProvider } = require('./auth/providers');
const { createMailer } = require('./auth/mailers');
const { openDb } = require('./db');
const { createApp } = require('./app');
const { createWebsiteSync } = require('./websiteSync');

const ROOT = path.join(__dirname, '..');

async function main() {
  const dbFile = path.resolve(ROOT, process.env.DB_FILE || 'data/forest-app.db');
  const uploadsDir = path.resolve(ROOT, process.env.UPLOADS_DIR || 'uploads');
  const allowDevUser = process.env.NODE_ENV !== 'production' && process.env.ALLOW_DEV_USER !== '0';

  // Coalesce writes (default 250 ms). 0 = write after every change.
  const saveDelayMs = process.env.DB_SAVE_DELAY_MS === undefined ? 250 : Number(process.env.DB_SAVE_DELAY_MS);
  const db = await openDb({ file: dbFile, saveDelayMs });
  const production = process.env.NODE_ENV === 'production';

  // Login tokens are signed with this. Production must supply a long random one; in development one is created
  // once and kept next to the database, so tokens survive restarts.
  let jwtSecret = process.env.JWT_SECRET;
  if (production && (!jwtSecret || jwtSecret.length < 32)) {
    throw new Error('Set JWT_SECRET to a random string of at least 32 characters when NODE_ENV=production');
  }
  if (!jwtSecret) {
    const secretFile = path.join(path.dirname(dbFile), '.jwt-secret');
    if (!fs.existsSync(secretFile)) {
      fs.mkdirSync(path.dirname(secretFile), { recursive: true });
      fs.writeFileSync(secretFile, crypto.randomBytes(32).toString('hex'), { mode: 0o600 });
    }
    jwtSecret = fs.readFileSync(secretFile, 'utf8').trim();
  }
  // People are verified by an e-mailed code (free) or, if SIGNUP_CHANNEL=phone, by SMS (costs money, needs DLT registration in India).
  // Only the chosen channel is switched on; its endpoints answer 404 otherwise.
  const signupChannel = process.env.SIGNUP_CHANNEL === 'phone' ? 'phone' : 'email';
  const otpProvider = signupChannel === 'phone' ? createProvider(process.env.OTP_PROVIDER || 'console', { production }) : null;
  const emailProvider = signupChannel === 'email' ? createMailer(process.env.MAIL_PROVIDER || 'console', { production }) : null;
  const splitList = (v) => (v || '').split(',').map((d) => d.trim()).filter(Boolean);
  // CORS only matters for web pages. The mobile app doesn't need it, so production allows only what is listed.
  const corsOrigins = production
    ? (process.env.CORS_ORIGINS ? process.env.CORS_ORIGINS.split(',').map((o) => o.trim()) : false)
    : '*';
  const app = createApp({
    db, uploadsDir, allowDevUser, jwtSecret, otpProvider, emailProvider, signupChannel,
    googleClientIds: splitList(process.env.GOOGLE_CLIENT_IDS),
    publicBaseUrl: process.env.PUBLIC_BASE_URL || null,
    playStoreUrl: process.env.PLAY_STORE_URL || null,
    promptOffsetMin: process.env.PROMPT_UTC_OFFSET_MIN === undefined ? 330 : Number(process.env.PROMPT_UTC_OFFSET_MIN),
    signupEmailDomains: splitList(process.env.SIGNUP_EMAIL_DOMAINS),
    blockedEmailDomains: splitList(process.env.SIGNUP_BLOCKED_EMAIL_DOMAINS),
    minAge: Number(process.env.MIN_AGE) || 18,
    defaultCountryCode: process.env.DEFAULT_COUNTRY_CODE || '+91',
    allowLegacyUpload: process.env.ALLOW_LEGACY_UPLOAD === undefined ? allowDevUser : process.env.ALLOW_LEGACY_UPLOAD === '1',
    rateLimit: process.env.RATE_LIMIT !== '0',
    accessLog: production ? process.env.ACCESS_LOG !== '0' : process.env.ACCESS_LOG === '1',
    corsOrigins,
    trustProxy: process.env.TRUST_PROXY ? (Number.isNaN(Number(process.env.TRUST_PROXY)) ? process.env.TRUST_PROXY : Number(process.env.TRUST_PROXY)) : false,
    jobTimeoutMs: Number(process.env.JOB_TIMEOUT_MS) || 180000,
    moderationToken: process.env.MODERATION_TOKEN || null,
    moderationBlocklist: (process.env.MODERATION_BLOCKLIST || '').split(','),
    grievanceOfficer: { name: process.env.GRIEVANCE_OFFICER_NAME || null, email: process.env.GRIEVANCE_OFFICER_EMAIL || null },
    otpDailyBudget: Number(process.env.OTP_DAILY_BUDGET) || (signupChannel === 'email' ? 250 : 500),
    otpPerIpPerDay: Number(process.env.OTP_PER_IP_PER_DAY) || 20
  });
  app.locals.jobs.resumePending();

  // Optional one-way copy of anonymous numbers + the debate graph to the project website (see src/websiteSync.js).
  if (process.env.WEBSITE_SYNC_URL && process.env.WEBSITE_SYNC_TOKEN) {
    const sync = createWebsiteSync({
      db,
      url: process.env.WEBSITE_SYNC_URL,
      token: process.env.WEBSITE_SYNC_TOKEN,
      includeTitles: process.env.WEBSITE_SYNC_TITLES === '1',
      intervalMs: (Number(process.env.WEBSITE_SYNC_SECONDS) || 60) * 1000
    });
    sync.start();
    console.log(`  website sync: ON -> ${process.env.WEBSITE_SYNC_URL}`);
  }

  const port = Number(process.env.PORT) || 3000;
  const server = app.listen(port, '0.0.0.0', () => {
    console.log(`FOREST app API on http://localhost:${port}`);
    console.log(`  database: ${dbFile}`);
    console.log(`  uploads:  ${uploadsDir}`);
    console.log(`  dev user header (TEMP): ${allowDevUser ? 'ON (loopback only)' : 'off'}`);
    if (allowDevUser) console.warn('  WARNING: development mode. Set NODE_ENV=production on any server other people can reach.');
    const codes = otpProvider || emailProvider;
    console.log(`  sign-up codes: by ${signupChannel}, ${codes.name}${codes.exposeCode ? ' (printed in this log, development only)' : ''}`);
    console.log(`  moderation page: ${process.env.MODERATION_TOKEN ? 'ON at /admin' : 'off (set MODERATION_TOKEN)'}; grievance officer: ${process.env.GRIEVANCE_OFFICER_NAME ? 'set' : 'NOT SET yet'}`);
    console.log(`  rate limiting: ${process.env.RATE_LIMIT !== '0' ? 'on' : 'OFF'}`);
  });

  const shutdown = () => {
    db.flush();
    server.close(() => process.exit(0));
    // Idle keep-alive connections would otherwise hold the server open and stall a restart.
    if (server.closeIdleConnections) server.closeIdleConnections();
    setTimeout(() => process.exit(0), 5000).unref(); // never hang on a stuck request
  };
  process.on('exit', () => { try { db.flush(); } catch (err) { console.error('[db] final save failed:', err.message); } });
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
