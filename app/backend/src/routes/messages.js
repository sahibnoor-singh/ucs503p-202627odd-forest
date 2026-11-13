// Direct messages (mounted at /api/messages). Not chat: the only thing sent is a video (POST /api/posts/:id/share, routes/shares.js) and
// the only reply is one of a few emoji reactions to it. There is no free text, so there is nothing to abuse.
//
//   GET    /conversations                      the inbox: who sent you what, the last activity, unread counts
//   GET    /unread                             { unread } number of conversations with something new (for the badge)
//   GET    /with/:userId?limit=40&before=<id>  the videos in the conversation with one person, oldest first
//   POST   /with/:userId/read                  mark everything read
//   POST   /:id/open                           the recipient opened a sent video (feeds the friend-taste signal)
//   PUT    /:id/reaction        { emoji }      react to a video (one per person; a new one replaces the old; the sender is told)
//   DELETE /:id/reaction
//
// Rules (CLAUDE.md: no unsolicited contact from strangers): a conversation only exists between people who follow each other
// (friends.js decides at send time); sending is routes/shares.js. Conversations with someone blocked, deleted or suspended are hidden.

const express = require('express');
const { requireUser } = require('../middleware/user');
const { wrap, parseLimit, HttpError } = require('../http');
const { getUser, getUsersMap, getPostsMap, toUser } = require('../queries');
const { videoJson } = require('../videoJson');
const { blockedEitherWay } = require('../friends');
const { findConversation, addMessage, markRead } = require('../conversations');

const REACTIONS = ['❤️', '😂', '😮', '😢', '👍', '🔥'];

module.exports = function messageRoutes({ db, clock = Date.now }) {
  const router = express.Router();

  /** The other person in a conversation row. */
  const otherOf = (conv, me) => (conv.user_lo === me ? conv.user_hi : conv.user_lo);

  /** A person who can still appear in my conversations: exists, not deleted or suspended, nobody blocked. */
  function visiblePerson(me, user) {
    return !!user && !user.deleted_at && !user.suspended_at && !blockedEitherWay(db, me, user.id);
  }

  const readAt = (conversationId, me) =>
    (db.get('SELECT read_at FROM conversation_reads WHERE conversation_id = ? AND user_id = ?', [conversationId, me]) || {}).read_at || '';

  const unreadIn = (conversationId, me) => db.get(
    'SELECT COUNT(*) AS n FROM messages WHERE conversation_id = ? AND sender_id != ? AND created_at > ?', [conversationId, me, readAt(conversationId, me)]
  ).n;

  function preview(message, me) {
    const mine = message.sender_id === me;
    if (message.kind === 'REACTION') return mine ? `You reacted ${message.body}` : `Reacted ${message.body} to your video`;
    return mine ? 'You sent a video' : 'Sent you a video';
  }

  /** The JSON for a list of VIDEO messages of one conversation, with videos and both people's reactions. */
  function messagesJson(rows, me) {
    if (!rows.length) return [];
    const ids = rows.map((m) => m.id);
    const marks = ids.map(() => '?').join(',');
    const reactions = new Map();
    db.all(`SELECT message_id, user_id, emoji FROM message_reactions WHERE message_id IN (${marks})`, ids).forEach((r) => {
      const entry = reactions.get(r.message_id) || { mine: null, theirs: null };
      if (r.user_id === me) entry.mine = r.emoji; else entry.theirs = r.emoji;
      reactions.set(r.message_id, entry);
    });
    const posts = getPostsMap(db, rows.map((m) => m.post_id));
    const playable = [...posts.values()].filter((p) => p.status === 'READY' && p.kind === 'VIDEO' && p.media_filename);
    const videos = new Map(videoJson(db, playable, me).map((v) => [v.id, v]));
    return rows.map((m) => ({
      id: m.id,
      fromMe: m.sender_id === me,
      video: videos.get(m.post_id) || null,
      createdAt: m.created_at,
      reactions: reactions.get(m.id) || { mine: null, theirs: null }
    }));
  }

  router.get('/conversations', requireUser, wrap(async (req, res) => {
    const me = req.user.id;
    const convs = db.all(
      'SELECT * FROM conversations WHERE user_lo = ? OR user_hi = ? ORDER BY last_message_at DESC LIMIT 100', [me, me]
    );
    const users = getUsersMap(db, convs.map((c) => otherOf(c, me)));
    const out = [];
    for (const c of convs) {
      const other = users.get(otherOf(c, me));
      if (!visiblePerson(me, other)) continue;
      const last = db.get("SELECT * FROM messages WHERE conversation_id = ? AND kind IN ('VIDEO', 'REACTION') ORDER BY created_at DESC, rowid DESC LIMIT 1", [c.id]);
      if (!last) continue;
      out.push({
        id: c.id,
        with: toUser(other),
        last: { kind: last.kind, fromMe: last.sender_id === me, preview: preview(last, me), createdAt: last.created_at },
        unread: unreadIn(c.id, me)
      });
    }
    res.json({ conversations: out, unreadTotal: out.filter((c) => c.unread > 0).length });
  }));

  router.get('/unread', requireUser, wrap(async (req, res) => {
    const me = req.user.id;
    const convs = db.all('SELECT * FROM conversations WHERE user_lo = ? OR user_hi = ?', [me, me]);
    const users = getUsersMap(db, convs.map((c) => otherOf(c, me)));
    const n = convs.filter((c) => visiblePerson(me, users.get(otherOf(c, me))) && unreadIn(c.id, me) > 0).length;
    res.json({ unread: n });
  }));

  function person(req) {
    const other = getUser(db, req.params.userId);
    if (!other || other.deleted_at || other.suspended_at || other.id === req.user.id || blockedEitherWay(db, req.user.id, other.id)) {
      throw new HttpError(404, 'User not found');
    }
    return other;
  }

  router.get('/with/:userId', requireUser, wrap(async (req, res) => {
    const me = req.user.id;
    const other = person(req);
    const limit = parseLimit(req.query.limit, 40, 100);
    const conv = findConversation(db, me, other.id);
    let rows = [];
    let hasMore = false;
    if (conv) {
      let before = '';
      const params = [conv.id];
      if (req.query.before) {
        const anchor = db.get('SELECT created_at, rowid AS rid FROM messages WHERE id = ? AND conversation_id = ?', [String(req.query.before), conv.id]);
        if (!anchor) throw new HttpError(400, 'Invalid cursor');
        before = 'AND (created_at < ? OR (created_at = ? AND rowid < ?))';
        params.push(anchor.created_at, anchor.created_at, anchor.rid);
      }
      rows = db.all(`SELECT * FROM messages WHERE conversation_id = ? AND kind = 'VIDEO' ${before} ORDER BY created_at DESC, rowid DESC LIMIT ?`, [...params, limit + 1]);
      hasMore = rows.length > limit;
      rows = rows.slice(0, limit).reverse();
    }
    res.json({ with: toUser(other), messages: messagesJson(rows, me), hasMore });
  }));

  router.post('/with/:userId/read', requireUser, wrap(async (req, res) => {
    const other = person(req);
    const conv = findConversation(db, req.user.id, other.id);
    if (conv) markRead(db, conv.id, req.user.id);
    res.json({ ok: true });
  }));

  /** A video message in a conversation the caller is part of (and may still see). */
  function mineMessage(req) {
    const m = db.get("SELECT * FROM messages WHERE id = ? AND kind = 'VIDEO'", [req.params.id]);
    const conv = m && db.get('SELECT * FROM conversations WHERE id = ?', [m.conversation_id]);
    const me = req.user.id;
    if (!conv || (conv.user_lo !== me && conv.user_hi !== me)) throw new HttpError(404, 'Message not found');
    if (!visiblePerson(me, getUser(db, otherOf(conv, me)))) throw new HttpError(404, 'Message not found');
    return { m, conv };
  }

  router.post('/:id/open', requireUser, wrap(async (req, res) => {
    const me = req.user.id;
    const { m } = mineMessage(req);
    if (m.sender_id !== me) {
      db.run(
        'UPDATE shares SET opened_at = ? WHERE sender_id = ? AND recipient_id = ? AND post_id = ? AND opened_at IS NULL',
        [new Date(clock()).toISOString(), m.sender_id, me, m.post_id]
      );
    }
    res.json({ ok: true });
  }));

  router.put('/:id/reaction', requireUser, wrap(async (req, res) => {
    const me = req.user.id;
    const { m, conv } = mineMessage(req);
    const emoji = req.body && req.body.emoji;
    if (!REACTIONS.includes(emoji)) throw new HttpError(400, 'That reaction is not available', { field: 'emoji' });
    db.tx(() => {
      db.run('INSERT OR REPLACE INTO message_reactions (message_id, user_id, emoji, created_at) VALUES (?, ?, ?, ?)', [
        m.id, me, emoji, new Date(clock()).toISOString()
      ]);
      // the other person is told: a reaction shows in their inbox like a message (one per person per video, the newest)
      db.run("DELETE FROM messages WHERE kind = 'REACTION' AND ref_id = ? AND sender_id = ?", [m.id, me]);
      addMessage(db, { conversationId: conv.id, senderId: me, kind: 'REACTION', body: emoji, refId: m.id });
    });
    res.json({ reactions: messagesJson([m], me)[0].reactions });
  }));

  router.delete('/:id/reaction', requireUser, wrap(async (req, res) => {
    const me = req.user.id;
    const { m } = mineMessage(req);
    db.tx(() => {
      db.run('DELETE FROM message_reactions WHERE message_id = ? AND user_id = ?', [m.id, me]);
      db.run("DELETE FROM messages WHERE kind = 'REACTION' AND ref_id = ? AND sender_id = ?", [m.id, me]);
    });
    res.json({ reactions: messagesJson([m], me)[0].reactions });
  }));

  return router;
};

module.exports.REACTIONS = REACTIONS;
