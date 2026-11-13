// Creating a post/reply. Shared by POST /api/posts and the legacy
// POST /api/videos/upload so both follow the same rules.

const fs = require('fs');
const { HttpError } = require('./http');
const {
  uuid, nowIso, getPost, toItem, contextOf, isBlockedEitherWay
} = require('./queries');
const { normalizeStance } = require('./services/geminiService');
const { openDays } = require('./prompts');
const rooms = require('./rooms');

const MAX_TEXT = 280;
const MAX_TITLE = 120;
const MAX_PROCESSING_PER_USER = 5;   // unfinished videos one person may have queued
const MAX_PROCESSING_TOTAL = 100;    // the whole server's queue; beyond this we ask people to wait

const chars = (s) => [...s].length;

function withTimeout(promise, ms, fallback) {
  let timer;
  const timeout = new Promise((resolve) => { timer = setTimeout(() => resolve(fallback), ms); });
  return Promise.race([promise.catch(() => fallback), timeout]).finally(() => clearTimeout(timer));
}

function createPostService({ db, jobs, analyzer, textClassifyTimeoutMs, moderation = null, clock = Date.now, promptOffsetMin = 330 }) {
  /**
   * What a new opinion may be attached to: today's (or yesterday's) question, or a motion room the person is in and that is open.
   * Replies are never attached. Returns { promptDay, roomId } with nulls for "nothing".
   */
  function checkContext(user, parent, promptDay, roomId) {
    promptDay = promptDay ? String(promptDay) : null;
    roomId = roomId ? String(roomId) : null;
    if (!promptDay && !roomId) return { promptDay: null, roomId: null };
    if (parent) throw new HttpError(400, 'Only a new opinion can answer a question or join a room');
    if (promptDay && roomId) throw new HttpError(400, 'Choose either the daily question or a room, not both');
    if (promptDay && !openDays(clock(), promptOffsetMin).includes(promptDay)) {
      throw new HttpError(400, 'That question is no longer open', { field: 'promptDay' });
    }
    if (roomId) rooms.requireOpenForPosting(db, roomId, user.id, clock());
    return { promptDay, roomId };
  }

  /**
   * @param {{user: object, kind: string, parentId?: string, title?: string, body?: string, file?: object}} input
   * @returns the feed item for the new post. Video posts come back PROCESSING.
   */
  /** The post being replied to must exist, be visible, and not be between blocked people. Returns it (or null for a root). */
  function loadParent(user, parentId) {
    if (!parentId) return null;
    const parent = getPost(db, String(parentId));
    if (!parent) throw new HttpError(404, 'The post you are replying to was not found');
    if (parent.status !== 'READY') throw new HttpError(409, 'That post is still being processed');
    if (isBlockedEitherWay(db, user.id, parent.user_id)) throw new HttpError(403, "You can't reply to this post");
    return parent;
  }

  /** Analysis costs Gemini quota and runs one at a time, so a flood of uploads must not pile up. */
  function checkQueueRoom(user) {
    const mine = db.get("SELECT COUNT(*) AS n FROM posts WHERE user_id = ? AND status = 'PROCESSING'", [user.id]).n;
    if (mine >= MAX_PROCESSING_PER_USER) {
      throw new HttpError(429, `You already have ${mine} videos being processed. Wait for them to finish.`);
    }
    const all = db.get("SELECT COUNT(*) AS n FROM posts WHERE status = 'PROCESSING'").n;
    if (all >= MAX_PROCESSING_TOTAL) {
      throw new HttpError(503, 'The server is busy processing videos. Try again in a minute.');
    }
  }

  /**
   * A post made in the editor (docs/EDITOR_PLAN.md): the recipe and its input files are stored, the post is PROCESSING,
   * and the job queue renders the video and analyses it. `files` are names inside the compose folder.
   * @param {{user, recipe: object, files: {video?: string, photos?: string[], music?: string}, parentId?, title?, body?}} input
   */
  async function createComposed({ user, recipe, files, parentId, title, body, promptDay, roomId, removeInputs }) {
    try {
      body = (body || '').trim() || null;
      title = (title || '').trim() || null;
      if (body && chars(body) > MAX_TEXT) throw new HttpError(400, `Caption is limited to ${MAX_TEXT} characters`, { field: 'body' });
      if (title && chars(title) > MAX_TITLE) throw new HttpError(400, `Title is limited to ${MAX_TITLE} characters`, { field: 'title' });
      const parent = loadParent(user, parentId);
      const context = checkContext(user, parent, promptDay, roomId);
      checkQueueRoom(user);

      const id = uuid();
      db.run(
        `INSERT INTO posts (id, user_id, kind, parent_id, root_id, depth, title, body, media_filename, stance, status, recipe, prompt_day, room_id, created_at)
         VALUES (?, ?, 'VIDEO', ?, ?, ?, ?, ?, NULL, ?, 'PROCESSING', ?, ?, ?, ?)`,
        [
          id, user.id, parent ? parent.id : null, parent ? parent.root_id : id, parent ? parent.depth + 1 : 0,
          parent ? null : title, body, parent ? 'UNRESOLVED' : 'PARENT', JSON.stringify({ render: recipe, files }),
          context.promptDay, context.roomId, nowIso()
        ]
      );
      jobs.enqueue(id);
      return toItem(db, getPost(db, id), user.id);
    } catch (err) {
      if (removeInputs) removeInputs();
      throw err;
    }
  }

  async function createPost({ user, kind, parentId, title, body, promptDay, roomId, file }) {
    try {
      kind = String(kind || '').toUpperCase();
      if (kind !== 'VIDEO' && kind !== 'TEXT') throw new HttpError(400, 'kind must be VIDEO or TEXT');

      body = (body || '').trim() || null;
      title = (title || '').trim() || null;
      if (body && chars(body) > MAX_TEXT) throw new HttpError(400, `Text is limited to ${MAX_TEXT} characters`);
      if (title && chars(title) > MAX_TITLE) throw new HttpError(400, `Title is limited to ${MAX_TITLE} characters`);

      const parent = loadParent(user, parentId);
      const context = checkContext(user, parent, promptDay, roomId);

      if (kind === 'TEXT') {
        if (!parent) throw new HttpError(400, 'Text posts must be replies');
        if (!body) throw new HttpError(400, 'Write something first');
        if (file) throw new HttpError(400, 'Text posts cannot include a file');
      } else if (!file) {
        throw new HttpError(400, 'A video file is required');
      }

      if (kind === 'VIDEO') checkQueueRoom(user);

      let stance = 'PARENT';
      if (parent) {
        stance = kind === 'TEXT'
          ? normalizeStance(await withTimeout(
              analyzer.classifyReplyText(body, contextOf(parent)), textClassifyTimeoutMs, 'UNRESOLVED'))
          : 'UNRESOLVED'; // video: replaced once analysis finishes
      }

      const id = uuid();
      // Automatic first pass for text: a configured word hides it from everyone but the author (who sees it as posted).
      const hit = kind === 'TEXT' && moderation ? moderation.screenText(body) : null;
      db.run(
        `INSERT INTO posts (id, user_id, kind, parent_id, root_id, depth, title, body,
                            media_filename, stance, status, prompt_day, room_id, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          id, user.id, kind,
          parent ? parent.id : null,
          parent ? parent.root_id : id,
          parent ? parent.depth + 1 : 0,
          parent ? null : title, // replies carry a caption in body, not a title
          body,
          file ? file.filename : null,
          stance,
          kind === 'VIDEO' ? 'PROCESSING' : (hit ? 'HIDDEN' : 'READY'),
          context.promptDay, context.roomId, nowIso()
        ]
      );
      if (hit) moderation.log('auto', 'HIDE', { postId: id, userId: user.id, reason: 'AUTO_SCREEN', note: `matched "${hit}"` });
      if (kind === 'VIDEO') jobs.enqueue(id);
      return toItem(db, getPost(db, id), user.id);
    } catch (err) {
      if (file) fs.rmSync(file.path, { force: true }); // don't leave orphan uploads
      throw err;
    }
  }

  return { createPost, createComposed };
}

module.exports = { createPostService, MAX_TEXT, MAX_TITLE, MAX_PROCESSING_PER_USER, MAX_PROCESSING_TOTAL };
