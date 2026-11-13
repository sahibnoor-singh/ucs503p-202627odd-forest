// Who is calling.
//   Authorization: Bearer <access token>   the real thing (sign up / log in at /api/auth/*)
//   X-Dev-User: <username>                 TEMPORARY, only when ALLOW_DEV_USER is on (never in production) AND the
//                                          request comes straight from this machine (see isLocalRequest). Anyone
//                                          could otherwise act as any user on a server started without NODE_ENV=production.
//                                          Remove once the app signs in with tokens.
// A bad or expired token is a 401. It is never quietly replaced by the dev header.

const { getUser, getUserByName } = require('../queries');

/**
 * True only for a connection from this same machine (the emulator, or a phone over `adb reverse`, both arrive
 * as loopback), and never when a proxy forwarded it. The raw socket address is used, not req.ip, because
 * req.ip can be rewritten by X-Forwarded-For.
 */
function isLocalRequest(req) {
  if (req.get('x-forwarded-for') || req.get('forwarded') || req.get('x-real-ip')) return false;
  const addr = req.socket && req.socket.remoteAddress;
  return addr === '127.0.0.1' || addr === '::1' || addr === '::ffff:127.0.0.1';
}

const SUSPENDED_MESSAGE = 'Your account is suspended. You can contact us from the Terms and Privacy page to appeal.';

function authenticate(db, { enabledDevUser, tokens }) {
  return (req, res, next) => {
    const header = req.get('authorization');
    if (header) {
      const m = /^Bearer (.+)$/i.exec(header);
      if (!m || !tokens) return res.status(401).json({ error: 'Invalid or expired token' });
      let payload;
      try {
        payload = tokens.verifyAccess(m[1]);
      } catch {
        return res.status(401).json({ error: 'Invalid or expired token' });
      }
      const user = getUser(db, payload.sub);
      // A deleted account's tokens keep verifying until they expire, so the account itself is checked too.
      if (!user || user.deleted_at) return res.status(401).json({ error: 'Invalid or expired token' });
      if (user.suspended_at) return res.status(403).json({ error: SUSPENDED_MESSAGE }); // 403, not 401: the app must not read it as "login expired"
      req.user = user;
      return next();
    }
    const name = req.get('x-dev-user');
    if (enabledDevUser && name) {
      if (!isLocalRequest(req)) return res.status(401).json({ error: 'The dev-user header only works from the same machine' });
      const user = getUserByName(db, name.trim());
      if (user && user.suspended_at) return res.status(403).json({ error: SUSPENDED_MESSAGE });
      if (!user || user.deleted_at) return res.status(401).json({ error: `Unknown dev user "${name}"` });
      req.user = user;
    }
    next();
  };
}

function requireUser(req, res, next) {
  if (!req.user) return res.status(401).json({ error: 'Sign in required' });
  next();
}

module.exports = { authenticate, requireUser, isLocalRequest, SUSPENDED_MESSAGE };
