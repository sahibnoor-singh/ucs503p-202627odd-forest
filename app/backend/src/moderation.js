// Moderation, demo level (see docs/LAST_STAGE_POLISH.md for what is missing).
// A person (the admin page) or the automatic screen can HIDE a post. Hidden posts get status 'HIDDEN', which is not
// READY, so every feed, thread and Discover query already skips them. Everything is written to moderation_log.

const { nowIso } = require('./queries');

const REPORT_REASONS = ['MISINFORMATION', 'HARASSMENT', 'SPAM', 'VIOLENCE', 'COPYRIGHT', 'OTHER'];
const COPYRIGHT_STRIKE_LIMIT = 3; // upheld copyright takedowns before an account is suspended

function createModeration({ db, blocklist = [], strikeLimit = COPYRIGHT_STRIKE_LIMIT }) {
  const words = blocklist.map((w) => w.trim().toLowerCase()).filter(Boolean);

  function log(actor, action, { postId = null, userId = null, reason = null, note = null } = {}) {
    db.run('INSERT INTO moderation_log (at, actor, action, post_id, user_id, reason, note) VALUES (?, ?, ?, ?, ?, ?, ?)', [
      nowIso(), actor, action, postId, userId, reason, note
    ]);
  }

  /** The first listed word found in [text], or null. Whole-word, case-insensitive. The list comes from config (empty by default). */
  function screenText(text) {
    if (!words.length || !text) return null;
    const lower = String(text).toLowerCase();
    return words.find((w) => new RegExp(`(^|[^\\p{L}\\p{N}])${w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}($|[^\\p{L}\\p{N}])`, 'u').test(lower)) || null;
  }

  /** Hides a visible post. Returns false if it was not READY (nothing to hide). */
  function hidePost(postId, { actor = 'admin', reason = null, note = null } = {}) {
    const post = db.get('SELECT * FROM posts WHERE id = ?', [postId]);
    if (!post || post.status !== 'READY') return false;
    db.tx(() => {
      db.run("UPDATE posts SET status = 'HIDDEN' WHERE id = ?", [postId]);
      db.run("UPDATE reports SET status = 'ACTIONED' WHERE post_id = ? AND status = 'OPEN'", [postId]);
      log(actor, 'HIDE', { postId, userId: post.user_id, reason, note });
      if (reason === 'COPYRIGHT') enforceStrikes(post.user_id);
    });
    return true;
  }

  function restorePost(postId, { actor = 'admin', note = null } = {}) {
    const post = db.get('SELECT * FROM posts WHERE id = ?', [postId]);
    if (!post || post.status !== 'HIDDEN') return false;
    db.tx(() => {
      db.run("UPDATE posts SET status = 'READY' WHERE id = ?", [postId]);
      log(actor, 'RESTORE', { postId, userId: post.user_id, note });
    });
    return true;
  }

  /** Closes the open reports on a post without hiding it. */
  function dismissReports(postId, { actor = 'admin', note = null } = {}) {
    const n = db.run("UPDATE reports SET status = 'DISMISSED' WHERE post_id = ? AND status = 'OPEN'", [postId]);
    if (n) {
      const post = db.get('SELECT user_id FROM posts WHERE id = ?', [postId]);
      log(actor, 'DISMISS', { postId, userId: post && post.user_id, note });
    }
    return n;
  }

  /** Repeat-infringer rule: N upheld copyright hides that were not restored -> the account is suspended. */
  function enforceStrikes(userId) {
    const strikes = db.get(
      `SELECT COUNT(*) AS n FROM moderation_log l
       WHERE l.user_id = ? AND l.action = 'HIDE' AND l.reason = 'COPYRIGHT'
         AND NOT EXISTS (SELECT 1 FROM moderation_log r WHERE r.post_id = l.post_id AND r.action = 'RESTORE' AND r.id > l.id)`,
      [userId]
    ).n;
    if (strikes >= strikeLimit) suspend(userId, `${strikes} upheld copyright takedowns`);
  }

  function suspend(userId, note) {
    const user = db.get('SELECT suspended_at FROM users WHERE id = ?', [userId]);
    if (!user || user.suspended_at) return;
    db.run('UPDATE users SET suspended_at = ? WHERE id = ?', [nowIso(), userId]);
    log('admin', 'SUSPEND', { userId, reason: 'COPYRIGHT', note });
  }

  function unsuspend(userId, note) {
    const n = db.run('UPDATE users SET suspended_at = NULL WHERE id = ? AND suspended_at IS NOT NULL', [userId]);
    if (n) log('admin', 'UNSUSPEND', { userId, note });
    return n > 0;
  }

  return { screenText, hidePost, restorePost, dismissReports, suspend, unsuspend, log };
}

module.exports = { createModeration, REPORT_REASONS, COPYRIGHT_STRIKE_LIMIT };
