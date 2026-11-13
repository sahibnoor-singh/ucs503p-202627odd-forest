# Release checklist: closed alpha to a real phone in a stranger's hand

What is done, what must be done before real users, and what is knowingly not built. Tick things off here as they happen.
Written 2026-10-20 after a full sweep of unfinished items. Nothing below is legal advice.

## Done and checked in this sweep

| Area | What |
|---|---|
| Safety | Report with a reason and Block with confirm and Undo from: the reels menu, a received video in the messages, the messages top menu, the search profile card. A **Blocked accounts** list in Account to unblock. Blocked people vanish from the Discover grid and search at once. |
| Legal in the app | Terms of use and Privacy notice screens (plain language, draft), linked from sign-up ("By creating an account you confirm you are 18 or older and agree to…") and from Account. The grievance contact is read from the server. |
| Honesty | The stories row on Home was a placeholder ("not built yet"), so it is no longer shown. `StoriesRow` stays in the code for when reposts exist (`docs/STORIES_SPEC.md`). |
| Failure handling | Release builds show a plain message in place of a broken widget instead of a red screen; uncaught errors are logged and swallowed (`lib/services/app_errors.dart`). A release build made without `API_BASE_URL` says so instead of silently pointing at the emulator. |
| Server | Access log (method, path, status, time, short user id; never the query, a body or a token), on by default when `NODE_ENV=production`. |
| Brand | Real app icon (Android adaptive and legacy, iOS set) instead of the Flutter logo. |
| Sign-up | **By e-mailed code, free** (no DLT, no SMS cost): 6-digit code, 5 minutes, one use. One mailbox is one account (Gmail dots and +tags collapse), throw-away domains refused, optional allow-list of domains (`SIGNUP_EMAIL_DOMAINS`, e.g. a campus). SMS stays available (`SIGNUP_CHANNEL=phone`) but is not needed. |
| Google sign-in | "Continue with Google" on the login and sign-up screens when the server has `GOOGLE_CLIENT_IDS`. A new person picks only a username and birth date (18+ still enforced); no password. An existing account with a verified e-mail is linked. Deleting a Google-only account asks for a fresh Google confirmation. Needs the Google Cloud setup in `docs/YOUR_TODO.md` and is not yet tried against real Google. |
| Onboarding | After sign-up, two skippable pages once: pick 3 to 8 topics (seeds the taste profile), then follow a few suggested people. Closing the app in the middle brings it back. Plan: `docs/ONBOARDING_PLAN.md`. |
| Look | Login, sign-up, onboarding follow the phone's light or dark setting (also the start-up splash). Brand header, step dots, bigger code box, the real four-colour Google G, and a date-of-birth sheet with month, day and year wheels instead of a calendar grid. |
| Question of the day | One neutral question per day (48 in rotation), the same for everyone, shown at the top of Home. Answering it opens the normal upload choices tagged with the day; answers have their own page. Works for a new account that follows nobody. |
| Reply wanted | "Waiting for an answer": recent opinions nobody (or only one or two people) has answered, with a Reply button. Gives people their first reply, which is why they come back. |
| Motion rooms | A society makes a room with one motion and an end date, shares a 6-character code; members post videos; the AI marks each FOR or AGAINST the motion and the room page shows the split. Account, Debate rooms. |
| Invite friends | A code and link per person (Account, Invite friends). Signing up with it makes you and the friend follow each other. An invite code field at the end of sign-up. |
| Public pages | `/p/<id>` (a shared debate, escaped, no script, link preview), `/invite/<code>`, `/terms`, `/privacy`. "Copy link" now copies a real link. |
| Measuring | Small product events from the app and the server (no content), and a founders' page at `/admin/insights` (needs the moderation token): joined, onboarding finished, the first-minute funnel, answered within 24 h, next-day return. |
| Video screen and notifications | One look for the video screen (picture and name open the profile, Follow beside the name, a Reply arrow, comments, two-line title with more, 2 FOR · 3 AGAINST), arrow keys and mouse drag for laptops. A follow from a reel tells the author "@x followed you from this reel" (bell on Home, list with the reel cover). |
| Profile page | The Account tab is the person's own profile (bio, personality keywords and approved summary, credibility, their videos, followers, saved posts), with settings behind a gear. Built by Yaksh, merged with the rest (see MERGE_NOTES). An AI summary stays a private draft until approved; deleting an account clears all of it. |
| Tests | App 538, server 355. The analyzer has no errors or warnings. |

## Before anyone outside the team uses it (must)

> **Hosting:** the server is packaged for AWS or Oracle in `deploy/` (Docker + Caddy for HTTPS, `npm run preflight` to check the settings, nightly backup to S3, `update.sh`). Follow `docs/DEPLOY.md`; it covers the server items below that mention nginx, pm2 and certificates, and what the AWS credits buy.

**Server**
- [ ] `NODE_ENV=production`, `JWT_SECRET` (32+ random characters), `MODERATION_TOKEN`, `TRUST_PROXY=1` behind nginx.
- [ ] HTTPS only (a Let's Encrypt certificate on nginx). Release Android builds refuse plain `http://` to a real host.
- [ ] A real sender for sign-up codes: `MAIL_PROVIDER=smtp` with `SMTP_HOST`, `SMTP_USER`, `SMTP_PASS`, `MAIL_FROM` (see `.env.example`). Written and tested with a fake mail transport, **never run against a live account**: send a code to your own Gmail and check it lands in the inbox, not spam. The sender domain needs SPF and DKIM records. `console` is refused in production on purpose.
- [ ] Google sign-in: `GOOGLE_CLIENT_IDS` set (Web client id), Android OAuth clients for the debug and release SHA-1 (and the Play App Signing SHA-1). Try it on a real phone with your own Google account: new account, log out, log in again, delete.
- [ ] Set `OTP_DAILY_BUDGET` to just under your mail service's daily allowance (default 250).
- [ ] `PUBLIC_BASE_URL` set to the real address (links to debates and invites are built from it) and `PLAY_STORE_URL` once the listing exists. Use `<PUBLIC_BASE_URL>/privacy` as the privacy policy URL in the Play Console.
- [ ] Open `/admin/insights` once with the moderation token and read it: it is how you will know whether the pilot works.
- [ ] `GRIEVANCE_OFFICER_NAME` and `GRIEVANCE_OFFICER_EMAIL` set (shown in the app and at `GET /api/legal/contact`).
- [ ] `MODERATION_BLOCKLIST` filled with the words you want held for review.
- [ ] Backups: schedule `node scripts/backup.js` (cron) and **restore one to a scratch folder** to prove it works. Keep copies off the server.
- [ ] Process manager (pm2) set to restart on crash and on reboot; log rotation for the access log.
- [ ] Disk alerts. Videos live on local disk; the database is held in memory and rewritten to one file (see `docs/perf.md`, comfortable to a few tens of MB).
- [ ] Remove demo data: do not load `snapshot/` or run `seed:*` on the production server.
- [ ] If the old website is deployed from the same repo: change the admin login `admin` / `admin123` first (CLAUDE.md hard rule).

**App**
- [ ] Build with the real server: `flutter build appbundle --release --dart-define=API_BASE_URL=https://your-server` (do **not** pass `DEV_USER`; it is ignored in release anyway).
- [ ] A release signing key: create it once, put `key.properties` next to `android/`, keep the keystore backed up. Without it the build falls back to the debug key and the Play Store refuses it.
- [ ] Bump `version:` in `pubspec.yaml` for every upload.
- [ ] Test on at least two real phones, one low-end, on mobile data: sign up, post a video and a text reply, reply, send a video, react, block, report, delete account.
- [ ] Store listing: a public URL for the privacy notice (the in-app text must also be hosted on a web page; Play requires a link), the data safety form (e-mail address, name, date of birth, videos, usage data, shared with Google Gemini for processing), a content rating that reflects user-generated content, target age 18+.

**Legal and policy**
- [ ] A lawyer reads the in-app Terms and Privacy notice (`lib/features/legal/legal_screens.dart`). They are plain-language drafts written from what the app really does, not reviewed documents.
- [ ] A written takedown and appeals routine: who looks at the report queue, how often (suggest daily), who decides appeals, how a complaint to the grievance contact is answered (the back office at `/admin` has the queue and the complaint list).
- [ ] An election-period plan (who watches political reports, how fast you can act).
- [ ] Music: a person's own file is fine for the alpha. Before a public launch use a licensed library or remove music from posts.

## Known gaps (decided, not forgotten)

- **Invite and debate links open a web page, not the app.** A person installs the app and types the invite code at sign-up (App Links need the real domain and the release key's fingerprint, so they come with the first real deploy).
- **The daily question list is 48 long.** It repeats every 48 days; add more in `src/prompts.js` (keep them two-sided and neutral).
- **Rooms are public posts.** The room gathers and counts; it does not hide anything. A private debate room would need its own visibility rules.
- **The FOR/AGAINST split in a room is the AI's reading** of each video against the motion, and can be wrong; the room page says "undecided" for what it could not place.

- **No push notifications.** Needs a Firebase project and its `google-services.json`. Today the messages poll (a few seconds while open, 30 s for the badge on Home). Replies have no notification at all. This is the biggest retention gap.
- **No crash reporting.** `reportError` in `app_errors.dart` is the single place to add Sentry or Crashlytics.
- **No analytics.** Add events before the pilot (see `docs/PRODUCT_REPORT.html`).
- **No public web page** behind share links (`forest.app/p/<id>`).
- **Profile page** is being built by your friend; Account is still a small placeholder with settings, blocked accounts and legal links.
- **iOS** is generated but never built or tested (needs a Mac and an Apple developer account).
- **Real-phone performance** has not been measured with numbers. The profile build ran smoothly by eye on a CPH2805; the automated measurement could not connect.
- **Single server process**: fine for hundreds of people, plan the database move before the open-campus phase.

## Smoke test before every release

1. Fresh install, sign up with a new e-mail (the code arrives, not in spam), see the terms and privacy links work.
2. Post a video reply; watch it go from Processing to Ready with a label and subtitles.
2b. A brand-new account: the topics page, then the people page, then Home with the people you followed.
3. Open Discover, search a word, open a result, swipe FOR and AGAINST.
4. Send a video to a friend; on their phone see the badge on the plane, open it, react.
5. Report a video (pick a reason). Block the sender from the messages. Check they vanish. Unblock from Account, Blocked accounts.
6. Turn friend taste off and on in Account.
7. Delete the account; log in again must fail.
