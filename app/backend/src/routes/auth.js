// Sign-up and login. Flow for a new person:
//   0. GET  /api/auth/config                        which way this server verifies people: "email" or "phone"
//   1. GET  /api/auth/username-available?u=…        (as they type)
//   2. POST /api/auth/email/send  {email}           a code goes to their inbox      (or /otp/send {phone} for SMS)
//   3. POST /api/auth/email/verify {email, code}    -> signupToken (15 min)         (or /otp/verify {phone, code})
//   or POST /api/auth/google {idToken}              "Continue with Google": an existing account is logged in ({token, user});
//      a new person gets {needsProfile: true, signupToken, email, fullName} and finishes with step 4 (no password needed)
//   4. POST /api/auth/signup      {signupToken, fullName, username, dob, password, email?} -> {token, user}
//      (with an e-mail token the verified address is the account's e-mail; the body's email is ignored)
// Returning users: POST /api/auth/login {identifier, password} where identifier is username, e-mail or phone.

const express = require('express');
const { wrap, HttpError } = require('../http');
const { uuid, toUser } = require('../queries');
const { normalizePhone } = require('../auth/phone');
const { usernameProblem, normalizeUsername, suggestUsernames } = require('../auth/username');
const { checkDob } = require('../auth/dob');
const { passwordProblem, hashPassword, verifyPassword, burnTime } = require('../auth/password');

const { normalizeEmail, emailProblem, EMAIL } = require('../auth/email');
const invites = require('../invites');
const { baseUrl } = require('../publicUrl');
const LOCK_WINDOW_MS = 15 * 60 * 1000;
const MAX_FAILS_PER_ACCOUNT_AND_IP = 8;   // someone guessing at one account from one place
const MAX_FAILS_PER_ACCOUNT = 40;         // ...or spread over many places

module.exports = function authRoutes({
  db, tokens, events = { track() {} }, publicBaseUrl = null, otp, emailOtp, google = null, googleClientId = null, signupChannel = 'email', emailRules = {}, clock, minAge, defaultCountryCode, otpDailyBudget = 500, otpPerIpPerDay = 20
}) {
  const router = express.Router();
  const fails = new Map(); // key -> { count, since }

  function failureCount(key) {
    const e = fails.get(key);
    if (!e) return 0;
    if (clock() - e.since > LOCK_WINDOW_MS) { fails.delete(key); return 0; }
    return e.count;
  }
  function recordFailure(key) {
    if (fails.size > 50000) fails.clear();
    const e = fails.get(key);
    if (!e || clock() - e.since > LOCK_WINDOW_MS) fails.set(key, { count: 1, since: clock() });
    else e.count++;
  }

  // Every code is a paid SMS (or counts against the mail service's free allowance), and the per-number limits don't stop someone asking for codes to thousands of
  // different numbers. So there is also a per-address cap and one overall daily budget (resets at UTC midnight and
  // on restart). When the budget is spent, sign-up pauses for the day instead of the bill growing.
  const otpToday = { day: '', total: 0, byIp: new Map() };
  function countOtpRequest(ip) {
    const day = new Date(clock()).toISOString().slice(0, 10);
    if (otpToday.day !== day) { otpToday.day = day; otpToday.total = 0; otpToday.byIp = new Map(); }
    const fromIp = otpToday.byIp.get(ip) || 0;
    if (fromIp >= otpPerIpPerDay) throw new HttpError(429, 'Too many codes requested from this connection today. Try again tomorrow');
    if (otpToday.total >= otpDailyBudget) throw new HttpError(503, 'Sign-ups are paused for today. Please try again tomorrow');
    return () => { otpToday.total++; otpToday.byIp.set(ip, fromIp + 1); }; // counted only once a code was really sent
  }

  // 200 for "no": while typing, a taken name is an answer, not an error.
  router.get('/username-available', (req, res) => {
    const problem = usernameProblem(req.query.u);
    if (problem) return res.json({ available: false, reason: problem });
    const name = normalizeUsername(req.query.u);
    if (db.get('SELECT 1 AS x FROM users WHERE username = ? COLLATE NOCASE', [name])) {
      return res.json({ available: false, reason: 'TAKEN', suggestions: suggestUsernames(db, name) });
    }
    res.json({ available: true });
  });

  router.get('/config', (req, res) => {
    res.json({ signupChannel, channels: [...(emailOtp ? ['email'] : []), ...(otp ? ['phone'] : [])], googleClientId: google ? googleClientId : null, publicBaseUrl: baseUrl(req, publicBaseUrl) });
  });

  // A channel that is not switched on answers as if the route did not exist.
  const needs = (service, what) => (req, res, next) => (service ? next() : next(new HttpError(404, `Sign-up by ${what} is not enabled`)));

  router.post('/email/send', needs(emailOtp, 'e-mail'), wrap(async (req, res) => {
    const typed = req.body && req.body.email;
    const problem = emailProblem(typed, emailRules);
    if (problem) throw new HttpError(400, problem, { field: 'email' });
    const email = normalizeEmail(typed);
    // Checked before sending so we don't mail someone who should log in instead.
    if (db.get('SELECT 1 AS x FROM users WHERE email = ? COLLATE NOCASE', [email])) {
      throw new HttpError(409, 'An account with this e-mail already exists. Log in instead', { field: 'email' });
    }
    const countIt = countOtpRequest(req.ip);
    const out = await emailOtp.send(email);
    countIt();
    res.json({ sent: true, email, resendInSec: out.resendInSec, ...(out.devCode ? { devCode: out.devCode } : {}) });
  }));

  router.post('/email/verify', needs(emailOtp, 'e-mail'), wrap(async (req, res) => {
    const problem = emailProblem(req.body && req.body.email, emailRules);
    if (problem) throw new HttpError(400, problem, { field: 'email' });
    const email = normalizeEmail(req.body.email);
    emailOtp.verify(email, req.body.code);
    if (db.get('SELECT 1 AS x FROM users WHERE email = ? COLLATE NOCASE', [email])) {
      throw new HttpError(409, 'An account with this e-mail already exists. Log in instead', { field: 'email' });
    }
    res.json({ verified: true, email, signupToken: tokens.signSignup({ email }) });
  }));

  router.post('/google', needs(google, 'Google'), wrap(async (req, res) => {
    let g;
    try {
      g = await google.verify(String((req.body && req.body.idToken) || ''));
    } catch {
      throw new HttpError(401, 'Google sign-in failed. Try again');
    }
    if (!g.emailVerified || !normalizeEmail(g.email)) throw new HttpError(400, 'Your Google account has no verified e-mail address');
    const problem = emailProblem(g.email, emailRules);
    if (problem) throw new HttpError(400, problem, { field: 'email' });
    const email = normalizeEmail(g.email);

    let user = db.get('SELECT * FROM users WHERE google_sub = ?', [g.sub]);
    if (!user) {
      user = db.get('SELECT * FROM users WHERE email = ? COLLATE NOCASE', [email]);
      if (user) {
        // The same address already has an account. Google has proved the person owns it, so link it, but only when that
        // address was verified when the account was made; otherwise someone could have typed it in without owning it.
        if (!user.email_verified || user.google_sub) {
          throw new HttpError(409, 'An account with this e-mail already exists. Log in with your password', { field: 'email' });
        }
        db.run('UPDATE users SET google_sub = ? WHERE id = ?', [g.sub, user.id]);
      }
    }
    if (user) {
      if (user.suspended_at) throw new HttpError(403, 'Your account is suspended. You can contact us from the Terms and Privacy page to appeal.');
      return res.json({ token: tokens.signAccess(user.id), expiresInSec: tokens.accessTtlSec, user: toUser(user) });
    }
    res.json({
      needsProfile: true,
      email,
      fullName: g.name.replace(/\s+/g, ' ').trim().slice(0, 60),
      signupToken: tokens.signSignup({ email, googleSub: g.sub })
    });
  }));

  router.post('/otp/send', needs(otp, 'phone'), wrap(async (req, res) => {
    const phone = normalizePhone(req.body && req.body.phone, defaultCountryCode);
    if (!phone) throw new HttpError(400, 'Enter a valid mobile number', { field: 'phone' });
    // Checked before sending so we don't pay for an SMS to someone who should log in instead.
    if (db.get('SELECT 1 AS x FROM users WHERE phone = ?', [phone])) {
      throw new HttpError(409, 'An account with this number already exists. Log in instead', { field: 'phone' });
    }
    const countIt = countOtpRequest(req.ip);
    const out = await otp.send(phone);
    countIt();
    res.json({ sent: true, phone, resendInSec: out.resendInSec, ...(out.devCode ? { devCode: out.devCode } : {}) });
  }));

  router.post('/otp/verify', needs(otp, 'phone'), wrap(async (req, res) => {
    const phone = normalizePhone(req.body && req.body.phone, defaultCountryCode);
    if (!phone) throw new HttpError(400, 'Enter a valid mobile number', { field: 'phone' });
    otp.verify(phone, req.body.code);
    if (db.get('SELECT 1 AS x FROM users WHERE phone = ?', [phone])) {
      throw new HttpError(409, 'An account with this number already exists. Log in instead', { field: 'phone' });
    }
    res.json({ verified: true, phone, signupToken: tokens.signSignup(phone) });
  }));

  router.post('/signup', wrap(async (req, res) => {
    const b = req.body || {};
    let proof;
    try {
      proof = tokens.verifySignup(String(b.signupToken || ''));
    } catch {
      throw new HttpError(401, 'Your verification has expired. Verify again', { field: 'signupToken' });
    }
    const phone = proof.phone || null;

    const fullName = String(b.fullName || '').replace(/\s+/g, ' ').trim();
    if (!fullName || fullName.length > 60 || /[\u0000-\u001f\u007f]/.test(fullName)) {
      throw new HttpError(400, 'Enter your full name (up to 60 characters)', { field: 'fullName' });
    }

    const problem = usernameProblem(b.username);
    if (problem === 'INVALID') throw new HttpError(400, 'Usernames are 3-30 characters: letters, numbers, . or _', { field: 'username', reason: 'INVALID' });
    if (problem === 'RESERVED') throw new HttpError(400, "That username isn't available", { field: 'username', reason: 'RESERVED' });
    const username = normalizeUsername(b.username);

    let email = null;
    if (proof.email) email = proof.email; // the address that was just confirmed
    else if (b.email !== undefined && b.email !== null && String(b.email).trim() !== '') {
      email = String(b.email).trim().toLowerCase();
      if (email.length > 254 || !EMAIL.test(email)) throw new HttpError(400, 'Enter a valid e-mail address, or leave it blank', { field: 'email' });
    }

    // An invite code that is typed must be a real one, so a typo is not silently ignored.
    let inviter = null;
    if (b.inviteCode !== undefined && b.inviteCode !== null && String(b.inviteCode).trim() !== '') {
      inviter = invites.findInviter(db, b.inviteCode);
      if (!inviter) throw new HttpError(400, 'That invite code is not valid. Check it, or leave it blank', { field: 'inviteCode' });
    }

    const dob = checkDob(b.dob, { minAge, today: new Date(clock()) });
    if (dob.error) throw new HttpError(400, dob.error, { field: 'dob', ...(dob.tooYoung ? { tooYoung: true } : {}) });

    // Someone who came through Google needs no password; if they give one anyway it is checked and kept.
    const wantsPassword = !proof.googleSub || (b.password !== undefined && b.password !== null && b.password !== '');
    let passwordHash = null;
    if (wantsPassword) {
      const pwProblem = passwordProblem(b.password, { username });
      if (pwProblem) throw new HttpError(400, pwProblem, { field: 'password' });
      passwordHash = await hashPassword(b.password);
    }
    const id = uuid();
    try {
      db.run(
        `INSERT INTO users (id, username, full_name, is_bot, phone, phone_verified, email, email_verified, google_sub, dob, password_hash, created_at)
         VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [id, username, fullName, phone, phone ? 1 : 0, email, proof.email ? 1 : 0, proof.googleSub || null, b.dob, passwordHash, new Date(clock()).toISOString()]
      );
    } catch (err) {
      // Two people can race for the same name; the unique index decides, and we say which field clashed.
      const m = /UNIQUE constraint failed: users\.(\w+)/.exec(err.message);
      if (m) {
        const field = { username: 'username', phone: 'phone', email: 'email', google_sub: 'email' }[m[1]] || m[1];
        const label = { username: 'username', phone: 'phone number', email: 'e-mail' }[field] || field;
        throw new HttpError(409, `That ${label} is already in use`, { field, ...(field === 'username' ? { reason: 'TAKEN' } : {}) });
      }
      throw err;
    }
    if (inviter) {
      invites.accept(db, id, inviter, new Date(clock()).toISOString());
      events.track('invite_accepted', inviter.id);
    }
    events.track('signup', id, { method: proof.googleSub ? 'google' : proof.email ? 'email' : 'phone', invited: !!inviter });
    res.status(201).json({
      token: tokens.signAccess(id),
      expiresInSec: tokens.accessTtlSec,
      user: toUser(db.get('SELECT * FROM users WHERE id = ?', [id]))
    });
  }));

  router.post('/login', wrap(async (req, res) => {
    const { identifier, password } = req.body || {};
    if (typeof identifier !== 'string' || typeof password !== 'string' || !identifier.trim() || !password) {
      throw new HttpError(400, 'Enter your username (or e-mail or phone) and password');
    }
    const id = identifier.trim().toLowerCase().slice(0, 100);
    const accountKey = `acct:${id}`;
    const placeKey = `acct+ip:${id}:${req.ip}`;
    if (failureCount(placeKey) >= MAX_FAILS_PER_ACCOUNT_AND_IP || failureCount(accountKey) >= MAX_FAILS_PER_ACCOUNT) {
      const retryAfterSec = Math.ceil(LOCK_WINDOW_MS / 1000);
      throw new HttpError(429, 'Too many failed attempts. Try again in 15 minutes', { retryAfterSec });
    }

    // username first (a username can be all digits), then e-mail, then phone
    let user = null;
    if (id.includes('@')) user = db.get('SELECT * FROM users WHERE email IN (?, ?) COLLATE NOCASE', [normalizeEmail(id) || id, id]);
    else {
      user = db.get('SELECT * FROM users WHERE username = ? COLLATE NOCASE', [id]);
      const phone = !user && normalizePhone(identifier, defaultCountryCode);
      if (phone) user = db.get('SELECT * FROM users WHERE phone = ?', [phone]);
    }

    // Same work and same message whether or not the account exists, so neither time nor words reveal it.
    let ok = false;
    if (user && user.password_hash) ok = await verifyPassword(password, user.password_hash);
    else await burnTime(password);
    if (!ok) {
      recordFailure(accountKey);
      recordFailure(placeKey);
      throw new HttpError(401, 'Wrong username or password');
    }
    if (user.suspended_at) throw new HttpError(403, 'Your account is suspended. You can contact us from the Terms and Privacy page to appeal.');
    fails.delete(placeKey);
    res.json({ token: tokens.signAccess(user.id), expiresInSec: tokens.accessTtlSec, user: toUser(user) });
  }));

  return router;
};
