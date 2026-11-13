// In-memory fixed-window rate limiter. Per signed-in user, or per IP when anonymous.
// One process, so no shared store is needed yet. Behind nginx set TRUST_PROXY=1 so req.ip is the real client.

const DEFAULTS = {
  api:          { max: 600, windowMs: 60000 }, // everything under /api, per minute
  post:         { max: 15,  windowMs: 60000 }, // new opinions / replies
  like:         { max: 120, windowMs: 60000 },
  report:       { max: 10,  windowMs: 60000 },
  social:       { max: 60,  windowMs: 60000 }, // follow / unfollow / block
  legacyUpload: { max: 10,  windowMs: 60000 },
  interact:     { max: 120, windowMs: 60000 }, // Discover watch-time pings, which write a row each
  message:      { max: 60,  windowMs: 60000 }, // sending messages and reacting
  share:        { max: 30,  windowMs: 60000 }, // sending videos to friends
  room:         { max: 20,  windowMs: 60000 }, // creating and joining motion rooms
  events:       { max: 30,  windowMs: 60000 }, // the app's batches of product events
  search:       { max: 60,  windowMs: 60000 }, // typing in the Discover search box (the app waits between keystrokes)
  usernameCheck: { max: 60, windowMs: 60000 }, // the live "is this name free?" check while typing
  otpSend:      { max: 5,   windowMs: 60000 },
  otpVerify:    { max: 10,  windowMs: 60000 },
  signup:       { max: 10,  windowMs: 60000 },
  login:        { max: 10,  windowMs: 60000 }
};

const MAX_TRACKED = 100000; // hard cap so a flood of distinct IPs can't grow memory without bound

function createRateLimiter(name, { max, windowMs }) {
  const hits = new Map(); // key -> { count, resetAt }
  let lastSweep = Date.now();

  return function rateLimit(req, res, next) {
    const now = Date.now();
    if (now - lastSweep > windowMs || hits.size > MAX_TRACKED) {
      for (const [k, v] of hits) if (v.resetAt <= now) hits.delete(k);
      if (hits.size > MAX_TRACKED) hits.clear();
      lastSweep = now;
    }
    const key = req.user ? `u:${req.user.id}` : `ip:${req.ip}`;
    let entry = hits.get(key);
    if (!entry || entry.resetAt <= now) {
      entry = { count: 0, resetAt: now + windowMs };
      hits.set(key, entry);
    }
    entry.count++;
    if (entry.count > max) {
      const retryAfterSec = Math.max(1, Math.ceil((entry.resetAt - now) / 1000));
      res.set('Retry-After', String(retryAfterSec));
      return res.status(429).json({ error: 'Too many requests. Slow down and try again shortly.', retryAfterSec });
    }
    next();
  };
}

/** @param {boolean|object} option  true = defaults, object = per-limiter overrides {name: {max, windowMs}} */
function createLimiters(option) {
  const overrides = typeof option === 'object' ? option : {};
  const out = {};
  for (const name of Object.keys(DEFAULTS)) {
    out[name] = createRateLimiter(name, { ...DEFAULTS[name], ...(overrides[name] || {}) });
  }
  return out;
}

module.exports = { createLimiters, DEFAULTS };
