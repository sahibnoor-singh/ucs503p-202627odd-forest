// The JSON the reels screens parse (docs/api.md "Video"), for many posts in a fixed number of queries.
// Shared by Discover and search so both always describe a video the same way.

const { parseAnalysis, getUsersMap } = require('./queries');

const marks = (n) => new Array(n).fill('?').join(',');

/** 0-100 from the AI fact-check: mean of the per-claim scores, 50 when nothing was scored. */
function credibilityOf(analysis) {
  const scores = ((analysis && analysis.claims) || [])
    .map((c) => Number(c && c.credibilityScore))
    .filter((n) => Number.isFinite(n));
  if (!scores.length) return 50;
  const avg = scores.reduce((a, b) => a + b, 0) / scores.length;
  return Math.max(0, Math.min(100, Math.round(avg > 0 && avg <= 1 ? avg * 100 : avg)));
}

/** The JSON the reels screens parse, for many posts in a fixed number of queries. */
function videoJson(db, rows, me) {
  if (!rows.length) return [];
  const ids = [...new Set(rows.map((r) => r.id))];
  const m = marks(ids.length);
  const users = getUsersMap(db, rows.map((r) => r.user_id));
  const likes = new Map(db.all(`SELECT post_id, COUNT(*) n FROM likes WHERE post_id IN (${m}) GROUP BY post_id`, ids)
    .map((r) => [r.post_id, r.n]));
  const liked = new Set(me
    ? db.all(`SELECT post_id FROM likes WHERE user_id = ? AND post_id IN (${m})`, [me, ...ids]).map((r) => r.post_id)
    : []);
  const sides = new Map(me
    ? db.all(`SELECT post_id, side FROM viewer_opinions WHERE user_id = ? AND post_id IN (${m})`, [me, ...ids])
        .map((r) => [r.post_id, r.side])
    : []);
  const followed = new Set(me
    ? db.all(`SELECT followee_id FROM follows WHERE follower_id = ? AND followee_id IN (${marks(new Set(rows.map((r) => r.user_id)).size)})`,
        [me, ...new Set(rows.map((r) => r.user_id))]).map((r) => r.followee_id)
    : []);
  const replies = new Map();
  db.all(
    `SELECT parent_id, stance, COUNT(*) n FROM posts
     WHERE parent_id IN (${m}) AND status = 'READY' AND kind = 'VIDEO' GROUP BY parent_id, stance`, ids
  ).forEach((r) => {
    const t = replies.get(r.parent_id) || { all: 0, FOR: 0, AGAINST: 0 };
    t.all += r.n;
    if (r.stance === 'FOR' || r.stance === 'AGAINST') t[r.stance] += r.n;
    replies.set(r.parent_id, t);
  });
  const views = new Map(db.all(
    `SELECT post_id, COUNT(*) t, COALESCE(SUM(completed), 0) c FROM post_views WHERE post_id IN (${m}) GROUP BY post_id`, ids
  ).map((r) => [r.post_id, r]));

  return rows.map((row) => {
    const analysis = parseAnalysis(row);
    const author = users.get(row.user_id);
    const tally = replies.get(row.id) || { all: 0, FOR: 0, AGAINST: 0 };
    const v = views.get(row.id);
    return {
      id: row.id,
      title: row.title || null,
      caption: row.title || row.body || '',
      filename: row.media_filename || '',
      coverUrl: row.media_filename && row.cover_filename ? `/uploads/${row.cover_filename}` : null, // the picture for the grid tile and the poster
      status: row.status.toLowerCase(),
      role: row.parent_id ? 'CHILD' : 'PARENT',
      parentVideoId: row.parent_id || null,
      stance: row.stance,
      credibility: credibilityOf(analysis),
      durationS: 0,
      userId: author.username,
      authorId: row.user_id, // the account's id (userId is the username): what block and report need
      authorAvatarUrl: author.avatar_url || null, // the profile picture, shown beside the name on a video
      authorFollowed: followed.has(row.user_id), // does the viewer follow the author (the Follow button on a video is hidden when so)
      userName: author.username,
      isBot: !!author.is_bot,
      createdAt: row.created_at,
      likeCount: likes.get(row.id) || 0,
      replyCount: tally.all,
      forCount: tally.FOR,
      againstCount: tally.AGAINST,
      viewerSide: sides.get(row.id) || null,
      liked: liked.has(row.id),
      totalViews: v ? v.t : 0,
      completedViews: v ? v.c : 0,
      transcript: analysis
    };
  });
}

module.exports = { videoJson, credibilityOf };
