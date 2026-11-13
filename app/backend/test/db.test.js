const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { openDb } = require('../src/db');

const tmpFile = () => path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'forest-dbtest-')), 'app.db');
const addUser = (db, name) => db.run(
  'INSERT INTO users (id, username, full_name, created_at) VALUES (?, ?, ?, ?)', [name, name, name, 'now']);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

test('immediate mode (default) writes after every change', async () => {
  const file = tmpFile();
  const db = await openDb({ file });
  const base = db.stats.saves;
  for (let i = 0; i < 5; i++) addUser(db, `u${i}`);
  assert.equal(db.stats.saves - base, 5);
  db.close();
  const again = await openDb({ file });
  assert.equal(again.get('SELECT COUNT(*) AS n FROM users').n, 5);
  again.close();
});

test('coalesced mode: many changes become one write, and nothing is lost', async () => {
  const file = tmpFile();
  const db = await openDb({ file, saveDelayMs: 40 });
  const base = db.stats.saves;
  for (let i = 0; i < 200; i++) addUser(db, `u${i}`);
  assert.equal(db.stats.saves - base, 0, 'no write yet, they are queued');
  await sleep(120);
  assert.equal(db.stats.saves - base, 1, 'one write covers all 200 changes');
  const onDisk = await openDb({ file }); // a second reader sees them
  assert.equal(onDisk.get('SELECT COUNT(*) AS n FROM users').n, 200);
  onDisk.close();
  db.close();
});

test('flush() and close() write pending changes immediately', async () => {
  const file = tmpFile();
  const db = await openDb({ file, saveDelayMs: 60000 }); // would never fire on its own in this test
  addUser(db, 'a');
  db.flush();
  let check = await openDb({ file });
  assert.equal(check.get('SELECT COUNT(*) AS n FROM users').n, 1);
  check.close();

  addUser(db, 'b');
  db.close(); // close must not drop the pending change
  check = await openDb({ file });
  assert.equal(check.get('SELECT COUNT(*) AS n FROM users').n, 2);
  check.close();
});

test('a transaction is written once, and a rolled-back one is not written at all', async () => {
  const file = tmpFile();
  const db = await openDb({ file });
  const base = db.stats.saves;
  db.tx(() => { addUser(db, 'a'); addUser(db, 'b'); addUser(db, 'c'); });
  assert.equal(db.stats.saves - base, 1);
  assert.throws(() => db.tx(() => { addUser(db, 'd'); throw new Error('nope'); }), /nope/);
  assert.equal(db.stats.saves - base, 1);
  assert.equal(db.get('SELECT COUNT(*) AS n FROM users').n, 3);
  db.close();
});

test('memory databases never touch the disk and flush is harmless', async () => {
  const db = await openDb();
  addUser(db, 'a');
  db.flush();
  assert.equal(db.stats.saves, 0);
  assert.equal(db.file, null);
  db.close();
});

test('no stray temp file is left behind after saving', async () => {
  const file = tmpFile();
  const db = await openDb({ file, saveDelayMs: 10 });
  addUser(db, 'a');
  await sleep(60);
  db.close();
  assert.deepEqual(fs.readdirSync(path.dirname(file)).sort(), ['app.db']);
});
