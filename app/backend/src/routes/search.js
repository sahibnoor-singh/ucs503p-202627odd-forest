// Search: accounts and posts. GET /api/search?q=&type=all|accounts|posts&limit=&cursor=   (mounted at /api/search)
//
//   all       best few accounts + the best posts (no paging: open a tab for more)
//   accounts  people whose username, name or bio contains every word of the query
//   posts     videos (openers and replies) whose title, caption, transcript or summary contain every word
//
// Only what is already visible elsewhere can be found: READY posts (the ones that passed moderation), never anything by a
// suspended or deleted person, nothing from anyone you blocked or who blocked you. A query that contains a word on the
// moderation blocklist finds nothing. Posts rank by how well they match, then credibility (not likes or views, CLAUDE.md) and
// freshness. The query is never stored or logged.

const express = require('express');
const { requireUser } = require('../middleware/user');
const { wrap, parseLimit, HttpError } = require('../http');
const { toUser } = require('../queries');
const { videoJson } = require('../videoJson');

const MAX_QUERY = 80;
const MAX_WORDS = 5;
const MIN_QUERY = 2;
const CANDIDATES = 300; // newest matching posts looked at
const POOL = 100; // best of those that can be paged through
const ACCOUNTS_IN_ALL = 5;
const TYPES = ['all', 'accounts', 'posts'];

/** Lower-cases ASCII only, exactly like SQLite's lower(), so what we compare with LIKE and what is stored agree. */
const lowerAscii = (s) => s.replace(/[A-Z]/g, (c) => c.toLowerCase());
const likeOf = (word) => `%${word.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const marks = (n) => new Array(n).fill('?').join(',');

function parseQuery(raw) {
  const text = lowerAscii(String(raw || '').replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim()).slice(0, MAX_QUERY).trim();
  const words = [...new Set(text.split(' ').filter(Boolean))].slice(0, MAX_WORDS);
  return { text, words };
}

const encodeCursor = (offset) => Buffer.from(`o:${offset}`).toString('base64url');
function decodeCursor(cursor) {
  if (!cursor) return 0;
  try {
    const m = /^o:(\d{1,4})$/.exec(Buffer.from(String(cursor), 'base64url').toString());
    if (m && Number(m[1]) <= POOL) return Number(m[1]);
  } catch { /* fall through */ }
  throw new HttpError(400, 'Invalid cursor');
}

module.exports = function searchRoutes({ db, moderation = null, clock = Date.now }) {
  const router = express.Router();

  const notBlocked = (me, col) => ({
    sql: `AND ${col} NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?)
          AND ${col} NOT IN (SELECT blocker_id FROM blocks WHERE blocked_id = ?)`,
    params: [me, me]
  });

  /** Points for how well [text] matches one word: a word that starts with it beats one that merely contains it. */
  function wordScore(text, word, starts, contains) {
    if (!text) return 0;
    if (new RegExp(`(^|[^\\p{L}\\p{N}])${escapeRe(word)}`, 'u').test(text)) return starts;
    return text.includes(word) ? contains : 0;
  }

  function searchPosts(me, { text, words }, offset, limit) {
    const b = notBlocked(me, 'p.user_id');
    const rows = db.all(
      `SELECT p.* FROM posts p JOIN users u ON u.id = p.user_id
       WHERE p.kind = 'VIDEO' AND p.status = 'READY' AND p.media_filename IS NOT NULL
         AND u.deleted_at IS NULL AND u.suspended_at IS NULL ${b.sql}
         ${words.map(() => "AND p.search_text LIKE ? ESCAPE '\\'").join(' ')}
       ORDER BY p.created_at DESC, p.id DESC LIMIT ?`,
      [...b.params, ...words.map(likeOf), CANDIDATES]
    );
    const relevance = (row) => {
      const title = (row.title || '').toLowerCase();
      const body = (row.body || '').toLowerCase();
      let score = 0;
      for (const w of words) {
        score += Math.max(wordScore(title, w, 10, 6), wordScore(body, w, 4, 2), 2); // 2: found only in what was said
      }
      if (words.length > 1) score += title.includes(text) ? 8 : body.includes(text) ? 4 : 0;
      return score;
    };
    // the best-matching of the newest (rows are already newest first, and a stable sort keeps that among equals)
    const pool = rows.map((row) => ({ row, relevance: relevance(row) })).sort((x, y) => y.relevance - x.relevance).slice(0, POOL);
    const videos = videoJson(db, pool.map((x) => x.row), me);
    const now = clock();
    const ranked = videos.map((video, i) => {
      const ageDays = Math.max(0, (now - new Date(video.createdAt).getTime()) / 86400000);
      const score = pool[i].relevance * (0.8 + 0.2 * (video.credibility / 100)) + 1.5 * Math.exp(-ageDays / 14);
      return { video, score };
    }).sort((x, y) => y.score - x.score).map((x) => x.video);
    const page = ranked.slice(offset, offset + limit);
    return { posts: page, nextCursor: offset + limit < ranked.length ? encodeCursor(offset + limit) : null };
  }

  function searchAccounts(me, { text, words }, offset, limit) {
    const b = notBlocked(me, 'u.id');
    const rows = db.all(
      `SELECT u.* FROM users u
       WHERE u.deleted_at IS NULL AND u.suspended_at IS NULL ${b.sql}
         ${words.map(() => "AND (u.username LIKE ? ESCAPE '\\' OR u.full_name LIKE ? ESCAPE '\\' OR COALESCE(u.bio, '') LIKE ? ESCAPE '\\')").join(' ')}
       LIMIT ?`,
      [...b.params, ...words.flatMap((w) => [likeOf(w), likeOf(w), likeOf(w)]), CANDIDATES]
    );
    if (!rows.length) return { accounts: [], nextCursor: null };
    const ids = rows.map((r) => r.id);
    const m = marks(ids.length);
    const followers = new Map(db.all(`SELECT followee_id id, COUNT(*) n FROM follows WHERE followee_id IN (${m}) GROUP BY followee_id`, ids).map((r) => [r.id, r.n]));
    const postCounts = new Map(db.all(`SELECT user_id id, COUNT(*) n FROM posts WHERE status = 'READY' AND user_id IN (${m}) GROUP BY user_id`, ids).map((r) => [r.id, r.n]));
    const followed = new Set(db.all(`SELECT followee_id id FROM follows WHERE follower_id = ? AND followee_id IN (${m})`, [me, ...ids]).map((r) => r.id));

    const scored = rows.map((u) => {
      const name = u.username.toLowerCase();
      const full = (u.full_name || '').toLowerCase();
      let score = name === text ? 100 : name.startsWith(text) ? 60 : 0;
      for (const w of words) {
        score += Math.max(wordScore(name, w, 30, 12), wordScore(full, w, 25, 10), wordScore((u.bio || '').toLowerCase(), w, 3, 3));
      }
      if (followed.has(u.id)) score += 8;
      score += Math.log2(1 + (followers.get(u.id) || 0));
      return { u, score };
    }).sort((x, y) => y.score - x.score || x.u.username.localeCompare(y.u.username));

    const page = scored.slice(offset, offset + limit).map(({ u }) => ({
      user: toUser(u),
      followerCount: followers.get(u.id) || 0,
      postCount: postCounts.get(u.id) || 0,
      followedByMe: followed.has(u.id),
      isMe: u.id === me
    }));
    return { accounts: page, nextCursor: offset + limit < scored.length ? encodeCursor(offset + limit) : null };
  }

  router.get('/', requireUser, wrap(async (req, res) => {
    const me = req.user.id;
    const type = req.query.type === undefined ? 'all' : String(req.query.type);
    if (!TYPES.includes(type)) throw new HttpError(400, `type must be one of: ${TYPES.join(', ')}`);
    const limit = parseLimit(req.query.limit, 20, 30);
    const offset = type === 'all' ? 0 : decodeCursor(req.query.cursor);
    const query = parseQuery(req.query.q);

    const out = { q: query.text, type, accounts: [], posts: [], nextCursor: null };
    const searchable = query.text.length >= MIN_QUERY && !(moderation && moderation.screenText(query.text));
    if (!searchable) return res.json(out);

    if (type === 'all' || type === 'accounts') {
      const r = searchAccounts(me, query, offset, type === 'all' ? ACCOUNTS_IN_ALL : limit);
      out.accounts = r.accounts;
      if (type === 'accounts') out.nextCursor = r.nextCursor;
    }
    if (type === 'all' || type === 'posts') {
      const r = searchPosts(me, query, offset, limit);
      out.posts = r.posts;
      if (type === 'posts') out.nextCursor = r.nextCursor;
    }
    res.json(out);
  }));

  return router;
};
