// Copies the `videos` table of an old Website backend database (FOREST.db,
// e.g. the one on the Oracle server) into this app's `posts` table.
//
//   npm run import-legacy -- <path\to\FOREST.db> [--uploads <old uploads dir>]
//
// Safe to run twice: rows whose id already exists are skipped. The old
// database is only read. Only READY videos are imported. The authors become
// bot-labelled placeholder users, because the old site had no real accounts.

const fs = require('fs');
const path = require('path');
const initSqlJs = require('sql.js');
const { v4: uuid } = require('uuid');
const { normalizeStance } = require('../src/services/geminiService');

const ROOT = path.join(__dirname, '..');

async function importLegacy(db, legacyDbFile, { uploadsFrom = null, uploadsDir = path.join(ROOT, 'uploads') } = {}) {
  const SQL = await initSqlJs();
  const legacy = new SQL.Database(fs.readFileSync(legacyDbFile));
  const result = legacy.exec('SELECT * FROM videos ORDER BY created_at ASC');
  legacy.close();
  const cols = result.length ? result[0].columns : [];
  const rows = (result.length ? result[0].values : []).map((v) => Object.fromEntries(cols.map((c, i) => [c, v[i]])));

  const summary = { imported: 0, skippedExisting: 0, skippedNotReady: 0, missingMedia: 0, orphanedReplies: 0 };
  const byId = new Map(rows.map((r) => [String(r.id), r]));
  const done = new Set();
  if (uploadsFrom) fs.mkdirSync(uploadsDir, { recursive: true });

  function userFor(rawName) {
    const name = String(rawName || 'legacy_user').toLowerCase().replace(/[^a-z0-9._]/g, '_').slice(0, 30);
    const username = name.length >= 3 ? name : 'legacy_user';
    let u = db.get('SELECT id FROM users WHERE username = ? COLLATE NOCASE', [username]);
    if (!u) {
      db.run('INSERT INTO users (id, username, full_name, is_bot, created_at) VALUES (?, ?, ?, 1, ?)', [
        uuid(), username, username, new Date().toISOString()
      ]);
      u = db.get('SELECT id FROM users WHERE username = ? COLLATE NOCASE', [username]);
    }
    return u.id;
  }

  function importRow(row) {
    const id = String(row.id);
    if (done.has(id)) return;
    done.add(id);

    let parent = null;
    if (row.parent_video_id) {
      const legacyParent = byId.get(String(row.parent_video_id));
      if (legacyParent) importRow(legacyParent); // parents first
      parent = db.get('SELECT * FROM posts WHERE id = ?', [String(row.parent_video_id)]);
      if (!parent) summary.orphanedReplies++; // parent missing or not imported: becomes a root
    }
    if (db.get('SELECT 1 AS x FROM posts WHERE id = ?', [id])) return void summary.skippedExisting++;
    if (row.status !== 'READY') return void summary.skippedNotReady++;

    if (uploadsFrom && row.filename) {
      const src = path.join(uploadsFrom, row.filename);
      if (fs.existsSync(src)) fs.copyFileSync(src, path.join(uploadsDir, row.filename));
      else summary.missingMedia++;
    }
    db.run(
      `INSERT INTO posts (id, user_id, kind, parent_id, root_id, depth, title, body, media_filename,
                          stance, status, analysis, created_at)
       VALUES (?, ?, 'VIDEO', ?, ?, ?, ?, NULL, ?, ?, 'READY', ?, ?)`,
      [
        id, userFor(row.user_id),
        parent ? parent.id : null, parent ? parent.root_id : id, parent ? parent.depth + 1 : 0,
        row.title || null, row.filename || null,
        parent ? normalizeStance(row.stance) : 'PARENT',
        row.transcript || null, row.created_at || new Date().toISOString()
      ]
    );
    summary.imported++;
  }

  db.tx(() => rows.forEach(importRow));
  return summary;
}

module.exports = { importLegacy };

if (require.main === module) {
  (async () => {
    require('dotenv').config({ path: path.join(ROOT, '.env') });
    const { openDb } = require('../src/db');
    const args = process.argv.slice(2);
    const legacyFile = args.find((a) => !a.startsWith('--') && args[args.indexOf(a) - 1] !== '--uploads');
    const up = args.indexOf('--uploads');
    if (!legacyFile) {
      console.error('Usage: npm run import-legacy -- <path/to/FOREST.db> [--uploads <old uploads dir>]');
      process.exit(1);
    }
    const dbFile = path.resolve(ROOT, process.env.DB_FILE || 'data/forest-app.db');
    const db = await openDb({ file: dbFile });
    try {
      const out = await importLegacy(db, legacyFile, {
        uploadsFrom: up >= 0 ? args[up + 1] : null,
        uploadsDir: path.resolve(ROOT, process.env.UPLOADS_DIR || 'uploads')
      });
      console.log(out);
    } finally {
      db.close();
    }
  })();
}
