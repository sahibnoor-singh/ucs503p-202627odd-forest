// One command to get a working local backend with videos, on any machine:
//
//   npm run seed:demo          resets the database and fills it with sample people, posts and
//                              8 small generated test videos (made here with the bundled ffmpeg,
//                              so nothing needs to be downloaded or installed)
//   npm run seed:demo -- --media-dir <folder>
//                              the same, but using your own clips from <folder> (the first 8) instead
//
// The videos are plain generated patterns: placeholders so every screen has something to play and
// scroll. To use your own clips instead:  npm run seed -- --reset --media-dir <folder of your clips>

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const mediaArg = (() => { const i = process.argv.indexOf('--media-dir'); return i >= 0 ? process.argv[i + 1] : null; })();
const dir = mediaArg ? path.resolve(mediaArg) : path.join(ROOT, 'data', 'demo-clips');
const ffmpeg = require('ffmpeg-static');

// [name, lavfi source] - different looks so a swipe visibly changes video
const looks = [
  ['demo_1', 'gradients=s=540x960:d=12:r=24:speed=0.03:c0=0x1f6b3a:c1=0x0e1412:c2=0x7bd98f:c3=0x16201c'],
  ['demo_2', 'gradients=s=540x960:d=12:r=24:speed=0.03:c0=0x5b4bb5:c1=0x0e1412:c2=0xa99cf0:c3=0x16201c'],
  ['demo_3', 'gradients=s=540x960:d=12:r=24:speed=0.03:c0=0xb0402f:c1=0x0e1412:c2=0xf2897a:c3=0x16201c'],
  ['demo_4', 'testsrc2=s=540x960:d=12:r=24'],
  ['demo_5', 'mandelbrot=s=540x960:r=24'],
  ['demo_6', 'gradients=s=540x960:d=12:r=24:speed=0.05:c0=0x2563eb:c1=0x0e1412:c2=0x93c5fd:c3=0x16201c'],
  ['demo_7', 'life=s=270x480:r=24:mold=10:ratio=0.1:death_color=#0e1412:life_color=#7bd98f,scale=540:960:flags=neighbor'],
  ['demo_8', 'rgbtestsrc=s=540x960:d=12:r=24'],
];

if (mediaArg && !fs.existsSync(dir)) { console.error('Media folder not found: ' + dir); process.exit(1); }
fs.mkdirSync(dir, { recursive: true });
let made = 0;
for (const [name, src] of mediaArg ? [] : looks) {
  const out = path.join(dir, name + '.mp4');
  if (fs.existsSync(out) && fs.statSync(out).size > 10000) continue;
  const r = spawnSync(ffmpeg, [
    '-y', '-loglevel', 'error', '-f', 'lavfi', '-i', src, '-t', '12',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '30', '-preset', 'veryfast', '-movflags', '+faststart', out,
  ], { encoding: 'utf8' });
  if (r.status !== 0) {
    console.warn(`Could not generate ${name} (${(r.stderr || '').trim().split('\n').pop()}); skipping it.`);
    fs.rmSync(out, { force: true });
  } else {
    made++;
  }
}
const clipFiles = fs.readdirSync(dir).filter((f) => /\.(mp4|webm|mov)$/i.test(f)).sort().slice(0, 8);
if (!clipFiles.length) {
  console.error(mediaArg ? 'No video files in ' + dir : 'No demo videos could be generated. Run `npm run seed -- --reset` for data without videos.');
  process.exit(1);
}
console.log(`${mediaArg ? 'Your clips' : 'Demo videos'} ready: ${clipFiles.length} in ${dir}${made ? ` (${made} newly generated)` : ''}`);

const res = spawnSync(process.execPath, [path.join(__dirname, 'seed.js'), '--reset', '--media-dir', dir], {
  stdio: 'inherit',
  env: process.env,
});
if (res.status !== 0) process.exit(res.status === null ? 1 : res.status);

// The base seed has only two opinion videos. Add more debate topics, each with an AGAINST and a FOR
// video reply, so the feed page has plenty to swipe through and the debate tree has real branches.
(async () => {
  require('dotenv').config({ path: path.join(ROOT, '.env') });
  const { v4: uuid } = require('uuid');
  const { openDb } = require('../src/db');
  const dbFile = path.resolve(ROOT, process.env.DB_FILE || 'data/forest-app.db');
  const uploads = path.resolve(ROOT, process.env.UPLOADS_DIR || 'uploads');
  // the names seed.js gives the copies it makes of these same clips (so older leftovers in uploads/ are not used)
  const files = clipFiles.map((f) => 'seed-' + f.replace(/[^a-zA-Z0-9.-]/g, '_')).filter((f) => fs.existsSync(path.join(uploads, f)));
  if (!files.length) return;
  const db = await openDb({ file: dbFile });
  try {
    const id = (u) => db.get('SELECT id FROM users WHERE username = ?', [u]).id;
    const minsAgo = (m) => new Date(Date.now() - m * 60000).toISOString();
    let n = 0;
    const clip = () => files[n++ % files.length];
    const add = (by, parent, title, body, stance, minutes) => {
      const p = parent ? db.get('SELECT id, root_id, depth FROM posts WHERE id = ?', [parent]) : null;
      const pid = uuid();
      db.run(
        `INSERT INTO posts (id, user_id, kind, parent_id, root_id, depth, title, body, media_filename,
                            stance, status, analysis, created_at)
         VALUES (?, ?, 'VIDEO', ?, ?, ?, ?, ?, ?, ?, 'READY', NULL, ?)`,
        [pid, id(by), p ? p.id : null, p ? p.root_id : pid, p ? p.depth + 1 : 0, title, body, clip(),
          stance, minsAgo(minutes)]
      );
      return pid;
    };
    const topics = [
      ['riya_k', 'Should attendance be compulsory in college?', 'dev.p', 'kabir_m'],
      ['kabir_m', 'Is a four-day week better for students?', 'simran.v', 'aman_s'],
      ['simran.v', 'Should exams be open-book?', 'priya_n', 'riya_k'],
      ['dev.p', 'Are reels making us worse at paying attention?', 'aman_s', 'priya_n'],
      ['priya_n', 'Should voting be compulsory in India?', 'kabir_m', 'dev.p'],
      ['aman_s', 'Is learning in your home language better?', 'riya_k', 'simran.v'],
    ];
    db.tx(() => {
      topics.forEach(([by, title, againstBy, forBy], i) => {
        const root = add(by, null, title, null, 'PARENT', 400 + i * 45);
        add(againstBy, root, null, 'I disagree, and here is why.', 'AGAINST', 200 + i * 20);
        add(forBy, root, null, 'I agree, and here is my reason.', 'FOR', 150 + i * 20);
      });
    });
    console.log(`Added ${topics.length} extra debate topics (each with an AGAINST and a FOR video reply).`);
  } finally {
    db.close();
  }
})().catch((e) => { console.error(e.message); process.exit(1); });
