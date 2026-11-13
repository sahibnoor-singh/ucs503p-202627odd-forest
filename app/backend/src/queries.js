// Reads + the JSON shapes the API returns (see docs/api.md).

const { v4: uuid } = require('uuid');

const nowIso = () => new Date().toISOString();

function getUser(db, id) {
  return db.get('SELECT * FROM users WHERE id = ?', [id]);
}

function getUserByName(db, username) {
  return db.get('SELECT * FROM users WHERE username = ? COLLATE NOCASE', [username]);
}

function getPost(db, id) {
  return db.get('SELECT * FROM posts WHERE id = ?', [id]);
}

function toUser(u) {
  return {
    id: u.id,
    username: u.username,
    fullName: u.full_name,
    avatarUrl: u.avatar_url || null,
    isBot: !!u.is_bot
  };
}

function parseAnalysis(row) {
  if (!row.analysis) return null;
  try {
    return JSON.parse(row.analysis);
  } catch {
    return { transcript: row.analysis };
  }
}

/** Text the AI should compare a reply against: transcript, else summary, else the post's own words. */
function contextOf(row) {
  const a = parseAnalysis(row);
  const text = (a && (a.transcript || a.overallSummary)) || row.body || row.title || '';
  return text.slice(0, 2000) || null;
}

const marks = (n) => new Array(n).fill('?').join(',');
const unique = (list) => [...new Set(list.filter(Boolean))];

/**
 * Reference implementation of "how many replies are below this post" (direct +
 * indirect, READY only). One recursive query per post, so it is slow in bulk;
 * the app uses threadCountsBatch. Kept so tests can prove the two agree.
 */
function threadCounts(db, postId) {
  const r = db.get(
    `WITH RECURSIVE d(id, stance) AS (
       SELECT id, stance FROM posts WHERE parent_id = ? AND status = 'READY'
       UNION ALL
       SELECT p.id, p.stance FROM posts p JOIN d ON p.parent_id = d.id WHERE p.status = 'READY'
     )
     SELECT COUNT(*) AS n,
            COALESCE(SUM(CASE WHEN stance = 'FOR' THEN 1 ELSE 0 END), 0) AS f,
            COALESCE(SUM(CASE WHEN stance = 'AGAINST' THEN 1 ELSE 0 END), 0) AS a
     FROM d`,
    [postId]
  );
  return { replyCount: r.n, forCount: r.f, againstCount: r.a };
}

/**
 * threadCounts for many posts in two queries.
 * - Opinions (depth 0): every reply carries root_id, so it is one indexed GROUP BY.
 *   (A reply can only be added under a READY post, so a READY reply always has an
 *   all-READY chain above it, which makes the root_id shortcut exact.)
 * - Replies: one recursive query seeded with all of them.
 * @returns Map(postId -> {replyCount, forCount, againstCount})
 */
function threadCountsBatch(db, rows) {
  const out = new Map(rows.map((r) => [r.id, { replyCount: 0, forCount: 0, againstCount: 0 }]));
  const agg = `COUNT(*) AS n,
               COALESCE(SUM(CASE WHEN stance = 'FOR' THEN 1 ELSE 0 END), 0) AS f,
               COALESCE(SUM(CASE WHEN stance = 'AGAINST' THEN 1 ELSE 0 END), 0) AS a`;
  const fill = (list) => list.forEach((r) => {
    out.set(r.id, { replyCount: r.n, forCount: r.f, againstCount: r.a });
  });

  const roots = unique(rows.filter((r) => !r.parent_id).map((r) => r.id));
  if (roots.length) {
    fill(db.all(
      `SELECT root_id AS id, ${agg} FROM posts
       WHERE root_id IN (${marks(roots.length)}) AND id != root_id AND status = 'READY'
       GROUP BY root_id`,
      roots
    ));
  }
  const replies = unique(rows.filter((r) => r.parent_id).map((r) => r.id));
  if (replies.length) {
    fill(db.all(
      `WITH RECURSIVE d(anc, id, stance) AS (
         SELECT parent_id, id, stance FROM posts
           WHERE parent_id IN (${marks(replies.length)}) AND status = 'READY'
         UNION ALL
         SELECT d.anc, p.id, p.stance FROM posts p JOIN d ON p.parent_id = d.id WHERE p.status = 'READY'
       )
       SELECT anc AS id, ${agg} FROM d GROUP BY anc`,
      replies
    ));
  }
  return out;
}

function getUsersMap(db, ids) {
  const list = unique(ids);
  const map = new Map();
  if (!list.length) return map;
  db.all(`SELECT * FROM users WHERE id IN (${marks(list.length)})`, list).forEach((u) => map.set(u.id, u));
  return map;
}

function getPostsMap(db, ids) {
  const list = unique(ids);
  const map = new Map();
  if (!list.length) return map;
  db.all(`SELECT * FROM posts WHERE id IN (${marks(list.length)})`, list).forEach((p) => map.set(p.id, p));
  return map;
}

function postJson(row, { likeCount, likedByMe, counts, detail, room }) {
  const analysis = parseAnalysis(row);
  const post = {
    id: row.id,
    kind: row.kind,
    parentId: row.parent_id || null,
    rootId: row.root_id,
    depth: row.depth,
    title: row.title || null,
    body: row.body || null,
    mediaUrl: row.media_filename ? `/uploads/${row.media_filename}` : null,
    coverUrl: row.media_filename && row.cover_filename ? `/uploads/${row.cover_filename}` : null,
    stance: row.stance,
    status: row.status,
    summary: (analysis && analysis.overallSummary) || null,
    hasCaptions: !!(analysis && Array.isArray(analysis.captions) && analysis.captions.length),
    createdAt: row.created_at,
    promptDay: row.prompt_day || null,
    room: room || null,
    roomStance: row.room_stance || null,
    likeCount,
    likedByMe,
    ...counts
  };
  if (detail) post.analysis = analysis;
  return post;
}

/** Post JSON for many rows with a fixed number of queries (not per row). */
function toPosts(db, rows, meId, { detail = false } = {}) {
  if (!rows.length) return [];
  const ids = unique(rows.map((r) => r.id));
  const likeCounts = new Map(
    db.all(`SELECT post_id, COUNT(*) AS n FROM likes WHERE post_id IN (${marks(ids.length)}) GROUP BY post_id`, ids)
      .map((r) => [r.post_id, r.n])
  );
  const liked = new Set(
    meId
      ? db.all(`SELECT post_id FROM likes WHERE user_id = ? AND post_id IN (${marks(ids.length)})`, [meId, ...ids])
          .map((r) => r.post_id)
      : []
  );
  const counts = threadCountsBatch(db, rows);
  const roomIds = unique(rows.map((r) => r.room_id));
  const rooms = new Map(roomIds.length
    ? db.all(`SELECT id, name FROM rooms WHERE id IN (${marks(roomIds.length)})`, roomIds).map((r) => [r.id, { id: r.id, name: r.name }])
    : []);
  return rows.map((row) => postJson(row, {
    likeCount: likeCounts.get(row.id) || 0,
    likedByMe: liked.has(row.id),
    counts: counts.get(row.id),
    room: row.room_id ? rooms.get(row.room_id) : null,
    detail
  }));
}

function toPost(db, row, meId, opts) {
  return toPosts(db, [row], meId, opts)[0];
}

function feedType(row) {
  if (!row.parent_id) return 'POST';
  return row.kind === 'VIDEO' ? 'VIDEO_REPLY' : 'TEXT_REPLY';
}

/**
 * The cards a client renders: each post, who wrote it, the post it directly
 * replies to (with its author), and the root of the debate when that is a
 * different post than the parent. Fixed number of queries for any page size.
 */
function toItems(db, rows, meId, opts) {
  if (!rows.length) return [];
  const parents = getPostsMap(db, rows.map((r) => r.parent_id));
  const rootIds = rows.filter((r) => r.parent_id && r.root_id !== r.parent_id).map((r) => r.root_id);
  const roots = getPostsMap(db, rootIds);

  // everything that needs full post JSON: the page itself + the parents shown under it
  const parentRows = [...parents.values()];
  const mainPosts = toPosts(db, rows, meId, opts);
  const parentPosts = new Map(toPosts(db, parentRows, meId).map((p) => [p.id, p]));

  const users = getUsersMap(db, [
    ...rows.map((r) => r.user_id),
    ...parentRows.map((r) => r.user_id),
    ...[...roots.values()].map((r) => r.user_id)
  ]);

  return rows.map((row, i) => {
    const item = {
      type: feedType(row),
      actor: toUser(users.get(row.user_id)),
      post: mainPosts[i],
      parent: null,
      root: null,
      createdAt: row.created_at
    };
    if (row.parent_id) {
      const parent = parents.get(row.parent_id);
      item.parent = { actor: toUser(users.get(parent.user_id)), post: parentPosts.get(parent.id) };
      if (row.root_id !== row.parent_id) {
        const root = roots.get(row.root_id);
        item.root = { id: root.id, username: users.get(root.user_id).username, title: root.title || null };
      }
    }
    return item;
  });
}

function toItem(db, row, meId, opts) {
  return toItems(db, [row], meId, opts)[0];
}

function isBlockedEitherWay(db, a, b) {
  return !!db.get(
    `SELECT 1 AS x FROM blocks
     WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)`,
    [a, b, b, a]
  );
}

const encodeCursor = (row) =>
  Buffer.from(`${row.created_at}|${row.id}`).toString('base64url');

function decodeCursor(cursor) {
  try {
    const [createdAt, id] = Buffer.from(String(cursor), 'base64url').toString().split('|');
    return createdAt && id ? { createdAt, id } : null;
  } catch {
    return null;
  }
}

module.exports = {
  uuid, nowIso, getUser, getUserByName, getPost, toUser, toPost, toPosts, toItem, toItems,
  parseAnalysis, contextOf, threadCounts, threadCountsBatch, getUsersMap, getPostsMap, isBlockedEitherWay,
  encodeCursor, decodeCursor
};
