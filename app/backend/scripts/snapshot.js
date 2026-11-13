// Share the exact data you see on your machine (accounts, posts, replies, likes and the videos) with someone else.
//
//   npm run snapshot:save    copy your local database + the videos it uses into  snapshot/  (then commit it)
//   npm run snapshot:load    the other way round: put snapshot/ into data/ and uploads/ (RESETS the local database)
//
// The snapshot folder is committed on purpose so a teammate gets the same videos and posts after a pull. This is for
// the private dev repo only: the videos in it must be removed before any public launch.

const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const ROOT = path.join(__dirname, '..');
const SNAP = path.join(ROOT, 'snapshot');
const dbFile = path.resolve(ROOT, process.env.DB_FILE || 'data/forest-app.db');
const uploadsDir = path.resolve(ROOT, process.env.UPLOADS_DIR || 'uploads');
const mode = process.argv[2];

async function main() {
  if (mode === 'save') {
    if (!fs.existsSync(dbFile)) throw new Error('No local database at ' + dbFile + ' (run the backend or a seed first).');
    const { openDb } = require('../src/db');
    const db = await openDb({ file: dbFile });
    const files = new Set(db.all("SELECT media_filename AS f FROM posts WHERE media_filename IS NOT NULL AND media_filename != ''").map((r) => r.f));
    // cover pictures (the Discover grid tiles) too
    db.all("SELECT cover_filename AS f FROM posts WHERE cover_filename IS NOT NULL AND cover_filename != ''").forEach((r) => files.add(r.f));
    // profile pictures live in the same folder (avatar_url = /uploads/<file>)
    db.all("SELECT avatar_url AS u FROM users WHERE avatar_url LIKE '/uploads/%'").forEach((r) => files.add(path.basename(r.u)));
    db.close();
    fs.rmSync(SNAP, { recursive: true, force: true });
    fs.mkdirSync(path.join(SNAP, 'uploads'), { recursive: true });
    fs.copyFileSync(dbFile, path.join(SNAP, 'forest-app.db'));
    let copied = 0;
    for (const f of files) {
      const src = path.join(uploadsDir, f);
      if (!fs.existsSync(src)) { console.warn('  missing video file, post will show "video not available": ' + f); continue; }
      fs.copyFileSync(src, path.join(SNAP, 'uploads', f));
      copied++;
    }
    console.log(`Saved snapshot/: the database and ${copied} media file(s) (videos, cover pictures and profile pictures). Commit the snapshot folder.`);
  } else if (mode === 'load') {
    if (!fs.existsSync(path.join(SNAP, 'forest-app.db'))) throw new Error('No snapshot/forest-app.db here. Pull the latest code first.');
    fs.mkdirSync(path.dirname(dbFile), { recursive: true });
    fs.mkdirSync(uploadsDir, { recursive: true });
    fs.copyFileSync(path.join(SNAP, 'forest-app.db'), dbFile);
    let copied = 0;
    for (const f of fs.readdirSync(path.join(SNAP, 'uploads'))) {
      fs.copyFileSync(path.join(SNAP, 'uploads', f), path.join(uploadsDir, f));
      copied++;
    }
    console.log(`Loaded the snapshot: database + ${copied} media file(s). Start the backend with  npm start  and sign in as dev / dev_123.`);
  } else {
    throw new Error('Usage: node scripts/snapshot.js save|load');
  }
}

main().then(() => { process.exitCode = 0; }).catch((e) => { console.error('\n' + e.message + '\n'); process.exit(1); });
