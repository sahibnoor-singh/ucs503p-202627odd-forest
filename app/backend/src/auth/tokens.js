// Signed tokens (HS256 JWT). Two kinds, told apart by `typ`, so one can never be used as the other:
//   access  - proves who you are on every request (30 days for now; refresh tokens come later)
//   signup  - proves you verified this phone number or e-mail address; only /auth/signup accepts it (15 minutes)

const jwt = require('jsonwebtoken');

const ACCESS_TTL_SEC = 30 * 24 * 3600;
const SIGNUP_TTL_SEC = 15 * 60;

function createTokens(secret) {
  if (!secret || String(secret).length < 16) throw new Error('A JWT secret of at least 16 characters is required');

  const sign = (payload, ttl) => jwt.sign(payload, secret, { algorithm: 'HS256', expiresIn: ttl });
  const verify = (token, typ) => {
    // `algorithms` is pinned so a token can't pick "none" or a different algorithm.
    const payload = jwt.verify(token, secret, { algorithms: ['HS256'] });
    if (payload.typ !== typ) throw new Error('wrong token type');
    return payload;
  };

  return {
    accessTtlSec: ACCESS_TTL_SEC,
    signAccess: (userId) => sign({ typ: 'access', sub: userId }, ACCESS_TTL_SEC),
    verifyAccess: (token) => verify(token, 'access'),
    // [contact] is { phone } or { email }; a bare string is a phone number.
    signSignup: (contact) => sign({ typ: 'signup', ...(typeof contact === 'string' ? { phone: contact } : contact) }, SIGNUP_TTL_SEC),
    verifySignup: (token) => verify(token, 'signup')
  };
}

module.exports = { createTokens };
