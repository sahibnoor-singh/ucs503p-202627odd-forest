// What to do today: the question of the day, the answers to it, and the opinions still waiting for a first reply.
// These are what a new person sees on Home even before they follow anyone, and they are why a returning person has a reason to open it.

const express = require('express');
const { requireUser } = require('../middleware/user');
const { wrap, parseLimit } = require('../http');
const { toItems } = require('../queries');
const { dayKey, promptFor } = require('../prompts');

const REPLY_WANTED_DAYS = 7;
const REPLY_WANTED_MAX_REPLIES = 2; // an opinion with this many replies or fewer still counts as waiting

const NOT_BLOCKED = `AND p.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?)
         AND p.user_id NOT IN (SELECT blocker_id FROM blocks WHERE blocked_id = ?)`;

module.exports = function todayRoutes({ db, clock = Date.now, promptOffsetMin = 330 }) {
  const router = express.Router();

  // GET /api/prompts/today -> { day, text, topic, answerCount, answered }
  router.get('/prompts/today', requireUser, wrap(async (req, res) => {
    const day = dayKey(clock(), promptOffsetMin);
    const prompt = promptFor(day);
    const answerCount = db.get(
      `SELECT COUNT(*) AS n FROM posts p JOIN users u ON u.id = p.user_id
       WHERE p.prompt_day = ? AND p.parent_id IS NULL AND p.status = 'READY' AND u.deleted_at IS NULL ${NOT_BLOCKED}`,
      [day, req.user.id, req.user.id]
    ).n;
    const answered = !!db.get('SELECT 1 AS x FROM posts WHERE prompt_day = ? AND user_id = ? AND parent_id IS NULL LIMIT 1', [day, req.user.id]);
    res.json({ ...prompt, answerCount, answered });
  }));

  // GET /api/prompts/today/answers?limit=10 -> { items }   People's video answers to today's question, newest first.
  router.get('/prompts/today/answers', requireUser, wrap(async (req, res) => {
    const day = dayKey(clock(), promptOffsetMin);
    const limit = parseLimit(req.query.limit, 10, 30);
    const rows = db.all(
      `SELECT p.* FROM posts p JOIN users u ON u.id = p.user_id
       WHERE p.prompt_day = ? AND p.parent_id IS NULL AND p.status = 'READY' AND u.deleted_at IS NULL AND u.suspended_at IS NULL ${NOT_BLOCKED}
       ORDER BY p.created_at DESC, p.id DESC LIMIT ?`,
      [day, req.user.id, req.user.id, limit]
    );
    res.json({ items: toItems(db, rows, req.user.id) });
  }));

  // GET /api/reply-wanted?limit=5 -> { items }
  // Recent video opinions (not yours, not from people you blocked or who blocked you) that nobody has answered yet, or only once or
  // twice, and that you have not answered. The ones with fewest replies come first, then the newest. Answering one of these is the
  // quickest way to give someone their first reply, which is the thing that makes a person come back.
  router.get('/reply-wanted', requireUser, wrap(async (req, res) => {
    const me = req.user.id;
    const limit = parseLimit(req.query.limit, 5, 20);
    const since = new Date(clock() - REPLY_WANTED_DAYS * 86400000).toISOString();
    const rows = db.all(
      `SELECT * FROM (
         SELECT p.*,
                (SELECT COUNT(*) FROM posts r WHERE r.root_id = p.id AND r.id != p.id AND r.status = 'READY') AS reply_n
         FROM posts p JOIN users u ON u.id = p.user_id
         WHERE p.parent_id IS NULL AND p.kind = 'VIDEO' AND p.status = 'READY' AND p.media_filename IS NOT NULL
           AND p.user_id != ? AND p.created_at > ?
           AND u.deleted_at IS NULL AND u.suspended_at IS NULL
           AND NOT EXISTS (SELECT 1 FROM posts m WHERE m.root_id = p.id AND m.user_id = ?)
           ${NOT_BLOCKED}
       ) WHERE reply_n <= ?
       ORDER BY reply_n ASC, created_at DESC, id DESC LIMIT ?`,
      [me, since, me, me, me, REPLY_WANTED_MAX_REPLIES, limit]
    );
    res.json({ items: toItems(db, rows, me) });
  }));

  return router;
};
