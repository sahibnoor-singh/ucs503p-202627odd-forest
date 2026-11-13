const fs = require('fs');
const path = require('path');
const express = require('express');
const { requireUser } = require('../middleware/user');
const { wrap, parseLimit, HttpError } = require('../http');
const { createUpload } = require('../upload');
const { CAPTION_LANGUAGES } = require('../services/geminiService');
const { createComposeUpload, removeFiles } = require('../compose/upload');
const { validateRecipe } = require('../compose/recipe');
const { REPORT_REASONS } = require('../moderation');
const { nowIso, uuid, getPost, toItem, toPosts, toUser, getUsersMap, parseAnalysis } = require('../queries');
const { createProfiles } = require('../profiles');


module.exports = function postRoutes({ db, uploadsDir, composeDir, composer, postService, jobs, analyzer, events = { track() {} } }) {
  const router = express.Router();
  const upload = createUpload(uploadsDir);
  const { learnFromLike } = createProfiles(db);
  const composeUpload = createComposeUpload(composeDir);

  /** Unfinished/failed posts are only visible to their author (who polls them). */
  function visiblePost(req) {
    const row = getPost(db, req.params.id);
    if (!row) throw new HttpError(404, 'Post not found');
    if (row.status !== 'READY' && (!req.user || req.user.id !== row.user_id)) {
      throw new HttpError(404, 'Post not found');
    }
    return row;
  }

  // POST /api/posts  (multipart/form-data)
  //   kind=VIDEO|TEXT, parentId?, title?, body?, video (file, required for VIDEO)
  router.post('/', requireUser, upload.single('video'), wrap(async (req, res) => {
    const item = await postService.createPost({
      user: req.user,
      kind: req.body.kind,
      parentId: req.body.parentId,
      title: req.body.title,
      body: req.body.body,
      promptDay: req.body.promptDay,
      roomId: req.body.roomId,
      file: req.file
    });
    events.track(item.post.parentId ? 'reply_created' : 'post_created', req.user.id, { kind: item.post.kind === 'TEXT' ? 'text' : 'video', prompt: !!item.post.promptDay, room: !!item.post.room });
    if (item.post.promptDay) events.track('prompt_answered', req.user.id);
    res.status(201).json(item);
  }));

  // POST /api/posts/compose  (multipart/form-data)   a post made in the editor (docs/api.md "Editor posts").
  //   recipe  = JSON (mode VIDEO | TEXT | PHOTOS, see src/compose/recipe.js)
  //   photos  = up to 10 image files, music = one audio file, video = one video file (whichever the mode needs)
  //   parentId?, title?, body? (caption)   as for POST /api/posts
  // Answers 201 at once with the post as PROCESSING; the server renders it to a normal video, then analyses it.
  router.post('/compose', requireUser, composeUpload, wrap(async (req, res) => {
    const files = req.files || {};
    const cleanUp = () => removeFiles(files);
    try {
      let raw;
      try {
        raw = JSON.parse(String(req.body.recipe || ''));
      } catch {
        throw new HttpError(400, 'recipe must be JSON', { field: 'recipe' });
      }
      const photos = files.photos || [];
      const [music] = files.music || [];
      const [video] = files.video || [];

      // What we can learn about the files up front (the real rendering happens later, in the queue).
      const read = async (file, field, needs) => {
        let info;
        try {
          info = await composer.probe(file.path);
        } catch {
          throw new HttpError(400, `That ${field} file could not be read`, { field });
        }
        if (!info[needs]) throw new HttpError(400, `That ${field} file has no ${needs === 'hasVideo' ? 'picture' : 'sound'}`, { field });
        return info;
      };
      const videoInfo = video ? await read(video, 'video', 'hasVideo') : null;
      if (music) await read(music, 'music', 'hasAudio');

      const recipe = validateRecipe(raw, { photoCount: photos.length, hasMusic: !!music, hasVideo: !!video, videoInfo });
      const item = await postService.createComposed({
        user: req.user,
        recipe,
        files: { video: video && video.filename, music: music && music.filename, photos: photos.map((p) => p.filename) },
        parentId: req.body.parentId,
        title: req.body.title,
        body: req.body.body,
        promptDay: req.body.promptDay,
        roomId: req.body.roomId,
        removeInputs: cleanUp
      });
      events.track(item.post.parentId ? 'reply_created' : 'post_created', req.user.id, { kind: 'video', prompt: !!item.post.promptDay, room: !!item.post.room });
      if (item.post.promptDay) events.track('prompt_answered', req.user.id);
      res.status(201).json(item);
    } catch (err) {
      cleanUp(); // idempotent: createComposed already did it for its own errors
      throw err;
    }
  }));

  router.get('/:id', wrap(async (req, res) => {
    res.json(toItem(db, visiblePost(req), req.user && req.user.id, { detail: true }));
  }));

  // GET /api/posts/:id/captions?lang=original|en|hi|pa|...
  // Subtitle lines for a video: { captions: [{ start, end, text }], language, lang, languages }, times in seconds.
  // "language" is what is spoken in the video, "lang" what these lines are in, "languages" what can be asked for.
  // The spoken language and English are made when the video is analysed; any other language is translated the first time
  // it is asked for and then kept. Empty for a video with no speech. Same visibility as the post itself.
  const translating = new Map(); // "postId:lang" -> promise, so two people asking at once cost one translation
  const TRANSLATE_TIMEOUT_MS = 40000;

  async function translatedTrack(row, lang, original) {
    const key = row.id + ':' + lang;
    if (!translating.has(key)) {
      const work = (async () => {
        let timer;
        const timeout = new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('translation timed out')), TRANSLATE_TIMEOUT_MS); });
        try {
          const cues = await Promise.race([analyzer.translateCaptions(original, lang), timeout]);
          if (!cues) return null;
          const fresh = getPost(db, row.id);
          const a = fresh && parseAnalysis(fresh);
          if (a) { // keep it for next time, unless the post is gone meanwhile
            a.captionTracks = { ...(a.captionTracks || {}), [lang]: cues };
            db.run('UPDATE posts SET analysis = ? WHERE id = ?', [JSON.stringify(a), row.id]);
          }
          return cues;
        } finally { clearTimeout(timer); }
      })().finally(() => translating.delete(key));
      translating.set(key, work);
    }
    return translating.get(key);
  }

  router.get('/:id/captions', wrap(async (req, res) => {
    const row = visiblePost(req);
    const a = parseAnalysis(row) || {};
    const original = Array.isArray(a.captions) ? a.captions : [];
    const language = a.language || null;
    const asked = String(req.query.lang || 'original').toLowerCase();
    let lang = 'original';
    let captions = original;
    if (asked !== 'original' && asked !== language) {
      if (!CAPTION_LANGUAGES.some((l) => l.code === asked)) throw new HttpError(400, 'Unsupported caption language');
      const kept = a.captionTracks && a.captionTracks[asked];
      if (Array.isArray(kept)) {
        captions = kept; lang = asked;
      } else if (original.length && analyzer && typeof analyzer.translateCaptions === 'function') {
        let cues = null;
        try { cues = await translatedTrack(row, asked, original); } catch (err) { console.warn('[captions] translation failed:', err.message); }
        if (!cues) throw new HttpError(503, 'Could not translate the captions right now. Try again in a moment.');
        captions = cues; lang = asked;
      } else if (original.length) {
        throw new HttpError(503, 'Translation is not available.');
      }
    } else if (asked === language) {
      lang = asked;
    }
    res.json({ captions, language, lang, languages: CAPTION_LANGUAGES });
  }));

  // GET /api/posts/:id/thread?limit=100
  // Every reply below the post, direct and indirect, flattened depth-first with
  // the newest sibling first. Rebuild the tree on the client from post.parentId.
  router.get('/:id/thread', wrap(async (req, res) => {
    const root = visiblePost(req);
    const me = req.user ? req.user.id : '';
    const limit = parseLimit(req.query.limit, 100, 200);

    const rows = db.all(
      `WITH RECURSIVE d(id) AS (
         SELECT id FROM posts
           WHERE parent_id = ? AND status = 'READY'
             AND user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?)
         UNION ALL
         SELECT p.id FROM posts p JOIN d ON p.parent_id = d.id
           WHERE p.status = 'READY'
             AND p.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?)
       )
       SELECT p.* FROM posts p WHERE p.id IN (SELECT id FROM d)`,
      [root.id, me, me]
    );

    const children = new Map();
    for (const r of rows) {
      if (!children.has(r.parent_id)) children.set(r.parent_id, []);
      children.get(r.parent_id).push(r);
    }
    const ordered = [];
    const walk = (parentId) => {
      const kids = (children.get(parentId) || [])
        .sort((a, b) => (a.created_at < b.created_at ? 1 : a.created_at > b.created_at ? -1 : 0));
      for (const k of kids) {
        ordered.push(k);
        walk(k.id);
      }
    };
    walk(root.id);

    const shown = ordered.slice(0, limit);
    const meId = req.user && req.user.id;
    const posts = toPosts(db, shown, meId);
    const users = getUsersMap(db, shown.map((r) => r.user_id));
    res.json({
      item: toItem(db, root, meId),
      replies: shown.map((r, i) => ({ actor: toUser(users.get(r.user_id)), post: posts[i] })),
      total: ordered.length
    });
  }));

  // POST /api/posts/:id/retry  (author only). Re-runs analysis for a video that FAILED
  // (e.g. a timeout), without uploading it again.
  router.post('/:id/retry', requireUser, wrap(async (req, res) => {
    const row = getPost(db, req.params.id);
    if (!row || row.user_id !== req.user.id) throw new HttpError(404, 'Post not found');
    if (row.status !== 'FAILED') throw new HttpError(409, 'Only a failed video can be retried');
    let inputsThere;
    if (row.recipe) {
      const { files } = JSON.parse(row.recipe);
      const names = [files.video, files.music, ...(files.photos || [])].filter(Boolean);
      inputsThere = names.every((n) => fs.existsSync(path.join(composeDir, path.basename(n))));
    } else {
      inputsThere = !!row.media_filename && fs.existsSync(path.join(uploadsDir, row.media_filename));
    }
    if (!inputsThere) {
      throw new HttpError(410, 'The uploaded file is gone. Please upload the video again');
    }
    db.run("UPDATE posts SET status = 'PROCESSING' WHERE id = ?", [row.id]);
    jobs.enqueue(row.id);
    res.json(toItem(db, getPost(db, row.id), req.user.id));
  }));

  function likeable(req) {
    const row = getPost(db, req.params.id);
    if (!row || row.status !== 'READY') throw new HttpError(404, 'Post not found');
    return row;
  }
  const likeCount = (id) => db.get('SELECT COUNT(*) AS n FROM likes WHERE post_id = ?', [id]).n;

  router.post('/:id/like', requireUser, wrap(async (req, res) => {
    const row = likeable(req);
    const had = db.get('SELECT 1 AS x FROM likes WHERE user_id = ? AND post_id = ?', [req.user.id, row.id]);
    db.run('INSERT OR IGNORE INTO likes (user_id, post_id, created_at) VALUES (?, ?, ?)', [
      req.user.id, row.id, nowIso()
    ]);
    if (!had) learnFromLike(req.user.id, row);
    res.json({ liked: true, likeCount: likeCount(row.id) });
  }));

  router.delete('/:id/like', requireUser, wrap(async (req, res) => {
    const row = likeable(req);
    db.run('DELETE FROM likes WHERE user_id = ? AND post_id = ?', [req.user.id, row.id]);
    res.json({ liked: false, likeCount: likeCount(row.id) });
  }));

  // POST /api/posts/:id/report  {reason}. Reports go to a human review queue;
  // nothing is removed automatically.
  router.post('/:id/report', requireUser, wrap(async (req, res) => {
    const row = getPost(db, req.params.id);
    if (!row) throw new HttpError(404, 'Post not found');
    if (row.user_id === req.user.id) throw new HttpError(400, "You can't report your own post");
    const reason = String((req.body && req.body.reason) || '').toUpperCase();
    if (!REPORT_REASONS.includes(reason)) {
      throw new HttpError(400, `reason must be one of ${REPORT_REASONS.join(', ')}`);
    }
    db.run('INSERT OR IGNORE INTO reports (id, reporter_id, post_id, reason, created_at) VALUES (?, ?, ?, ?, ?)', [
      uuid(), req.user.id, row.id, reason, nowIso()
    ]);
    res.status(201).json({ reported: true });
  }));

  return router;
};
