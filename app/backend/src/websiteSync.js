// One-way: this app's backend sends an anonymous summary of its data to the project website, so the
// website can show live numbers and the debate graph. The website never sends anything back.
// OFF unless WEBSITE_SYNC_URL and WEBSITE_SYNC_TOKEN are both set.
//
// What leaves this machine: counts, and one node per READY post (hashed id, kind, stance, depth, time,
// is-a-bot flag) with the reply edges between them. Titles only when WEBSITE_SYNC_TITLES=1.
// Never sent: phone numbers, e-mails, birth dates, passwords, names, usernames, media files or links,
// AI transcripts, reports' contents.

const crypto = require('crypto');

const MAX_NODES = 1500;
const shortId = (id) => crypto.createHash('sha256').update(String(id)).digest('hex').slice(0, 10);

function buildSnapshot(db, { includeTitles = false, now = () => new Date() } = {}) {
  const n = (sql) => db.get(sql).n;
  const stats = {
    users: n('SELECT COUNT(*) n FROM users WHERE is_bot = 0'),
    bots: n('SELECT COUNT(*) n FROM users WHERE is_bot = 1'),
    opinions: n("SELECT COUNT(*) n FROM posts WHERE parent_id IS NULL AND status = 'READY'"),
    videoReplies: n("SELECT COUNT(*) n FROM posts WHERE parent_id IS NOT NULL AND kind = 'VIDEO' AND status = 'READY'"),
    textReplies: n("SELECT COUNT(*) n FROM posts WHERE parent_id IS NOT NULL AND kind = 'TEXT' AND status = 'READY'"),
    forReplies: n("SELECT COUNT(*) n FROM posts WHERE stance = 'FOR' AND status = 'READY'"),
    againstReplies: n("SELECT COUNT(*) n FROM posts WHERE stance = 'AGAINST' AND status = 'READY'"),
    unresolvedReplies: n("SELECT COUNT(*) n FROM posts WHERE stance = 'UNRESOLVED' AND status = 'READY'"),
    processing: n("SELECT COUNT(*) n FROM posts WHERE status = 'PROCESSING'"),
    failed: n("SELECT COUNT(*) n FROM posts WHERE status = 'FAILED'"),
    likes: n('SELECT COUNT(*) n FROM likes'),
    follows: n('SELECT COUNT(*) n FROM follows'),
    views: n('SELECT COUNT(*) n FROM post_views'),
    reports: n('SELECT COUNT(*) n FROM reports')
  };

  const rows = db.all(
    `SELECT p.id, p.kind, p.parent_id, p.depth, p.stance, p.created_at, p.title, u.is_bot
     FROM posts p JOIN users u ON u.id = p.user_id
     WHERE p.status = 'READY' ORDER BY p.created_at DESC, p.id DESC LIMIT ?`,
    [MAX_NODES]
  );
  const included = new Set(rows.map((r) => r.id));
  const nodes = rows.map((r) => {
    const node = {
      id: shortId(r.id), kind: r.kind, depth: r.depth, stance: r.stance,
      createdAt: r.created_at, isBot: !!r.is_bot
    };
    if (includeTitles && r.title) node.title = String(r.title).slice(0, 80);
    return node;
  });
  const edges = rows
    .filter((r) => r.parent_id && included.has(r.parent_id))
    .map((r) => ({ from: shortId(r.id), to: shortId(r.parent_id) }));

  return { version: 1, generatedAt: now().toISOString(), stats, nodes, edges };
}

/**
 * Pushes a snapshot whenever the data changed (checked every intervalMs). Failures are logged, never thrown,
 * and never affect the app.
 */
function createWebsiteSync({
  db, url, token, includeTitles = false, intervalMs = 60000, fetchImpl = fetch, log = console, timeoutMs = 10000
}) {
  let lastHash = null;
  let timer = null;
  let running = false;
  let lastError = null;

  async function pushOnce({ force = false } = {}) {
    if (running) return { skipped: 'busy' };
    running = true;
    try {
      const snapshot = buildSnapshot(db, { includeTitles });
      const { generatedAt, ...rest } = snapshot;
      const hash = crypto.createHash('sha256').update(JSON.stringify(rest)).digest('hex');
      if (!force && hash === lastHash) return { skipped: 'unchanged' };

      const res = await fetchImpl(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
        body: JSON.stringify(snapshot),
        signal: AbortSignal.timeout(timeoutMs)
      });
      if (!res.ok) throw new Error(`website answered ${res.status}`);
      lastHash = hash;
      if (lastError) log.log('[website-sync] working again');
      lastError = null;
      return { pushed: true, nodes: snapshot.nodes.length };
    } catch (err) {
      if (String(err.message) !== lastError) log.warn(`[website-sync] could not push: ${err.message} (will keep trying quietly)`);
      lastError = String(err.message);
      return { error: err.message };
    } finally {
      running = false;
    }
  }

  function start() {
    pushOnce();
    timer = setInterval(pushOnce, intervalMs);
    if (timer.unref) timer.unref();
  }
  function stop() { if (timer) clearInterval(timer); timer = null; }

  return { start, stop, pushOnce };
}

module.exports = { buildSnapshot, createWebsiteSync };
