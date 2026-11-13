// SQLite via sql.js (pure JS, no native build). The whole DB lives in memory and
// is written to one file after every committed change, same approach as the
// original Website backend. Fine for the closed alpha; moves to Postgres later.

const fs = require('fs');
const path = require('path');
const initSqlJs = require('sql.js');

const SCHEMA = `
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL UNIQUE COLLATE NOCASE,
  full_name TEXT NOT NULL,
  is_bot INTEGER NOT NULL DEFAULT 0,
  avatar_url TEXT,
  bio TEXT,
  -- Filled in by the accounts slice (phone/OTP sign-up). Nullable until then.
  phone TEXT,
  phone_verified INTEGER NOT NULL DEFAULT 0,
  email TEXT,
  email_verified INTEGER NOT NULL DEFAULT 0, -- 1 when the address was confirmed with a code at sign-up (or by Google)
  invite_code TEXT,                   -- what this person hands to friends (src/invites.js); made the first time it is asked for
  invited_by TEXT,                    -- the person whose code they signed up with
  onboarded_at TEXT,                  -- when they finished (or skipped) the first-run topic and follow pages; NULL = not yet (see routes/users.js)
  google_sub TEXT,                    -- Google's id for this person when they signed up with Google (see auth/google.js)
  dob TEXT,
  password_hash TEXT,
  friend_taste INTEGER NOT NULL DEFAULT 1, -- 1: friends' taste may shape this person's Discover (see friendTaste.js)
  personality_keywords TEXT,
  personality_summary TEXT,
  personality_summary_approved INTEGER NOT NULL DEFAULT 0,
  interests TEXT,
  suspended_at TEXT,                  -- set by moderation (e.g. 3 upheld copyright takedowns); the account cannot be used
  deleted_at TEXT,                    -- set when the person deletes their account (personal data is wiped, see routes/users.js)
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS follows (
  follower_id TEXT NOT NULL,
  followee_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (follower_id, followee_id)
);

CREATE INDEX IF NOT EXISTS idx_follows_followee ON follows(followee_id);

-- A phone number or e-mail belongs to one account (blank ones don't count).
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email COLLATE NOCASE) WHERE email IS NOT NULL;

-- Sign-up verification codes (stored hashed, see src/auth/otp.js). The key is a phone number or an e-mail address:
-- the column is still called "phone" from before e-mail existed, and the two can never collide (an address has an @).
CREATE TABLE IF NOT EXISTS otp_codes (
  phone TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_sent_at INTEGER NOT NULL,
  day TEXT NOT NULL,
  day_count INTEGER NOT NULL DEFAULT 0
);

-- One node type for the whole debate graph: opinions (depth 0) and replies.
CREATE TABLE IF NOT EXISTS posts (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  kind TEXT NOT NULL,                 -- VIDEO | TEXT
  parent_id TEXT,                     -- NULL for a root opinion
  root_id TEXT NOT NULL,              -- = id for roots
  depth INTEGER NOT NULL DEFAULT 0,   -- 0 root, 1 reply, 2 reply-to-reply ...
  title TEXT,
  body TEXT,                          -- text reply, or optional caption (<= 280)
  media_filename TEXT,
  cover_filename TEXT,                -- editor posts: a JPEG of the picture to show before the video plays (uploads/)
  stance TEXT NOT NULL DEFAULT 'PARENT', -- PARENT | FOR | AGAINST | UNRESOLVED
  status TEXT NOT NULL DEFAULT 'READY',  -- PROCESSING | READY | FAILED
  analysis TEXT,                      -- Gemini JSON (transcript, summary, claims)
  recipe TEXT,                        -- editor posts only: JSON {render, files} until the server has rendered the video (then NULL)
  prompt_day TEXT,                    -- the daily question (YYYY-MM-DD, see prompts.js) this opinion answers; roots only
  room_id TEXT,                       -- the motion room this opinion was posted into (rooms.js); roots only
  room_stance TEXT,                   -- FOR | AGAINST | UNRESOLVED: where the AI places a room post against the room's motion
  search_text TEXT,                   -- lower-cased title + body + transcript + summary, kept by triggers (see migrate); what search reads
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_posts_parent ON posts(parent_id);
CREATE INDEX IF NOT EXISTS idx_posts_root ON posts(root_id);
CREATE INDEX IF NOT EXISTS idx_posts_user_time ON posts(user_id, created_at);

CREATE TABLE IF NOT EXISTS likes (
  user_id TEXT NOT NULL,
  post_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (user_id, post_id)
);
CREATE INDEX IF NOT EXISTS idx_likes_post ON likes(post_id);

CREATE TABLE IF NOT EXISTS reports (
  id TEXT PRIMARY KEY,
  reporter_id TEXT NOT NULL,
  post_id TEXT NOT NULL,
  reason TEXT NOT NULL,
  created_at TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'OPEN',  -- OPEN | ACTIONED (post hidden) | DISMISSED (no violation)
  UNIQUE (reporter_id, post_id)
);

-- Every moderation decision, by a person or the automatic screen. Kept for the complaints process and regulators.
CREATE TABLE IF NOT EXISTS moderation_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  at TEXT NOT NULL,
  actor TEXT NOT NULL,                -- 'admin' | 'auto'
  action TEXT NOT NULL,               -- HIDE | RESTORE | DISMISS | SUSPEND | UNSUSPEND
  post_id TEXT,
  user_id TEXT,                       -- the author affected
  reason TEXT,
  note TEXT
);
CREATE INDEX IF NOT EXISTS idx_modlog_user ON moderation_log(user_id, action, reason);

-- "Report a problem" / appeals sent by people. Answered by the grievance officer.
CREATE TABLE IF NOT EXISTS complaints (
  id TEXT PRIMARY KEY,
  user_id TEXT,                       -- null when sent signed out
  contact TEXT,                       -- how to reach them (e-mail), optional
  post_id TEXT,
  message TEXT NOT NULL,
  created_at TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'OPEN',  -- OPEN | RESOLVED
  reply TEXT,
  resolved_at TEXT
);

-- Discover: which side a viewer took on a video, what they watched, and what we learned about their taste.
CREATE TABLE IF NOT EXISTS viewer_opinions (
  user_id TEXT NOT NULL,
  post_id TEXT NOT NULL,
  side TEXT NOT NULL,                 -- FOR | AGAINST
  created_at TEXT NOT NULL,
  PRIMARY KEY (user_id, post_id)
);
CREATE INDEX IF NOT EXISTS idx_opinions_post ON viewer_opinions(post_id);

CREATE TABLE IF NOT EXISTS post_views (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  post_id TEXT NOT NULL,
  watched_ms INTEGER NOT NULL DEFAULT 0,
  completed INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_views_post ON post_views(post_id);

-- Motion rooms (src/rooms.js): a society debates one motion for a few days.
CREATE TABLE IF NOT EXISTS rooms (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,          -- six characters, typed to join
  name TEXT NOT NULL,
  motion TEXT NOT NULL,               -- the statement being debated
  description TEXT,
  owner_id TEXT NOT NULL,
  starts_at TEXT,
  ends_at TEXT,
  closed_at TEXT,                     -- the owner closed it early, or left the app
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS room_members (
  room_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'MEMBER', -- OWNER | MEMBER
  joined_at TEXT NOT NULL,
  PRIMARY KEY (room_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_room_members_user ON room_members(user_id);

-- Product events (src/events.js): what people do, as small flags, for the founders' page.
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT,                       -- cleared when the person deletes their account
  name TEXT NOT NULL,
  props TEXT,                         -- small JSON of flags and numbers
  day TEXT NOT NULL,                  -- YYYY-MM-DD in the prompt time zone
  at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_events_day ON events(day, name);

CREATE TABLE IF NOT EXISTS user_profiles (
  user_id TEXT PRIMARY KEY,
  data TEXT NOT NULL,                 -- JSON: topics, creators, recentViews, counts (see src/recommendation.js)
  updated_at TEXT NOT NULL
);

-- A video one person sent to another (the paper-plane button). No message, no chat: just the post.
-- What the recipient does with it is read from post_views and likes, so nothing else is stored here.
CREATE TABLE IF NOT EXISTS shares (
  id TEXT PRIMARY KEY,
  sender_id TEXT NOT NULL,
  recipient_id TEXT NOT NULL,
  post_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  opened_at TEXT,                     -- when the recipient first opened it from their Discover
  UNIQUE (sender_id, recipient_id, post_id)
);
CREATE INDEX IF NOT EXISTS idx_shares_recipient ON shares(recipient_id, created_at);
CREATE INDEX IF NOT EXISTS idx_shares_sender ON shares(sender_id, created_at);

-- Notifications: something happened that the person should hear about. Today only 'follow' ("@x followed you", with the post they
-- followed from, when it was a reel). One row per (person, kind, actor), so following, unfollowing and following again never repeats it.
CREATE TABLE IF NOT EXISTS notifications (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,              -- who is told
  kind TEXT NOT NULL,                 -- 'follow'
  actor_id TEXT NOT NULL,             -- who did it
  post_id TEXT,                       -- the video it happened on (a follow from a reel), or NULL
  created_at TEXT NOT NULL,
  read_at TEXT,
  UNIQUE (user_id, kind, actor_id)
);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, created_at);

-- Direct messages: one conversation per pair of people (user_lo < user_hi). Only videos are sent (kind VIDEO) and the only reply is an
-- emoji reaction to one (kind REACTION: body = the emoji, ref_id = the video message it is about, so the sender is told); there is no
-- free text. One reaction per person per video message, and when each person last read the conversation (unread = messages from
-- the other person after that).
CREATE TABLE IF NOT EXISTS conversations (
  id TEXT PRIMARY KEY,
  user_lo TEXT NOT NULL,
  user_hi TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_message_at TEXT NOT NULL,
  UNIQUE (user_lo, user_hi)
);
CREATE INDEX IF NOT EXISTS idx_conversations_hi ON conversations(user_hi, last_message_at);
CREATE INDEX IF NOT EXISTS idx_conversations_lo ON conversations(user_lo, last_message_at);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  kind TEXT NOT NULL,                 -- VIDEO | REACTION
  body TEXT,                          -- the emoji (REACTION)
  post_id TEXT,                       -- the video that was sent (VIDEO)
  ref_id TEXT,                        -- the video message a REACTION is about
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, created_at);

CREATE TABLE IF NOT EXISTS message_reactions (
  message_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  emoji TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (message_id, user_id)
);

CREATE TABLE IF NOT EXISTS conversation_reads (
  conversation_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  read_at TEXT NOT NULL,
  PRIMARY KEY (conversation_id, user_id)
);

CREATE TABLE IF NOT EXISTS blocks (
  blocker_id TEXT NOT NULL,
  blocked_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (blocker_id, blocked_id)
);

CREATE TABLE IF NOT EXISTS bookmarks (
  user_id TEXT NOT NULL,
  post_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (user_id, post_id)
);
CREATE INDEX IF NOT EXISTS idx_bookmarks_user ON bookmarks(user_id, created_at);
`;

/**
 * CREATE TABLE IF NOT EXISTS never changes a table that already exists, so a column added later has to be
 * added to old database files here. Each step must be safe to run on every start.
 */
function migrate(raw) {
  const columns = (table) => {
    const stmt = raw.prepare(`PRAGMA table_info(${table})`);
    const names = [];
    while (stmt.step()) names.push(stmt.getAsObject().name);
    stmt.free();
    return names;
  };
  if (!columns('users').includes('deleted_at')) raw.run('ALTER TABLE users ADD COLUMN deleted_at TEXT');
  if (!columns('posts').includes('recipe')) raw.run('ALTER TABLE posts ADD COLUMN recipe TEXT');
  if (!columns('posts').includes('cover_filename')) raw.run('ALTER TABLE posts ADD COLUMN cover_filename TEXT');
  if (!columns('users').includes('email_verified')) raw.run('ALTER TABLE users ADD COLUMN email_verified INTEGER NOT NULL DEFAULT 0');
  if (!columns('users').includes('onboarded_at')) {
    raw.run('ALTER TABLE users ADD COLUMN onboarded_at TEXT');
    raw.run('UPDATE users SET onboarded_at = created_at'); // everyone who already had an account is past the first-run pages
  }
  if (!columns('users').includes('invite_code')) raw.run('ALTER TABLE users ADD COLUMN invite_code TEXT');
  if (!columns('users').includes('invited_by')) raw.run('ALTER TABLE users ADD COLUMN invited_by TEXT');
  if (!columns('posts').includes('prompt_day')) raw.run('ALTER TABLE posts ADD COLUMN prompt_day TEXT');
  if (!columns('posts').includes('room_id')) raw.run('ALTER TABLE posts ADD COLUMN room_id TEXT');
  if (!columns('posts').includes('room_stance')) raw.run('ALTER TABLE posts ADD COLUMN room_stance TEXT');
  // indexes on the columns above live here, not in the schema, because on an older database the columns only exist after the lines above
  raw.run('CREATE UNIQUE INDEX IF NOT EXISTS idx_users_invite ON users(invite_code) WHERE invite_code IS NOT NULL');
  raw.run('CREATE INDEX IF NOT EXISTS idx_posts_prompt ON posts(prompt_day) WHERE prompt_day IS NOT NULL');
  raw.run('CREATE INDEX IF NOT EXISTS idx_posts_room ON posts(room_id, created_at) WHERE room_id IS NOT NULL');
  if (!columns('users').includes('google_sub')) raw.run('ALTER TABLE users ADD COLUMN google_sub TEXT');
  // here, not in the schema above, because on a database from before Google sign-in the column only exists after the line above
  raw.run('CREATE UNIQUE INDEX IF NOT EXISTS idx_users_google ON users(google_sub) WHERE google_sub IS NOT NULL');
  if (!columns('users').includes('friend_taste')) raw.run('ALTER TABLE users ADD COLUMN friend_taste INTEGER NOT NULL DEFAULT 1');
  if (!columns('messages').includes('ref_id')) raw.run('ALTER TABLE messages ADD COLUMN ref_id TEXT');
  const hadSearchText = columns('posts').includes('search_text');
  if (!hadSearchText) raw.run('ALTER TABLE posts ADD COLUMN search_text TEXT');
  if (!columns('users').includes('suspended_at')) raw.run('ALTER TABLE users ADD COLUMN suspended_at TEXT');
  if (!columns('reports').includes('status')) raw.run("ALTER TABLE reports ADD COLUMN status TEXT NOT NULL DEFAULT 'OPEN'");

  // Profile personality fields
  const cols = new Set(columns('users'));
  if (!cols.has('personality_keywords')) raw.run('ALTER TABLE users ADD COLUMN personality_keywords TEXT');
  if (!cols.has('personality_summary')) raw.run('ALTER TABLE users ADD COLUMN personality_summary TEXT');
  if (!cols.has('personality_summary_approved')) raw.run("ALTER TABLE users ADD COLUMN personality_summary_approved INTEGER NOT NULL DEFAULT 0");
  if (!cols.has('interests')) raw.run('ALTER TABLE users ADD COLUMN interests TEXT');

  // search_text is always rebuilt by the database itself whenever a post's words change, so no write path can forget it (and an
  // account deletion, which empties title/body/analysis, empties it too). Recreated on every start so a change here takes effect.
  const words = (row) => `lower(
    coalesce(${row}.title, '') || ' ' || coalesce(${row}.body, '') || ' ' ||
    coalesce(CASE WHEN json_valid(${row}.analysis) THEN json_extract(${row}.analysis, '$.transcript') END, '') || ' ' ||
    coalesce(CASE WHEN json_valid(${row}.analysis) THEN json_extract(${row}.analysis, '$.overallSummary') END, ''))`;
  raw.run('DROP TRIGGER IF EXISTS posts_search_insert');
  raw.run('DROP TRIGGER IF EXISTS posts_search_update');
  raw.run(`CREATE TRIGGER posts_search_insert AFTER INSERT ON posts
           BEGIN UPDATE posts SET search_text = ${words('new')} WHERE id = new.id; END`);
  raw.run(`CREATE TRIGGER posts_search_update AFTER UPDATE OF title, body, analysis ON posts
           BEGIN UPDATE posts SET search_text = ${words('new')} WHERE id = new.id; END`);
  if (!hadSearchText) raw.run('UPDATE posts SET title = title'); // fills it in for the posts that already exist
}

/**
 * @param {object} opts
 * @param {string|null} [opts.file]  path of the .db file; omit / ':memory:' for tests.
 * @param {number} [opts.saveDelayMs]  0 (default) writes after every change. A positive value
 *   coalesces changes: one write at most every saveDelayMs, and never more than ~10% of the time
 *   (the delay stretches to 9x the last write's duration, so a big database can't hog the server).
 *   A crash can lose up to that delay of changes. flush() / close() / a clean shutdown write at once.
 */
async function openDb({ file = null, saveDelayMs = 0 } = {}) {
  const SQL = await initSqlJs();
  const persistent = file && file !== ':memory:';

  let raw;
  if (persistent && fs.existsSync(file)) {
    raw = new SQL.Database(fs.readFileSync(file));
  } else {
    raw = new SQL.Database();
  }
  raw.run(SCHEMA);
  migrate(raw);

  let txDepth = 0;
  let dirty = false;
  let timer = null;
  let lastWriteMs = 0;
  const stats = { saves: 0 };

  function writeNow() {
    const started = Date.now();
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = `${file}.tmp`;
    fs.writeFileSync(tmp, Buffer.from(raw.export()));
    fs.renameSync(tmp, file); // atomic: a crash never leaves a half-written DB
    dirty = false;
    stats.saves++;
    lastWriteMs = Date.now() - started;
  }

  /** Writes any pending changes immediately. */
  function flush() {
    if (timer) { clearTimeout(timer); timer = null; }
    if (persistent && dirty) writeNow();
  }

  /** Called after every committed change. */
  function save() {
    if (!persistent || txDepth > 0) return;
    dirty = true;
    if (!saveDelayMs) return writeNow();
    if (timer) return;
    timer = setTimeout(() => {
      timer = null;
      try {
        writeNow();
      } catch (err) {
        console.error('[db] background save failed, will retry on the next change:', err.message);
      }
    }, Math.max(saveDelayMs, lastWriteMs * 9));
    if (timer.unref) timer.unref(); // never keep the process alive just to save
  }

  function all(sql, params = []) {
    const stmt = raw.prepare(sql);
    try {
      stmt.bind(params);
      const rows = [];
      while (stmt.step()) rows.push(stmt.getAsObject());
      return rows;
    } finally {
      stmt.free();
    }
  }

  function get(sql, params = []) {
    return all(sql, params)[0] || null;
  }

  /** Runs a write. Persists per saveDelayMs unless inside tx(). Returns rows changed. */
  function run(sql, params = []) {
    raw.run(sql, params);
    const changed = raw.getRowsModified();
    save();
    return changed;
  }

  /** All-or-nothing group of writes, saved once at the end. */
  function tx(fn) {
    if (txDepth > 0) return fn();
    raw.run('BEGIN');
    txDepth++;
    try {
      const result = fn();
      raw.run('COMMIT');
      txDepth--;
      save();
      return result;
    } catch (err) {
      txDepth--;
      raw.run('ROLLBACK');
      throw err;
    }
  }

  if (persistent) { dirty = true; writeNow(); } // create/refresh the file right away
  return {
    all, get, run, tx, flush, raw, stats,
    file: persistent ? file : null,
    close: () => { flush(); raw.close(); }
  };
}

module.exports = { openDb };
