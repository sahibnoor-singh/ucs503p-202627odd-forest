// Sending a video to a friend (the paper-plane button).
//
//   POST /api/posts/:id/share   { recipientIds: [userId, ...] }   → { sent: [userId], skipped: [{ userId, reason }] }
//
// A sent video arrives in the recipient's direct messages (routes/messages.js) as a video message, and is also recorded in `shares`:
// what the recipient then does with it (opens, watches, likes) is what tells Discover how much their taste matches the sender's
// (friendTaste.js).
//
// Rules (CLAUDE.md: no unsolicited contact from strangers, rate-limit):
//   - only to friends (friends.js): people you follow who follow you back; never bots, yourself, anyone blocked either way, or an
//     account that is deleted or suspended
//   - videos only, and only READY ones a person could see anyway
//   - at most MAX_RECIPIENTS people per request and DAILY_LIMIT new sends per person per 24 hours (a 429 says when to come back)
//   - sending the same video to the same person again is not an error and changes nothing (no second message)

const express = require('express');
const { requireUser } = require('../middleware/user');
const { wrap, HttpError } = require('../http');
const { nowIso, uuid, getPost, getUsersMap } = require('../queries');
const { whyNotFriend, blockedEitherWay } = require('../friends');
const { getOrCreateConversation, addMessage } = require('../conversations');

const MAX_RECIPIENTS = 10;
const DAILY_LIMIT = 50;
const DAY_MS = 24 * 60 * 60 * 1000;

module.exports = function shareRoutes({ db, clock = Date.now }) {
  const router = express.Router();

  router.post('/posts/:id/share', requireUser, wrap(async (req, res) => {
    const me = req.user.id;
    const post = getPost(db, req.params.id);
    if (!post || post.status !== 'READY') throw new HttpError(404, 'Post not found');
    if (post.kind !== 'VIDEO' || !post.media_filename) throw new HttpError(400, 'Only videos can be sent');
    const author = db.get('SELECT deleted_at, suspended_at FROM users WHERE id = ?', [post.user_id]);
    if (!author || author.deleted_at || author.suspended_at || blockedEitherWay(db, me, post.user_id)) throw new HttpError(404, 'Post not found');

    const asked = req.body && req.body.recipientIds;
    if (!Array.isArray(asked) || !asked.length || !asked.every((id) => typeof id === 'string')) {
      throw new HttpError(400, 'recipientIds must be a list of user ids', { field: 'recipientIds' });
    }
    const recipientIds = [...new Set(asked)];
    if (recipientIds.length > MAX_RECIPIENTS) throw new HttpError(400, `You can send to at most ${MAX_RECIPIENTS} people at once`, { field: 'recipientIds' });

    const users = getUsersMap(db, recipientIds);
    const sent = [];
    const skipped = [];
    const fresh = [];
    for (const id of recipientIds) {
      const reason = whyNotFriend(db, me, users.get(id));
      if (reason) { skipped.push({ userId: id, reason }); continue; }
      if (db.get('SELECT 1 AS x FROM shares WHERE sender_id = ? AND recipient_id = ? AND post_id = ?', [me, id, post.id])) {
        sent.push(id); // already there: counts as sent, costs nothing
        continue;
      }
      fresh.push(id);
    }

    if (fresh.length) {
      const since = new Date(clock() - DAY_MS).toISOString();
      const today = db.get('SELECT COUNT(*) AS n FROM shares WHERE sender_id = ? AND created_at >= ?', [me, since]).n;
      if (today + fresh.length > DAILY_LIMIT) {
        throw new HttpError(429, `You can send at most ${DAILY_LIMIT} videos a day. Try again tomorrow.`, { retryAfterSec: 3600 });
      }
      db.tx(() => {
        for (const id of fresh) {
          db.run('INSERT INTO shares (id, sender_id, recipient_id, post_id, created_at) VALUES (?, ?, ?, ?, ?)', [uuid(), me, id, post.id, nowIso()]);
          const conv = getOrCreateConversation(db, me, id);
          addMessage(db, { conversationId: conv.id, senderId: me, kind: 'VIDEO', postId: post.id });
        }
      });
      sent.push(...fresh);
    }
    res.json({ sent, skipped });
  }));

  return router;
};
