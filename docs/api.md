# FOREST app API

The server behind the Flutter app. Code: [`app/backend`](../app/backend) (Node + Express + SQLite).
Runs on your laptop for now (see its README). This file is the contract the app is built against;
change it in the same commit as any behaviour change.

Differences from the early draft in `PHASE1_HOME_PLAN.md` §6 are listed at the bottom.

## Conventions

- JSON in and out. Errors are `{ "error": "message" }` with a normal HTTP status
  (400 bad input, 401 not signed in, 403 not allowed, 404 not found, 409 conflict, 413 file too big).
- Times are ISO-8601 UTC strings. Ids are opaque strings.
- Media URLs are relative (`/uploads/<file>`); prefix them with the server's base URL.
  Files are served with HTTP Range support, so video seeking works.
- **Who is calling.** Send `Authorization: Bearer <token>` (from sign-up or login below). A bad, expired or
  malformed token is always a 401; it is never quietly replaced by anything else.
  **TEMPORARY:** until the app signs in, a request may instead say `X-Dev-User: <username>`. This works only when
  the server runs with `ALLOW_DEV_USER=1` (default unless `NODE_ENV=production`). Remove it from the app once it
  uses tokens. `GET /api/dev/users` lists usernames you can use in development.
- **Limits (429 + `Retry-After`).** Per signed-in user (per IP when anonymous), per minute: 600 API calls
  overall, 15 new posts/replies, 120 likes, 10 reports, 60 follow/block actions. A person can also have at
  most 5 unfinished videos at once (429), and when the whole server has 100 queued it answers 503. Show the
  server's message and let the person retry. `GET /api/health` is never limited.
- Anything a user can see about a post is `READY`. A video that is `PROCESSING` or `FAILED` is visible
  only to its author (who polls `GET /api/posts/:id`).

## Shapes

```jsonc
// User
{ "id": "…", "username": "aman_s", "fullName": "Aman Singh", "avatarUrl": null, "isBot": false }

// Post
{
  "id": "…", "kind": "VIDEO" | "TEXT",
  "parentId": "…" | null,       // the post this directly replies to
  "rootId": "…",                // the opinion that started the debate (= id for a root)
  "depth": 0,                   // 0 opinion, 1 reply, 2 reply-to-a-reply, …
  "title": "…" | null,          // roots only
  "body": "…" | null,           // text reply, or optional caption (max 280 chars)
  "mediaUrl": "/uploads/x.mp4" | null,
  "coverUrl": "/uploads/x-cover.jpg" | null,   // a still picture of the video: its tile in the Discover grid and the poster before it plays (every video; editor posts use the frame the author picked, uploads a frame about 1 s in; null only if it could not be made)
  "stance": "PARENT" | "FOR" | "AGAINST" | "UNRESOLVED",   // roots are PARENT
  "status": "PROCESSING" | "READY" | "FAILED",
  "summary": "…" | null,        // Gemini's overallSummary, once analysed
  "hasCaptions": false,         // true when GET /api/posts/:id/captions has subtitle lines
  "createdAt": "…",
  "likeCount": 0, "likedByMe": false,
  "replyCount": 0,              // ALL replies below it, direct and indirect
  "forCount": 0, "againstCount": 0   // same scope, by stance
  // GET /api/posts/:id also adds "analysis": { transcript, overallSummary, claims[] } | null
}

// Item: one card
{
  "type": "POST" | "VIDEO_REPLY" | "TEXT_REPLY",   // card A, B, C
  "actor": User,
  "post": Post,
  "parent": { "actor": User, "post": Post } | null, // the post it directly replies to
  "root":   { "id", "username", "title" } | null,   // set only when root ≠ parent
  "createdAt": "…"
}
```

## Accounts

New person: **config → username check → e-mailed code → sign up**. Returning person: **log in**.
Errors that belong to one input field include `"field": "<name>"` so the app can highlight it.

### `GET /api/auth/username-available?u=riya_k`  (no sign-in)
Call it (debounced ~400 ms) while the person types. Always 200.
→ `{ "available": true }` or `{ "available": false, "reason": "TAKEN" | "INVALID" | "RESERVED", "suggestions": ["riya_k42", …] }`
(suggestions only for TAKEN, and each is free and valid). Rules: 3-30 chars, `a-z 0-9 . _`, case-insensitive, can't
start/end with `.` or contain `..`. Names starting with `forest`, `admin` or `official`, and words like `support`, are reserved.

### `GET /api/auth/config`  (no sign-in)
→ `{ "signupChannel": "email" | "phone", "channels": ["email"], "googleClientId": "…" | null }`. `googleClientId` is the Web OAuth client id
the app asks Google for a token with (`GOOGLE_CLIENT_IDS`); null means "Continue with Google" is off. Which way this server verifies new people (`SIGNUP_CHANNEL`, default
`email`). `channels` lists the routes that are switched on; the other channel's routes answer 404 "Sign-up by … is not enabled".

### `POST /api/auth/email/send`  `{ "email": "riya@example.com" }`
Sends a 6-digit code to the inbox. The address is normalised: lower-cased, and for Gmail dots and `+tags` are removed
(`r.iya+x@gmail.com` is `riya@gmail.com`), so one mailbox is one account. The reply carries the normalised address.
→ `{ "sent": true, "email": "riya@gmail.com", "resendInSec": 30 }` (+ `devCode` with the console provider only).
400 `field: "email"` for a badly shaped address, a `+tag` on a non-Gmail address, a throw-away domain (built-in list +
`SIGNUP_BLOCKED_EMAIL_DOMAINS`), or a domain outside `SIGNUP_EMAIL_DOMAINS` when that list is set. 409 `field: "email"` if the address
already has an account (checked before sending). Same limits as the SMS code: one per 30 s per address, 5 a day per address,
20 a day per connection, and the overall daily budget (`OTP_DAILY_BUDGET`, default 250). 502 if the mail service is down.

### `POST /api/auth/email/verify`  `{ "email", "code" }`
Same rules as the SMS code: 5 minutes, once, 5 wrong tries. → `{ "verified": true, "email", "signupToken": "…" }`.
Sign-up with this token stores the verified address as the account's e-mail (the `email` in the sign-up body is ignored).

### `POST /api/auth/google`  `{ "idToken" }`  (only when `GOOGLE_CLIENT_IDS` is set; otherwise 404)
"Continue with Google". The app signs in with Google on the phone and sends the ID token. The server checks Google's signature and that the
token was issued for our client id, and needs Google to say the e-mail is verified (400 otherwise); the e-mail rules above apply too
(`SIGNUP_EMAIL_DOMAINS`, throw-away domains).
- Known person (same Google id, or an account whose e-mail was verified at sign-up, which is then linked) → `200 { "token", "expiresInSec", "user" }`.
- New person → `200 { "needsProfile": true, "email", "fullName", "signupToken" }`. The app asks for a username and birth date and calls
  `POST /api/auth/signup` with that token; **no password is needed** (one given anyway is validated and kept).
- 401 for a token Google rejects. 409 `field: "email"` when the address belongs to an account whose e-mail was only typed, never verified
  (log in with the password instead). 403 for a suspended account.

### `POST /api/auth/otp/send`  `{ "phone": "9876543210" }`  (only when `SIGNUP_CHANNEL=phone`)
Sends a 6-digit code. Accepts `+919876543210`, `98765 43210`, etc. A bare 10-digit number gets `+91`.
→ `{ "sent": true, "phone": "+919876543210", "resendInSec": 30 }`. In development with the console provider the
response also has `devCode` so the app can fill it in; a real provider never returns it.
Limits: one code per 30 s per number (429 + `retryAfterSec`), 5 a day per number, 20 a day per connection
(`OTP_PER_IP_PER_DAY`), and one overall daily budget (`OTP_DAILY_BUDGET`, default 500; 503 "Sign-ups are paused for today" when spent). 409 `field: "phone"` if the number
already has an account (checked before sending, so no SMS is wasted). 502 if the SMS provider is down (try again at once).

### `POST /api/auth/otp/verify`  `{ "phone", "code" }`
Codes expire after 5 minutes, work once, and die after 5 wrong tries (ask for a new one).
→ `{ "verified": true, "phone", "signupToken": "…" }`. The signup token lasts 15 minutes and is **only** accepted by sign-up.

### `POST /api/auth/signup`
`{ "signupToken", "fullName", "username", "dob": "2000-05-20", "password", "email"? }`
- `fullName` 1-60 chars; `dob` must make them **18 or older** (exact to the day; 400 with `tooYoung: true` otherwise);
  `password` 8-128 chars, not a very common one, not the username; `email` optional (blank = none), validated.
- → `201 { "token", "expiresInSec", "user": User }`. The token is a login token, ready to use. Nothing private
  (phone, e-mail, birth date) is ever returned in a `User`.
- 401 `field: "signupToken"` if verification is missing/expired (verify again). 409 with `field` =
  `username` (`reason: "TAKEN"`), `phone` or `email` if it was taken in the meantime.

### `POST /api/auth/login`  `{ "identifier", "password" }`
`identifier` is a username, e-mail or phone number. → `{ "token", "expiresInSec", "user": User }`.
Every failure is the same `401 "Wrong username or password"` (no hint which part was wrong). After 8 wrong
passwords for one account from one place (or 40 from anywhere) it answers 429 for 15 minutes, even for the right password.
Accounts without a password (bots, imported data, people who signed up with Google) cannot log in this way.
`GET /api/me` has `account: { hasPassword, google }` so the app knows which proof to ask for. `DELETE /api/me` takes `{ "password" }`, or for an
account with no password `{ "idToken" }`: a fresh Google token for the same Google account.

`identifier` as an e-mail is matched in its normalised form too, so `Riya.K+x@gmail.com` finds `riyak@gmail.com`.
Login tokens last 30 days for now; refresh tokens, password reset and a sign-in link (instead of a code) are not built yet.

## Onboarding

The first-run pages after sign-up (`docs/ONBOARDING_PLAN.md`). Nothing here is required.

### `GET /api/onboarding/topics`  (signed in)
→ `{ "topics": [{ "id": "politics", "label": "Politics" }, …], "min": 3, "max": 8 }`. The list lives in `src/topics.js`.

### `POST /api/me/onboarding`  `{ "topics": ["politics", "tech"] }`  (signed in)
Seeds the person's taste profile with the words of each topic (affinity 0.7, a little above neutral; it never lowers anything already learned from
watching) and sets `onboarded_at` the first time. An empty list is "skip". More than 8 are cut to the first 8; an unknown id or a non-list is
400 `field: "topics"`. → `{ "topics": ["politics", "tech"] }`. Calling it again later changes the topics and does not reset anything else.
`GET /api/me` has `account.onboarded`. Everyone who had an account before this existed counts as done.

## Profile page

The Account tab is the person's own profile; settings (blocked accounts, log out, delete) are behind its gear. Code: `src/routes/profile.js`, `lib/features/profile/`.

- `GET /api/users/:id/profile` → `{ user, bio, followerCount, followingCount, postCount, followedByMe, blockedByMe, isMe, personality: { keywords, summary, summaryApproved, interests }, credibility, contributions }`. 404 for a deleted person or one who blocked you. **An AI-written `personality.summary` is a draft until its owner approves it: other people get `null` until `summaryApproved` is true.**
- `GET /api/users/:id/videos` the person's opinions, newest first. `GET /api/users/:id/followers` and `/following` with `followedByMe` on each row.
- `PATCH /api/me/profile` `{ fullName?, bio?, personalityKeywords? (≤8), personalitySummary?, personalitySummaryApproved?, interests? (≤10) }` → the new profile. 400 `field` names the input.
- `POST /api/me/personality/generate-summary` `{ keywords: [1-8 strings] }` asks Gemini to write a short summary from the keywords (nothing else is sent). The result is a draft the person must approve.
- `GET /api/me/bookmarks`, `POST /api/me/bookmarks/:postId`, `DELETE /api/me/bookmarks/:postId`: saved posts, private to the person.

Deleting an account clears the bio, personality fields, interests and saved posts.

## The question of the day, reply wanted

### `GET /api/prompts/today`  (signed in)
→ `{ "day": "2026-10-21", "text": "Should attendance be compulsory in colleges?", "topic": "education", "answerCount": 3, "answered": false }`.
One question per calendar day, the same for everyone, chosen from a fixed list by the date (`src/prompts.js`). The day turns over at midnight in
`PROMPT_UTC_OFFSET_MIN` (default 330, India). `answerCount` leaves out people you blocked.

### `GET /api/prompts/today/answers?limit=10`  (signed in)
→ `{ "items": [FeedItem] }`. Video answers to today's question, newest first (max 30).

### Answering it
`POST /api/posts` and `POST /api/posts/compose` accept `promptDay=YYYY-MM-DD` on a **new opinion**. Only today's or yesterday's day is open (400
`field: "promptDay"` otherwise); a reply cannot carry it (400); it cannot be combined with `roomId` (400). The post JSON then has `promptDay`.

### `GET /api/reply-wanted?limit=5`  (signed in)
→ `{ "items": [FeedItem] }`. Video opinions from the last 7 days with at most 2 replies, that are not yours, that you have not replied to, and
that are not from anyone you blocked or who blocked you. Fewest replies first, then newest. The quickest way to give someone their first reply.

## Motion rooms

A society or class debates one motion for a few days. A room is only visible to its members; what is posted in it is an ordinary public post.
Each room opinion is judged by the AI against the **motion** (not against another post) and gets `post.roomStance` = `FOR` / `AGAINST` / `UNRESOLVED`;
its normal `stance` stays `PARENT`. Post JSON has `room: { id, name }` for such posts.

- `POST /api/rooms` `{ name (≤60), motion (10-200), description? (≤500), startsAt?, endsAt? }` → 201 `{ room }`. You become the owner. 5 open rooms per owner (429). 400 `field` names the input.
- `GET /api/rooms/mine` → `{ rooms: [Room] }`, open ones first.
- `POST /api/rooms/join` `{ code }` → `{ room }`. The code is 6 characters, any case, spaces and dashes ignored. 404 `field: "code"` for an unknown one, 409 for a closed or full (500) room. Joining twice changes nothing.
- `GET /api/rooms/:id` → `{ room, members: [User] }` (members only; 404 to anyone else).
- `GET /api/rooms/:id/posts?limit=20` → `{ items: [FeedItem] }`, the room's opinions, newest first.
- `POST /api/rooms/:id/leave` (the owner cannot: 409). `POST /api/rooms/:id/close` (owner only; a closed room stays readable).
- Posting into a room: `roomId` on `POST /api/posts` or `/compose`, new opinions only. The room must be OPEN (409 "not started yet" / "closed"); not a member is 404.

`Room`: `{ id, code? (members only), name, motion, description, startsAt, endsAt, status: UPCOMING | OPEN | CLOSED, role: OWNER | MEMBER | null, owner: User,
memberCount, posts, forCount, againstCount, undecided, createdAt }`. Deleting an account removes the person from every room and closes the rooms they ran.

## Invites

### `GET /api/me/invite`  (signed in)
→ `{ "code": "K7M2QXA", "link": "https://…/invite/K7M2QXA", "invitedCount": 2 }`. The code is made the first time and stays the same.

### Signing up with one
`POST /api/auth/signup` takes `inviteCode` (any case, spaces and dashes ignored). A code that is not real is 400 `field: "inviteCode"` and nothing is created; blank means none.
A good code makes the new person and the inviter follow each other. Bots, deleted and suspended people cannot invite.

## Events (what the founders measure)

### `POST /api/events`  `{ "events": [{ "name": "app_open", "props": { … } }] }`  (signed in)
→ `{ "recorded": n }`. Up to 50 per call. Only these names are kept, the rest are dropped without an error: `app_open`, `prompt_opened`, `reply_wanted_opened`,
`invite_copied`, `link_copied`, `room_opened`, `onboarding_topics_shown`, `both_sides_heard` (someone watched a FOR and an AGAINST reply of one debate; no ids). `props` is a flat object of short strings, numbers and booleans, under 300 bytes, or it is dropped.
Never send video, text, search words or contact details. The server records `signup`, `onboarding_done`, `post_created`, `reply_created`, `prompt_answered`, `room_created`,
`room_joined` and `invite_accepted` itself. Deleting an account detaches that person's events (the counts stay).

### `GET /api/admin/insights?days=14`  (moderation token) and the page `/admin/insights`
Real people only (no bots, no deleted accounts): totals, a day-by-day table (joined, finished onboarding, active, opinions, replies, answers to the question), the first-minute
funnel for people who joined in the window, the share of opinions answered within 24 hours and the median hours to a first reply, and next-day return.

## Public pages (no sign-in, no script)

- `GET /p/:id` a shared debate: the video, summary, FOR / AGAINST counts and up to five replies, with link-preview tags. Everything from people is escaped and the page has a content policy that forbids script. 404 for anything not public (unknown, processing, hidden, failed, or the author is deleted or suspended). `noindex`.
- `GET /invite/:code` names the inviter and shows the code; a code that is not real says nothing about anyone.
- `GET /terms` and `GET /privacy`: the same words as the app (`src/legalText.js`, kept in step by a test). The Play Store needs a public privacy URL: use `/privacy`.
- Settings: `PUBLIC_BASE_URL` (the address used in links; default is the address the request came in on), `PLAY_STORE_URL` (a button on the pages, shown only when set). `GET /api/auth/config` returns `publicBaseUrl` so the app copies the right link.

## Endpoints

### `GET /api/home?limit=20&cursor=…`  (signed in)
Posts and replies by people you follow, newest first. Excludes blocked authors and replies to
blocked authors. Max `limit` 50.
→ `{ "items": [Item], "nextCursor": "…" | null }`. Pass `nextCursor` back as `cursor` for the next page.
An invalid cursor is a 400.

### `POST /api/posts`  (signed in, `multipart/form-data`)
| field | |
|---|---|
| `kind` | `VIDEO` or `TEXT` (required) |
| `parentId` | post being replied to. Omit for a new opinion (VIDEO only) |
| `title` | roots only, max 120 chars |
| `body` | TEXT: required, max 280 chars (emoji count as one). VIDEO: optional caption |
| `video` | file, required for VIDEO. Extension must be one of mp4 mov webm mkv avi m4a mp3 wav ogg aac **and** the type must be video/audio (or octet-stream). Max 50 MB. Anything else is a 400 |

→ `201` with an **Item**.
- TEXT replies are classified FOR/AGAINST/UNRESOLVED by Gemini before the response (8 s limit, then UNRESOLVED).
- A video without a `title` (root) or `body` gets them from the pipeline once analysed: a specific debate question and a 1–2 sentence
  description, both written only from what is said in the video. What the author sent is never overwritten.
- VIDEO posts come back `status: "PROCESSING"`. Audio extraction and Gemini run in the background, one at a
  time, each step with a 3-minute deadline (a stuck step marks the video `FAILED` so the queue keeps moving).
  Poll `GET /api/posts/:id` until `READY` or `FAILED` (then offer **Retry**). A server restart resumes unfinished videos.
- You can't reply to a post that is not `READY` (409), or to someone you blocked / who blocked you (403).
- Text posts must be replies (400).

### `POST /api/posts/:id/retry`  (signed in, author only)
Re-runs analysis for a video that ended `FAILED` (for example after a timeout) without uploading it again.
→ the **Item**, now `PROCESSING`. 404 if it isn't yours, 409 if it isn't `FAILED`, 410 if the stored file is gone
(upload again).

### `GET /api/posts/:id/captions?lang=original|en|hi|pa|bn|ta|te|mr|gu`  (signed in optional)
Subtitle lines for a video: `{ "captions": [{ "start": 1.5, "end": 3.2, "text": "…" }], "language": "hi", "lang": "original", "languages": [{ "code": "en", "name": "English", "native": "English" }, …] }`.
Times are seconds from the start of the video, sorted, no overlaps. `language` is what is spoken in the video (ISO 639-1, null when
unknown), `lang` is what these lines are in (`original` = as spoken, Hindi stays Hindi), `languages` is what can be asked for.
- `lang` omitted or `original`, or equal to the spoken language: the lines as spoken.
- English is made when the video is analysed (when it is not already spoken in English); any other language is translated by Gemini
  the first time someone asks and kept after that (two people asking at once cost one translation).
- `400` for an unsupported `lang`; `503` when a translation could not be made right now (try again).
- Empty list for a video with no speech or one analysed before captions existed (`npm run captions:backfill`).
- Same visibility as the post (404 for someone else's unfinished video).
The old `/api/videos/*` routes send the spoken-language lines inside `transcript.captions`.

### `GET /api/posts/:id`  (signed in optional)
→ an **Item** with `post.analysis` included. 404 for unfinished/failed posts unless you are the author.

### `GET /api/posts/:id/thread?limit=100`  (signed in optional)
Every reply under the post, depth-first, newest sibling first, as a flat list. Rebuild the tree from `post.parentId`.
Replies by users you blocked, and everything under them, are left out. Max `limit` 200.
→ `{ "item": Item, "replies": [{ "actor": User, "post": Post }], "total": 12 }`

### `POST /api/posts/:id/like` · `DELETE /api/posts/:id/like`  (signed in)
Idempotent. → `{ "liked": true|false, "likeCount": 3 }`

### `POST /api/posts/:id/report`  (signed in) body `{ "reason": "MISINFORMATION" | "HARASSMENT" | "SPAM" | "VIOLENCE" | "OTHER" }`
One report per person per post. Not your own post. Nothing is removed automatically; reports are stored
for human review. → `201 { "reported": true }`

### `POST /api/users/:id/follow` · `DELETE /api/users/:id/follow`  (signed in)
→ `{ "following": true|false }`. 400 on yourself, 403 if either of you blocked the other.

A new follow tells the person once ("@riya followed you", see Notifications). Send `{ "fromPostId": "<video id>" }` in the body when it was done from a reel: the note then reads "@riya followed you from this reel" and carries that video (only if it is the followed person's own, ready video).

### Notifications  (signed in)
- `GET /api/notifications` → `{ unread, notifications: [{ id, kind: 'follow', text, createdAt, read, actor: {id, username, fullName, avatarUrl, isBot}, post: {id, title, coverUrl} | null }] }`, newest first, 50 at most. Blocked people, deleted accounts and videos that are gone are left out.
- `POST /api/notifications/read` → `{ unread: 0 }`: marks all read (the app calls it when the list is opened).
- One row per person who followed you: following, unfollowing and following again does not tell you twice.

### `POST /api/users/:id/block` · `DELETE /api/users/:id/block`  (signed in)
Blocking also removes the follow in both directions. → `{ "blocked": true|false }`

### `GET /api/users/suggested?limit=10`  (signed in)
Who to follow: people who have posted, that you don't follow and haven't blocked (or been blocked by), most
recently active first. Use it for onboarding and for an empty Home. Max `limit` 30.
→ `{ "users": [ { "user": User, "followerCount": 3, "postCount": 12 } ] }`

### `GET /api/users/:id`  (signed in)
Profile header. → `{ "user": User, "followerCount", "followingCount", "postCount", "followedByMe", "blockedByMe", "isMe" }`.
`postCount` counts finished posts only. 404 if the user doesn't exist **or has blocked you**. A user you blocked
is still viewable (so the app can offer Unblock).

### `DELETE /api/me`  `{ "password" }`  (signed in)
Deletes the account. `403 "Wrong password"` otherwise (403, not 401, because the app treats a 401 as "your login expired" and
signs out). On success → `{ "deleted": true }`: phone, e-mail, birth date, password, name and avatar are wiped, the username becomes
`deleted_xxxx`, likes/follows/blocks/reports/views are removed, video files are deleted from disk, and the person's posts stay but
are emptied (a text reply reads `[deleted]`, a video has no file) because other people's replies hang below them. Tokens issued
earlier stop working immediately (401). The phone number can sign up again.

### `GET /api/me/blocks`  (signed in)
People you have blocked, newest first. → `{ "users": [User] }`

### `GET /api/me`  (signed in)
→ `{ "user": User, "followingCount": 0, "followerCount": 0, "settings": { "friendTaste": true } }`

### `PUT /api/me/settings`  (signed in)
`{ "friendTaste": boolean }` → `{ "settings": { "friendTaste": boolean } }`. Whether friends' taste may shape this person's Discover (default on).
Anything but a boolean → `400`.

### `GET /api/health`
→ `{ "ok": true, "service": "forest-app-api" }`

### `GET /api/dev/users`  (only with `ALLOW_DEV_USER=1`)
→ `{ "users": [User] }`

## Discover (the reels tab)

Served from this backend, so Home and Discover share one set of users, posts, likes, reports and blocks.
Same paths and JSON the Flutter reels screens already use. Only `VIDEO` posts appear (never text replies).
Reading works signed out; every write needs sign-in (`401` otherwise). Blocked people (either direction) are hidden.

**Video** (not the same shape as `Post`): `{ id, title, caption, filename, coverUrl (`/uploads/...-cover.jpg` or null), status: "ready"|"processing"|"failed", role: "PARENT"|"CHILD",
parentVideoId, stance, credibility (0-100, mean of the AI fact-check scores, 50 if none), durationS (0, not tracked yet), authorId (the account id), authorAvatarUrl (the author's profile picture path or null),
userId, userName (both the username), authorId (the account's id, what block and report need), isBot, createdAt, likeCount, replyCount, forCount, againstCount (direct video replies),
viewerSide: "FOR"|"AGAINST"|null, liked, totalViews, completedViews, transcript (the AI analysis object, or null) }`.
Play it from `<base>/uploads/<filename>`.

- `GET /api/videos/feed?limit=10&cursor=` → `{ videos: [Video], nextCursor }`. Newest 120 READY opinions, ranked per person by
  PIPS (`src/recommendation.js`: watch interest, topic and creator affinity, novelty, engagement, freshness, minus repeats).
  `nextCursor` carries the ids already served, so one scroll never repeats a video. Max limit 30. Bad cursor → `400`.
  A page is mostly the person's own PIPS ranking, plus two bounded extras (`src/friendTaste.js`, all numbers are constants there):
  **friends**: up to 25 % of a page (less when the friendship is weaker) taken from what a friend's taste would pick, when that friend has
  sent the person at least 3 videos on at least 2 different days and the person liked, finished or watched them (a skipped or ignored video
  counts against, older reactions count for half after 60 days); and **exploration**: at least 10 % of a page (once the person's taste is
  known) that is away from their usual topics. Every extra post must have a fact-check score of at least 40 and not be a repeat; friends must be
  mutual followers, never bots, nobody blocked. A friend's profile is only used on the server and is never sent. The person can switch friend
  influence off (`PUT /api/me/settings`); exploration stays. `&explain=1` adds `source` (`own`/`friend`/`explore`) and `via` (the friend) to each
  video, on a development server only (ALLOW_DEV_USER).
  Every Discover video from `/feed` that was added by one of the two extras also carries `why`: `{ kind: "friend", by: "<friend's username>" }`
  or `{ kind: "explore" }` (own picks have none), so the app can say "Picked by @riya's taste" or "Something different from your usual".
  The Discover tab's grid reads this same list (24 at a time, each tile is `coverUrl` + counts) and a tapped tile opens the reels feed on
  that video, carrying on from the grid's `nextCursor`, so the grid and the reels can never disagree about order.
- Liking a video (Discover or Home) also teaches the person's profile (its topics and its creator, once per like; unliking does not undo it, and a
  like is not counted as a view).
- `GET /api/videos/:id` → Video. Unfinished videos are visible only to their author.
- `GET /api/videos/:id/status` → `{ id, status, stance, credibility }` (poll after an upload).
- `GET /api/videos/:id/replies?side=FOR|AGAINST` → `[Video]` direct video replies, best first (max 100). `400` on another side.
- `GET /api/videos/:id/strongest-reply?side=FOR` → `{ reply: Video|null }`.
- `GET /api/videos/:id/tree` → `[Video]` the whole video debate (any node in it), root first, breadth-first, strongest first, max 200.
- `PUT /api/videos/:id/opinion` `{side}` → `{ side, strongestReply }`. `DELETE` → `{ ok: true }`.
- `PUT|DELETE /api/videos/:id/like` → `{ liked, likeCount }` (the same likes as `POST /api/posts/:id/like`).
- `POST /api/videos/:id/views` `{watchedMs, completed}` → `{ ok: true }`. `watchedMs` is clamped to 0..6 h.
- `POST /api/videos/:id/interactions` (also `POST /api/videos/interactions` with `videoId` in the body)
  `{watchDurationMs?, completed?, skipped?, rewatched?, saved?, shared?}` → `{ ok, profile }`. Teaches the ranking; `watchDurationMs` also records a view.
- `GET /api/videos/profile` → the caller's taste profile. `POST /api/videos/profile/reset` → `{ ok: true }` (forget it).
- `POST /api/videos/:id/report` `{reason}` → `{ ok: true }`. Goes into the same review queue as Home reports; a reason that is not
  one of the Home reasons is filed as `OTHER`. One report per person per video; not your own.

Not carried over from the old server on purpose: `DELETE /api/videos/:id`, `POST /api/videos/clear-graph`, `GET /api/videos/graph`.

## Search (the Discover search box)

`GET /api/search?q=&type=all|accounts|posts&limit=20&cursor=`   needs sign-in. → `{ q, type, accounts: [Hit], posts: [Video], nextCursor }`

- `q` is tidied (control characters and extra spaces dropped, 80 characters, at most 5 words). Under 2 characters, or a query containing a word on
  the moderation blocklist, answers `200` with empty lists. Every word must match (AND). `%` and `_` are ordinary characters.
- **accounts**: username, full name or bio contains each word. Hit = `{ user, followerCount, postCount, followedByMe, isMe }` (never phone or e-mail).
  Ranked: exact username, then prefix, then word matches, people you follow first, then follower count. Bots appear with `user.isBot`.
- **posts**: READY `VIDEO` posts, openers and replies (text replies are not searched), whose title, caption, transcript or summary contain each word
  (`posts.search_text`, kept up to date by database triggers, so account deletion empties it). Shape is the Discover `Video`. A reply's
  `parentVideoId` says which debate it belongs to. Ranked by match quality (a word that starts a title beats one in the transcript), then credibility
  and freshness; likes and views are not used.
- Never returned: unfinished, failed or hidden posts; anything by a suspended or deleted person; anyone you blocked or who blocked you.
- `all`: the best 5 accounts and the best `limit` posts, `nextCursor` null. `accounts` / `posts`: paged, best 100 reachable. Bad cursor or type → `400`.
- Rate limit: 60 a minute per person. Queries are not stored or logged.

## Sending a video to a friend and direct messages (the paper-plane, and the plane at the top of Home)

Not chat. **The only thing that can be sent is a video, and the only reply is one of six emoji reactions.** There is no free text, so there is
nothing to abuse, no message requests and no stranger contact (CLAUDE.md). Everything below needs sign-in.

- `GET /api/users/friends` → `{ users: [User] }`. People you follow who follow you back, never bots, nobody blocked either way, nobody deleted or
  suspended. The ones you have sent to most come first. (The paper-plane sheet lists these.)
- `POST /api/posts/:id/share` `{ recipientIds: [userId, ...] }` (1 to 10) → `{ sent: [userId], skipped: [{ userId, reason }] }`.
  Only READY videos (`400` "Only videos can be sent" for text posts; `404` for anything the caller cannot see). `reason` is `NOT_FRIENDS`, `BOT`,
  `SELF` or `UNAVAILABLE` (blocked, deleted, suspended, unknown). Sending the same video to the same person again is not an error, is not counted and
  adds no second message. At most 50 new sends per person per rolling 24 hours (`429` with `retryAfterSec`), 30 requests a minute. A send adds a
  video message to the conversation between the two people (created on first use) and a row in `shares`, which is what Discover's friend-taste
  reads (what the recipient then does with the video).
- `GET /api/messages/conversations` → `{ conversations: [{ id, with: User, last: { kind, fromMe, preview, createdAt }, unread }], unreadTotal }`.
  Newest activity first. `preview` is "Sent you a video", "You sent a video", "Reacted 🔥 to your video" or "You reacted 🔥". `unread` counts what the
  other person did since you last read (videos and reactions). Conversations with someone blocked either way, deleted or suspended are left out.
- `GET /api/messages/unread` → `{ unread }`: how many conversations have something new (the badge on the plane).
- `GET /api/messages/with/:userId?limit=40&before=<messageId>` → `{ with: User, messages: [{ id, fromMe, video: Video | null, createdAt,
  reactions: { mine, theirs } }], hasMore }`. Oldest first within the page; `before` pages backwards. `video` is null when the post is no longer
  available. Nothing but videos is listed. Readable even after you stop being friends (nothing new can be sent).
- `POST /api/messages/with/:userId/read` → `{ ok: true }`: everything in that conversation is read.
- `POST /api/messages/:id/open` → `{ ok: true }`: the recipient opened a received video (first time sets `shares.opened_at`).
- `PUT /api/messages/:id/reaction` `{ emoji }` → `{ reactions }`. The emoji must be one of ❤️ 😂 😮 😢 👍 🔥 (`400` otherwise). One per person per
  video; a new one replaces the old. The sender is told: it shows in their inbox as something new. `DELETE` takes it back (and the note). 60 a minute.
- `404` for a message that is not in one of your conversations, with someone you cannot see, or that is not a video. Deleting an account deletes
  its conversations, messages, reactions and shares on both sides.

## Website live-data feed (one way: app -> website)

Optional. With `WEBSITE_SYNC_URL` and `WEBSITE_SYNC_TOKEN` set, `app/backend` checks every `WEBSITE_SYNC_SECONDS` (60) whether its data
changed and, if so, `POST`s an anonymous snapshot to the website's `/api/app-sync` (bearer token, must equal `APP_SYNC_TOKEN` on the
website). The website only stores it and draws it at `/app-live`; it never calls the app. Off by default; a down website is logged once
and never affects the app.
Sent: counts, and per READY post a hashed id, kind, depth, stance, time, bot flag, plus reply edges (max 1500 newest). Titles only with
`WEBSITE_SYNC_TITLES=1`. Never sent: names, usernames, phones, e-mails, birth dates, passwords, media, AI transcripts.
Code: `app/backend/src/websiteSync.js`; website side `Website/backend/routes/appSync.js` and `Website/frontend/app-live.html`.

## Moderation and complaints (demo level)

See `docs/LAST_STAGE_POLISH.md` for what is missing before real users. Report reasons: `MISINFORMATION`, `HARASSMENT`, `SPAM`, `VIOLENCE`, `COPYRIGHT`, `OTHER`.

- `GET /api/legal/contact` -> `{ grievanceOfficer: { name, email } | null }` (null until `GRIEVANCE_OFFICER_NAME` is set).
- `POST /api/complaints` `{ message (10-2000 chars), contact?, postId? }` -> `201 { received, id }`. Signed in or not. Used for problem reports and appeals.
- **Back office** (needs `MODERATION_TOKEN`; without it everything below answers 404). `GET /admin` is a one-page UI; the API uses `Authorization: Bearer <MODERATION_TOKEN>`
  (10 wrong tokens per address per 15 minutes, then 429):
  `GET /api/admin/reports`, `POST /api/admin/posts/:id/hide {reason?, note?}`, `.../restore`, `.../dismiss`, `POST /api/admin/users/:id/unsuspend`,
  `GET /api/admin/log`, `GET /api/admin/complaints`, `POST /api/admin/complaints/:id/resolve {reply}`.
- A **hidden** post has status `HIDDEN`: it disappears from every feed, thread and Discover list (the author can still open it by id). Every action is written to `moderation_log`.
- **Automatic first pass:** if `MODERATION_BLOCKLIST` (comma list, empty by default) matches a text reply or a video transcript, the post is hidden at once (log actor `auto`); a person can restore it.
- **Repeat infringers:** 3 standing `COPYRIGHT` hides (not restored) suspend the account. A suspended account gets `403` on every request and on login (403, not 401, so the app does not sign out and loop).

## Editor posts (`POST /api/posts/compose`)

For the Upload tab / reply editor (docs/EDITOR_PLAN.md). The phone sends a small **recipe** plus the files; the server renders one normal MP4
(H.264 + AAC, always with a sound track), then the post goes through the same pipeline as any video. Signed in; counts against the same post
rate limit and the 5-unfinished-videos limit as `POST /api/posts`.

`multipart/form-data`: `recipe` (JSON string), `photos` (up to 10 files: `.jpg .jpeg .png .webp`, 10 MB each), `music` (one file: `.mp3 .m4a .aac .wav .ogg`,
15 MB), `video` (one file: `.mp4 .mov .webm .mkv`, 50 MB), and optional `parentId`, `title` (roots, 120 chars), `body` (caption, 280 chars).
Answers `201` with an Item (like `POST /api/posts`): `post.status` is `PROCESSING` and `mediaUrl` is `null` until the render is done; poll
`GET /api/posts/:id` (or `GET /api/videos/:id/status`) as for any video. Errors are `400 { error, field }` naming the part of the recipe that is wrong.
`POST /api/posts/:id/retry` works for a failed render while its input files are still on the server.

```jsonc
{
  "mode": "VIDEO" | "TEXT" | "PHOTOS",

  // all modes (optional)
  "coverSec": 0..duration,      // the moment of the finished video whose picture becomes `coverUrl`; default: 0 for VIDEO, 2 s (or half) for TEXT/PHOTOS
  "adjust": { "brightness": -0.5..0.5 (0), "contrast": 0.5..2 (1), "saturation": 0..3 (1), "hue": -180..180 (0), "blur": 0..10 (0) },
  "overlays": [ { "text": "≤120 chars", "x": 0..1 (.5), "y": 0..1 (.5), "size": 20..120 (56), "color": "#rrggbb", "font": "sans|serif|mono",
                  "startSec": 0.., "endSec": ..duration } ],          // max 5; x,y = centre of the text as a fraction of the picture
  "music": { "volume": 0..1 (.8), "startSec": 0.. (0) },               // only with a music file; looped if shorter; fades out in the last second

  // VIDEO: needs the `video` file
  "trim": { "startSec": 0.., "endSec": .. },                           // result 0.5..60 s; no trim = the first 60 s
  "muteOriginal": false,                                               // also forced when the file has no sound
  "crop": { "x": 0..1, "y": 0..1, "w": 0.1..1, "h": 0.1..1 },          // fractions of the picture; must stay inside it
  // the picture keeps its own shape (the cropped one, height capped at 1280, always an even size); overlay times are measured on the trimmed video

  // TEXT: a 720x1280 video made of a background and big text
  "durationSec": 3..60 (8),
  "text": { "content": "1..280 chars", "color": "#rrggbb", "font": "sans|serif|mono", "size": 32..120 (64),
            "align": "left|center|right", "animation": "none|fade|slideUp|typewriter|wordByWord" },
  "background": { "type": "solid", "color": "#rrggbb" } | { "type": "gradient", "from": "#rrggbb", "to": "#rrggbb", "angle": 0..360 },  // 0 = `from` at the top, 90 = at the left

  // PHOTOS: 1..10 `photos` files, 720x1280, each fitted inside with black bars (crop applies per photo)
  "photoOrder": [2,0,1],        // which uploaded photo to show in each position (default: as uploaded)
  "slideSeconds": 1..8 (3), "transition": "none|fade" (fade = 0.5 s cross-fade); total must be <= 60 s
}
```

- **What the AI sees.** With speech (a video that is not muted) the *voice-only* track (no music) goes to Gemini, and the caption and any text overlays
  are added to the transcript. With nothing to transcribe (text, photos, muted video) the words the person wrote are the transcript, and for a reply the
  stance comes from classifying those words against the post it answers (UNRESOLVED if the AI is unavailable). There are no per-claim fact-checks for these.
- **Privacy.** The uploaded inputs are kept in a private folder (never under `/uploads`), deleted when the render succeeds, and also when the account is deleted.
  A failed render keeps them so Retry works.
- **Text** draws Latin letters, Hindi (Devanagari), Punjabi (Gurmukhi) and emoji. Emoji come out in one colour (the text's). Other scripts need a font added to
  `app/backend/assets/fonts` and to `src/compose/scripts.js` (see the README there), otherwise they draw as boxes.
- **Cover.** After the render a JPEG of the moment `coverSec` (at most 720 px tall) is written beside the video; `coverUrl` names it. If it cannot be made the
  post is still fine, with `coverUrl: null`. It is deleted with the video.
- **Upload types.** Each file part must carry its own type (`image/jpeg`, `audio/mpeg`, `video/mp4`, ...): photos are refused as `application/octet-stream`.
- `FFMPEG_PATH` overrides the bundled ffmpeg.

## Legacy endpoints (so today's Discover and Upload tabs keep working)

Same shape as the old Website backend. **Temporary**; the app should move to `/api/posts`.

- `GET /api/videos/all` (**development only**: 404 in production, because it is public and includes transcripts) → `[ { id, title, filename, status, role: "PARENT"|"CHILD", parent_video_id, stance, transcript, created_at, user_id } ]`.
  Videos only (no text replies), no sign-in. The newest 1000, listed oldest-first. `user_id` is the username.
- `POST /api/videos/upload` (multipart: `video`, `role`, `parentVideoId`, `title`, `userId`) → `201 { message, video }`.
  No sign-in. The upload is attributed to a find-or-create placeholder user named after `userId`, flagged
  as a bot so the app labels it, and never as a real account. Unlike the old server it returns immediately
  with `status: "PROCESSING"`. **Dev only:** with `NODE_ENV=production` it answers 404 unless `ALLOW_LEGACY_UPLOAD=1`.

## Serving media
`/uploads/<file>` is served with the right video/audio type, `X-Content-Type-Options: nosniff`, a sandboxing
`Content-Security-Policy`, and `Cache-Control: public, max-age=31536000, immutable` (file names are unique, so
clients and CDNs may cache them forever). Range requests work. API responses are `Cache-Control: no-store`.

## Differences from the draft in PHASE1_HOME_PLAN.md §6
- The Home endpoint is `GET /api/home`, not `/api/feed` (so it can't be confused with the Feed tab).
- `GET /api/posts/:id/thread` takes `limit`, not `cursor` (the whole conversation, capped at 200).
- Video posts are accepted asynchronously (`PROCESSING` → `READY`), because analysis takes seconds.
- Accounts are built (see above) but the app doesn't use them yet; `X-Dev-User` stands in until it does.
  Not built: Firebase/WhatsApp/MSG91 code delivery (only the dev console provider exists), e-mail
  verification, password reset, refresh tokens, account deletion.
- Report reasons are a fixed list. Follow/block take the user's `id`.
