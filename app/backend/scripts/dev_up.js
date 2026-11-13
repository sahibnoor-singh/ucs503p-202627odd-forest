// Makes sure the local backend is running, then exits. Gradle runs this before every debug build, so pressing Play on
// main.dart in Android Studio starts the backend too (see app/android/app/build.gradle.kts). Safe to run by hand.
//
//   - already answering on the port  -> does nothing
//   - first run on a machine         -> npm install, and loads snapshot/ (the shared videos and data) if there is no database yet
//   - then starts `node src/server.js` in the background (log: data/backend.log) and waits until it answers
//
// The backend keeps running after Android Studio closes; stop it from Task Manager (node.exe) or by running `npm start`
// yourself after ending it. It never fails the build: any problem is printed and the build goes on.

const fs = require('fs');
const path = require('path');
const http = require('http');
const { spawn, spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
require('dotenv').config({ path: path.join(ROOT, '.env') });
const PORT = Number(process.env.PORT || 3000);

function health() {
  return new Promise((resolve) => {
    const req = http.get({ host: '127.0.0.1', port: PORT, path: '/api/health', timeout: 1500 }, (res) => {
      res.resume();
      resolve(res.statusCode === 200);
    });
    req.on('error', () => resolve(false));
    req.on('timeout', () => { req.destroy(); resolve(false); });
  });
}

async function main() {
  if (await health()) { console.log(`[forest] backend already running on port ${PORT}`); return; }

  const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
  if (!fs.existsSync(path.join(ROOT, 'node_modules'))) {
    console.log('[forest] first run: npm install (a minute or two)...');
    const r = spawnSync(npm, ['install'], { cwd: ROOT, stdio: 'inherit', shell: process.platform === 'win32' });
    if (r.status !== 0) { console.log('[forest] npm install failed; start the backend by hand (see docs/RUN_LOCALLY.md)'); return; }
  }
  const dbFile = path.resolve(ROOT, process.env.DB_FILE || 'data/forest-app.db');
  if (!fs.existsSync(dbFile) && fs.existsSync(path.join(ROOT, 'snapshot', 'forest-app.db'))) {
    console.log('[forest] no local database yet: loading the shared snapshot (videos and data)...');
    spawnSync(process.execPath, [path.join(__dirname, 'snapshot.js'), 'load'], { cwd: ROOT, stdio: 'inherit' });
  }

  fs.mkdirSync(path.join(ROOT, 'data'), { recursive: true });
  const log = fs.openSync(path.join(ROOT, 'data', 'backend.log'), 'a');
  const child = spawn(process.execPath, ['src/server.js'], {
    cwd: ROOT, detached: true, stdio: ['ignore', log, log], windowsHide: true,
  });
  child.unref();

  for (let i = 0; i < 30; i++) {
    await new Promise((r) => setTimeout(r, 500));
    if (await health()) { console.log(`[forest] backend started on port ${PORT}`); return; }
  }
  console.log('[forest] backend did not answer in 15 s; see app/backend/data/backend.log');
}

main().catch((e) => console.log('[forest] could not start the backend: ' + e.message)).then(() => process.exit(0));
