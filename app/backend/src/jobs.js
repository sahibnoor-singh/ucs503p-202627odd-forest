// In-process queue for the slow part of a video post: audio extraction +
// Gemini. One job at a time so we never burst through Gemini quota.
// A restart re-queues anything still PROCESSING (resumePending).

const fs = require('fs');
const os = require('os');
const path = require('path');
const { v4: uuid } = require('uuid');
const { getPost, contextOf } = require('./queries');
const { textOf } = require('./compose/recipe');
const { normalizeStance } = require('./services/geminiService');

/** Rejects if [promise] takes longer than [ms]. The work itself can't be cancelled, but the queue moves on. */
function withDeadline(promise, ms, label) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms} ms`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

/**
 * @param {object} o
 * @param {object} [o.composer]    renders editor posts (src/compose); needed only when such posts exist
 * @param {string} [o.composeDir]  where the editor's input files live (not served publicly)
 */
function createJobs({ db, analyzer, uploadsDir, jobTimeoutMs = 180000, moderation = null, composer = null, composeDir = null }) {
  let chain = Promise.resolve();

  const removeInputs = (files) => {
    if (!files || !composeDir) return;
    const names = [files.video, files.music, ...(files.photos || [])].filter(Boolean);
    for (const n of names) fs.rmSync(path.join(composeDir, path.basename(n)), { force: true });
  };

  /** The motion a room post is argued against, or null for any other post. */
  const motionOf = (post) => {
    if (!post.room_id) return null;
    const room = db.get('SELECT motion FROM rooms WHERE id = ?', [post.room_id]);
    return room ? room.motion : null;
  };

  /** Posts with nothing to transcribe (text, photos, muted video): the AI sees what the person wrote instead. */
  async function analyseWords(post, recipe, parent) {
    const text = textOf(recipe.render, post.body);
    let stance = 'PARENT';
    let roomStance = null;
    const classify = async (against) => {
      if (!text) return 'UNRESOLVED';
      try {
        return normalizeStance(await withDeadline(analyzer.classifyReplyText(text, against), 8000, 'stance'));
      } catch { return 'UNRESOLVED'; /* the AI is optional */ }
    };
    if (parent) stance = await classify(contextOf(parent));
    const motion = motionOf(post);
    if (motion) roomStance = await classify(motion);
    return {
      analysis: { transcript: text, overallSummary: text.slice(0, 200), claims: [], source: 'TEXT' },
      stance,
      roomStance
    };
  }

  async function processVideoPost(postId) {
    let post = getPost(db, postId);
    if (!post || post.status !== 'PROCESSING') return;

    const stored = post.recipe ? JSON.parse(post.recipe) : null; // {render, files} for editor posts
    const audioPath = path.join(os.tmpdir(), `forest-${postId}.mp3`);
    const voicePath = composeDir ? path.join(composeDir, `voice-${postId}.mp3`) : null;
    let renderedPath = null;
    let renderedCover = null;
    try {
      const parent = post.parent_id ? getPost(db, post.parent_id) : null;

      // Step 1 (editor posts only): render the recipe to an MP4 in uploads/.
      if (stored) {
        if (!composer || !composeDir) throw new Error('this server cannot render editor posts');
        const r = stored.render;
        const outName = `${Date.now()}-${uuid().slice(0, 8)}-composed.mp4`;
        renderedPath = path.join(uploadsDir, outName);
        const coverName = outName.replace(/\.mp4$/, '-cover.jpg');
        const coverPath = path.join(uploadsDir, coverName);
        renderedCover = coverPath;
        const at = (n) => path.join(composeDir, path.basename(n));
        const rendered = await withDeadline(composer.render({
          recipe: r,
          inputs: {
            video: stored.files.video && at(stored.files.video),
            music: stored.files.music && at(stored.files.music),
            photos: r.mode === 'PHOTOS' ? r.photoOrder.map((i) => at(stored.files.photos[i])) : undefined
          },
          outPath: renderedPath,
          coverPath,
          voicePath: r.mode === 'VIDEO' && !r.muteOriginal ? voicePath : null,
          workDir: path.join(composeDir, `work-${postId}`),
          timeoutMs: jobTimeoutMs
        }), Math.ceil(jobTimeoutMs * 1.1), 'render'); // ffmpeg is killed at jobTimeoutMs; this is only the backstop
        // The author may have deleted their account while this was rendering: then the file must not be kept.
        post = getPost(db, postId);
        if (!post || post.status !== 'PROCESSING') {
          fs.rmSync(renderedPath, { force: true });
          fs.rmSync(coverPath, { force: true });
          return;
        }
        const hasCover = !!(rendered && rendered.cover) && fs.existsSync(coverPath);
        db.run('UPDATE posts SET media_filename = ?, cover_filename = ? WHERE id = ?', [outName, hasCover ? coverName : null, postId]);
        post.media_filename = outName;
      }

      // An uploaded video gets a still picture: the tile in the Discover grid, and the poster shown before it plays.
      // (Editor posts made theirs while rendering.) Never worth failing the post over.
      if (!stored && typeof analyzer.makeThumbnail === 'function') {
        const thumbName = `${path.parse(post.media_filename).name}-cover.jpg`;
        const thumbPath = path.join(uploadsDir, thumbName);
        try {
          if (await withDeadline(analyzer.makeThumbnail(path.join(uploadsDir, post.media_filename), thumbPath), jobTimeoutMs, 'thumbnail')) {
            renderedCover = thumbPath;
            db.run('UPDATE posts SET cover_filename = ? WHERE id = ?', [thumbName, postId]);
          }
        } catch (err) {
          console.warn(`[jobs] thumbnail for ${postId} skipped: ${err.message}`);
        }
      }

      // Step 2: understand the post (speech -> Gemini; no speech -> the words the person wrote).
      let analysis;
      let stance;
      let roomStance = null;
      const speech = !stored || (stored.render.mode === 'VIDEO' && !stored.render.muteOriginal);
      if (speech) {
        const source = stored ? voicePath : path.join(uploadsDir, post.media_filename);
        // One stuck call must not block every later video, so each job has a deadline.
        if (!stored) await withDeadline(analyzer.extractAudio(source, audioPath), jobTimeoutMs, 'audio extraction');
        const motion = motionOf(post);
        analysis = await withDeadline(analyzer.analyzeAudio(stored ? voicePath : audioPath, parent ? contextOf(parent) : motion), jobTimeoutMs, 'analysis');
        stance = parent ? normalizeStance(analysis.detectedStance) : 'PARENT';
        if (motion) roomStance = normalizeStance(analysis.detectedStance); // judged against the motion, not against a parent post
        if (stored) analysis.transcript = `${analysis.transcript || ''}${textOf(stored.render, post.body) ? `\n${textOf(stored.render, post.body)}` : ''}`.trim();
      } else {
        ({ analysis, stance, roomStance } = await analyseWords(post, stored, parent));
      }


      // The post's heading (roots) and description, written from what is said or written. They only fill what the author
      // left empty, and a failure here never fails the post.
      let title = null;
      let body = null;
      if (typeof analyzer.describePost === 'function') {
        try {
          const d = await withDeadline(analyzer.describePost({
            transcript: analysis.transcript, summary: analysis.overallSummary,
            parentContext: parent ? contextOf(parent) : null, isRoot: !parent
          }), jobTimeoutMs, 'description');
          if (d) { title = d.title || null; body = d.body || null; }
        } catch (err) {
          console.warn(`[jobs] description for ${postId} skipped: ${err.message}`);
        }
      }
      // English subtitles are made up front; the other languages the first time somebody asks (GET /captions?lang=).
      if (typeof analyzer.translateCaptions === 'function' && analysis.language && analysis.language !== 'en' &&
          Array.isArray(analysis.captions) && analysis.captions.length) {
        try {
          const en = await withDeadline(analyzer.translateCaptions(analysis.captions, 'en'), jobTimeoutMs, 'translation');
          if (en) analysis.captionTracks = { ...(analysis.captionTracks || {}), en };
        } catch (err) {
          console.warn(`[jobs] English captions for ${postId} skipped: ${err.message}`);
        }
      }

      // The author may have deleted their account while the AI was working (that empties the post and removes its
      // file). The result must not be written back: it would put their transcript back into the database.
      const stillThere = getPost(db, postId);
      if (!stillThere || !stillThere.media_filename || stillThere.status !== 'PROCESSING') return;
      // Automatic first pass: a configured word in what was said or written hides the post right away (a person can restore it).
      const hit = moderation && moderation.screenText(`${analysis.transcript || ''} ${analysis.overallSummary || ''}`);
      db.run(
        `UPDATE posts SET stance = ?, room_stance = ?, analysis = ?, status = ?, recipe = NULL,
                          title = COALESCE(NULLIF(title, ''), ?), body = COALESCE(NULLIF(body, ''), ?) WHERE id = ?`,
        [stance, roomStance, JSON.stringify(analysis), hit ? 'HIDDEN' : 'READY', title, body, postId]
      );
      if (hit) moderation.log('auto', 'HIDE', { postId, userId: stillThere.user_id, reason: 'AUTO_SCREEN', note: `matched "${hit}"` });
      if (stored) removeInputs(stored.files); // done: the inputs are not kept (a failed post keeps them so Retry can run again)
    } catch (err) {
      console.error(`[jobs] video post ${postId} failed:`, err.message);
      db.run("UPDATE posts SET status = 'FAILED', cover_filename = NULL WHERE id = ?", [postId]);
      if (renderedPath) fs.rmSync(renderedPath, { force: true });
      if (renderedCover) fs.rmSync(renderedCover, { force: true });
    } finally {
      fs.rmSync(audioPath, { force: true });
      if (voicePath) fs.rmSync(voicePath, { force: true });
    }
  }

  function enqueue(postId) {
    chain = chain.then(() => processVideoPost(postId)).catch((err) => {
      console.error('[jobs] unexpected error:', err);
    });
    return chain;
  }

  function resumePending() {
    db.all("SELECT id FROM posts WHERE status = 'PROCESSING' AND (media_filename IS NOT NULL OR recipe IS NOT NULL) ORDER BY created_at")
      .forEach((r) => enqueue(r.id));
  }

  return { enqueue, resumePending, idle: () => chain, removeInputs };
}

module.exports = { createJobs };
