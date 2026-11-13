# Run FOREST on your own machine

The app needs its backend running on your PC, or Home shows "Could not load Home" and the feed page shows nothing real.
Home and the feed page both read from `app/backend`. Your live database and uploads are local to each
machine, but a shared copy (`app/backend/snapshot/`) is committed, and one command loads it.

## 1. Backend (once per machine, then each time you work)
**Shortcut (Android Studio / `flutter run`):** every debug build starts the backend for you, first run included (it does
`npm install` and loads the shared snapshot if needed), so pressing Play on `main.dart` is enough. Needs Node.js installed.
It does nothing if the backend is already running, and its log is `app/backend/data/backend.log`. The backend keeps running
after you close Android Studio; end the `node.exe` process to stop it. Opt out with `FOREST_NO_BACKEND=1`. The manual steps
below still work.

```
cd app/backend
npm install
npm run snapshot:load  # RECOMMENDED: exact same posts, replies and real videos the lead dev sees (resets your local database)
# (or, for generated placeholder videos instead:  npm run seed:demo )
npm start              # keep this window open. Check: http://localhost:3000/api/health  ->  {"ok":true,...}
```
The `snapshot/` folder is committed, so after a `git pull` you get the same videos and data. The lead dev refreshes it with
`npm run snapshot:save` and commits it. "Video not available" in the app means the backend has no video file for that post:
run `npm run snapshot:load` and restart `npm start`.

No ffmpeg install is needed (it is bundled). Videos from `seed:demo` are generated placeholders; to use your own clips:
`npm run seed:demo -- --media-dir <folder of your own clips>` (same data and topics, your videos).

**Subtitles.** New uploads get subtitles automatically (same Gemini call as the transcript). Videos analysed earlier get them with
`npm run captions:backfill` (stop the backend first; needs a Gemini key). The CC button next to mute switches them on and off.

**Cover pictures.** Every uploaded video gets a still picture (the Discover grid tile, and the poster before it plays) automatically. Videos
posted before that existed get theirs with `npm run thumbnails:backfill` (stop the backend first; needs no key). `snapshot:save` includes them.

**Content that matches the videos (needs a Gemini key).** `seed:demo` text is made up, so it will not match your clips.
To have each video transcribed for real, titled from what it says, and answered by bot replies written from that
content, put `GEMINI_API_KEY=...` in `app/backend/.env` and run
`npm run seed:real -- --media-dir <folder of videos>` (resets the local database; takes about 15 minutes because videos are
analysed one at a time). Which videos are debate roots, which reply to what and which bot posts them is in
`app/backend/scripts/seed_content.json`. Everything else comes out of the real pipeline: transcript, captions, English captions,
heading, description and the FOR/AGAINST label of each reply. Each bot gets a drawn profile picture. All accounts it makes are
bots and are labelled BOT in the app. `--debates 2` posts only the first two debates, as a quick try.

Optional: put `GEMINI_API_KEY=...` in `app/backend/.env` for real transcripts and stances. Without it, new video replies
get an "unavailable" transcript and the UNRESOLVED stance. Everything else works.

## 2. App
**Android emulator** (it reaches your PC at `10.0.2.2`, which is the app's default):
```
cd app
flutter run --dart-define=DEV_USER=dev      # skips the login screen while developing
```
Without `DEV_USER` the app opens on the login screen: sign in as `dev` / `dev_123` (that account is made by the seed),
or sign up with any e-mail address (in development the code is filled in for you and printed in the server window).
**A real phone over USB** (USB debugging on):
```
adb reverse tcp:3000 tcp:3000
cd app
flutter run --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=DEV_USER=dev
```
`DEV_USER` is a debug-build shortcut that skips login. To try another account, for example one that follows nobody (shows the
"who to follow" screen): `--dart-define=DEV_USER=aman_s`.

## 3. If something does not work
| What you see | Cause and fix |
|---|---|
| "Could not load Home. Can't reach the server at http://10.0.2.2:3000" | The backend is not running. Do step 1 and keep `npm start` open. |
| Feed page shows an error, a spinner, or nothing to swipe to | Same cause: the backend is not running (or has no videos: run `npm run seed:demo`). |
| `npm start` says the port is in use | An old backend is still running. Close it (or end the `node` process) and start again. |
| Swiping does nothing on a reply page | By design: on a reply, swipe down goes back and left/right switch FOR and AGAINST replies. Swipe up for the next video works on a main video. |
| App looks stuck on old data after changing the backend | `adb shell pm clear com.forest.forest_app`, then reopen it. |
| `INSTALL_FAILED_INSUFFICIENT_STORAGE` on the emulator | Uninstall the old app from the emulator (or wipe its data in Device Manager), then run again. |
| Your phone cannot reach the PC without USB | Use the PC's Wi-Fi IP: `--dart-define=API_BASE_URL=http://<pc-ip>:3000`, and allow port 3000 in Windows Firewall. |

More: `docs/DEVELOPER_GUIDE.md` (how the code is organised), `docs/api.md` (what the server offers).
