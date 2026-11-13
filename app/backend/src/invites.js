// Invite codes. Each person has one short code to hand to friends. A new person who signs up with it follows the inviter and is followed
// back at once, so a friend's first Home is not empty (the cold-start problem; docs/PRODUCT_REPORT.html). Nothing is unlocked by it and
// nobody is paid for it: it only connects two people who already know each other.

const crypto = require('crypto');
const { HttpError } = require('./http');

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const LENGTH = 7;

/** The person's code, made the first time it is asked for. */
function inviteCodeFor(db, userId) {
  const row = db.get('SELECT invite_code FROM users WHERE id = ?', [userId]);
  if (row && row.invite_code) return row.invite_code;
  for (let i = 0; i < 20; i++) {
    let code = '';
    for (let j = 0; j < LENGTH; j++) code += ALPHABET[crypto.randomInt(ALPHABET.length)];
    if (db.get('SELECT 1 AS x FROM users WHERE invite_code = ?', [code])) continue;
    db.run('UPDATE users SET invite_code = ? WHERE id = ? AND invite_code IS NULL', [code, userId]);
    return db.get('SELECT invite_code FROM users WHERE id = ?', [userId]).invite_code;
  }
  throw new HttpError(503, 'Could not make an invite code. Try again');
}

/** What people type or paste: any case, spaces and dashes ignored. */
const normalizeCode = (raw) => String(raw === undefined || raw === null ? '' : raw).toUpperCase().replace(/[\s-]/g, '');

/** The person who owns [raw], or null. Deleted, suspended and bot accounts cannot invite. */
function findInviter(db, raw) {
  const code = normalizeCode(raw);
  if (code.length !== LENGTH) return null;
  return db.get(
    'SELECT * FROM users WHERE invite_code = ? AND deleted_at IS NULL AND suspended_at IS NULL AND is_bot = 0',
    [code]
  ) || null;
}

/** Records who invited [newUserId] and makes the two follow each other. Call inside the sign-up transaction. */
function accept(db, newUserId, inviter, nowIso) {
  db.run('UPDATE users SET invited_by = ? WHERE id = ?', [inviter.id, newUserId]);
  db.run('INSERT OR IGNORE INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [newUserId, inviter.id, nowIso]);
  db.run('INSERT OR IGNORE INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [inviter.id, newUserId, nowIso]);
}

const invitedCount = (db, userId) => db.get('SELECT COUNT(*) AS n FROM users WHERE invited_by = ? AND deleted_at IS NULL', [userId]).n;

module.exports = { LENGTH, inviteCodeFor, normalizeCode, findInviter, accept, invitedCount };
