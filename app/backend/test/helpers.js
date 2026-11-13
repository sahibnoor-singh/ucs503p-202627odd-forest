const fs = require('fs');
const os = require('os');
const path = require('path');
const { v4: uuid } = require('uuid');
const { openDb } = require('../src/db');
const { createApp } = require('../src/app');
const { createProvider } = require('../src/auth/providers');
const { createMailer } = require('../src/auth/mailers');

const TEST_SECRET = 'test-secret-for-unit-tests-0123456789';

/** Boots the real app on a random port with an in-memory DB and a fake Gemini/ffmpeg. */
async function startServer(opts = {}) {
  const db = await openDb();
  const uploadsDir = fs.mkdtempSync(path.join(os.tmpdir(), 'forest-test-uploads-'));
  const calls = { analyze: [], classify: [] };
  const analyzer = {
    extractAudio: async (video, audio) => fs.writeFileSync(audio, 'fake-audio'),
    analyzeAudio: async (audio, ctx) => {
      calls.analyze.push(ctx);
      return { transcript: 'spoken words', detectedStance: opts.videoStance || 'AGAINST', overallSummary: 'A summary', claims: [] };
    },
    classifyReplyText: async (text, ctx) => {
      calls.classify.push({ text, ctx });
      return opts.textStance || 'FOR';
    },
    ...opts.analyzer
  };
  const otpProvider = createProvider('memory');
  const emailProvider = createMailer('memory');
  const app = createApp({
    db, uploadsDir, analyzer, jwtSecret: TEST_SECRET, otpProvider, emailProvider, allowDevUser: true, textClassifyTimeoutMs: opts.timeoutMs || 500,
    ...opts.appOptions
  });
  const server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  const base = `http://127.0.0.1:${server.address().port}`;

  async function api(method, url, { user, json, form } = {}) {
    const headers = {};
    let body;
    if (user) headers['x-dev-user'] = user;
    if (json !== undefined) {
      headers['content-type'] = 'application/json';
      body = JSON.stringify(json);
    }
    if (form) body = form;
    const res = await fetch(base + url, { method, headers, body });
    const text = await res.text();
    let data = text;
    try { data = JSON.parse(text); } catch { /* not JSON (static file) */ }
    return { status: res.status, data, headers: res.headers, text };
  }

  return {
    app, db, api, uploadsDir, calls, base, otpProvider, emailProvider,
    idle: () => app.locals.jobs.idle(),
    close: async () => {
      await app.locals.jobs.idle();
      await new Promise((resolve) => server.close(resolve));
      db.close();
      fs.rmSync(uploadsDir, { recursive: true, force: true });
    }
  };
}

const iso = (minutesAgo) => new Date(Date.now() - minutesAgo * 60000).toISOString();

function addUser(db, username, { bot = false } = {}) {
  const id = uuid();
  db.run('INSERT INTO users (id, username, full_name, is_bot, created_at) VALUES (?, ?, ?, ?, ?)', [
    id, username, username, bot ? 1 : 0, iso(0)
  ]);
  return id;
}

function follow(db, followerId, followeeId) {
  db.run('INSERT INTO follows (follower_id, followee_id, created_at) VALUES (?, ?, ?)', [followerId, followeeId, iso(0)]);
}

/** Inserts a post directly so tests control timestamps. Returns its id. */
function addPost(db, {
  id = uuid(), userId, kind = 'VIDEO', parentId = null, title = null, body = null,
  stance, status = 'READY', minutesAgo = 0, media = 'x.mp4', analysis = null
}) {
  const parent = parentId ? db.get('SELECT * FROM posts WHERE id = ?', [parentId]) : null;
  db.run(
    `INSERT INTO posts (id, user_id, kind, parent_id, root_id, depth, title, body, media_filename,
                        stance, status, analysis, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      id, userId, kind, parentId, parent ? parent.root_id : id, parent ? parent.depth + 1 : 0,
      title, body, kind === 'VIDEO' ? media : null,
      stance || (parent ? 'UNRESOLVED' : 'PARENT'), status,
      analysis ? JSON.stringify(analysis) : null, iso(minutesAgo)
    ]
  );
  return id;
}

function videoForm(fields = {}, { name = 'clip.mp4', type = 'video/mp4', content = 'fake-video-bytes' } = {}) {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) if (v !== undefined) fd.append(k, v);
  fd.append('video', new Blob([content], { type }), name);
  return fd;
}

function jsonForm(fields) {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) fd.append(k, v);
  return fd;
}

module.exports = { TEST_SECRET, startServer, addUser, follow, addPost, videoForm, jsonForm, iso };
