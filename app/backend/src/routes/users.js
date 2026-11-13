const fs = require('fs');
const path = require('path');
const express = require('express');
const { notifyFollow } = require('./notifications');
const { requireUser } = require('../middleware/user');
const { wrap, HttpError, parseLimit } = require('../http');
const { nowIso, getUser, toUser, isBlockedEitherWay } = require('../queries');
const { verifyPassword } = require('../auth/password');
const { createProfiles } = require('../profiles');
const topics = require('../topics');

module.exports = function userRoutes({ db, google, events = { track() {} }, allowDevUser, uploadsDir, composeDir, jobs }) {
  const router = express.Router();

  router.get('/me', requireUser, (req, res) => {
    const me = req.user.id;
    res.json({
      user: toUser(req.user),
      followingCount: db.get('SELECT COUNT(*) AS n FROM follows WHERE follower_id = ?', [me]).n,
      followerCount: db.get('SELECT COUNT(*) AS n FROM follows WHERE followee_id = ?', [me]).n,
      settings: { friendTaste: req.user.friend_taste !== 0 },
      // What the app needs to know to ask for the right proof before something serious (deleting the account)
      account: { hasPassword: !!req.user.password_hash, google: !!req.user.google_sub, onboarded: !!req.user.onboarded_at }
    });
  });

  // GET /api/onboarding/topics   The topics a new person can pick, and how many to ask for.
  router.get('/onboarding/topics', requireUser, (req, res) => {
    res.json({ topics: topics.publicTopics(), min: topics.MIN_PICK, max: topics.MAX_PICK });
  });

  // POST /api/me/onboarding  { topics: ["politics", "tech"] }   Seeds the taste profile with the chosen topics and marks the first-run
  // pages as done (the first time only, so choosing again later never re-triggers them). An empty list is "skip": nothing is seeded.
  router.post('/me/onboarding', requireUser, wrap(async (req, res) => {
    const ids = req.body && req.body.topics;
    if (!Array.isArray(ids) || ids.length > topics.MAX_PICK * 2 || ids.some((id) => typeof id !== 'string' || !topics.isTopicId(id))) {
      throw new HttpError(400, 'Pick topics from the list', { field: 'topics' });
    }
    const chosen = [...new Set(ids)].slice(0, topics.MAX_PICK);
    if (chosen.length) {
      const { getProfile, saveProfile } = createProfiles(db);
      saveProfile(topics.seedProfile(getProfile(req.user.id), chosen));
    }
    const first = !req.user.onboarded_at;
    db.run('UPDATE users SET onboarded_at = COALESCE(onboarded_at, ?) WHERE id = ?', [nowIso(), req.user.id]);
    if (first) events.track('onboarding_done', req.user.id, { topics: chosen.length, skipped: chosen.length === 0 });
    res.json({ topics: chosen });
  }));

  // PUT /api/me/settings  { friendTaste: boolean }   Whether friends' taste may shape this person's Discover. Off keeps it to
  // their own ranking (plus the exploration that is always there).
  router.put('/me/settings', requireUser, wrap(async (req, res) => {
    const body = req.body || {};
    if (typeof body.friendTaste !== 'boolean') throw new HttpError(400, 'friendTaste must be true or false', { field: 'friendTaste' });
    db.run('UPDATE users SET friend_taste = ? WHERE id = ?', [body.friendTaste ? 1 : 0, req.user.id]);
    res.json({ settings: { friendTaste: body.friendTaste } });
  }));

  // DELETE /api/me  {password} or, for an account made with Google and no password, {idToken}   Deletes the account (Play Store and DPDP both require a way to).
  // The person's personal data is wiped, their video files are removed and their posts are emptied (see below).
  // The row itself stays, renamed "deleted_xxxx", so replies that other people wrote under their posts keep
  // working. Tokens issued before stop working at once (see middleware/user.js).
  router.delete('/me', requireUser, wrap(async (req, res) => {
    const me = req.user;
    const body = req.body || {};
    if (me.password_hash) {
      if (typeof body.password !== 'string' || !(await verifyPassword(body.password, me.password_hash))) {
        throw new HttpError(403, 'Wrong password'); // 403, not 401: the app treats 401 as "your login expired" and signs out
      }
    } else {
      // No password to ask for: a fresh Google sign-in as the same Google account proves it is them.
      let g = null;
      try { g = google && typeof body.idToken === 'string' ? await google.verify(body.idToken) : null; } catch { /* handled below */ }
      if (!g || !me.google_sub || g.sub !== me.google_sub) throw new HttpError(403, 'Confirm with the Google account you signed up with');
    }
    const files = db.all('SELECT media_filename, cover_filename FROM posts WHERE user_id = ? AND (media_filename IS NOT NULL OR cover_filename IS NOT NULL)', [me.id])
      .flatMap((r) => [r.media_filename, r.cover_filename]).filter(Boolean);
    // editor posts that were still waiting to render (or failed) keep their inputs in the compose folder
    const pendingInputs = db.all('SELECT recipe FROM posts WHERE user_id = ? AND recipe IS NOT NULL', [me.id])
      .map((r) => JSON.parse(r.recipe).files);
    db.tx(() => {
      db.run(
        `UPDATE users SET username = ?, full_name = 'Deleted user', phone = NULL, phone_verified = 0, email = NULL,
                dob = NULL, password_hash = NULL, google_sub = NULL, invite_code = NULL, invited_by = NULL, email_verified = 0, avatar_url = NULL,
                personality_keywords = NULL, personality_summary = NULL, personality_summary_approved = 0, interests = NULL, bio = NULL, deleted_at = ? WHERE id = ?`,
        [`deleted_${me.id.replace(/-/g, '').slice(0, 10)}`, nowIso(), me.id]
      );
      // The posts stay (still READY) but are emptied: other people's replies hang below them, and removing the
      // post would orphan those threads and break the reply counts. Text replies read "[deleted]"; a video
      // simply has no file any more ("Video not available" in the app).
      db.run(
        `UPDATE posts SET media_filename = NULL, cover_filename = NULL, title = NULL, analysis = NULL, recipe = NULL,
                body = CASE WHEN kind = 'TEXT' THEN '[deleted]' ELSE NULL END
         WHERE user_id = ?`, [me.id]);
      db.run('UPDATE rooms SET closed_at = ? WHERE owner_id = ? AND closed_at IS NULL', [nowIso(), me.id]);
      // Videos still being analysed will never finish (their file is gone); free their place in the queue.
      db.run("UPDATE posts SET status = 'FAILED' WHERE user_id = ? AND status = 'PROCESSING'", [me.id]);
      for (const sql of [
        'DELETE FROM likes WHERE user_id = ?', 'DELETE FROM follows WHERE follower_id = ? OR followee_id = ?',
        'DELETE FROM notifications WHERE user_id = ? OR actor_id = ?',
        'DELETE FROM blocks WHERE blocker_id = ?', 'DELETE FROM reports WHERE reporter_id = ?',
        'DELETE FROM viewer_opinions WHERE user_id = ?', 'DELETE FROM post_views WHERE user_id = ?',
        'DELETE FROM user_profiles WHERE user_id = ?', 'DELETE FROM shares WHERE sender_id = ? OR recipient_id = ?',
        // their conversations go with them: every message, reaction and read mark, on both sides
        `DELETE FROM message_reactions WHERE message_id IN (SELECT m.id FROM messages m JOIN conversations c ON c.id = m.conversation_id
                                                           WHERE c.user_lo = ? OR c.user_hi = ?)`,
        'DELETE FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE user_lo = ? OR user_hi = ?)',
        'DELETE FROM conversation_reads WHERE conversation_id IN (SELECT id FROM conversations WHERE user_lo = ? OR user_hi = ?)',
        'DELETE FROM conversations WHERE user_lo = ? OR user_hi = ?',
        'DELETE FROM message_reactions WHERE user_id = ?',
        // rooms: they leave every room, and a room they ran is closed (nobody is left to run it)
        'DELETE FROM room_members WHERE user_id = ?',
        // saved posts are private to the person who saved them
        'DELETE FROM bookmarks WHERE user_id = ?',
        // events are kept for the counts but no longer point at a person
        'UPDATE events SET user_id = NULL WHERE user_id = ?'
      ]) db.run(sql, Array(sql.split('?').length - 1).fill(me.id));
    });
    // Files last: if one cannot be removed the account is still gone and the leftover is only an orphan.
    for (const f of files) fs.rmSync(path.join(uploadsDir, path.basename(f)), { force: true });
    for (const inputs of pendingInputs) jobs.removeInputs(inputs);
    res.json({ deleted: true });
  }));

  // People you have blocked, so the app can offer "Unblock".
  router.get('/me/blocks', requireUser, (req, res) => {
    const rows = db.all(
      `SELECT u.* FROM blocks b JOIN users u ON u.id = b.blocked_id
       WHERE b.blocker_id = ? ORDER BY b.created_at DESC`, [req.user.id]);
    res.json({ users: rows.map(toUser) });
  });

  // TEMP: lets the app list seeded users so a developer can pick who they are.
  if (allowDevUser) {
    router.get('/dev/users', (req, res) => {
      res.json({ users: db.all('SELECT * FROM users ORDER BY username').map(toUser) });
    });
  }

  // GET /api/users/suggested?limit=10  Who to follow: people you don't follow and haven't blocked (or been
  // blocked by) who have posted, most recently active first. Keeps a new account's Home from being empty.
  router.get('/users/suggested', requireUser, wrap(async (req, res) => {
    const me = req.user.id;
    const limit = parseLimit(req.query.limit, 10, 30);
    // Rank by recent activity first (one pass over posts), then count followers only for the rows we return.
    const rows = db.all(
      `SELECT u.*, a.post_count, a.last_post_at
       FROM users u
       JOIN (SELECT user_id, COUNT(*) AS post_count, MAX(created_at) AS last_post_at
             FROM posts WHERE status = 'READY' GROUP BY user_id) a ON a.user_id = u.id
       WHERE u.id != ?
         AND u.id NOT IN (SELECT followee_id FROM follows WHERE follower_id = ?)
         AND u.id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?)
         AND u.id NOT IN (SELECT blocker_id FROM blocks WHERE blocked_id = ?)
       ORDER BY a.last_post_at DESC, u.id
       LIMIT ?`,
      [me, me, me, me, limit]
    );
    const followers = new Map();
    if (rows.length) {
      db.all(
        `SELECT followee_id AS id, COUNT(*) AS n FROM follows WHERE followee_id IN (${rows.map(() => '?').join(',')}) GROUP BY followee_id`,
        rows.map((r) => r.id)
      ).forEach((r) => followers.set(r.id, r.n));
    }
    res.json({
      users: rows.map((r) => ({ user: toUser(r), followerCount: followers.get(r.id) || 0, postCount: r.post_count }))
    });
  }));

  // GET /api/users/friends  People you can send a video to: you follow each other. Not bots, nobody blocked either way, nobody
  // deleted or suspended. The ones you have sent to most come first.
  router.get('/users/friends', requireUser, wrap(async (req, res) => {
    const me = req.user.id;
    const rows = db.all(
      `SELECT u.* FROM users u
       WHERE u.id != ? AND u.is_bot = 0 AND u.deleted_at IS NULL AND u.suspended_at IS NULL
         AND EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.followee_id = u.id)
         AND EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = u.id AND f.followee_id = ?)
         AND u.id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?)
         AND u.id NOT IN (SELECT blocker_id FROM blocks WHERE blocked_id = ?)
       ORDER BY (SELECT COUNT(*) FROM shares s WHERE s.sender_id = ? AND s.recipient_id = u.id) DESC, u.username
       LIMIT 200`,
      [me, me, me, me, me, me]
    );
    res.json({ users: rows.map(toUser) });
  }));

  // GET /api/users/:id  Profile header. 404 if they have blocked you (we don't reveal that).
  router.get('/users/:id', requireUser, wrap(async (req, res) => {
    const target = getUser(db, req.params.id);
    if (!target || target.deleted_at) throw new HttpError(404, 'User not found');
    const me = req.user.id;
    if (db.get('SELECT 1 AS x FROM blocks WHERE blocker_id = ? AND blocked_id = ?', [target.id, me])) {
      throw new HttpError(404, 'User not found');
    }
    const count = (sql) => db.get(sql, [target.id]).n;
    res.json({
      user: toUser(target),
      followerCount: count('SELECT COUNT(*) AS n FROM follows WHERE followee_id = ?'),
      followingCount: count('SELECT COUNT(*) AS n FROM follows WHERE follower_id = ?'),
      postCount: count("SELECT COUNT(*) AS n FROM posts WHERE user_id = ? AND status = 'READY'"),
      followedByMe: !!db.get('SELECT 1 AS x FROM follows WHERE follower_id = ? AND followee_id = ?', [me, target.id]),
      blockedByMe: !!db.get('SELECT 1 AS x FROM blocks WHERE blocker_id = ? AND blocked_id = ?', [me, target.id]),
      isMe: target.id === me
    });
  }));

  function targetUser(req) {
    const target = getUser(db, req.params.id);
    if (!target || target.deleted_at) throw new HttpError(404, 'User not found');
    if (target.id === req.user.id) throw new HttpError(400, "You can't do that to yourself");
    return target;
  }

  router.post('/users/:id/follow', requireUser, wrap(async (req, res) => {
    const target = targetUser(req);
    if (isBlockedEitherWay(db, req.user.id, target.id)) throw new HttpError(403, "You can't follow this user");
    const already = db.get('SELECT 1 AS x FROM follows WHERE follower_id = ? AND followee_id = ?', [req.user.id, target.id]);
    db.run('INSERT OR IGNORE INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [
      req.user.id, target.id, nowIso()
    ]);
    // A new follow tells the person (once), naming the reel it was done from when the app says so ({ fromPostId }).
    if (!already) notifyFollow(db, { userId: target.id, actorId: req.user.id, postId: req.body && req.body.fromPostId });
    res.json({ following: true });
  }));

  router.delete('/users/:id/follow', requireUser, wrap(async (req, res) => {
    const target = targetUser(req);
    db.run('DELETE FROM follows WHERE follower_id = ? AND followee_id = ?', [req.user.id, target.id]);
    res.json({ following: false });
  }));

  // Blocking also removes the follow in both directions.
  router.post('/users/:id/block', requireUser, wrap(async (req, res) => {
    const target = targetUser(req);
    db.tx(() => {
      db.run('INSERT OR IGNORE INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)', [
        req.user.id, target.id, nowIso()
      ]);
      db.run(
        `DELETE FROM follows WHERE (follower_id = ? AND followee_id = ?) OR (follower_id = ? AND followee_id = ?)`,
        [req.user.id, target.id, target.id, req.user.id]
      );
    });
    res.json({ blocked: true });
  }));

  router.delete('/users/:id/block', requireUser, wrap(async (req, res) => {
    const target = targetUser(req);
    db.run('DELETE FROM blocks WHERE blocker_id = ? AND blocked_id = ?', [req.user.id, target.id]);
    res.json({ blocked: false });
  }));

  return router;
};
