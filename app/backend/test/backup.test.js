const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { backup, parseArgs } = require('../scripts/backup');
const { openDb } = require('../src/db');
const { addUser } = require('./helpers');

function setup() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'forest-backup-'));
  return { dir, dbFile: path.join(dir, 'app.db'), uploadsDir: path.join(dir, 'uploads'), out: path.join(dir, 'backups') };
}

test('a backup is a complete database that opens with the same data', async () => {
  const t = setup();
  try {
    const db = await openDb({ file: t.dbFile });
    addUser(db, 'riya');
    db.close();
    const r = backup({ dbFile: t.dbFile, uploadsDir: t.uploadsDir, dir: t.out, now: new Date('2026-10-17T12:30:05.123Z') });
    assert.match(path.basename(r.db), /^forest-app-2026-10-17T12-30-05Z\.db$/);
    const copy = await openDb({ file: r.db });
    assert.equal(copy.get('SELECT username FROM users').username, 'riya');
    copy.close();
    assert.deepEqual(fs.readdirSync(t.out).filter((f) => f.endsWith('.tmp')), [], 'no half-written leftovers');
  } finally { fs.rmSync(t.dir, { recursive: true, force: true }); }
});

test('uploads are copied only when asked, and old backups (with their uploads) are pruned', () => {
  const t = setup();
  try {
    fs.mkdirSync(t.uploadsDir);
    fs.writeFileSync(t.dbFile, 'db');
    fs.writeFileSync(path.join(t.uploadsDir, 'a.mp4'), 'video');
    const day = (n) => new Date(Date.UTC(2026, 9, n, 2, 0, 0));
    const plain = backup({ dbFile: t.dbFile, uploadsDir: t.uploadsDir, dir: t.out, now: day(1) });
    assert.equal(plain.uploads, null);
    for (const n of [2, 3, 4]) backup({ dbFile: t.dbFile, uploadsDir: t.uploadsDir, dir: t.out, now: day(n), keep: 2, withUploads: true });
    const left = fs.readdirSync(t.out).sort();
    assert.deepEqual(left, [
      'forest-app-2026-10-03T02-00-00Z.db', 'forest-app-2026-10-04T02-00-00Z.db',
      'uploads-2026-10-03T02-00-00Z', 'uploads-2026-10-04T02-00-00Z'
    ]);
    assert.equal(fs.readFileSync(path.join(t.out, 'uploads-2026-10-04T02-00-00Z', 'a.mp4'), 'utf8'), 'video');
  } finally { fs.rmSync(t.dir, { recursive: true, force: true }); }
});

test('no database is an error, not an empty backup; bad options are refused', () => {
  const t = setup();
  try {
    assert.throws(() => backup({ dbFile: t.dbFile, uploadsDir: t.uploadsDir, dir: t.out }), /No database/);
    assert.throws(() => parseArgs(['--keep', '0']), /at least 1/);
    assert.throws(() => parseArgs(['--wat']), /Unknown option/);
    assert.deepEqual(parseArgs(['--uploads', '--keep', '5', '--dir', 'x']), { uploads: true, keep: 5, dir: 'x' });
  } finally { fs.rmSync(t.dir, { recursive: true, force: true }); }
});
