// Username rules (Instagram-like): 3-30 chars, a-z 0-9 . _ ; can't start/end with "." or contain "..".
// Stored lowercase; uniqueness is case-insensitive.

const crypto = require('crypto');

const RESERVED = new Set([
  'admin', 'administrator', 'root', 'system', 'support', 'help', 'official', 'moderator', 'mod', 'staff', 'team',
  'security', 'contact', 'info', 'about', 'api', 'www', 'mail', 'null', 'undefined', 'me', 'user', 'users',
  'login', 'logout', 'signup', 'register', 'settings', 'explore', 'discover', 'home', 'upload', 'account',
  'terms', 'privacy', 'press', 'legal', 'bot', 'bots'
]);
// Nobody but us may look like us, so anything starting with these is off limits at signup.
// 'deleted' is what a closed account is renamed to (deleted_<id>); letting anyone register such a name could make
// that rename collide with an existing username and break account deletion.
const RESERVED_PREFIXES = ['forest', 'admin', 'official', 'deleted'];

/** @returns null if the format is fine, else 'INVALID' | 'RESERVED' */
function usernameProblem(raw) {
  if (typeof raw !== 'string') return 'INVALID';
  const u = raw.trim().toLowerCase();
  if (!/^[a-z0-9._]{3,30}$/.test(u)) return 'INVALID';
  if (u.startsWith('.') || u.endsWith('.') || u.includes('..')) return 'INVALID';
  if (RESERVED.has(u) || RESERVED_PREFIXES.some((p) => u.startsWith(p))) return 'RESERVED';
  return null;
}

const normalizeUsername = (raw) => String(raw).trim().toLowerCase();

/** Up to [count] free alternatives to a taken name. */
function suggestUsernames(db, base, count = 3) {
  const stem = normalizeUsername(base).replace(/[^a-z0-9._]/g, '').replace(/^\.+|\.+$/g, '').slice(0, 24) || 'user';
  const out = [];
  const tryName = (name) => {
    if (out.length >= count || out.includes(name) || usernameProblem(name)) return;
    if (!db.get('SELECT 1 AS x FROM users WHERE username = ? COLLATE NOCASE', [name])) out.push(name);
  };
  const digits = () => String(crypto.randomInt(10, 1000));
  for (let i = 0; i < 12 && out.length < count; i++) {
    tryName(`${stem}${digits()}`);
    tryName(`${stem}_${digits()}`);
    tryName(`${stem}.${digits()}`);
  }
  return out;
}

module.exports = { usernameProblem, normalizeUsername, suggestUsernames, RESERVED_PREFIXES };
