const express = require('express');
const { requireUser } = require('../middleware/user');
const { wrap, parseLimit } = require('../http');
const { toItems, encodeCursor, decodeCursor } = require('../queries');

module.exports = function homeRoutes({ db }) {
  const router = express.Router();

  // GET /api/home?limit=20&cursor=...
  // Posts and replies by people the caller follows, newest first.
  router.get('/', requireUser, wrap(async (req, res) => {
    const me = req.user.id;
    const limit = parseLimit(req.query.limit, 20, 50);
    const cursor = req.query.cursor ? decodeCursor(req.query.cursor) : null;
    if (req.query.cursor && !cursor) return res.status(400).json({ error: 'Invalid cursor' });

    // The block checks are real work on every candidate row, so only add them for people who have blocks.
    const hasBlocks = !!db.get('SELECT 1 AS x FROM blocks WHERE blocker_id = ? LIMIT 1', [me]);
    const params = [me];
    let blockSql = '';
    if (hasBlocks) {
      blockSql = `AND p.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?)
         AND (p.parent_id IS NULL OR
              (SELECT user_id FROM posts WHERE id = p.parent_id)
                NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?))`;
      params.push(me, me);
    }
    let cursorSql = '';
    if (cursor) {
      cursorSql = 'AND (p.created_at < ? OR (p.created_at = ? AND p.id < ?))';
      params.push(cursor.createdAt, cursor.createdAt, cursor.id);
    }
    params.push(limit + 1);

    const rows = db.all(
      `SELECT p.* FROM posts p
       WHERE p.status = 'READY'
         AND p.user_id IN (SELECT followee_id FROM follows WHERE follower_id = ?)
         ${blockSql}
         ${cursorSql}
       ORDER BY p.created_at DESC, p.id DESC
       LIMIT ?`,
      params
    );

    const page = rows.slice(0, limit);
    res.json({
      items: toItems(db, page, me),
      nextCursor: rows.length > limit ? encodeCursor(page[page.length - 1]) : null
    });
  }));

  return router;
};
