// "Someone followed you" and its list.
//
//   GET  /api/notifications        → { unread, notifications: [{ id, kind, text, createdAt, read, actor: {id, username, fullName, avatarUrl, isBot},
//                                                               post: { id, title, coverUrl } | null }] }   newest first, 50 at most
//   POST /api/notifications/read   → { unread: 0 }                 marks everything read (opening the list does this)
//
// A follow is recorded by `notifyFollow`, called from POST /api/users/:id/follow when the follow is new. The text names the reel the
// person was watching when they followed ("@riya followed you from this reel"), and the row keeps that post so the app can show its
// cover and open it. Blocked, deleted and suspended people are never told, and nobody is told about themselves.

const express = require('express');
const { requireUser } = require('../middleware/user');
const { wrap } = require('../http');
const { uuid, nowIso, getPost, getUsersMap } = require('../queries');

const LIMIT = 50;

/** Tells [userId] that [actorId] followed them. [postId] is the video they followed from (checked: it must be the target's own, ready video). */
function notifyFollow(db, { userId, actorId, postId }) {
  if (!userId || !actorId || userId === actorId) return;
  const target = db.get('SELECT deleted_at, suspended_at FROM users WHERE id = ?', [userId]);
  if (!target || target.deleted_at || target.suspended_at) return;
  let from = null;
  if (postId) {
    const post = getPost(db, String(postId));
    if (post && post.user_id === userId && post.status === 'READY') from = post.id;
  }
  // One row per person who followed: a second follow does not tell them again (INSERT OR IGNORE keeps the first, read or not).
  db.run(
    'INSERT OR IGNORE INTO notifications (id, user_id, kind, actor_id, post_id, created_at) VALUES (?, ?, ?, ?, ?, ?)',
    [uuid(), userId, 'follow', actorId, from, nowIso()]
  );
}

const unreadOf = (db, userId) => db.get('SELECT COUNT(*) AS n FROM notifications WHERE user_id = ? AND read_at IS NULL', [userId]).n;

module.exports = function notificationRoutes({ db }) {
  const router = express.Router();

  router.get('/notifications', requireUser, wrap(async (req, res) => {
    const me = req.user.id;
    const rows = db.all(
      `SELECT n.* FROM notifications n
       WHERE n.user_id = ? AND n.actor_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?)
         AND n.actor_id NOT IN (SELECT blocker_id FROM blocks WHERE blocked_id = ?)
       ORDER BY n.created_at DESC LIMIT ?`, [me, me, me, LIMIT]);
    const users = getUsersMap(db, rows.map((r) => r.actor_id));
    const out = [];
    for (const r of rows) {
      const actor = users.get(r.actor_id);
      if (!actor || actor.deleted_at) continue;
      const post = r.post_id ? getPost(db, r.post_id) : null;
      const shown = post && post.status === 'READY' && post.media_filename ? post : null;
      out.push({
        id: r.id,
        kind: r.kind,
        text: shown ? `@${actor.username} followed you from this reel` : `@${actor.username} followed you`,
        createdAt: r.created_at,
        read: !!r.read_at,
        actor: { id: actor.id, username: actor.username, fullName: actor.full_name, avatarUrl: actor.avatar_url || null, isBot: !!actor.is_bot },
        post: shown ? { id: shown.id, title: shown.title || null, coverUrl: shown.cover_filename ? `/uploads/${shown.cover_filename}` : null } : null
      });
    }
    res.json({ unread: unreadOf(db, me), notifications: out });
  }));

  router.post('/notifications/read', requireUser, wrap(async (req, res) => {
    db.run('UPDATE notifications SET read_at = ? WHERE user_id = ? AND read_at IS NULL', [nowIso(), req.user.id]);
    res.json({ unread: 0 });
  }));

  return router;
};

module.exports.notifyFollow = notifyFollow;
