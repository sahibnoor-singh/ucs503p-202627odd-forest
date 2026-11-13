const fs = require('fs');
const express = require('express');
const cors = require('cors');
const multer = require('multer');

const { HttpError } = require('./http');
const { authenticate } = require('./middleware/user');
const { createTokens } = require('./auth/tokens');
const { createOtpService } = require('./auth/otp');
const { createProvider } = require('./auth/providers');
const { createMailer } = require('./auth/mailers');
const { createGoogleVerifier } = require('./auth/google');
const authRoutes = require('./routes/auth');
const { createJobs } = require('./jobs');
const { createLimiters } = require('./middleware/rateLimit');
const { createPostService } = require('./postService');
const homeRoutes = require('./routes/home');
const postRoutes = require('./routes/posts');
const userRoutes = require('./routes/users');
const notificationRoutes = require('./routes/notifications');
const compatRoutes = require('./routes/compat');
const discoverRoutes = require('./routes/discover');
const searchRoutes = require('./routes/search');
const shareRoutes = require('./routes/shares');
const messageRoutes = require('./routes/messages');
const adminRoutes = require('./routes/admin');
const legalRoutes = require('./routes/legal');
const todayRoutes = require('./routes/today');
const roomRoutes = require('./routes/rooms');
const growthRoutes = require('./routes/growth');
const publicRoutes = require('./routes/public');
const { createEvents } = require('./events');
const profileRoutes = require('./routes/profile');
const geminiService = require('./services/geminiService');
const { createModeration } = require('./moderation');
const { createComposer } = require('./compose');

/** Default analyzer = real ffmpeg + Gemini. Tests pass a fake. */
function realAnalyzer() {
  const { extractAudio } = require('./services/audioService');
  const { analyzeAudio, classifyReplyText, describePost, translateCaptions } = require('./services/geminiService');
  const { makeThumbnail } = require('./services/thumbnailService');
  return { extractAudio, analyzeAudio, classifyReplyText, describePost, translateCaptions, makeThumbnail };
}

/**
 * @param {object} o
 * @param {object} o.db            from openDb()
 * @param {string} o.uploadsDir    where media files live (served at /uploads)
 * @param {object} [o.analyzer]    { extractAudio, analyzeAudio, classifyReplyText, describePost?, translateCaptions?, makeThumbnail? }
 * @param {string} o.jwtSecret     signs login tokens and hashes OTP codes (>= 16 chars; use 32+ random bytes in production)
 * @param {object|null} [o.otpProvider] { name, send(phone, code), exposeCode? }; default is the in-memory test provider; null = no sign-up by phone
 * @param {object|null} [o.emailProvider] { name, send(email, code), exposeCode? } (src/auth/mailers.js); default is the in-memory test one; null = no sign-up by e-mail
 * @param {string[]} [o.googleClientIds]  OAuth client ids that may sign people in with Google; the first is given to the app. Empty = Google sign-in off
 * @param {object} [o.googleVerifier]  { verify(idToken) -> { sub, email, emailVerified, name } }; default checks real Google tokens (tests pass a fake)
 * @param {string} [o.publicBaseUrl]  the address people outside the app use (links to debates and invites); default is the address each request came in on
 * @param {string} [o.playStoreUrl]  where the public pages send people to get the app; none shown when unset
 * @param {number} [o.promptOffsetMin]  minutes ahead of UTC that the daily question changes at midnight of (default 330, India)
 * @param {'email'|'phone'} [o.signupChannel]  which one the app should offer (GET /api/auth/config); default email
 * @param {string[]} [o.signupEmailDomains]  when not empty, only these e-mail domains may sign up (e.g. a campus domain)
 * @param {string[]} [o.blockedEmailDomains]  more throw-away domains to refuse on top of the built-in list
 * @param {number} [o.minAge]      youngest allowed age at sign-up (default 18)
 * @param {string} [o.defaultCountryCode]  prefix for bare 10-digit phone numbers (default +91)
 * @param {Function} [o.clock]     () => ms since epoch; tests fast-forward it
 * @param {boolean} [o.allowDevUser]  honour the TEMP X-Dev-User header
 * @param {boolean} [o.allowLegacyUpload]  the unauthenticated POST /api/videos/upload (default: same as allowDevUser)
 * @param {boolean|object} [o.rateLimit]   true = default limits, or {name: {max, windowMs}} overrides; false = off
 * @param {string[]|'*'|false} [o.corsOrigins]  '*' = any site (dev), a list = only those, false = no CORS headers
 * @param {number|string|boolean} [o.trustProxy]  set to 1 behind nginx so rate limits see the real client IP
 * @param {number} [o.jobTimeoutMs]  deadline for each background video-analysis step
 * @param {number} [o.legacyListLimit]  max rows the legacy GET /api/videos/all returns (newest N)
 * @param {number} [o.otpDailyBudget]   most sign-up SMS codes this server will send per day in total (caps the bill if someone floods it)
 * @param {string} [o.moderationToken]  enables /admin and /api/admin (Bearer token); unset = they answer 404
 * @param {string[]} [o.moderationBlocklist]  words that hide a post automatically (empty by default)
 * @param {{name:string,email:string}} [o.grievanceOfficer]  published at GET /api/legal/contact
 * @param {object} [o.composer]   renders editor posts: { probe(file), render(opts) }; default is the real ffmpeg (src/compose)
 * @param {string} [o.composeDir]  private folder for the editor's input files (default: next to uploadsDir, never served)
 * @param {number} [o.otpPerIpPerDay]   most codes one address can ask for per day
 * @param {boolean|Function} [o.accessLog]  one line per request (method, path without its query, status, ms) so a production problem can be traced;
 *   true prints it, a function receives the line. Never logs query strings (they hold what people search for) or bodies.
 */
function createApp({
  db, uploadsDir, jwtSecret, otpProvider = createProvider('memory'), emailProvider = createMailer('memory'),
  googleClientIds = [], googleVerifier = null,
  signupChannel = 'email', signupEmailDomains = [], blockedEmailDomains = [], minAge = 18, defaultCountryCode = '+91',
  clock = Date.now, analyzer = realAnalyzer(), allowDevUser = false, allowLegacyUpload = allowDevUser,
  rateLimit = false, corsOrigins = '*', trustProxy = false, textClassifyTimeoutMs = 8000, jobTimeoutMs = 180000,
  legacyListLimit = 1000, otpDailyBudget = 500, otpPerIpPerDay = 20,
  moderationToken = null, moderationBlocklist = [], grievanceOfficer = null,
  composer = null, composeDir = `${uploadsDir}-compose`, accessLog = false,
  publicBaseUrl = null, playStoreUrl = null, promptOffsetMin = 330,
  gemini = geminiService
}) {
  if (!jwtSecret) throw new Error('createApp needs a jwtSecret');
  fs.mkdirSync(uploadsDir, { recursive: true });
  fs.mkdirSync(composeDir, { recursive: true });
  composer = composer || createComposer();
  const tokens = createTokens(jwtSecret);
  const otp = otpProvider ? createOtpService({ db, provider: otpProvider, secret: jwtSecret, clock }) : null;
  const google = googleVerifier || createGoogleVerifier({ clientIds: googleClientIds });
  const emailOtp = emailProvider ? createOtpService({ db, provider: emailProvider, secret: jwtSecret, clock }) : null;

  const app = express();
  app.disable('x-powered-by');
  if (trustProxy) app.set('trust proxy', trustProxy);

  if (accessLog) {
    const write = typeof accessLog === 'function' ? accessLog : (line) => console.log(line);
    app.use((req, res, next) => {
      const started = process.hrtime.bigint();
      const route = req.originalUrl.split('?')[0]; // read now: routers rewrite req.url while they run
      res.on('finish', () => {
        const ms = Number((process.hrtime.bigint() - started) / 1000000n);
        write(`${new Date().toISOString()} ${req.method} ${route} ${res.statusCode} ${ms}ms${req.user ? ` user=${req.user.id.slice(0, 8)}` : ''}`);
      });
      next();
    });
  }
  app.use((req, res, next) => {
    res.set('X-Content-Type-Options', 'nosniff');
    res.set('Referrer-Policy', 'no-referrer');
    if (req.path.startsWith('/api')) {
      res.set('Cache-Control', 'no-store'); // personal data: never cached by a proxy
      res.set('X-Frame-Options', 'DENY');
    }
    next();
  });
  if (corsOrigins) app.use(cors(corsOrigins === '*' ? {} : { origin: corsOrigins }));
  app.use(express.json());

  // Uploaded media. File names are unique, so they can be cached for good. The CSP sandbox and nosniff mean
  // that even a file that somehow carried HTML could never run script in the browser.
  app.use('/uploads', (req, res, next) => {
    res.set('Content-Security-Policy', "default-src 'none'; sandbox");
    res.set('Cache-Control', 'public, max-age=31536000, immutable');
    next();
  }, express.static(uploadsDir, { dotfiles: 'deny', index: false }));

  const moderation = createModeration({ db, blocklist: moderationBlocklist });
  const jobs = createJobs({ db, analyzer, uploadsDir, jobTimeoutMs, moderation, composer, composeDir });
  const events = createEvents(db, clock);
  const postService = createPostService({ db, jobs, analyzer, textClassifyTimeoutMs, moderation, clock, promptOffsetMin });
  const ctx = { db, google, events, publicBaseUrl, promptOffsetMin, clock, uploadsDir, composeDir, composer, jobs, postService, analyzer, moderation, allowDevUser, allowLegacyUpload, legacyListLimit };

  app.get('/api/health', (req, res) => res.json({ ok: true, service: 'forest-app-api' }));

  // The back office uses its own token, not a user login, so it sits before the user authentication.
  app.use(adminRoutes({ db, moderation, moderationToken, clock, promptOffsetMin }));
  // Pages anyone can open without the app: a shared debate, an invite, the Terms and Privacy notice.
  app.use(publicRoutes({ db, publicBaseUrl, playStoreUrl }));

  app.use(authenticate(db, { enabledDevUser: allowDevUser, tokens }));

  if (rateLimit) {
    const limit = createLimiters(rateLimit);
    app.use('/api', limit.api);
    app.post('/api/posts', limit.post);
    app.post('/api/posts/compose', limit.post);
    app.post('/api/videos/upload', limit.legacyUpload);
    app.post('/api/posts/:id/like', limit.like);
    app.delete('/api/posts/:id/like', limit.like);
    app.post('/api/posts/:id/report', limit.report);
    // Discover (reels) writes; same budgets as their Home equivalents.
    app.put('/api/videos/:id/like', limit.like);
    app.delete('/api/videos/:id/like', limit.like);
    app.put('/api/videos/:id/opinion', limit.like);
    app.post('/api/videos/:id/report', limit.report);
    app.post('/api/videos/:id/views', limit.interact);
    app.post('/api/videos/:id/interactions', limit.interact);
    app.post('/api/videos/interactions', limit.interact);
    app.get('/api/search', limit.search);
    app.post('/api/posts/:id/share', limit.share);
    app.put('/api/messages/:id/reaction', limit.message);
    app.post('/api/complaints', limit.report);
    app.delete('/api/me', limit.login); // checks a password, so it gets the login budget
    app.use('/api/users', limit.social);
    app.get('/api/auth/username-available', limit.usernameCheck);
    app.post('/api/auth/otp/send', limit.otpSend);
    app.post('/api/auth/otp/verify', limit.otpVerify);
    app.post('/api/auth/email/send', limit.otpSend);
    app.post('/api/auth/email/verify', limit.otpVerify);
    app.post('/api/auth/google', limit.otpVerify);
    app.post('/api/rooms', limit.room);
    app.post('/api/rooms/join', limit.room);
    app.post('/api/events', limit.events);
    app.post('/api/auth/signup', limit.signup);
    app.post('/api/auth/login', limit.login);
  }
  app.use('/api/auth', authRoutes({
    db, tokens, events, publicBaseUrl, otp, emailOtp, google, googleClientId: googleClientIds[0] || (googleVerifier ? 'configured' : null), signupChannel, emailRules: { allowedDomains: signupEmailDomains, blockedDomains: blockedEmailDomains },
    clock, minAge, defaultCountryCode, otpDailyBudget, otpPerIpPerDay
  }));
  app.use('/api', todayRoutes(ctx));
  app.use('/api/rooms', roomRoutes(ctx));
  app.use('/api', growthRoutes(ctx));
  app.use('/api/home', homeRoutes(ctx));
  app.use('/api/posts', postRoutes(ctx));
  app.use('/api/videos', compatRoutes(ctx));
  app.use('/api/videos', discoverRoutes(ctx));
  app.use('/api/search', searchRoutes(ctx));
  app.use('/api', shareRoutes(ctx));
  app.use('/api/messages', messageRoutes(ctx));
  app.use('/api', legalRoutes({ db, grievanceOfficer }));
  app.use('/api', profileRoutes({ db, gemini }));
  app.use('/api', notificationRoutes(ctx));
  app.use('/api', userRoutes(ctx));

  app.use((req, res) => res.status(404).json({ error: 'Not found' }));

  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    if (err instanceof HttpError) {
      if (err.extra && err.extra.retryAfterSec) res.set('Retry-After', String(err.extra.retryAfterSec));
      return res.status(err.status).json({ error: err.message, ...err.extra });
    }
    if (err instanceof multer.MulterError) {
      const status = err.code === 'LIMIT_FILE_SIZE' ? 413 : 400;
      return res.status(status).json({ error: status === 413 ? 'File is larger than 50 MB' : err.message });
    }
    if (err.status && err.status < 500) return res.status(err.status).json({ error: err.message }); // e.g. bad JSON
    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  });

  app.locals.db = db;
  app.locals.jobs = jobs;
  return app;
}

module.exports = { createApp };
