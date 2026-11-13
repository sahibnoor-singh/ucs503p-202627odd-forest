# FOREST app API (local)

Needs Node 18 or newer.

Node + Express + SQLite (sql.js). The server for the Flutter app: Home feed, replies (video or text),
likes, follows, report/block, and the Gemini pipeline. The contract is in [`docs/api.md`](../../docs/api.md).

Runs on your own computer for now. Nothing here is deployed, and it does not touch `Website/`.

## Run it (Windows PowerShell)
```powershell
cd app\backend
npm install
copy .env.example .env        # then paste your Gemini key into .env (optional)
npm run seed                  # sample users + posts (see below for adding your own clips)
npm start                     # http://localhost:3000
npm test                      # no Gemini key or ffmpeg needed
node scripts/bench.js         # load benchmark, see docs/perf.md
```
Try it: `curl -H "X-Dev-User: dev" http://localhost:3000/api/home`

Without a Gemini key everything still works: replies are labelled UNRESOLVED and video posts get a
"AI analysis not available" summary.

## Point the app at it
- **Android emulator:** `http://10.0.2.2:3000`
- **Real phone (USB):** run `adb reverse tcp:3000 tcp:3000`, then use `http://localhost:3000`
- **Real phone (Wi-Fi):** `http://<your PC's IP>:3000` (allow Node through the Windows firewall).
  The `X-Dev-User` shortcut is refused over Wi-Fi (it only works from the same machine, see below), so log in with the
  real screens (`dev` / `dev_123` after `npm run seed`).

Debug builds of the app allow plain `http` (`app/android/app/src/debug/AndroidManifest.xml`);
release builds do not.

## Data
- Database file: `data/forest-app.db` (created on first run, git-ignored). Delete it to start fresh.
- Uploaded media: `uploads/` (git-ignored).
- `npm run seed -- --reset` wipes and re-seeds. `npm run seed -- --media-dir D:\your\clips` also copies up
  to 8 mp4/webm/mov clips in so video posts play. Use clips you recorded yourself, never other
  platforms' videos. Every sample person is flagged as a bot, so the app shows them as BOT; that is
  intentional (CLAUDE.md hard rule). Don't ship seed data.
- `npm run import-legacy -- D:\path\FOREST.db --uploads D:\path\old-uploads` copies the READY videos from the old
  Oracle database into this one (read-only on the old file; safe to repeat).

## Accounts (sign-up and login)
Built to the plan: e-mailed 6-digit code → full name, username (live availability check), birth date (18+),
password. Details in [`docs/api.md`](../../docs/api.md#accounts). In development the code is printed in the server
window (`MAIL_PROVIDER=console`) and returned as `devCode`. `npm run seed` creates a loginable developer account:
username `dev`, password `dev_123`, phone `+919999900001`.
Login tokens are signed with `JWT_SECRET`; if you don't set one in development, a random one is created once in `data/.jwt-secret`.
Real e-mail: `MAIL_PROVIDER=smtp` with any service's SMTP login (Brevo, Resend, Amazon SES, ...); see `.env.example` and
`src/auth/mailers.js`. It is unit-tested with a fake transport but not yet run against a live account: send a code to your own address first.
The sender domain needs SPF and DKIM or codes land in spam. Optional `SIGNUP_EMAIL_DOMAINS` limits sign-up to some domains (a campus pilot).
Sign-up by SMS is still there (`SIGNUP_CHANNEL=phone`, `OTP_PROVIDER=msg91` is a **placeholder**: needs your MSG91 account and a DLT template,
never run against the live service). Both channels are capped (`OTP_DAILY_BUDGET`, `OTP_PER_IP_PER_DAY`).
"Continue with Google" (`GOOGLE_CLIENT_IDS`, see `src/auth/google.js` and `docs/YOUR_TODO.md` for the Google Cloud steps) skips the code: Google has verified the e-mail.
Account deletion (`DELETE /api/me`) exists. Not built yet: WhatsApp/Firebase delivery, a sign-in link instead of a code, password reset.

## Safety switches (see .env.example)
Rate limits are on by default (`RATE_LIMIT=0` turns them off for load tests). In production (`NODE_ENV=production`)
the dev-user header and the legacy upload are off, and CORS is closed unless `CORS_ORIGINS` lists web origins.
Behind nginx set `TRUST_PROXY=1`.

## Backups and the website feed
- `npm run backup` (`-- --uploads` to include videos, `-- --keep 30`) writes a dated copy of the database to `data/backups/`.
  Put it in cron for the nightly backup and copy the folder off the machine: see `scripts/backup.js`.
- Set `WEBSITE_SYNC_URL` + `WEBSITE_SYNC_TOKEN` to show this app's anonymous numbers and debate graph on the website's `/app-live` page.

## What is temporary
- `X-Dev-User` stands in for sign-in (the app only uses it with `--dart-define=DEV_USER=...`). It is refused unless the request
  comes straight from this machine, and off entirely when `NODE_ENV=production`.
- `GET /api/videos/all` and `POST /api/videos/upload` are development-only leftovers (404 in production).
- Not built yet: S3 storage, deployment. SQLite on local disk is for the closed alpha only.

## Tests
`npm test` runs everything (about 125 tests, no network). Files worth knowing: `audit_round1.test.js` (each security finding pinned),
`scale.test.js` (fails if an endpoint starts running one SQL query per row), `hardening.test.js`, `auth_flow.test.js`.
See [`docs/DEVELOPER_GUIDE.md`](../../docs/DEVELOPER_GUIDE.md) for how the code fits together.

## Layout
```
src/server.js        starts everything       src/app.js        builds the Express app
src/db.js            SQLite + schema         src/queries.js    reads + the JSON shapes
src/postService.js   creating posts/replies  src/jobs.js       background video analysis
src/routes/          home, posts, users, compat
src/services/        audio (ffmpeg) + gemini (copied from Website/backend, then adapted)
scripts/             seed.js, import_legacy.js
test/                node:test suites (fake Gemini + ffmpeg)
```

## Differences from the copied Website code
- Gemini now falls back to UNRESOLVED when it is unavailable. The old fallback labelled replies AGAINST.
- No key at all skips the 14-model retry cascade instead of failing through it.
- Text replies are classified too (`classifyReplyText`).
- ffmpeg loads lazily, so tests and seeding don't need the binary.

## Running it on a real server
See `docs/DEPLOY.md` and the `deploy/` folder at the repository root. `npm run preflight` checks the production settings before the first start.
