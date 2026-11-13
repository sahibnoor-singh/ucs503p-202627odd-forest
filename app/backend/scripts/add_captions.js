// Adds subtitles to videos that were analysed before captions existed. New uploads get captions automatically.
//
//   npm run captions:backfill           every READY video without captions
//   npm run captions:backfill -- --all  redo all of them
//
// Needs a Gemini key (GEMINI_API_KEY / GEMINI_API_KEYS in .env). One short Gemini call per video, one at a time.
// STOP THE BACKEND FIRST: it keeps the database in memory and would overwrite what this script writes.
// Afterwards run  npm run snapshot:save  if you share the data with a teammate.

const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.join(__dirname, '..');
require('dotenv').config({ path: path.join(ROOT, '.env') });

const { openDb } = require('../src/db');
const { extractAudio } = require('../src/services/audioService');
const { transcribeCaptions, hasApiKeys } = require('../src/services/geminiService');

const redoAll = process.argv.includes('--all');

(async () => {
  if (!hasApiKeys()) { console.error('\nNo Gemini key found. Put GEMINI_API_KEY (or GEMINI_API_KEYS=a,b,c) in app/backend/.env.\n'); process.exit(1); }
  const dbFile = path.resolve(ROOT, process.env.DB_FILE || 'data/forest-app.db');
  const uploadsDir = path.resolve(ROOT, process.env.UPLOADS_DIR || 'uploads');
  const db = await openDb({ file: dbFile, saveDelayMs: 0 });
  try {
    const rows = db.all("SELECT id, media_filename, analysis FROM posts WHERE status = 'READY' AND media_filename IS NOT NULL AND media_filename != ''");
    let done = 0, withSpeech = 0, skipped = 0;
    for (const row of rows) {
      let analysis = null;
      try { analysis = row.analysis ? JSON.parse(row.analysis) : null; } catch { /* keep null */ }
      if (!redoAll && analysis && Array.isArray(analysis.captions) && analysis.captions.length) { skipped++; continue; }
      const video = path.join(uploadsDir, row.media_filename);
      if (!fs.existsSync(video)) { console.warn(`  missing file, skipped: ${row.media_filename}`); continue; }
      const audio = path.join(os.tmpdir(), `forest-captions-${row.id}.mp3`);
      try {
        await extractAudio(video, audio);
        const captions = await transcribeCaptions(audio);
        analysis = { ...(analysis || {}), captions };
        db.run('UPDATE posts SET analysis = ? WHERE id = ?', [JSON.stringify(analysis), row.id]);
        done++; if (captions.length) withSpeech++;
        console.log(`  ${row.media_filename}: ${captions.length} caption line(s)`);
      } catch (e) {
        console.warn(`  ${row.media_filename}: failed (${e.message})`);
      } finally {
        fs.rmSync(audio, { force: true });
      }
    }
    console.log(`\nDone. ${done} video(s) processed (${withSpeech} with speech), ${skipped} already had captions.`);
  } finally {
    db.close();
  }
  process.exit(0);
})().catch((e) => { console.error(e.stack || e.message); process.exit(1); });
