// One-time codes for verifying a phone number or an e-mail address (the key is whichever was given).
// - 6 digits from a CSPRNG, stored only as an HMAC (a stolen database doesn't reveal live codes)
// - expire after 5 minutes, die after 5 wrong guesses, one per 30 s, 5 per phone per day
// - the clock is injectable so tests can fast-forward

const crypto = require('crypto');
const { HttpError } = require('../http');

function createOtpService({
  db, provider, secret, clock = Date.now,
  ttlMs = 5 * 60 * 1000, cooldownMs = 30 * 1000, maxAttempts = 5, maxPerDay = 5
}) {
  const hash = (phone, code) => crypto.createHmac('sha256', secret).update(`${phone}:${code}`).digest('hex');
  const day = (t) => new Date(t).toISOString().slice(0, 10);

  async function send(phone) {
    const now = clock();
    const row = db.get('SELECT * FROM otp_codes WHERE phone = ?', [phone]);
    if (row && now - row.last_sent_at < cooldownMs) {
      const retryAfterSec = Math.ceil((cooldownMs - (now - row.last_sent_at)) / 1000);
      throw new HttpError(429, `Wait ${retryAfterSec} seconds before asking for another code`, { retryAfterSec });
    }
    const sentToday = row && row.day === day(now) ? row.day_count : 0;
    if (sentToday >= maxPerDay) {
      throw new HttpError(429, 'Too many codes requested for this number or address today. Try again tomorrow');
    }

    const code = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
    try {
      await provider.send(phone, code);
    } catch (err) {
      console.error('[otp] provider failed:', err.message);
      throw new HttpError(502, 'We could not send the code. Try again in a moment'); // nothing stored, no cooldown spent
    }
    db.run(
      `INSERT INTO otp_codes (phone, code_hash, expires_at, attempts, last_sent_at, day, day_count)
       VALUES (?, ?, ?, 0, ?, ?, ?)
       ON CONFLICT(phone) DO UPDATE SET code_hash = excluded.code_hash, expires_at = excluded.expires_at,
         attempts = 0, last_sent_at = excluded.last_sent_at, day = excluded.day, day_count = excluded.day_count`,
      [phone, hash(phone, code), now + ttlMs, now, day(now), sentToday + 1]
    );
    return { resendInSec: Math.ceil(cooldownMs / 1000), devCode: provider.exposeCode ? code : undefined };
  }

  /** Throws unless [code] is the live code for [phone]. A correct code can be used once. */
  function verify(phone, code) {
    const now = clock();
    const row = db.get('SELECT * FROM otp_codes WHERE phone = ?', [phone]);
    if (!row || now > row.expires_at) throw new HttpError(400, 'That code has expired. Ask for a new one');
    if (row.attempts >= maxAttempts) throw new HttpError(429, 'Too many wrong tries. Ask for a new code');

    const given = Buffer.from(hash(phone, String(code || '').trim()), 'hex');
    const expected = Buffer.from(row.code_hash, 'hex');
    if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) {
      db.run('UPDATE otp_codes SET attempts = attempts + 1 WHERE phone = ?', [phone]);
      const left = maxAttempts - row.attempts - 1;
      throw new HttpError(400, left > 0 ? `That code is wrong. ${left} ${left === 1 ? 'try' : 'tries'} left` : 'Too many wrong tries. Ask for a new code');
    }
    db.run('DELETE FROM otp_codes WHERE phone = ?', [phone]);
  }

  return { send, verify };
}

module.exports = { createOtpService };
