// Gives every video that was posted before cover pictures existed its still picture (the Discover grid tile and the poster).
// New uploads get theirs automatically.
//
//   npm run thumbnails:backfill           every video without a cover picture
//   npm run thumbnails:backfill -- --all  redo all of them
//
// No Gemini key needed, only the bundled ffmpeg.
// STOP THE BACKEND FIRST: it keeps the database in memory and would overwrite what this script writes.
// Afterwards run  npm run snapshot:save  if you share the data with a teammate.

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
require('dotenv').config({ path: path.join(ROOT, '.env') });

const { openDb } = require('../src/db');
const { makeThumbnail } = require('../src/services/thumbnailService');

const redoAll = process.argv.includes('--all');

(async () => {
  const dbFile = path.resolve(ROOT, process.env.DB_FILE || 'data/forest-app.db');
  const uploadsDir = path.resolve(ROOT, process.env.UPLOADS_DIR || 'uploads');
  const db = await openDb({ file: dbFile, saveDelayMs: 0 });
  try {
    const rows = db.all(
      `SELECT id, media_filename, cover_filename FROM posts
       WHERE status = 'READY' AND media_filename IS NOT NULL AND media_filename != ''`
    );
    let made = 0, skipped = 0, failed = 0;
    for (const row of rows) {
      const hasPicture = row.cover_filename && fs.existsSync(path.join(uploadsDir, row.cover_filename));
      if (hasPicture && !redoAll) { skipped++; continue; }
      const video = path.join(uploadsDir, row.media_filename);
      if (!fs.existsSync(video)) { console.warn(`  missing file, skipped: ${row.media_filename}`); failed++; continue; }
      const name = `${path.parse(row.media_filename).name}-cover.jpg`;
      if (await makeThumbnail(video, path.join(uploadsDir, name))) {
        db.run('UPDATE posts SET cover_filename = ? WHERE id = ?', [name, row.id]);
        made++;
        console.log(`  ${name}`);
      } else {
        console.warn(`  could not read a picture from ${row.media_filename}`);
        failed++;
      }
    }
    console.log(`\nDone. ${made} picture(s) made, ${skipped} already had one${failed ? `, ${failed} could not be made` : ''}.`);
  } finally {
    db.close();
  }
  process.exit(0);
})().catch((e) => { console.error(e.stack || e.message); process.exit(1); });
