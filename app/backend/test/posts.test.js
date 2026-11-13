const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { startServer, addUser, follow, addPost, videoForm, jsonForm } = require('./helpers');

let s, root, ids;
before(async () => {
  s = await startServer();
  ids = { aman: addUser(s.db, 'aman'), riya: addUser(s.db, 'riya'), kabir: addUser(s.db, 'kabir') };
  root = addPost(s.db, { userId: ids.aman, title: 'Mandatory Punjabi', body: 'cultural continuity', minutesAgo: 100 });
});
after(() => s.close());

const textReply = (parentId, body, user = 'riya') =>
  s.api('POST', '/api/posts', { user, form: jsonForm({ kind: 'TEXT', parentId, body }) });

test('posting needs a user', async () => {
  const res = await s.api('POST', '/api/posts', { form: jsonForm({ kind: 'TEXT', parentId: root, body: 'hi' }) });
  assert.equal(res.status, 401);
});

test('text reply: stance comes from the classifier, which is shown the parent', async () => {
  s.calls.classify.length = 0;
  const res = await textReply(root, '  Dropouts rise for migrant kids.  ');
  assert.equal(res.status, 201);
  const { post, type, actor, parent } = res.data;
  assert.equal(type, 'TEXT_REPLY');
  assert.equal(post.kind, 'TEXT');
  assert.equal(post.body, 'Dropouts rise for migrant kids.'); // trimmed
  assert.equal(post.stance, 'FOR'); // helper's fake classifier says FOR
  assert.equal(post.status, 'READY');
  assert.equal(post.depth, 1);
  assert.equal(post.rootId, root);
  assert.equal(actor.username, 'riya');
  assert.equal(parent.post.id, root);
  assert.equal(s.calls.classify.length, 1);
  assert.match(s.calls.classify[0].ctx, /cultural continuity/);
});

test('text reply validation', async () => {
  const bad = async (fields, status, pattern) => {
    const res = await s.api('POST', '/api/posts', { user: 'riya', form: jsonForm(fields) });
    assert.equal(res.status, status, JSON.stringify(fields));
    assert.match(res.data.error, pattern);
  };
  await bad({ kind: 'TEXT', parentId: root, body: '   ' }, 400, /Write something/);
  await bad({ kind: 'TEXT', parentId: root, body: 'x'.repeat(281) }, 400, /280/);
  await bad({ kind: 'TEXT', body: 'no parent' }, 400, /must be replies/);
  await bad({ kind: 'TEXT', parentId: 'does-not-exist', body: 'hi' }, 404, /not found/);
  await bad({ kind: 'NOPE', body: 'hi' }, 400, /kind must be/);
  await bad({ kind: 'VIDEO' }, 400, /video file is required/);
  // exactly 280 characters (emoji count as one) is fine
  const ok = await s.api('POST', '/api/posts', { user: 'riya', form: jsonForm({ kind: 'TEXT', parentId: root, body: '😀'.repeat(280) }) });
  assert.equal(ok.status, 201);
});

test('a slow or broken classifier never blocks a reply: it falls back to UNRESOLVED', async () => {
  const slow = await startServer({ timeoutMs: 100, analyzer: { classifyReplyText: () => new Promise(() => {}) } });
  const broken = await startServer({ analyzer: { classifyReplyText: async () => { throw new Error('quota'); } } });
  try {
    for (const srv of [slow, broken]) {
      addUser(srv.db, 'u');
      const p = addPost(srv.db, { userId: addUser(srv.db, 'a'), title: 't' });
      const res = await srv.api('POST', '/api/posts', { user: 'u', form: jsonForm({ kind: 'TEXT', parentId: p, body: 'hello' }) });
      assert.equal(res.status, 201);
      assert.equal(res.data.post.stance, 'UNRESOLVED');
    }
  } finally { await slow.close(); await broken.close(); }
});

test('reply to a reply: stored under the reply, counted in the whole debate', async () => {
  const r = (await textReply(root, 'level one', 'riya')).data.post;
  const rr = (await textReply(r.id, 'level two', 'kabir')).data;
  assert.equal(rr.post.depth, 2);
  assert.equal(rr.post.parentId, r.id);
  assert.equal(rr.post.rootId, root);
  assert.deepEqual(rr.root, { id: root, username: 'aman', title: 'Mandatory Punjabi' });

  const rootNow = (await s.api('GET', `/api/posts/${root}`, { user: 'aman' })).data.post;
  const parentNow = (await s.api('GET', `/api/posts/${r.id}`, { user: 'aman' })).data.post;
  assert.ok(rootNow.replyCount >= 2);
  assert.equal(parentNow.replyCount, 1);
});

test('video opinion: accepted as PROCESSING, analysed in the background, then READY', async () => {
  // Hold the analysis open so we can look at the PROCESSING state deterministically.
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  const dev = await startServer({
    analyzer: {
      analyzeAudio: async () => {
        await gate;
        return { transcript: 'spoken words', detectedStance: 'AGAINST', overallSummary: 'A summary', claims: [] };
      }
    }
  });
  try {
    addUser(dev.db, 'aman'); addUser(dev.db, 'riya');
    const res = await dev.api('POST', '/api/posts', {
      user: 'aman', form: videoForm({ kind: 'VIDEO', title: 'My take', body: 'caption' })
    });
    assert.equal(res.status, 201);
    assert.equal(res.data.type, 'POST');
    assert.equal(res.data.post.status, 'PROCESSING');
    assert.equal(res.data.post.stance, 'PARENT');
    const id = res.data.post.id;

    // not visible to other people while it is processing, visible to the author
    assert.equal((await dev.api('GET', `/api/posts/${id}`, { user: 'riya' })).status, 404);
    assert.equal((await dev.api('GET', `/api/posts/${id}`, { user: 'aman' })).status, 200);

    release();
    await dev.idle();
    const done = (await dev.api('GET', `/api/posts/${id}`, { user: 'riya' })).data.post;
    assert.equal(done.status, 'READY');
    assert.equal(done.stance, 'PARENT'); // roots never take the analysed stance
    assert.equal(done.summary, 'A summary');
    assert.equal(done.title, 'My take');

    // the file is stored and served, and Range requests work (needed for video seeking)
    const file = await dev.api('GET', done.mediaUrl);
    assert.equal(file.status, 200);
    assert.equal(file.text, 'fake-video-bytes');
    const range = await fetch(dev.base + done.mediaUrl, { headers: { range: 'bytes=0-3' } });
    assert.equal(range.status, 206);
  } finally { release(); await dev.close(); }
});

test('video reply: stance comes from the audio analysis, which is shown the parent', async () => {
  s.calls.analyze.length = 0;
  const res = await s.api('POST', '/api/posts', {
    user: 'kabir', form: videoForm({ kind: 'VIDEO', parentId: root, title: 'ignored on replies' })
  });
  assert.equal(res.status, 201);
  assert.equal(res.data.type, 'VIDEO_REPLY');
  assert.equal(res.data.post.title, null);
  await s.idle();
  const post = (await s.api('GET', `/api/posts/${res.data.post.id}`, { user: 'kabir' })).data.post;
  assert.equal(post.stance, 'AGAINST');
  assert.equal(post.status, 'READY');
  assert.match(s.calls.analyze[0], /cultural continuity/);
});

test('Gemini returning EVIDENCE or garbage is stored as UNRESOLVED', async () => {
  const dev = await startServer({ videoStance: 'EVIDENCE' });
  try {
    addUser(dev.db, 'u');
    const p = addPost(dev.db, { userId: addUser(dev.db, 'a'), title: 't' });
    const res = await dev.api('POST', '/api/posts', { user: 'u', form: videoForm({ kind: 'VIDEO', parentId: p }) });
    await dev.idle();
    assert.equal((await dev.api('GET', `/api/posts/${res.data.post.id}`, { user: 'u' })).data.post.stance, 'UNRESOLVED');
  } finally { await dev.close(); }
});

test('a failed analysis marks the post FAILED and hides it from everyone but the author', async () => {
  const dev = await startServer({ analyzer: { analyzeAudio: async () => { throw new Error('boom'); } } });
  try {
    addUser(dev.db, 'u'); addUser(dev.db, 'other');
    const res = await dev.api('POST', '/api/posts', { user: 'u', form: videoForm({ kind: 'VIDEO', title: 't' }) });
    await dev.idle();
    assert.equal((await dev.api('GET', `/api/posts/${res.data.post.id}`, { user: 'u' })).data.post.status, 'FAILED');
    assert.equal((await dev.api('GET', `/api/posts/${res.data.post.id}`, { user: 'other' })).status, 404);
  } finally { await dev.close(); }
});

test('rejects non-media files and leaves no orphan upload behind', async () => {
  const before = fs.readdirSync(s.uploadsDir).length;
  const res = await s.api('POST', '/api/posts', {
    user: 'aman', form: videoForm({ kind: 'VIDEO', title: 't' }, { name: 'evil.exe', type: 'application/x-msdownload' })
  });
  assert.equal(res.status, 400);
  assert.match(res.data.error, /video and audio/);
  // validation failure after the upload was saved must clean the file up
  const res2 = await s.api('POST', '/api/posts', {
    user: 'aman', form: videoForm({ kind: 'VIDEO', parentId: 'missing' })
  });
  assert.equal(res2.status, 404);
  assert.equal(fs.readdirSync(s.uploadsDir).length, before);
});

test('cannot reply to a post that is still processing, or to someone who blocked you', async () => {
  const dev = await startServer();
  try {
    const u = addUser(dev.db, 'u'), a = addUser(dev.db, 'a');
    const busy = addPost(dev.db, { userId: a, status: 'PROCESSING' });
    const ok = addPost(dev.db, { userId: a, title: 't' });
    const form = (p) => jsonForm({ kind: 'TEXT', parentId: p, body: 'hi' });
    assert.equal((await dev.api('POST', '/api/posts', { user: 'u', form: form(busy) })).status, 409);
    await dev.api('POST', `/api/users/${u}/block`, { user: 'a' }); // a blocks u
    assert.equal((await dev.api('POST', '/api/posts', { user: 'u', form: form(ok) })).status, 403);
  } finally { await dev.close(); }
});

test('thread: flat list, depth-first, newest sibling first, blocked subtree hidden', async () => {
  const dev = await startServer();
  try {
    const me = addUser(dev.db, 'me'), a = addUser(dev.db, 'a'), b = addUser(dev.db, 'b'), c = addUser(dev.db, 'c');
    const top = addPost(dev.db, { userId: a, title: 'top', minutesAgo: 100 });
    const old = addPost(dev.db, { userId: b, kind: 'TEXT', parentId: top, body: 'old', minutesAgo: 50 });
    const recent = addPost(dev.db, { userId: c, kind: 'TEXT', parentId: top, body: 'recent', minutesAgo: 10 });
    const child = addPost(dev.db, { userId: a, kind: 'TEXT', parentId: old, body: 'child of old', minutesAgo: 40 });

    let res = await dev.api('GET', `/api/posts/${top}/thread`, { user: 'me' });
    assert.equal(res.status, 200);
    assert.equal(res.data.item.post.id, top);
    assert.deepEqual(res.data.replies.map((r) => r.post.id), [recent, old, child]);
    assert.equal(res.data.total, 3);
    assert.equal(res.data.replies[2].post.parentId, old);

    await dev.api('POST', `/api/users/${b}/block`, { user: 'me' }); // hides b and b's whole subtree
    res = await dev.api('GET', `/api/posts/${top}/thread`, { user: 'me' });
    assert.deepEqual(res.data.replies.map((r) => r.post.id), [recent]);
    assert.ok(me && child);
  } finally { await dev.close(); }
});

test('GET /api/posts/:id includes the analysis only in detail', async () => {
  const dev = await startServer();
  try {
    const a = addUser(dev.db, 'a');
    const p = addPost(dev.db, { userId: a, title: 't', analysis: { transcript: 'hi', overallSummary: 'sum', claims: [{ claim: 'c' }] } });
    const res = await dev.api('GET', `/api/posts/${p}`);
    assert.equal(res.status, 200);
    assert.equal(res.data.post.analysis.claims[0].claim, 'c');
    assert.equal(res.data.post.summary, 'sum');
    assert.equal((await dev.api('GET', '/api/posts/nope')).status, 404);
  } finally { await dev.close(); }
});

test('restart re-queues videos that were still processing', async () => {
  const dev = await startServer();
  try {
    const a = addUser(dev.db, 'a');
    const id = addPost(dev.db, { userId: a, status: 'PROCESSING', media: 'pending.mp4', title: 't' });
    fs.writeFileSync(path.join(dev.uploadsDir, 'pending.mp4'), 'x');
    dev.app.locals.jobs.resumePending();
    await dev.idle();
    assert.equal(dev.db.get('SELECT status FROM posts WHERE id = ?', [id]).status, 'READY');
  } finally { await dev.close(); }
});
