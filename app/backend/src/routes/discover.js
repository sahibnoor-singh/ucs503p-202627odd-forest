// Discover tab (the reels feed). Same paths and JSON shape the Flutter reels
// screens already use, but served from this backend's own database:
//   posts/likes/reports/blocks are the same rows Home uses; opinions, views and
//   the taste profile are Discover-only (see schema). Ranking is src/recommendation.js (PIPS).
// Only VIDEO posts appear here (text replies are a Home thing), and only ones that still have a file
// (an account deletion empties a person's posts, see routes/users.js).

const express = require('express');
const { requireUser } = require('../middleware/user');
const { wrap, parseLimit, HttpError } = require('../http');
const { nowIso, uuid, getPost } = require('../queries');
const { videoJson } = require('../videoJson');
const { createProfiles } = require('../profiles');
const friendTaste = require('../friendTaste');
const rec = require('../recommendation');
const { REPORT_REASONS } = require('../moderation');

const FEED_WINDOW = 120; // newest opinions considered per feed request
const MAX_WATCH_MS = 6 * 60 * 60 * 1000;

/** Ranking internals (weights, per-feature scores) are for the server only: not sent, so they can't be studied and gamed. */
const withoutScoring = ({ pipsScore, pipsDetails, source, via, ...video }) => video; // eslint-disable-line no-unused-vars

const clampInt = (v, max) => Math.max(0, Math.min(max, Math.round(Number(v)) || 0));

function encodeSeen(ids) {
  return Buffer.from(JSON.stringify(ids.map((i) => i.replace(/-/g, '')))).toString('base64url');
}
function decodeSeen(cursor) {
  try {
    const list = JSON.parse(Buffer.from(String(cursor), 'base64url').toString());
    if (!Array.isArray(list) || list.length > FEED_WINDOW || !list.every((x) => typeof x === 'string' && x.length === 32)) return null;
    return list.map((x) => `${x.slice(0, 8)}-${x.slice(8, 12)}-${x.slice(12, 16)}-${x.slice(16, 20)}-${x.slice(20)}`);
  } catch {
    return null;
  }
}

module.exports = function discoverRoutes({ db, clock = Date.now, allowDevUser = false }) {
  const router = express.Router();

  // Rows the caller may see: not by anyone blocked in either direction.
  function blockSql(me, col = 'p.user_id') {
    if (!me) return { sql: '', params: [] };
    return {
      sql: `AND ${col} NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?)
            AND ${col} NOT IN (SELECT blocker_id FROM blocks WHERE blocked_id = ?)`,
      params: [me, me]
    };
  }

  const toVideos = (rows, me) => videoJson(db, rows, me);

  const { getProfile, saveProfile, learnFromLike } = createProfiles(db);

  /** A READY video the caller can see. */
  function readyVideo(req) {
    const row = getPost(db, req.params.id || (req.body && req.body.videoId));
    if (!row || row.kind !== 'VIDEO' || row.status !== 'READY') throw new HttpError(404, 'Video not found');
    return row;
  }

  function directReplies(parent, me, side) {
    const b = blockSql(me);
    const params = [parent.id, ...b.params];
    let sideSql = '';
    if (side) { sideSql = 'AND p.stance = ?'; params.push(side); }
    const rows = db.all(
      `SELECT p.* FROM posts p
       WHERE p.parent_id = ? AND p.kind = 'VIDEO' AND p.status = 'READY' AND p.media_filename IS NOT NULL ${b.sql} ${sideSql}
       ORDER BY p.created_at DESC, p.id DESC LIMIT 100`,
      params
    );
    const [parentVideo] = toVideos([parent], me);
    return rec.rankVideos(toVideos(rows, me), me ? getProfile(me) : null, { parentVideo, now: clock() }).map(withoutScoring);
  }

  const sideOf = (v) => {
    const side = String(v || '').toUpperCase();
    return side === 'FOR' || side === 'AGAINST' ? side : null;
  };

  // GET /api/videos/feed?limit=10&cursor=...   ranked opinions (PIPS), never repeats within one scroll
  router.get('/feed', wrap(async (req, res) => {
    const me = req.user ? req.user.id : null;
    const limit = parseLimit(req.query.limit, 10, 30);
    let seen = [];
    if (req.query.cursor) {
      seen = decodeSeen(req.query.cursor);
      if (!seen) return res.status(400).json({ error: 'Invalid cursor' });
    }
    const b = blockSql(me);
    const rows = db.all(
      `SELECT p.* FROM posts p
       WHERE p.kind = 'VIDEO' AND p.status = 'READY' AND p.media_filename IS NOT NULL AND p.parent_id IS NULL ${b.sql}
       ORDER BY p.created_at DESC, p.id DESC LIMIT ?`,
      [...b.params, FEED_WINDOW]
    ).filter((r) => !seen.includes(r.id));

    const now = clock();
    const myProfile = me ? getProfile(me) : null;
    const ranked = rec.rankVideos(toVideos(rows, me), myProfile, { now });
    let page = ranked.slice(0, limit).map((v) => ({ ...v, source: 'own' }));
    let rest = ranked.length - page.length;
    if (me && ranked.length) {
      // the person's own ranking, plus a few posts a consistent friend's taste would pick and a few from outside their habits
      const plan = friendTaste.planPage({
        edges: friendTaste.friendEdges(db, me, now), limit, friendsOn: req.user.friend_taste !== 0, knownTopics: Object.keys(myProfile.topics).length
      });
      ({ page, rest } = friendTaste.composePage({
        ranked, limit, plan, now, myName: req.user.username,
        profileOf: getProfile,
        usernameOf: (id) => (db.get('SELECT username FROM users WHERE id = ?', [id]) || {}).username
      }));
    }
    // ?explain=1 shows which source put each post on the page; only on a development server
    const explain = allowDevUser && req.query.explain === '1';
    res.json({
      videos: page.map((v) => {
        // `why` is shown to the person ("picked by riya's taste"); `source`/`via` are the developer's view of the same thing
        const why = v.source === 'friend' ? { kind: 'friend', by: v.via } : v.source === 'explore' ? { kind: 'explore' } : null;
        return {
          ...withoutScoring(v),
          ...(why ? { why } : {}),
          ...(explain ? { source: v.source, ...(v.via ? { via: v.via } : {}) } : {})
        };
      }),
      nextCursor: rest > 0 ? encodeSeen([...seen, ...page.map((v) => v.id)]) : null
    });
  }));

  router.get('/profile', requireUser, wrap(async (req, res) => {
    res.json({ ...getProfile(req.user.id), updatedAt: nowIso() });
  }));

  router.post('/profile/reset', requireUser, wrap(async (req, res) => {
    db.run('DELETE FROM user_profiles WHERE user_id = ?', [req.user.id]);
    res.json({ ok: true, message: 'User interest profile reset successfully' });
  }));

  // POST /api/videos/interactions  and  /api/videos/:id/interactions
  router.post(['/interactions', '/:id/interactions'], requireUser, wrap(async (req, res) => {
    const row = readyVideo(req);
    const body = req.body || {};
    const clean = { userId: req.user.id, at: nowIso() };
    if (body.watchDurationMs !== undefined) clean.watchDurationMs = clampInt(body.watchDurationMs, MAX_WATCH_MS);
    ['completed', 'skipped', 'rewatched', 'saved', 'shared'].forEach((k) => { clean[k] = body[k] === true; });

    const [video] = toVideos([row], req.user.id);
    const profile = rec.updateProfileWithInteraction(getProfile(req.user.id), video, clean);
    db.tx(() => {
      saveProfile(profile);
      if (clean.watchDurationMs !== undefined) {
        db.run('INSERT INTO post_views (user_id, post_id, watched_ms, completed, created_at) VALUES (?, ?, ?, ?, ?)', [
          req.user.id, row.id, clean.watchDurationMs, clean.completed ? 1 : 0, clean.at
        ]);
      }
    });
    res.json({ ok: true, profile });
  }));

  // POST /api/videos/:id/views  {watchedMs, completed}
  router.post('/:id/views', requireUser, wrap(async (req, res) => {
    const row = readyVideo(req);
    const body = req.body || {};
    db.run('INSERT INTO post_views (user_id, post_id, watched_ms, completed, created_at) VALUES (?, ?, ?, ?, ?)', [
      req.user.id, row.id, clampInt(body.watchedMs, MAX_WATCH_MS), body.completed === true ? 1 : 0, nowIso()
    ]);
    res.json({ ok: true });
  }));

  router.get('/:id/status', wrap(async (req, res) => {
    const row = getPost(db, req.params.id);
    const mine = row && req.user && row.user_id === req.user.id;
    if (!row || row.kind !== 'VIDEO' || (row.status !== 'READY' && !mine)) throw new HttpError(404, 'Video not found');
    const [v] = toVideos([row], req.user && req.user.id);
    res.json({ id: v.id, status: v.status, stance: v.stance, credibility: v.credibility });
  }));

  router.get('/:id/replies', wrap(async (req, res) => {
    const parent = readyVideo(req);
    const side = req.query.side ? sideOf(req.query.side) : null;
    if (req.query.side && !side) throw new HttpError(400, 'side must be FOR or AGAINST');
    res.json(directReplies(parent, req.user && req.user.id, side));
  }));

  router.get('/:id/strongest-reply', wrap(async (req, res) => {
    const parent = readyVideo(req);
    const side = sideOf(req.query.side || 'FOR');
    if (!side) throw new HttpError(400, 'side must be FOR or AGAINST');
    res.json({ reply: directReplies(parent, req.user && req.user.id, side)[0] || null });
  }));

  // The whole debate this video belongs to, starting at its root, strongest replies first (max 200).
  router.get('/:id/tree', wrap(async (req, res) => {
    const target = readyVideo(req);
    const me = req.user && req.user.id;
    const b = blockSql(me);
    const rows = db.all(
      `SELECT p.* FROM posts p
       WHERE p.root_id = ? AND p.kind = 'VIDEO' AND p.status = 'READY' AND p.media_filename IS NOT NULL ${b.sql}
       ORDER BY p.created_at ASC, p.id ASC LIMIT 400`,
      [target.root_id, ...b.params]
    );
    const videos = toVideos(rows, me);
    const kids = new Map();
    let root = null;
    for (const v of videos) {
      if (!v.parentVideoId) { root = v; continue; }
      if (!kids.has(v.parentVideoId)) kids.set(v.parentVideoId, []);
      kids.get(v.parentVideoId).push(v);
    }
    const out = [];
    if (root) {
      const queue = [root];
      while (queue.length && out.length < 200) {
        const next = queue.shift();
        out.push(next);
        queue.push(...(kids.get(next.id) || []).sort((a, c) => c.credibility - a.credibility));
      }
    }
    res.json(out);
  }));

  // PUT /api/videos/:id/opinion {side}: which side the viewer takes; answers with the best reply from that side.
  router.put('/:id/opinion', requireUser, wrap(async (req, res) => {
    const row = readyVideo(req);
    const side = sideOf(req.body && req.body.side);
    if (!side) throw new HttpError(400, 'Body side must be FOR or AGAINST');
    db.run('INSERT OR REPLACE INTO viewer_opinions (user_id, post_id, side, created_at) VALUES (?, ?, ?, ?)', [
      req.user.id, row.id, side, nowIso()
    ]);
    res.json({ side, strongestReply: directReplies(row, req.user.id, side)[0] || null });
  }));

  router.delete('/:id/opinion', requireUser, wrap(async (req, res) => {
    db.run('DELETE FROM viewer_opinions WHERE user_id = ? AND post_id = ?', [req.user.id, req.params.id]);
    res.json({ ok: true });
  }));

  const likeCount = (id) => db.get('SELECT COUNT(*) AS n FROM likes WHERE post_id = ?', [id]).n;

  router.put('/:id/like', requireUser, wrap(async (req, res) => {
    const row = readyVideo(req);
    const had = db.get('SELECT 1 AS x FROM likes WHERE user_id = ? AND post_id = ?', [req.user.id, row.id]);
    db.run('INSERT OR IGNORE INTO likes (user_id, post_id, created_at) VALUES (?, ?, ?)', [req.user.id, row.id, nowIso()]);
    if (!had) learnFromLike(req.user.id, row);
    res.json({ liked: true, likeCount: likeCount(row.id) });
  }));

  router.delete('/:id/like', requireUser, wrap(async (req, res) => {
    const row = readyVideo(req);
    db.run('DELETE FROM likes WHERE user_id = ? AND post_id = ?', [req.user.id, row.id]);
    res.json({ liked: false, likeCount: likeCount(row.id) });
  }));

  // POST /api/videos/:id/report {reason}: unknown reason texts are filed under OTHER.
  router.post('/:id/report', requireUser, wrap(async (req, res) => {
    const row = getPost(db, req.params.id);
    if (!row || row.kind !== 'VIDEO') throw new HttpError(404, 'Video not found');
    if (row.user_id === req.user.id) throw new HttpError(400, "You can't report your own post");
    const asked = String((req.body && req.body.reason) || '').toUpperCase();
    const reason = REPORT_REASONS.includes(asked) ? asked : 'OTHER';
    db.run('INSERT OR IGNORE INTO reports (id, reporter_id, post_id, reason, created_at) VALUES (?, ?, ?, ?, ?)', [
      uuid(), req.user.id, row.id, reason, nowIso()
    ]);
    res.json({ ok: true });
  }));

  // Must stay last: a bare /:id would swallow the paths above.
  router.get('/:id', wrap(async (req, res) => {
    const row = getPost(db, req.params.id);
    const mine = row && req.user && row.user_id === req.user.id;
    if (!row || row.kind !== 'VIDEO' || (row.status !== 'READY' && !mine)) throw new HttpError(404, 'Video not found');
    res.json(toVideos([row], req.user && req.user.id)[0]);
  }));

  return router;
};
