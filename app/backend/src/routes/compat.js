// Keeps the endpoints the current Flutter Discover/Upload tabs use working
// (they were written against the old Website backend):
//   GET  /api/videos/all     old row shape, videos only, oldest first
//   POST /api/videos/upload  old multipart form; no sign-in (legacy behaviour)
// Differences from the old server: the upload returns immediately with
// status PROCESSING (analysis runs in the background), and uploads are
// attributed to a find-or-create user named after the `userId` field.
// TEMP: remove once the app has moved to /api/posts and accounts.

const fs = require('fs');
const express = require('express');
const { wrap, HttpError } = require('../http');
const { createUpload } = require('../upload');
const { uuid, nowIso, getPost, getUser, getUserByName, parseAnalysis } = require('../queries');

module.exports = function compatRoutes({ db, uploadsDir, postService, allowLegacyUpload, legacyListLimit }) {
  const router = express.Router();
  const upload = createUpload(uploadsDir);

  function legacyVideo(row) {
    return {
      id: row.id,
      title: row.title || null,
      filename: row.media_filename || '',
      status: row.status,
      role: row.parent_id ? 'CHILD' : 'PARENT',
      parent_video_id: row.parent_id || null,
      stance: row.stance,
      transcript: parseAnalysis(row),
      created_at: row.created_at,
      user_id: getUser(db, row.user_id).username
    };
  }

  // Same switch as the legacy upload below: development only. It is public and unauthenticated and includes
  // transcripts, so in production it answers 404. The app now uses /api/videos/feed instead.
  const legacyEnabled = (req, res, next) =>
    allowLegacyUpload ? next() : res.status(404).json({ error: 'Not found' });

  router.get('/all', legacyEnabled, (req, res) => {
    // Capped to the newest N so this public, unauthenticated list can't grow without bound.
    const rows = db.all(
      `SELECT * FROM (SELECT * FROM posts WHERE kind = 'VIDEO' AND status = 'READY' ORDER BY created_at DESC, id DESC LIMIT ?)
       ORDER BY created_at ASC, id ASC`,
      [legacyListLimit]
    );
    res.json(rows.map(legacyVideo));
  });

  function legacyUser(rawName) {
    const name = String(rawName || 'test_user').toLowerCase().replace(/[^a-z0-9._]/g, '_').slice(0, 30);
    const username = name.length >= 3 ? name : 'test_user';
    let user = getUserByName(db, username);
    // This endpoint has no sign-in, so it must never post as a real person.
    if (user && !user.is_bot) return legacyUser('legacy_upload');
    if (!user) {
      // Not a real account, so it is labelled as a bot (CLAUDE.md hard rule).
      db.run('INSERT INTO users (id, username, full_name, is_bot, created_at) VALUES (?, ?, ?, 1, ?)', [
        uuid(), username, username, nowIso()
      ]);
      user = getUserByName(db, username);
    }
    return user;
  }

  // No sign-in here, so it is dev-only by default. In production it answers 404 (checked before any file is stored).
  const legacyUploadEnabled = legacyEnabled;

  router.post('/upload', legacyUploadEnabled, upload.single('video'), wrap(async (req, res) => {
    if (!req.file) throw new HttpError(400, 'No video or audio file provided.');
    const isReply = String(req.body.role || '').toUpperCase() === 'CHILD';
    if (isReply && !req.body.parentVideoId) {
      fs.rmSync(req.file.path, { force: true });
      throw new HttpError(400, 'parentVideoId is required for a reply.');
    }
    const item = await postService.createPost({
      user: legacyUser(req.body.userId),
      kind: 'VIDEO',
      parentId: isReply ? req.body.parentVideoId : null,
      title: req.body.title,
      file: req.file
    });
    res.status(201).json({ message: 'Upload accepted', video: legacyVideo(getPost(db, item.post.id)) });
  }));

  return router;
};
