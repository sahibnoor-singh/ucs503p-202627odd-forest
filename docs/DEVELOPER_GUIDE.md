# FOREST developer guide

For anyone new to the code (including future you). Product background is in `README.md`; the operating rules are in `CLAUDE.md`.
This file answers "where is X and how do I change it safely".

## The big picture
```
Flutter app (app/lib)  ──HTTP/JSON──►  app/backend (Node + Express + SQLite)  ──►  ffmpeg + Gemini (video analysis)
   Home tab, Discover tab, Upload, Account            one process, one database file         ▲ runs in a background queue
                                                            │
                                                            └─(optional, one way)─► Website /app-live  (anonymous numbers + graph)
```
The contract between the two halves is **`docs/api.md`**. Change it in the same commit as any behaviour change.
`Website/` is the frozen college site; the app never depends on it, and its only link to the app is the one-way feed above.

## Run everything
```powershell
cd app\backend ; npm install ; npm run seed ; npm start        # API on :3000 (dev / dev_123)
cd app         ; flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000     # emulator; see app/backend/README.md for phones
```
Skip the login screen while developing: add `--dart-define=DEV_USER=dev` (debug builds only).

## Tests (run both before every push)
| What | Command | Notes |
|---|---|---|
| Backend | `cd app/backend && npm test` | ~125 tests, no network, no Gemini key |
| App | `cd app && flutter test` | ~180 tests, fake servers, no phone needed |
| App ⇄ backend | start the seeded backend, then `flutter test test/live_api_test.dart --dart-define=LIVE_API=http://localhost:3000` | real HTTP, sign-up/login/Discover/delete |
| Lint | `cd app && flutter analyze` | must show no errors or warnings |
| Load | `node app/backend/scripts/bench.js` | numbers in `docs/perf.md` |

Habit that found real bugs here: after a test passes first time, **break the code on purpose** and check the test fails. Several tests exist only
because a mutation survived.

## Backend map (`app/backend/src`)
| File | Job |
|---|---|
| `server.js` | reads `.env`, opens the database, starts the app, wires the optional website sync. Production safety checks live here. |
| `app.js` | builds the Express app (`createApp`): middleware order, rate limits, routes. Everything is injectable so tests run the real app with fakes. |
| `db.js` | schema, `migrate()` for old files, tiny wrapper (`all/get/run/tx`). The whole database lives in memory and is saved atomically to one file. |
| `queries.js` | the JSON shapes (`toItems`, `toPosts`) and batched counts. **Never query inside a per-row loop**: `scale.test.js` will fail. |
| `middleware/user.js` | who is calling: Bearer token, or the dev header (same-machine only). Deleted accounts are rejected here. |
| `middleware/rateLimit.js` | in-memory limits per user/IP. |
| `auth/*` | passwords (scrypt), tokens (HS256, two kinds), phone/e-mail/username/dob rules, one-time codes, e-mail and SMS providers (`mailers.js`, `providers.js`). |
| `routes/home.js, posts.js, users.js` | Home feed, posting/replying/likes/reports, profiles, follow/block, account deletion. |
| `routes/discover.js` | the reels tab: ranked feed (`recommendation.js`), replies, tree, opinion, views. |
| `postService.js`, `jobs.js` | creating a post; the one-at-a-time queue that runs ffmpeg + Gemini with deadlines. |
| `websiteSync.js` | one-way anonymous snapshot to the website. |
| `scripts/` | `seed.js`, `import_legacy.js`, `backup.js`, `bench.js`. |

### Rules the backend keeps (each has a test; do not loosen without reading it)
1. A 401 means **"your login is dead"**: the app signs out on it. Never answer 401 for anything else (a wrong password on delete is 403).
2. Anything a user can see about a post is `READY`; unfinished videos are visible only to their author.
3. Uploads need an allowed extension **and** a video/audio type; files are served `nosniff` with a sandbox CSP.
4. Passwords and one-time codes are stored only as hashes; the e-mailed or SMS code is never returned outside development.
5. Every code costs money or free-tier allowance: per-number/address, per-connection and daily caps (`routes/auth.js`). E-mail sign-up also refuses throw-away domains and "+tag" tricks (`auth/email.js`).
6. Bot/seed accounts are flagged `is_bot` and the UI must label them.
7. Account deletion wipes personal data and files but keeps (emptied) posts, because other people's replies hang below them.
8. Ranking internals are never sent to clients.
9. Production: `NODE_ENV=production` requires `JWT_SECRET` (32+ chars) and refuses the console code providers; the dev header and the public video list are off.

## App map (`app/lib`)
| Folder | Job |
|---|---|
| `main.dart` | wiring: `Session` → `ApiClient` → `AuthGate` → per-person objects → `RootShell` (4 tabs). |
| `services/api_client.dart` | the one HTTP client: token header, error → `ApiException` (message safe to show), 401 → sign out. |
| `services/session.dart` | who is logged in; token storage behind `TokenStore`. |
| `features/auth/` | login, 3-step sign-up (`signup_controller.dart` holds all the rules; the screens are thin). |
| `features/home/`, `features/thread/`, `features/viewer/` | Home tab (cards, likes, replies, threads). `feed_controller.dart` is the brain. |
| `features/reels/` | Discover tab. `reels_repository.dart` (server calls), `reel_controller.dart` (video players), `video_reel.dart` (one reel). |
| `data/` | repositories: the real ones and `fake_feed_repository.dart` for tests. |
| `ui/`, `theme/` | shared widgets and the monochrome theme (`context.forest`). |

Conventions: state that belongs to one person is created **inside** the logged-in scope (`_SignedInScope` in `main.dart`), so logging out can never
leak the previous person's data. Repositories throw `ApiException`; screens decide what to show. Fire-and-forget pings (watch time) swallow errors.

## How to add an endpoint
1. Write it in `docs/api.md` first. 2. Route in `app/backend/src/routes/`, parameterised SQL only, batched reads. 3. Tests: success, signed-out, wrong person,
bad input, and (if it lists rows) a case in `scale.test.js`. 4. App: method in a repository, handle `ApiException`, add a fake-server test.

## Known gaps (honest list)
- No profile pages, search or notifications yet. Stories are specified (`docs/STORIES_SPEC.md`) but not built.
- Real e-mail needs an SMTP login (`smtp` in `auth/mailers.js`, tested with a fake transport only). Real SMS needs your MSG91 account; `msg91` in `auth/providers.js` is untested against the live service.
- The login token is kept in app storage; switch `TokenStore` to `flutter_secure_storage` before a public launch.
- Discover's feed considers the newest 120 opinions per request; older videos are unreachable until paging is deepened.
- Moderation: reports are stored but there is no review queue, no content filter, no takedown tool, and no written Terms/Privacy yet (LAUNCH_READINESS.md gates).
- SQLite in memory is fine for the closed alpha; move to PostgreSQL before the college beta (`docs/perf.md`).
- AI results can be steered by what people say in a video (prompt injection), so credibility scores must not alone decide payouts.
- The Android release build is signed with the debug key until `android/key.properties` exists (`app/android/app/build.gradle.kts`). Not verified in this sandbox: run `flutter build apk --release` once.
