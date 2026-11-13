#!/usr/bin/env node
// Makes a dated copy of the database (and, with --uploads, the video files), then deletes old copies.
//
//   npm run backup                     # data/backups/forest-app-2026-10-17T12-00-00Z.db, keeps the newest 14
//   npm run backup -- --uploads        # also copies uploads/ into data/backups/uploads-<same stamp>/
//   npm run backup -- --keep 30 --dir /mnt/usb/forest
//
// Safe while the server runs: the server writes its database file atomically (write to .tmp, then rename), so a
// copy is always a complete database. Put it in cron for the nightly backup the launch checklist asks for:
//   30 2 * * *  cd /path/to/app/backend && node scripts/backup.js --uploads >> backup.log 2>&1
// A backup that stays on the same disk does not protect against losing the disk: copy the folder off the machine.

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');

function parseArgs(argv) {
  const out = { uploads: false, keep: 14, dir: null };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--uploads') out.uploads = true;
    else if (argv[i] === '--keep') out.keep = Number(argv[++i]);
    else if (argv[i] === '--dir') out.dir = argv[++i];
    else throw new Error(`Unknown option ${argv[i]}`);
  }
  if (!Number.isInteger(out.keep) || out.keep < 1) throw new Error('--keep needs a whole number of at least 1');
  return out;
}

/** @returns {{db: string, uploads: string|null, removed: string[]}} */
function backup({ dbFile, uploadsDir, dir, keep = 14, withUploads = false, now = new Date() }) {
  if (!fs.existsSync(dbFile)) throw new Error(`No database at ${dbFile}`);
  fs.mkdirSync(dir, { recursive: true });
  const stamp = now.toISOString().replace(/\.\d+Z$/, 'Z').replace(/:/g, '-');
  const dbCopy = path.join(dir, `forest-app-${stamp}.db`);
  fs.copyFileSync(dbFile, `${dbCopy}.tmp`);
  fs.renameSync(`${dbCopy}.tmp`, dbCopy); // never leave a half-written backup that looks real

  let uploadsCopy = null;
  if (withUploads && fs.existsSync(uploadsDir)) {
    uploadsCopy = path.join(dir, `uploads-${stamp}`);
    fs.cpSync(uploadsDir, uploadsCopy, { recursive: true });
  }

  // Keep only the newest `keep` backups (the stamp sorts by time). Uploads folders go with their database copy.
  const dbs = fs.readdirSync(dir).filter((f) => /^forest-app-.*\.db$/.test(f)).sort();
  const removed = [];
  for (const old of dbs.slice(0, Math.max(0, dbs.length - keep))) {
    fs.rmSync(path.join(dir, old));
    removed.push(old);
    const sibling = path.join(dir, old.replace(/^forest-app-/, 'uploads-').replace(/\.db$/, ''));
    fs.rmSync(sibling, { recursive: true, force: true });
  }
  return { db: dbCopy, uploads: uploadsCopy, removed };
}

if (require.main === module) {
  require('dotenv').config({ path: path.join(ROOT, '.env') });
  try {
    const args = parseArgs(process.argv.slice(2));
    const result = backup({
      dbFile: path.resolve(ROOT, process.env.DB_FILE || 'data/forest-app.db'),
      uploadsDir: path.resolve(ROOT, process.env.UPLOADS_DIR || 'uploads'),
      dir: path.resolve(ROOT, args.dir || 'data/backups'),
      keep: args.keep,
      withUploads: args.uploads
    });
    console.log(`Backed up to ${result.db}${result.uploads ? ` and ${result.uploads}` : ''}; removed ${result.removed.length} old.`);
  } catch (err) {
    console.error(`Backup failed: ${err.message}`);
    process.exit(1);
  }
}

module.exports = { backup, parseArgs };
