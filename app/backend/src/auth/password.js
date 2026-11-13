// Password hashing with Node's built-in scrypt (no extra dependency).
// Stored as  scrypt$N$r$p$<salt b64>$<hash b64>  so the cost can be raised later without breaking old hashes.

const crypto = require('crypto');
const { promisify } = require('util');

const scrypt = promisify(crypto.scrypt);
const N = 16384, R = 8, P = 1, KEYLEN = 64;
const MAXMEM = 64 * 1024 * 1024;

const MIN_LENGTH = 8;
const MAX_LENGTH = 128; // scrypt is deliberately expensive; don't let a 10 MB "password" burn the server

// Not a full breach list, just the passwords everyone tries first.
const COMMON = new Set([
  'password', 'password1', 'password123', '12345678', '123456789', '1234567890', 'qwertyui', 'qwerty123',
  'iloveyou', 'abc12345', '11111111', '00000000', 'letmein1', 'welcome1', 'forest123', 'admin123'
]);

/** @returns an error message, or null if the password is acceptable */
function passwordProblem(password, { username } = {}) {
  if (typeof password !== 'string') return 'Password is required';
  if (password.length < MIN_LENGTH) return `Password must be at least ${MIN_LENGTH} characters`;
  if (password.length > MAX_LENGTH) return `Password must be at most ${MAX_LENGTH} characters`;
  if (COMMON.has(password.toLowerCase())) return 'That password is too common. Pick something harder to guess';
  if (username && password.toLowerCase() === String(username).toLowerCase()) return "Password can't be your username";
  return null;
}

async function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const hash = await scrypt(password, salt, KEYLEN, { N, r: R, p: P, maxmem: MAXMEM });
  return ['scrypt', N, R, P, salt.toString('base64'), hash.toString('base64')].join('$');
}

async function verifyPassword(password, stored) {
  try {
    const [scheme, n, r, p, saltB64, hashB64] = String(stored).split('$');
    if (scheme !== 'scrypt') return false;
    const expected = Buffer.from(hashB64, 'base64');
    const actual = await scrypt(String(password).slice(0, MAX_LENGTH), Buffer.from(saltB64, 'base64'), expected.length,
      { N: Number(n), r: Number(r), p: Number(p), maxmem: MAXMEM });
    return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
  } catch {
    return false;
  }
}

// Used to spend the same time when the account doesn't exist, so response time doesn't reveal which usernames exist.
let dummyHash;
async function burnTime(password) {
  dummyHash = dummyHash || (await hashPassword('forest-dummy-password'));
  await verifyPassword(password, dummyHash);
}

module.exports = { passwordProblem, hashPassword, verifyPassword, burnTime, MIN_LENGTH, MAX_LENGTH };
