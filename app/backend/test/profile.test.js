const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const stream = require('stream');
const { v4: uuid } = require('uuid');

const { openDb } = require('../src/db');
const { createApp } = require('../src/app');
const { createProvider } = require('../src/auth/providers');
const { createMailer } = require('../src/auth/mailers');

const TEST_SECRET = 'test-secret-for-unit-tests-0123456789';

function inMemoryApi(app) {
  return function api(method, url, { user, json } = {}) {
    return new Promise((resolve, reject) => {
      const bodyStr = json !== undefined ? JSON.stringify(json) : null;
      const req = new stream.Readable({
        read() {
          if (bodyStr) this.push(bodyStr);
          this.push(null);
        }
      });
      req.method = method;
      req.url = url;
      const sock = new stream.Duplex({ read() {}, write(c, e, cb) { cb(); } });
      sock.remoteAddress = '127.0.0.1';
      req.socket = sock;
      req.headers = {};
      if (user) req.headers['x-dev-user'] = user;
      if (bodyStr) {
        req.headers['content-type'] = 'application/json';
        req.headers['content-length'] = Buffer.byteLength(bodyStr);
      }

      const res = new stream.Writable();
      res.statusCode = 200;
      res._headers = {};
      res.setHeader = (k, v) => { res._headers[k.toLowerCase()] = v; };
      res.getHeader = (k) => res._headers[k.toLowerCase()];
      res.get = res.getHeader;
      res.set = res.setHeader;
      const chunks = [];
      res._write = (chunk, enc, cb) => {
        chunks.push(chunk);
        cb();
      };
      res.writeHead = (code, headers) => {
        res.statusCode = code;
        if (headers) Object.assign(res._headers, headers);
      };
      res.end = function (chunk) {
        if (chunk) chunks.push(Buffer.from(chunk));
        const text = Buffer.concat(chunks).toString('utf8');
        let data = text;
        try { data = JSON.parse(text); } catch { /* not JSON */ }
        resolve({ status: res.statusCode, data, text, headers: res._headers });
      };

      app(req, res);
    });
  };
}

async function setupTestApp(opts = {}) {
  const db = await openDb();
  const uploadsDir = fs.mkdtempSync(path.join(os.tmpdir(), 'forest-profile-test-'));
  const gemini = opts.gemini || {
    generatePersonalitySummary: async (keywords) => `A thoughtful and energetic person focused on ${keywords.join(', ')}.`
  };
  const app = createApp({
    db,
    uploadsDir,
    jwtSecret: TEST_SECRET,
    otpProvider: createProvider('memory'),
    emailProvider: createMailer('memory'),
    allowDevUser: true,
    gemini
  });
  const api = inMemoryApi(app);

  return {
    db,
    app,
    api,
    gemini,
    close: async () => {
      db.close();
      fs.rmSync(uploadsDir, { recursive: true, force: true });
    }
  };
}

const iso = (minsAgo = 0) => new Date(Date.now() - minsAgo * 60000).toISOString();

function createUser(db, username, extra = {}) {
  const id = uuid();
  db.run(
    `INSERT INTO users (id, username, full_name, bio, is_bot, personality_keywords, personality_summary, personality_summary_approved, interests, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      id,
      username,
      extra.fullName || username,
      extra.bio || null,
      extra.bot ? 1 : 0,
      extra.personalityKeywords ? JSON.stringify(extra.personalityKeywords) : null,
      extra.personalitySummary || null,
      extra.personalitySummaryApproved ? 1 : 0,
      extra.interests ? JSON.stringify(extra.interests) : null,
      iso(extra.minsAgo || 0)
    ]
  );
  return id;
}

function createPost(db, {
  userId,
  kind = 'VIDEO',
  parentId = null,
  title = null,
  body = null,
  status = 'READY',
  analysis = null,
  minsAgo = 0
}) {
  const id = uuid();
  const parent = parentId ? db.get('SELECT * FROM posts WHERE id = ?', [parentId]) : null;
  db.run(
    `INSERT INTO posts (id, user_id, kind, parent_id, root_id, depth, title, body, media_filename, stance, status, analysis, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      id,
      userId,
      kind,
      parentId,
      parent ? parent.root_id : id,
      parent ? parent.depth + 1 : 0,
      title,
      body,
      kind === 'VIDEO' ? 'media.mp4' : null,
      parent ? 'UNRESOLVED' : 'PARENT',
      status,
      analysis ? JSON.stringify(analysis) : null,
      iso(minsAgo)
    ]
  );
  return id;
}

test('GET /api/users/:id/profile: basic stats, personality, contributions, and credibility', async () => {
  const env = await setupTestApp();
  try {
    const me = createUser(env.db, 'me', { fullName: 'My Name', bio: 'Hello world' });
    const userA = createUser(env.db, 'alice', {
      fullName: 'Alice Smith',
      bio: 'Debater and thinker',
      personalityKeywords: ['analytical', 'curious'],
      personalitySummary: 'A curious thinker who loves facts.',
      personalitySummaryApproved: true,
      interests: ['politics', 'tech']
    });

    // Alice starts 2 debates, has 1 reply, 1 processing post
    const p1 = createPost(env.db, {
      userId: userA,
      title: 'Debate 1',
      minsAgo: 10,
      analysis: {
        claims: [
          { claim: 'Claim 1', verdict: 'TRUE', credibilityScore: 0.9 },
          { claim: 'Claim 2', verdict: 'MOSTLY_TRUE', credibilityScore: 0.8 }
        ]
      }
    });
    const p2 = createPost(env.db, {
      userId: userA,
      title: 'Debate 2',
      minsAgo: 5,
      analysis: {
        claims: [
          { claim: 'Claim 3', verdict: 'MISLEADING', credibilityScore: 0.4 },
          { claim: 'Claim 4', verdict: 'UNVERIFIED_OPINION', credibilityScore: 0.5 }
        ]
      }
    });
    // Reply
    createPost(env.db, {
      userId: userA,
      parentId: p1,
      minsAgo: 2,
      analysis: {
        claims: [
          { claim: 'Claim 5', verdict: 'FALSE', credibilityScore: 0.1 }
        ]
      }
    });
    // Unfinished post
    createPost(env.db, { userId: userA, status: 'PROCESSING', minsAgo: 1 });

    // Follows
    env.db.run('INSERT INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [me, userA, iso(0)]);

    const res = await env.api('GET', `/api/users/${userA}/profile`, { user: 'me' });
    assert.equal(res.status, 200);

    const d = res.data;
    assert.equal(d.user.username, 'alice');
    assert.equal(d.user.fullName, 'Alice Smith');
    assert.equal(d.bio, 'Debater and thinker');
    assert.equal(d.followerCount, 1);
    assert.equal(d.followingCount, 0);
    assert.equal(d.postCount, 3); // 3 READY posts, PROCESSING ignored
    assert.equal(d.followedByMe, true);
    assert.equal(d.blockedByMe, false);
    assert.equal(d.isMe, false);

    // Personality
    assert.deepEqual(d.personality.keywords, ['analytical', 'curious']);
    assert.equal(d.personality.summary, 'A curious thinker who loves facts.');
    assert.equal(d.personality.summaryApproved, true);
    assert.deepEqual(d.personality.interests, ['politics', 'tech']);

    // Contributions
    assert.equal(d.contributions.totalPosts, 3);
    assert.equal(d.contributions.analyzedPosts, 3);
    assert.equal(d.contributions.debatesStarted, 2);
    assert.equal(d.contributions.totalReplies, 1);

    // Credibility
    // Claims: 0.9, 0.8, 0.4, 0.5, 0.1 -> sum 2.7 / 5 = 0.54
    assert.equal(d.credibility.analyzedVideos, 3);
    assert.equal(d.credibility.totalClaims, 5);
    assert.equal(d.credibility.score, 0.54);
    assert.equal(d.credibility.sufficient, true);
    assert.equal(d.credibility.verdictDistribution['True'], 1);
    assert.equal(d.credibility.verdictDistribution['Mostly True'], 1);
    assert.equal(d.credibility.verdictDistribution['Misleading'], 1);
    assert.equal(d.credibility.verdictDistribution['Opinion'], 1);
    assert.equal(d.credibility.verdictDistribution['False'], 1);
  } finally {
    await env.close();
  }
});

test('GET /api/users/:id/profile: credibility insufficient when < 3 claims', async () => {
  const env = await setupTestApp();
  try {
    const user = createUser(env.db, 'bob');
    createPost(env.db, {
      userId: user,
      title: 'Only 2 claims',
      analysis: {
        claims: [
          { claim: 'A', verdict: 'TRUE', credibilityScore: 0.9 },
          { claim: 'B', verdict: 'TRUE', credibilityScore: 0.9 }
        ]
      }
    });

    const res = await env.api('GET', `/api/users/${user}/profile`, { user: 'bob' });
    assert.equal(res.status, 200);
    assert.equal(res.data.isMe, true);
    assert.equal(res.data.credibility.totalClaims, 2);
    assert.equal(res.data.credibility.sufficient, false);
    assert.equal(res.data.credibility.score, 0.9);
  } finally {
    await env.close();
  }
});

test('GET /api/users/:id/profile: 404 when user not found, blocked by target, or deleted', async () => {
  const env = await setupTestApp();
  try {
    const me = createUser(env.db, 'me');
    const blocker = createUser(env.db, 'blocker');
    const deleted = createUser(env.db, 'deleted');
    env.db.run('UPDATE users SET deleted_at = ? WHERE id = ?', [iso(0), deleted]);
    env.db.run('INSERT INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)', [blocker, me, iso(0)]);

    assert.equal((await env.api('GET', '/api/users/non-existent/profile', { user: 'me' })).status, 404);
    assert.equal((await env.api('GET', `/api/users/${deleted}/profile`, { user: 'me' })).status, 404);
    assert.equal((await env.api('GET', `/api/users/${blocker}/profile`, { user: 'me' })).status, 404);
  } finally {
    await env.close();
  }
});

test('GET /api/users/:id/videos: returns paginated READY posts with actor and counts', async () => {
  const env = await setupTestApp();
  try {
    const me = createUser(env.db, 'me');
    const creator = createUser(env.db, 'creator');

    const p1 = createPost(env.db, { userId: creator, title: 'Post 1', minsAgo: 30 });
    const p2 = createPost(env.db, { userId: creator, title: 'Post 2', minsAgo: 20 });
    const p3 = createPost(env.db, { userId: creator, title: 'Post 3', minsAgo: 10 });
    createPost(env.db, { userId: creator, title: 'Draft', status: 'PROCESSING', minsAgo: 5 });

    // Like p3
    env.db.run('INSERT INTO likes (user_id, post_id, created_at) VALUES (?, ?, ?)', [me, p3, iso(0)]);

    const res = await env.api('GET', `/api/users/${creator}/videos?limit=2`, { user: 'me' });
    assert.equal(res.status, 200);
    assert.equal(res.data.posts.length, 2);
    assert.equal(res.data.posts[0].post.title, 'Post 3');
    assert.equal(res.data.posts[0].post.likeCount, 1);
    assert.equal(res.data.posts[0].post.likedByMe, true);
    assert.equal(res.data.posts[0].actor.username, 'creator');
    assert.ok(res.data.nextCursor);

    // Second page
    const page2 = await env.api('GET', `/api/users/${creator}/videos?limit=2&cursor=${encodeURIComponent(res.data.nextCursor)}`, { user: 'me' });
    assert.equal(page2.status, 200);
    assert.equal(page2.data.posts.length, 1);
    assert.equal(page2.data.posts[0].post.title, 'Post 1');
    assert.equal(page2.data.nextCursor, null);
  } finally {
    await env.close();
  }
});

test('PATCH /api/me/profile: updates allowed fields and validates input', async () => {
  const env = await setupTestApp();
  try {
    const me = createUser(env.db, 'me', { fullName: 'Original' });

    // Validation errors
    let err = await env.api('PATCH', '/api/me/profile', { user: 'me', json: { fullName: '' } });
    assert.equal(err.status, 400);

    err = await env.api('PATCH', '/api/me/profile', { user: 'me', json: { bio: 'a'.repeat(301) } });
    assert.equal(err.status, 400);

    err = await env.api('PATCH', '/api/me/profile', {
      user: 'me',
      json: { personalityKeywords: new Array(9).fill('kw') }
    });
    assert.equal(err.status, 400);

    err = await env.api('PATCH', '/api/me/profile', {
      user: 'me',
      json: { personalityKeywords: ['toolong'.repeat(10)] }
    });
    assert.equal(err.status, 400);

    err = await env.api('PATCH', '/api/me/profile', {
      user: 'me',
      json: { interests: new Array(11).fill('item') }
    });
    assert.equal(err.status, 400);

    // Valid update
    const res = await env.api('PATCH', '/api/me/profile', {
      user: 'me',
      json: {
        fullName: 'New Name',
        bio: 'Updated bio',
        personalityKeywords: ['analytical', 'logical'],
        personalitySummary: 'A logical debater.',
        personalitySummaryApproved: true,
        interests: ['law', 'policy']
      }
    });

    assert.equal(res.status, 200);
    assert.equal(res.data.user.fullName, 'New Name');
    assert.equal(res.data.bio, 'Updated bio');
    assert.deepEqual(res.data.personality.keywords, ['analytical', 'logical']);
    assert.equal(res.data.personality.summary, 'A logical debater.');
    assert.equal(res.data.personality.summaryApproved, true);
    assert.deepEqual(res.data.personality.interests, ['law', 'policy']);
    assert.equal(res.data.isMe, true);
  } finally {
    await env.close();
  }
});

test('POST /api/me/personality/generate-summary: generates summary and enforces rate limit', async () => {
  let callCount = 0;
  const mockGemini = {
    generatePersonalitySummary: async (keywords) => {
      callCount++;
      return `Generated summary for ${keywords.join(', ')}`;
    }
  };
  const env = await setupTestApp({ gemini: mockGemini });
  try {
    createUser(env.db, 'me');

    // Validation
    assert.equal((await env.api('POST', '/api/me/personality/generate-summary', { user: 'me', json: { keywords: [] } })).status, 400);
    assert.equal((await env.api('POST', '/api/me/personality/generate-summary', { user: 'me', json: { keywords: new Array(9).fill('k') } })).status, 400);

    // Successful generation 5 times (max budget per day)
    for (let i = 0; i < 5; i++) {
      const res = await env.api('POST', '/api/me/personality/generate-summary', {
        user: 'me',
        json: { keywords: ['curious', 'analytical'] }
      });
      assert.equal(res.status, 200);
      assert.equal(res.data.summary, 'Generated summary for curious, analytical');
    }
    assert.equal(callCount, 5);

    // 6th call hits rate limit 429
    const limited = await env.api('POST', '/api/me/personality/generate-summary', {
      user: 'me',
      json: { keywords: ['curious'] }
    });
    assert.equal(limited.status, 429);
  } finally {
    await env.close();
  }
});

test('POST /api/me/personality/generate-summary: 503 when gemini is unavailable', async () => {
  const env = await setupTestApp({
    gemini: { generatePersonalitySummary: async () => null }
  });
  try {
    createUser(env.db, 'me_503');
    const res = await env.api('POST', '/api/me/personality/generate-summary', {
      user: 'me_503',
      json: { keywords: ['thoughtful'] }
    });
    assert.equal(res.status, 503);
  } finally {
    await env.close();
  }
});

test('Bookmarks: POST, GET, DELETE /api/me/bookmarks', async () => {
  const env = await setupTestApp();
  try {
    const me = createUser(env.db, 'me');
    const author = createUser(env.db, 'author');
    const post1 = createPost(env.db, { userId: author, title: 'Post 1' });
    const post2 = createPost(env.db, { userId: author, title: 'Post 2' });

    // Bookmark post1
    let res = await env.api('POST', `/api/me/bookmarks/${post1}`, { user: 'me' });
    assert.equal(res.status, 200);
    assert.equal(res.data.bookmarked, true);

    // Idempotent POST
    res = await env.api('POST', `/api/me/bookmarks/${post1}`, { user: 'me' });
    assert.equal(res.status, 200);
    assert.equal(res.data.bookmarked, true);

    // Bookmark post2
    await env.api('POST', `/api/me/bookmarks/${post2}`, { user: 'me' });

    // List bookmarks
    const list = await env.api('GET', '/api/me/bookmarks', { user: 'me' });
    assert.equal(list.status, 200);
    assert.equal(list.data.bookmarks.length, 2);
    assert.equal(list.data.bookmarks[0].actor.username, 'author');
    assert.ok(list.data.bookmarks[0].post);
    assert.ok(list.data.bookmarks[0].savedAt);

    // Delete bookmark
    const del = await env.api('DELETE', `/api/me/bookmarks/${post1}`, { user: 'me' });
    assert.equal(del.status, 200);
    assert.equal(del.data.bookmarked, false);

    const listAfter = await env.api('GET', '/api/me/bookmarks', { user: 'me' });
    assert.equal(listAfter.data.bookmarks.length, 1);
    assert.equal(listAfter.data.bookmarks[0].post.id, post2);
  } finally {
    await env.close();
  }
});

test('Followers and following lists with pagination and followedByMe status', async () => {
  const env = await setupTestApp();
  try {
    const me = createUser(env.db, 'me');
    const target = createUser(env.db, 'target');
    const u1 = createUser(env.db, 'u1', { minsAgo: 5 });
    const u2 = createUser(env.db, 'u2', { minsAgo: 4 });
    const u3 = createUser(env.db, 'u3', { minsAgo: 3 });

    // u1, u2, u3 follow target
    env.db.run('INSERT INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [u1, target, iso(30)]);
    env.db.run('INSERT INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [u2, target, iso(20)]);
    env.db.run('INSERT INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [u3, target, iso(10)]);

    // 'me' follows u2
    env.db.run('INSERT INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [me, u2, iso(0)]);

    // Target follows u1 and u3
    env.db.run('INSERT INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [target, u1, iso(15)]);
    env.db.run('INSERT INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [target, u3, iso(5)]);

    // GET followers paginated
    const followersPage1 = await env.api('GET', `/api/users/${target}/followers?limit=2`, { user: 'me' });
    assert.equal(followersPage1.status, 200);
    assert.equal(followersPage1.data.users.length, 2);
    assert.equal(followersPage1.data.users[0].user.username, 'u3');
    assert.equal(followersPage1.data.users[0].followedByMe, false);
    assert.equal(followersPage1.data.users[1].user.username, 'u2');
    assert.equal(followersPage1.data.users[1].followedByMe, true);
    assert.ok(followersPage1.data.nextCursor);

    // Follower page 2
    const followersPage2 = await env.api(
      'GET',
      `/api/users/${target}/followers?limit=2&cursor=${encodeURIComponent(followersPage1.data.nextCursor)}`,
      { user: 'me' }
    );
    assert.equal(followersPage2.status, 200);
    assert.equal(followersPage2.data.users.length, 1);
    assert.equal(followersPage2.data.users[0].user.username, 'u1');
    assert.equal(followersPage2.data.nextCursor, null);

    // GET following
    const following = await env.api('GET', `/api/users/${target}/following`, { user: 'me' });
    assert.equal(following.status, 200);
    assert.equal(following.data.users.length, 2);
    assert.equal(following.data.users[0].user.username, 'u3');
    assert.equal(following.data.users[1].user.username, 'u1');
  } finally {
    await env.close();
  }
});
