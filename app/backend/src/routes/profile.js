const express = require('express');
const { requireUser } = require('../middleware/user');
const { wrap, HttpError, parseLimit } = require('../http');
const { getUser, getPost, toUser, toPosts, getUsersMap, decodeCursor } = require('../queries');

// In-memory rate limiting map for personality summary generation:
// userId -> { count: number, day: string (YYYY-MM-DD) }
const summaryRateLimits = new Map();

function checkSummaryRateLimit(userId) {
  const today = new Date().toISOString().slice(0, 10);
  const rec = summaryRateLimits.get(userId);
  if (!rec || rec.day !== today) {
    summaryRateLimits.set(userId, { count: 1, day: today });
    return true;
  }
  if (rec.count >= 5) {
    return false;
  }
  rec.count++;
  return true;
}

function normalizeVerdict(raw) {
  if (!raw || typeof raw !== 'string') return 'Opinion';
  const v = raw.trim().toUpperCase();
  if (v === 'TRUE') return 'True';
  if (v === 'MOSTLY_TRUE' || v === 'MOSTLY TRUE') return 'Mostly True';
  if (v === 'PARTIALLY_TRUE' || v === 'PARTIALLY TRUE') return 'Partially True';
  if (v === 'FALSE') return 'False';
  if (v === 'MISLEADING') return 'Misleading';
  if (v === 'UNVERIFIED_OPINION' || v === 'OPINION') return 'Opinion';
  return raw.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

function getCredibilityAndContributions(db, userId) {
  const contribRow = db.get(
    `SELECT
       COUNT(*) AS totalPosts,
       COALESCE(SUM(CASE WHEN analysis IS NOT NULL AND analysis != '' THEN 1 ELSE 0 END), 0) AS analyzedPosts,
       COALESCE(SUM(CASE WHEN parent_id IS NULL THEN 1 ELSE 0 END), 0) AS debatesStarted,
       COALESCE(SUM(CASE WHEN parent_id IS NOT NULL THEN 1 ELSE 0 END), 0) AS totalReplies
     FROM posts
     WHERE user_id = ? AND status = 'READY'`,
    [userId]
  ) || { totalPosts: 0, analyzedPosts: 0, debatesStarted: 0, totalReplies: 0 };

  const contributions = {
    totalPosts: contribRow.totalPosts,
    analyzedPosts: contribRow.analyzedPosts,
    totalReplies: contribRow.totalReplies,
    debatesStarted: contribRow.debatesStarted
  };

  const postsWithAnalysis = db.all(
    "SELECT analysis FROM posts WHERE user_id = ? AND status = 'READY' AND analysis IS NOT NULL AND analysis != ''",
    [userId]
  );

  let analyzedVideos = 0;
  let totalClaims = 0;
  let scoreSum = 0;
  let scoreCount = 0;
  const verdictDistribution = {};

  for (const row of postsWithAnalysis) {
    let analysis = null;
    try {
      analysis = typeof row.analysis === 'string' ? JSON.parse(row.analysis) : row.analysis;
    } catch {
      continue;
    }
    if (!analysis) continue;
    analyzedVideos++;

    const claims = Array.isArray(analysis.claims) ? analysis.claims : [];
    for (const c of claims) {
      if (!c || typeof c !== 'object') continue;
      totalClaims++;

      const s = typeof c.credibilityScore === 'number' ? c.credibilityScore : parseFloat(c.credibilityScore);
      if (typeof s === 'number' && !isNaN(s)) {
        scoreSum += s;
        scoreCount++;
      }

      const v = normalizeVerdict(c.verdict);
      verdictDistribution[v] = (verdictDistribution[v] || 0) + 1;
    }
  }

  const sufficient = totalClaims >= 3;
  const score = scoreCount > 0 ? Math.round((scoreSum / scoreCount) * 100) / 100 : null;

  const credibility = {
    score,
    analyzedVideos,
    totalClaims,
    verdictDistribution,
    sufficient
  };

  return { credibility, contributions };
}

function parsePersonality(userRow) {
  let keywords = [];
  if (userRow.personality_keywords) {
    try {
      const parsed = JSON.parse(userRow.personality_keywords);
      if (Array.isArray(parsed)) keywords = parsed;
    } catch {
      keywords = [];
    }
  }

  let interests = [];
  if (userRow.interests) {
    try {
      const parsed = JSON.parse(userRow.interests);
      if (Array.isArray(parsed)) interests = parsed;
    } catch {
      interests = [];
    }
  }

  return {
    keywords,
    summary: userRow.personality_summary || null,
    summaryApproved: userRow.personality_summary_approved === 1 || userRow.personality_summary_approved === true,
    interests
  };
}

function buildProfile(db, target, viewerId) {
  const isMe = target.id === viewerId;
  const count = (sql) => db.get(sql, [target.id]).n;

  const { credibility, contributions } = getCredibilityAndContributions(db, target.id);
  const personality = parsePersonality(target);
  // An AI-written summary is a draft until its owner approves it: nobody else is shown the draft (the app tells people it stays private).
  if (!isMe && !personality.summaryApproved) personality.summary = null;

  return {
    user: toUser(target),
    bio: target.bio || null,
    followerCount: count('SELECT COUNT(*) AS n FROM follows WHERE followee_id = ?'),
    followingCount: count('SELECT COUNT(*) AS n FROM follows WHERE follower_id = ?'),
    postCount: count("SELECT COUNT(*) AS n FROM posts WHERE user_id = ? AND status = 'READY'"),
    followedByMe: !!db.get('SELECT 1 FROM follows WHERE follower_id = ? AND followee_id = ?', [viewerId, target.id]),
    blockedByMe: !!db.get('SELECT 1 FROM blocks WHERE blocker_id = ? AND blocked_id = ?', [viewerId, target.id]),
    isMe,
    personality,
    credibility,
    contributions
  };
}

function checkTargetUser(db, targetId, viewerId) {
  const target = getUser(db, targetId);
  if (!target || target.deleted_at) {
    throw new HttpError(404, 'User not found');
  }
  // 404 if target user has blocked the viewer
  if (db.get('SELECT 1 FROM blocks WHERE blocker_id = ? AND blocked_id = ?', [target.id, viewerId])) {
    throw new HttpError(404, 'User not found');
  }
  return target;
}

module.exports = function profileRoutes({ db, gemini }) {
  const router = express.Router();

  // 1. GET /api/users/:id/profile
  router.get('/users/:id/profile', requireUser, wrap(async (req, res) => {
    const target = checkTargetUser(db, req.params.id, req.user.id);
    res.json(buildProfile(db, target, req.user.id));
  }));

  // 2. GET /api/users/:id/videos
  router.get('/users/:id/videos', requireUser, wrap(async (req, res) => {
    const target = checkTargetUser(db, req.params.id, req.user.id);
    const limit = parseLimit(req.query.limit, 20, 50);

    let cursorCreatedAt = null;
    if (req.query.cursor) {
      const decoded = decodeCursor(req.query.cursor);
      cursorCreatedAt = decoded ? decoded.createdAt : String(req.query.cursor);
    }

    const rows = db.all(
      `SELECT * FROM posts
       WHERE user_id = ? AND status = 'READY'
         AND (? IS NULL OR created_at < ?)
       ORDER BY created_at DESC
       LIMIT ?`,
      [target.id, cursorCreatedAt, cursorCreatedAt, limit + 1]
    );

    const hasMore = rows.length > limit;
    const pageRows = hasMore ? rows.slice(0, limit) : rows;
    const nextCursor = (hasMore && pageRows.length) ? pageRows[pageRows.length - 1].created_at : null;

    const posts = toPosts(db, pageRows, req.user.id);
    const actor = toUser(target);

    res.json({
      posts: posts.map((p) => ({
        actor,
        post: p,
        ...p
      })),
      nextCursor
    });
  }));

  // 3. PATCH /api/me/profile
  router.patch('/me/profile', requireUser, wrap(async (req, res) => {
    const body = req.body || {};
    const updates = [];
    const params = [];

    if (body.fullName !== undefined) {
      if (typeof body.fullName !== 'string') {
        throw new HttpError(400, 'fullName must be a string', { field: 'fullName' });
      }
      const name = body.fullName.trim();
      if (name.length < 1 || name.length > 80) {
        throw new HttpError(400, 'Full name must be between 1 and 80 characters', { field: 'fullName' });
      }
      updates.push('full_name = ?');
      params.push(name);
    }

    if (body.bio !== undefined) {
      if (body.bio !== null && typeof body.bio !== 'string') {
        throw new HttpError(400, 'bio must be a string', { field: 'bio' });
      }
      const bio = body.bio === null ? null : body.bio.trim();
      if (bio !== null && bio.length > 300) {
        throw new HttpError(400, 'Bio must be at most 300 characters', { field: 'bio' });
      }
      updates.push('bio = ?');
      params.push(bio);
    }

    if (body.personalityKeywords !== undefined) {
      if (!Array.isArray(body.personalityKeywords)) {
        throw new HttpError(400, 'personalityKeywords must be an array of strings', { field: 'personalityKeywords' });
      }
      if (body.personalityKeywords.length > 8) {
        throw new HttpError(400, 'personalityKeywords can contain at most 8 keywords', { field: 'personalityKeywords' });
      }
      const cleanKeywords = [];
      for (const kw of body.personalityKeywords) {
        if (typeof kw !== 'string') {
          throw new HttpError(400, 'Each keyword must be a string', { field: 'personalityKeywords' });
        }
        const trimmed = kw.trim();
        if (trimmed.length < 1 || trimmed.length > 30) {
          throw new HttpError(400, 'Each keyword must be between 1 and 30 characters', { field: 'personalityKeywords' });
        }
        cleanKeywords.push(trimmed);
      }
      updates.push('personality_keywords = ?');
      params.push(JSON.stringify(cleanKeywords));
    }

    if (body.personalitySummary !== undefined) {
      if (body.personalitySummary !== null && typeof body.personalitySummary !== 'string') {
        throw new HttpError(400, 'personalitySummary must be a string', { field: 'personalitySummary' });
      }
      const summary = body.personalitySummary === null ? null : body.personalitySummary.trim();
      if (summary !== null && summary.length > 500) {
        throw new HttpError(400, 'personalitySummary must be at most 500 characters', { field: 'personalitySummary' });
      }
      updates.push('personality_summary = ?');
      params.push(summary);
    }

    if (body.personalitySummaryApproved !== undefined) {
      if (typeof body.personalitySummaryApproved !== 'boolean') {
        throw new HttpError(400, 'personalitySummaryApproved must be a boolean', { field: 'personalitySummaryApproved' });
      }
      updates.push('personality_summary_approved = ?');
      params.push(body.personalitySummaryApproved ? 1 : 0);
    }

    if (body.interests !== undefined) {
      if (!Array.isArray(body.interests)) {
        throw new HttpError(400, 'interests must be an array of strings', { field: 'interests' });
      }
      if (body.interests.length > 10) {
        throw new HttpError(400, 'interests can contain at most 10 items', { field: 'interests' });
      }
      const cleanInterests = [];
      for (const item of body.interests) {
        if (typeof item !== 'string') {
          throw new HttpError(400, 'Each interest must be a string', { field: 'interests' });
        }
        const trimmed = item.trim();
        if (trimmed.length < 1 || trimmed.length > 40) {
          throw new HttpError(400, 'Each interest must be between 1 and 40 characters', { field: 'interests' });
        }
        cleanInterests.push(trimmed);
      }
      updates.push('interests = ?');
      params.push(JSON.stringify(cleanInterests));
    }

    if (updates.length > 0) {
      params.push(req.user.id);
      db.run(`UPDATE users SET ${updates.join(', ')} WHERE id = ?`, params);
    }

    const updated = getUser(db, req.user.id);
    res.json(buildProfile(db, updated, req.user.id));
  }));

  // 4. POST /api/me/personality/generate-summary
  router.post('/me/personality/generate-summary', requireUser, wrap(async (req, res) => {
    const keywords = req.body && req.body.keywords;
    if (!Array.isArray(keywords) || keywords.length < 1 || keywords.length > 8) {
      throw new HttpError(400, 'keywords must be an array of 1 to 8 strings', { field: 'keywords' });
    }

    const cleanKeywords = [];
    for (const kw of keywords) {
      if (typeof kw !== 'string') {
        throw new HttpError(400, 'Each keyword must be a string', { field: 'keywords' });
      }
      const trimmed = kw.trim();
      if (trimmed.length < 1 || trimmed.length > 30) {
        throw new HttpError(400, 'Each keyword must be between 1 and 30 characters', { field: 'keywords' });
      }
      cleanKeywords.push(trimmed);
    }

    if (!checkSummaryRateLimit(req.user.id)) {
      throw new HttpError(429, 'Rate limit exceeded: max 5 personality summaries per day');
    }

    let summary = null;
    try {
      if (gemini && typeof gemini.generatePersonalitySummary === 'function') {
        summary = await gemini.generatePersonalitySummary(cleanKeywords);
      }
    } catch (err) {
      console.warn(`[Personality Summary] Gemini generation failed: ${err.message}`);
    }

    if (!summary) {
      throw new HttpError(503, 'AI personality summary generation is currently unavailable. Please try again later.');
    }

    res.json({ summary });
  }));

  // 5. GET /api/me/bookmarks
  router.get('/me/bookmarks', requireUser, wrap(async (req, res) => {
    const me = req.user.id;
    const rows = db.all(
      `SELECT b.created_at AS saved_at, p.*
       FROM bookmarks b
       JOIN posts p ON p.id = b.post_id
       WHERE b.user_id = ? AND p.status = 'READY'
       ORDER BY b.created_at DESC`,
      [me]
    );

    const posts = toPosts(db, rows, me);
    const users = getUsersMap(db, rows.map((r) => r.user_id));

    const bookmarks = rows.map((row, i) => ({
      actor: toUser(users.get(row.user_id)),
      post: posts[i],
      savedAt: row.saved_at
    }));

    res.json({ bookmarks });
  }));

  // 6. POST /api/me/bookmarks/:postId
  router.post('/me/bookmarks/:postId', requireUser, wrap(async (req, res) => {
    const post = getPost(db, req.params.postId);
    if (!post || post.status !== 'READY') {
      throw new HttpError(404, 'Post not found');
    }

    const me = req.user.id;
    db.run(
      `INSERT OR IGNORE INTO bookmarks (user_id, post_id, created_at) VALUES (?, ?, ?)`,
      [me, post.id, new Date().toISOString()]
    );

    res.json({ bookmarked: true });
  }));

  // 7. DELETE /api/me/bookmarks/:postId
  router.delete('/me/bookmarks/:postId', requireUser, wrap(async (req, res) => {
    const me = req.user.id;
    db.run('DELETE FROM bookmarks WHERE user_id = ? AND post_id = ?', [me, req.params.postId]);
    res.json({ bookmarked: false });
  }));

  // 8. GET /api/users/:id/followers
  router.get('/users/:id/followers', requireUser, wrap(async (req, res) => {
    const target = checkTargetUser(db, req.params.id, req.user.id);
    const limit = parseLimit(req.query.limit, 20, 50);

    let cursor = null;
    if (req.query.cursor) {
      const decoded = decodeCursor(req.query.cursor);
      cursor = decoded ? decoded.createdAt : String(req.query.cursor);
    }

    const rows = db.all(
      `SELECT f.follower_id AS user_id, f.created_at
       FROM follows f
       JOIN users u ON u.id = f.follower_id
       WHERE f.followee_id = ? AND u.deleted_at IS NULL
         AND (? IS NULL OR f.created_at < ?)
       ORDER BY f.created_at DESC
       LIMIT ?`,
      [target.id, cursor, cursor, limit + 1]
    );

    const hasMore = rows.length > limit;
    const pageRows = hasMore ? rows.slice(0, limit) : rows;
    const nextCursor = (hasMore && pageRows.length) ? pageRows[pageRows.length - 1].created_at : null;

    const userIds = pageRows.map((r) => r.user_id);
    const userMap = getUsersMap(db, userIds);

    const marks = userIds.map(() => '?').join(',');
    const followedSet = userIds.length
      ? new Set(
          db.all(
            `SELECT followee_id FROM follows WHERE follower_id = ? AND followee_id IN (${marks})`,
            [req.user.id, ...userIds]
          ).map((r) => r.followee_id)
        )
      : new Set();

    const users = pageRows.map((r) => ({
      user: toUser(userMap.get(r.user_id)),
      followedByMe: followedSet.has(r.user_id)
    }));

    res.json({ users, nextCursor });
  }));

  // 9. GET /api/users/:id/following
  router.get('/users/:id/following', requireUser, wrap(async (req, res) => {
    const target = checkTargetUser(db, req.params.id, req.user.id);
    const limit = parseLimit(req.query.limit, 20, 50);

    let cursor = null;
    if (req.query.cursor) {
      const decoded = decodeCursor(req.query.cursor);
      cursor = decoded ? decoded.createdAt : String(req.query.cursor);
    }

    const rows = db.all(
      `SELECT f.followee_id AS user_id, f.created_at
       FROM follows f
       JOIN users u ON u.id = f.followee_id
       WHERE f.follower_id = ? AND u.deleted_at IS NULL
         AND (? IS NULL OR f.created_at < ?)
       ORDER BY f.created_at DESC
       LIMIT ?`,
      [target.id, cursor, cursor, limit + 1]
    );

    const hasMore = rows.length > limit;
    const pageRows = hasMore ? rows.slice(0, limit) : rows;
    const nextCursor = (hasMore && pageRows.length) ? pageRows[pageRows.length - 1].created_at : null;

    const userIds = pageRows.map((r) => r.user_id);
    const userMap = getUsersMap(db, userIds);

    const marks = userIds.map(() => '?').join(',');
    const followedSet = userIds.length
      ? new Set(
          db.all(
            `SELECT followee_id FROM follows WHERE follower_id = ? AND followee_id IN (${marks})`,
            [req.user.id, ...userIds]
          ).map((r) => r.followee_id)
        )
      : new Set();

    const users = pageRows.map((r) => ({
      user: toUser(userMap.get(r.user_id)),
      followedByMe: followedSet.has(r.user_id)
    }));

    res.json({ users, nextCursor });
  }));

  return router;
};
