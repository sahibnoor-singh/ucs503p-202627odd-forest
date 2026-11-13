# Phase 1 — Home tab, accounts & replies: build plan

Status: **planning, agreed direction** · Owner: Sahibnoor (Home tab + backend) · Feed/Discover tab: friend (shares theme + card components from this plan)

This is the source of truth for what we're building next and in what order.
Rule: nothing gets built that isn't described here first. If the plan is
wrong, fix the plan in the same PR as the code.

---

## 0. Why this plan exists

The first Home-tab pass was UI built before the data existed: the backend
only has `videos` (+ admin `uploads`) — no users, follows, likes, or
comments — so names, handles, "following" and counts on screen were
placeholders. To avoid a vibecoded app we build in this order, every time:

**spec → data model → API contract → UI on fake data of that exact shape → wire to real API**

---

## 1. Product rules (decided)

### 1.1 Everything is a reply
FOREST is a global debate hub, not a comment section under someone's post.
Every interaction that adds content is a **reply** to another node in the
debate graph. A reply can be:

| Kind  | What it is | Why |
|-------|-----------|-----|
| VIDEO | a recorded reply reel (the core of the product) | video debate is the point |
| TEXT  | a short written reply | low-effort entry point so new users actually interact; we nudge them towards video over time |

Both kinds go through stance classification (FOR / AGAINST / UNRESOLVED
against what they reply to). Text uses Gemini text-only — cheap, no FFmpeg.

### 1.2 Replying to a reply is allowed
- User **A** posts a reel (root). User **B** replies to A. User **C** replies to B.
- C's reply is stored with `parent = B's reply` and `root = A's post`.
- It shows **in B's reply thread and in A's debate** (A's post counts it in its total).
- No depth limit in data; UI shows depth ≥ 2 as "replying to @b" inside A's thread.

### 1.3 Scoring hooks (credibility score comes later — `S_Cᵢ = w(Vᵢ) × Eᵢ`)
We don't compute the score in Phase 1, but the data must support it:
- Posting a reel → score event for the author.
- Receiving a direct reply → full interaction weight for the parent's author.
- Receiving an indirect reply (reply-to-a-reply, like C→B inside A's debate) → **½ weight** for the root author (A); B gets full weight as the direct parent.
- Rank/streak/payout must gate on `S_Cᵢ`, not raw counts (CLAUDE.md hard rule) — so likes/views are stored but never used alone for rewards.

Store `root_id` and `depth` on every reply so this is a simple query later.

### 1.4 Likes
Any node (post, video reply, text reply) can be liked. One like per user per node.

### 1.5 Content safety & "manage your brainrot" (later phases, hooks now)
Not built in Phase 1, but cards reserve space for them:
- **Fact-check badge** on a card when the AI pipeline flags claims (pipeline already exists).
- **Propaganda / coordinated-content signals** → downrank + label, never silent removal without review.
- **Balanced exposure**: Discover deliberately surfaces the other stance (anti echo chamber).
- **Time-well-spent controls**: daily time summary, optional limits, "you're caught up" end-of-feed.
- Report / block on every card (**Phase 1 must ship this**, see slice 6).

---

## 2. Home feed card types

Home = activity from people you follow. **Plain mode only.** The clickable
prototype is `docs/design/home_prototype.html`; where this section and the
prototype disagree, the prototype wins and this section gets fixed.

### 2.0 Scope decisions (made after reviewing the prototype)
- **Plain mode only.** Flat icon actions, no pill-shaped capsules. The prototype's "Lab" mode is not built.
- **Stories row: yes. Repost: no.** The stories row is part of the approved prototype in Plain mode (see 2.1); only the Repost button is Lab-only, and it is not built.
- **Forward becomes "Share link".** The send icon copies the post link (`forest.app/p/<id>`, as in the prototype; no web page behind it yet) and shows a "Link copied" toast. No pick-people sheet: sending posts to people is messaging, which is Phase 4+ (CLAUDE.md).
- **Reels in cards are 4:5**, not 9:16. Tapping opens a full-screen viewer. Discover keeps its own full-screen 9:16 feed.
- The Plain/Lab switches and the theme button in the prototype are design tooling, not app UI. The app follows the system light/dark setting.
- Profile pages are a placeholder until accounts exist (§4).

### 2.1 Shared pieces (all three cards use these)

**Stories row.** A horizontally scrolling row at the top of the feed (it scrolls away with the cards), with a 1px bottom
border. First a "Your story" tile (dashed ring with a +); then one 60px ring per person you follow (avatar inside a 2px
`fg` ring), username underneath, 64px wide per tile. The people are the authors of the cards in the feed (Home only shows
people you follow), in feed order, not you. Bot accounts get a `BOT` tag under the name, so a long name can never hide it
(the prototype writes "· BOT" inline, which the ellipsis can cut off). Tapping a ring toggles a local "seen" look (ring turns
grey, `border` colour) and is forgotten when the app restarts. Tapping "Your story" shows the toast "Your story: not built yet".
There is no server support for stories (see section 10).

**Card shell (`ForestCard`).** Radius 14, 1px `border`, `surface` fill. Feed has 2px padding and 2px gap between
cards. Media runs edge to edge; every text row is inset 8px.

**Media (`PostMedia`).** A fixed 4:5 frame; the video fills it (cover), so nothing jumps while loading. (The API has no
width/height/duration, and we are not asking for them.) Overlays: play icon in the centre while paused, mute button
bottom-right, 4px progress bar along the bottom edge, and a duration pill (`m:ss`) bottom-left that appears once the
video has loaded. Overlays are white on a dark scrim in both themes. A video only loads while part of its card is on screen.
- Single tap → full-screen viewer (§2.4). Double tap → like with a heart burst (never un-likes).

**Header (`UserHeader`).** 26px avatar (person silhouette when `avatarUrl` is null), bold username, `BOT` tag when
`isBot`, then a grey sub-line. Tapping a name or avatar does nothing yet (no profile pages until accounts exist). Right side: a chip and `⋯`.
- Card A sub-line `· 3h`, chip `OPINION` (outlined, no fill).
- Card B sub-line `replied · 1h`, chip = the reply's stance.
- Card C sub-line `replied to @aman_s · 1h`, chip = the reply's stance.

**Caption line.** `username [BOT] text` on one flowing line, username bold. Text is the title plus the caption/summary
for an opinion, the body for a reply. Clamped to 2 lines with an inline `… more` that expands in place.
There is no separate summary block.

**Action row (`ActionBar`).** Left to right: `♡ count` · `💬 count` (opens the thread) · `↩ Reply` · centred
`N FOR · N AGAINST` (hidden when both are 0) · share icon (copy link). Like is optimistic; if the API call
fails, roll back and show a toast. Heart and comment counts come from the post; reply count is all replies below it.

### 2.2 The three cards

#### Card A: someone you follow posted an opinion
```
┌────────────────────────────────────────────┐
│ (●) aman_s  · 3h               [OPINION] ⋯ │
│ ┌────────────────────────────────────────┐ │
│ │                                        │ │
│ │       4:5 reel, edge to edge           │ │
│ │ 0:42                              🔇   │ │
│ └────────────────────────────────────────┘ │
│ aman_s Should Punjabi be mandatory… more   │
│ ♡ 40  💬 8  ↩ Reply   3 FOR · 5 AGAINST  ⇪ │
└────────────────────────────────────────────┘
```

#### Card B: someone you follow replied with a VIDEO
The reply's own reel is the big media. The video it replied to sits underneath as a small quoted block.
```
┌────────────────────────────────────────────┐
│ (●) riya_k  replied · 1h       [AGAINST] ⋯ │
│ ┌────────────────────────────────────────┐ │
│ │        4:5 reply reel                  │ │
│ └────────────────────────────────────────┘ │
│ riya_k Mandates hurt students from…        │
│ ♡ 12  💬 3  ↩ Reply                      ⇪ │
│ ┌──────────────────────────────────────┐   │
│ │┌────┐ Parent video @aman_s            │   │
│ ││ ▶  │ Should Punjabi be mandatory…    │   │
│ │└────┘ ♡ 40  💬 8                  ⇪   │   │
│ └──────────────────────────────────────┘   │
└────────────────────────────────────────────┘
```
Quoted block: a 46px-wide thumbnail strip (only if the parent is a video) with a play icon, then
`Parent video @user [BOT]`, the parent's title or text (2 lines), and a mini row `♡ count · 💬 count` with share at the
right. When the root is not the parent, a blue `in @aman_s's debate →` link sits at the right of the first line and
opens the root's thread. Tapping the block opens the full-screen viewer if the parent is a video, otherwise its thread.

#### Card C: someone you follow replied with TEXT
The reply text is plain 14px body text (not a big headline). The parent video is shown below as a boxed
original with its own header, 4:5 reel, caption and actions.
```
┌────────────────────────────────────────────┐
│ (●) riya_k  replied to @aman_s · 1h  [AGAINST] ⋯ │
│ Most states that did this saw dropout      │
│ rates rise for migrant kids.               │
│ ♡ 5  💬 1  ↩ Reply                       ⇪ │
│ ┌──────────────────────────────────────┐   │
│ │ (●) aman_s · 3h      [PARENT VIDEO]  │   │
│ │ ┌──────────────────────────────────┐ │   │
│ │ │        4:5 original reel         │ │   │
│ │ └──────────────────────────────────┘ │   │
│ │ aman_s Should Punjabi be mandatory…  │   │
│ │ ♡ 40  💬 8  ↩ Reply  3 FOR · 5 AGAINST ⇪│  │
│ │ in @aman_s's debate →   (root≠parent)│   │
│ └──────────────────────────────────────┘   │
└────────────────────────────────────────────┘
```

#### Reply to a reply
Same cards. The quoted/original block shows the **direct parent** (the reply being replied to), and the
`in @root's debate →` link points at the root.

### 2.3 States the API forces on us (not drawn in the prototype)
- **Video post with no `mediaUrl`** → dark media box with a video-off icon and "Video unavailable". Never crash, never show a spinner forever.
- **`status: PROCESSING`** (only ever your own post) → media box shows a spinner and a "Processing…" badge. Poll `GET /api/posts/:id` about every 3 s until `READY` or `FAILED`, then update the card in place.
- **`status: FAILED`** → media box shows "Processing failed".
- **`isBot: true`** → the `BOT` tag appears everywhere the username does: header, caption, quoted block, thread, viewer, profile (CLAUDE.md hard rule).
- **Empty feed** → "Nothing here yet" with a button to Discover.
- **Load error** → message + Retry. Pull to refresh. Next page loads with `nextCursor` when the user nears the end.
- **Missing parent** (`parent: null` on a reply) → render the reply without a quoted block rather than failing.

### 2.4 Sheets and overlays
All sheets slide up from the bottom (20px top radius, `raised` fill, grab handle) over a `scrim`.

- **`⋯` menu.** Context line (`username: snippet`), then **Report**, **Block @user**, **Copy link**.
- **Report.** "Why are you reporting this?" with five rows that map to the API reasons:
  Misinformation → `MISINFORMATION`, Harassment or hate → `HARASSMENT`, Spam or fake account → `SPAM`,
  Violent or graphic content → `VIOLENCE`, Something else → `OTHER`. Hint: "Reports go to a human review queue.
  Nothing is removed automatically." Success toast: "Reported. We will review it." Not offered on your own posts.
- **Block.** Removes that person's cards from the feed immediately; toast "Blocked @user" with **Undo** for about
  4.5 s (Undo = unblock). Blocking is by user id.
- **Reply sheet (`↩ Reply`).** Title "Reply to @user", a switch pill at the right (`Aa Text` ⇄ `Video`), a 2-line
  context quote of what you are replying to.
  - *Video mode (default):* one big **Upload video** button ("Record now or pick one from your gallery") that reveals
    two choices, **Record** (camera) and **Gallery** (system video picker). Hint: "Video replies are the heart of
    FOREST. Tap Text if you just want to write."
  - *Record:* camera preview, `m:ss / 1:00` timer, round record/stop button, max 60 s. After stopping: **Retake** / **Post reply**.
  - *Gallery:* after picking, show file name and size with **Post reply** and "Choose a different video". Over 50 MB is refused before upload with a clear message.
  - *Text mode:* textarea, 280 characters (an emoji counts as one), placeholder "Make your point in 280 characters",
    helper "Gemini will classify your stance" with a live `n/280` counter that turns red from 260. **Post reply** is disabled while empty.
  - After posting a text reply, toast "Reply posted. AI stance: FOR/AGAINST/UNRESOLVED". After posting a video reply (it comes back
    `PROCESSING`), toast "Reply posted. Analysing it now."
- **Thread sheet (`💬`).** Tall sheet (88% of height): "Replies" + close, the context quote, then the reply tree. Each node:
  avatar, username, `BOT`, age, stance chip, then the text or a video row (small 9:16 thumbnail with play icon, caption or
  "Video reply", `m:ss video`), a **Reply** text button, and a heart + count at the right. Replies are indented with elbow
  connector lines; siblings are newest first. Rebuild the tree from the flat list using `post.parentId`.
  Bottom composer: avatar, text field "Reply to @user…" (280 max, counter shown from 200), **Post**, and a camera button for a video reply.
  Tapping **Reply** on a node points the composer at that node. If the API capped the list, show "Showing X of Y replies".
  Empty: "No replies yet. Start the debate."
- **Full-screen viewer.** Black layer over the app. Top bar: back arrow, small avatar, username, `BOT`, age. Mute button top-right.
  Bottom: title or body and the same action row. Tap toggles pause, double tap likes.
- **Profile pages: not built.** Accounts come later, so tapping a username does nothing, and there is no Follow button
  (the API does not say whether you already follow someone).

### 2.5 Interactions
- Only one reel plays at a time: the most visible one, and only if more than about 45% of it is on screen. A reel the user paused stays paused.
- Videos start muted. The mute button is feed-wide: muting one mutes all, and a toast says "Videos muted" / "Sound on".
- `♡` on a card and `♡` on its quoted parent are independent.
- `↩ Reply` opens the reply sheet for that exact post. `💬` opens that post's thread. `⇪` copies the link.
- Horizontal swipe moves between the four tabs; Home scrolls vertically. The four-button bottom nav stays visible.

### 2.6 Feed rules (alpha)
- Chronological, newest first. No ranking algorithm in Phase 1.
- If several people you follow replied to the same post, show separate cards for now (grouping later).
- End of feed → "You're all caught up", "That is everything from people you follow." and a **Go to Discover** button.

---

## 3. Visual system (shared with Feed/Discover tab)

Instagram-style monochrome. Colour is for meaning only (stance chips, like
heart, errors, the blue accent for links and primary buttons), never for chrome.
Values below are copied from the prototype's CSS variables.

| Token | Dark | Light |
|-------|------|-------|
| `bg` (scaffold) | `#121212` | `#FFFFFF` |
| `surface` (cards) | `#1C1C1E` | `#FFFFFF` |
| `raised` (quoted block, sheets, inputs) | `#262628` | `#FAFAFA` |
| `border` | `#2C2C2E` | `#DBDBDB` |
| `fg` (primary text) | `#F5F5F5` | `#000000` |
| `fg2` (secondary text) | `#A8A8A8` | `#737373` |
| `accent` (links, primary buttons) | `#0095F6` | `#0095F6` |
| `like` | `#FF3040` | `#FF3040` |
| stance FOR | `#5FBF7F` | `#1E7B3F` |
| stance AGAINST | `#E5645F` | `#C0392B` |
| stance UNRESOLVED | `#A78BFA` | `#6D4AC9` |
| `scrim` | black 60% | black 45% |

(The old draft had a white accent on dark. The prototype uses `#0095F6` in both themes, so that wins.)

- **Stance chip:** pill, 10px, bold, letter-spacing about 0.07em, text in the stance colour on a 13% tint of that colour.
  `OPINION` / `PARENT VIDEO` chips are outlined (1px `border`, no fill, `fg2` text).
- **`BOT` tag:** 9px, heavy, letter-spacing about 0.08em, 1px `fg2` outline, 4px radius, `fg2` text.
- **Type:** system font (Roboto on Android, SF on iOS). Body 15, username 14 (600), caption and reply text 14,
  opinion title 15.5 (700), sub-lines 12, chips 10, action counts 13 (600). No bundled font.
- **Icons:** 18px line icons, about 1.9px stroke, round caps. Material or Cupertino outlined icons are fine; the exact SVG paths in
  the prototype need not be copied.
- **Home has no app bar.** Content starts below the status bar (safe area). The prototype shows no FOREST wordmark on Home.
- Theme follows the system light/dark setting. There is no in-app toggle.

Deliverable: `lib/theme/` tokens + `lib/ui/` components (`ForestCard`, `PostMedia`, `UserHeader`, `CaptionLine`,
`ActionBar`, `StanceChip`, `BotTag`, `QuotedBlock`, sheet helpers) that both tabs import. Friend reviews this PR before building on it.

---

## 4. Accounts (Instagram-style sign-up)

### Sign-up flow (screens)
1. **Mobile number** → OTP verify.
2. **Full name**.
3. **Username** (the visible nickname / @handle) — **real-time availability check** as they type (debounced 400 ms): ✓ available / ✗ taken / ✗ invalid, with suggestions when taken.
4. **Email** — optional, "Skip for now" allowed (verify link sent if entered).
5. **Date of birth** → must be 18+ (see Age below).
6. **Password**.
7. Done → pick a few people/topics to follow (so Home isn't empty).

### Username rules
3–30 chars, lowercase `a–z 0–9 . _`, can't start/end with `.`, no `..`,
case-insensitive unique, reserved list (`admin`, `forest`, `support`, …).
Bot/seed accounts get `is_bot = 1` and a visible **BOT** label everywhere (CLAUDE.md hard rule).

### Login
Phone or username or email + password → JWT (access) stored in secure storage.

### OTP delivery (decided)
Backend hides this behind one `OtpProvider` interface (`send(phone)`, `verify(phone, code)`) so switching provider never touches the app or the rest of the backend.

| Stage | Provider | Cost | Why |
|-------|----------|------|-----|
| Closed alpha (10–15 users) | **Firebase Phone Auth** | first 10 SMS/day free, then ~$0.07/SMS; needs Blaze billing plan | zero DLT paperwork, drop-in Flutter plugin |
| College beta onwards | **WhatsApp authentication template** (Meta Cloud API, no bot needed) — primary | ₹0.115 per delivered OTP | cheapest, no DLT, nearly every Indian user has WhatsApp |
| College beta onwards | **MSG91 SMS** — fallback when user has no WhatsApp / delivery fails | ~₹0.15–0.20 per OTP + one-time DLT registration | required for users without WhatsApp |

WhatsApp needs Meta Business verification first (can take days–weeks) — start it
during the alpha so it's ready for the beta.

### Age (decided)
- Instagram's global minimum is 13, but India's DPDP Act treats everyone under
  18 as a child needing verifiable parental consent (Instagram handles this with
  supervised Teen Accounts). We don't have that infrastructure.
- **Minimum age 18 for alpha + college beta** (the audience is college students
  anyway). Revisit 13–17 with a parental-consent flow before public launch.

### Email (decided)
**Optional at sign-up**, verified by link whenever it's added. Required before
password reset by email. Users without email recover via phone OTP.

---

## 5. Data model (Node + SQLite now; maps 1:1 to Postgres + Neo4j later)

```sql
users (
  id TEXT PK, phone TEXT UNIQUE, phone_verified INT,
  full_name TEXT, username TEXT UNIQUE COLLATE NOCASE,
  email TEXT UNIQUE, dob TEXT, password_hash TEXT,
  avatar_url TEXT, bio TEXT, is_bot INT DEFAULT 0,
  created_at TEXT
)

follows (follower_id, followee_id, created_at, PK(follower_id, followee_id))

-- Unified debate node. Replaces the role/parent split in `videos`.
posts (
  id TEXT PK, user_id TEXT,
  kind TEXT,            -- VIDEO | TEXT
  parent_id TEXT NULL,  -- null = root opinion
  root_id TEXT,         -- = id for roots
  depth INT,            -- 0 root, 1 reply, 2 reply-to-reply…
  title TEXT NULL, body TEXT NULL,   -- body = text reply / caption
  media_filename TEXT NULL,
  stance TEXT,          -- PARENT | FOR | AGAINST | UNRESOLVED
  status TEXT,          -- PROCESSING | READY | FAILED
  analysis JSON NULL,   -- Gemini transcript/summary/claims
  created_at TEXT
)

likes (user_id, post_id, created_at, PK(user_id, post_id))

reports (id, reporter_id, post_id, reason, created_at)
blocks  (blocker_id, blocked_id, created_at, PK(...))
```

- **Migration**: copy existing `videos` rows into `posts` (kind=VIDEO,
  depth 0/1). Keep `/api/videos/*` working (reading from `posts`) until the
  website and Discover tab have moved over — nothing breaks for the friend.
- Neo4j later: `(:User)-[:FOLLOWS]->(:User)`, `(:User)-[:POSTED]->(:Post)`,
  `(:Post)-[:REPLIES_TO {stance}]->(:Post)`, `(:User)-[:LIKED]->(:Post)` —
  same shapes the `forest/forest_backend` Spring prototype already sketches.

---

## 6. API contract (lives in `docs/api.md` once slice 2 starts)

| Method | Path | Notes |
|--------|------|-------|
| GET  | `/api/auth/username-available?u=` | real-time check, rate-limited |
| POST | `/api/auth/otp/send`, `/api/auth/otp/verify` | depends on provider decision |
| POST | `/api/auth/signup`, `/api/auth/login` | returns JWT + user |
| GET  | `/api/me` | current user |
| POST/DELETE | `/api/users/:id/follow` | |
| GET  | `/api/feed?cursor=` | Home feed items (below) |
| GET  | `/api/posts/:id` | node + counts |
| GET  | `/api/posts/:id/thread?cursor=` | replies under a node (all depths, with parent refs) |
| POST | `/api/posts` | multipart; `kind`, `parentId?`, `title?`, `body?`, `video?` |
| POST/DELETE | `/api/posts/:id/like` | |
| POST | `/api/posts/:id/report`, `/api/users/:id/block` | |

Feed item shape:
```json
{
  "type": "POST" | "VIDEO_REPLY" | "TEXT_REPLY",
  "actor": { "id", "username", "fullName", "avatarUrl", "isBot" },
  "post":   { ...Post, "likeCount", "replyCount", "forCount", "againstCount", "likedByMe" },
  "parent": { ...Post } | null,
  "root":   { "id", "username", "title" } | null,
  "createdAt": "…"
}
```

---

## 7. Flutter app architecture

```
lib/
  theme/        tokens (colours, type, spacing) — shared
  ui/           ForestCard, ReelPlayer, QuotedCard, ActionBar, StanceChip, UserHeader — shared
  models/       User, Post, FeedItem (fromJson matches §6 exactly)
  data/
    feed_repository.dart      abstract interface
    fake_feed_repository.dart sample data (used by tests + until API is live)
    api_feed_repository.dart  real HTTP
    auth_repository.dart      signup/login/username check
  features/
    home/       HomeScreen, FeedItemCard (switches on type → A/B/C)
    auth/       sign-up flow screens
    thread/     full debate thread view
    reply/      reply composer (video / text)
  services/     ApiClient (http + JWT), secure storage
```
State: `provider` (already a dependency). Screens never call `http` directly — only repositories.

---

## 8. Build slices (one PR each, in order)

Each slice: tests pass, `flutter analyze` clean, screenshots in the PR, no
dead buttons (anything not wired is hidden, not faked).

| # | Slice | Needs backend? | Done when |
|---|-------|---------------|-----------|
| 1 | **Theme + shared UI components** (§3) | no | light/dark screenshots approved by both founders + friend |
| 2 | **Models + FakeFeedRepository + Home cards A/B/C** (§2, §6 shapes) | no | Home renders all 3 card types + reply-to-reply from fake data; widget tests per card type |
| 3 | **Accounts backend + sign-up flow** (§4) | yes | can sign up with real-time username check, log in, see own profile |
| 4 | **posts / follows / likes tables + migration + `/api/feed`** (§5, §6) | yes | API tests; old `/api/videos/*` still works |
| 5 | **Wire app to API**: like, reply (video + text), follow, thread view | yes | end-to-end on a phone against staging |
| 6 | **Report / block** | yes | required for closed alpha |
| 7 | Change admin default creds, deploy for closed alpha | — | CLAUDE.md checklist |

Later (not Phase 1): credibility score, fact-check badges, propaganda
signals, time-well-spent controls, feed grouping, chat (Phase 4+).

---

## 9. Answered decisions log

| Question | Decision |
|---------|----------|
| Comments: video or text? | **Both.** Text lowers the barrier; video is nudged as primary. |
| Reply to a reply? | **Yes.** Stored with parent + root; appears in both threads; root author gets ½ score weight. |
| Sign-up fields | Mobile, full name, username (live availability), email, DOB, password. No Facebook/Google for now. |
| Look | Instagram monochrome: dark grey `#121212` / white. Colour only for meaning. |
| Shared design | Theme + components shipped in slice 1 and handed to the Feed-tab owner. |
| Backend | Stay on Node/Express + SQLite for Phase 1 (no Spring Boot until alpha validated). |
| OTP | Firebase Phone Auth for alpha → WhatsApp OTP (primary) + MSG91 SMS (fallback) from beta. Behind `OtpProvider` interface. |
| Minimum age | 18+ for alpha and beta (DPDP Act). Revisit before public launch. |
| Email | Optional at sign-up; verified when added. |
| Text reply length | 280 characters. |
| Prototype mode | **Plain only.** Lab mode (pill-shaped action capsules and the Repost button) is not built. The stories row is part of Plain mode and is built (as a local-only UI, see section 10). |
| Forward button | Becomes **Share link** (copies the post link). Sending to people is chat, Phase 4+. |
| Reel size in Home cards | **4:5** (clamped 4:5 to 1.91:1 once the API gives a ratio); tap opens a full-screen viewer. Discover stays full-screen 9:16. |
| Reply by video | Record (60 s max) **or** pick from the gallery (50 MB max, API limit). |
| Profile page | **Not built** until accounts exist: tapping a username does nothing; no Follow button. |
| Theme scope | The whole app uses the §3 monochrome tokens (done in `app/lib/theme/` only; Discover screen files untouched). Follows the system light/dark setting. |
| Home wordmark | Dropped: no app bar on Home, as in the prototype. |
| Video frame | Fixed 4:5 frame; the **whole video is fitted inside it** (never cropped or stretched), black bars fill the rest. The full-screen viewer does the same on the whole screen. Duration pill once the player has loaded. No `durationSec`/`aspectRatio` API fields. |
| Gallery picker | `image_picker` (system photo picker; no Android permission, iOS gets a photo-library string). |
| Block then Undo | Undo unblocks and, for someone whose card you blocked from, follows them again, because blocking removes the follow. |
| Icons | The prototype's own SVGs (`app/assets/icons/`, extracted from `home_prototype.html`), drawn with `flutter_svg` and tinted from the theme. No Material icons on Home, the bottom bar or the sheets. |
| Font | Roboto is bundled (`app/assets/fonts/`, Apache 2.0). Some Android skins (OxygenOS) have no "Roboto" system family and Flutter fell back to a serif. iOS keeps the system font. |
| Bottom bar | Custom `ForestNavBar` with the prototype icons and labels, replacing the Material bar. |
| Post header avatar | 36 dp (prototype 26), by request: the small circle looked cramped on a phone. The boxed original's header stays 30. |
| Stories row | No divider under it: it runs straight into the first card. A bot's `BOT` mark is a small pill on its ring (no extra row under the name), so names are never shortened for it. |
| Video loading | Session `VideoCache` (files in the app temp dir, wiped at every start, 300 MB cap, least-recently-used out first) plus `VideoPool` (last 5 players stay initialised and are shared between card and viewer). Scrolling back shows the last frame, not black; a reel seen once reopens from disk; the next screen of reels is opened before it is reached. Playback never waits for the download: it streams first and is saved in the background. |
| Fidelity checks | `test/fidelity_geometry_test.dart` pins the measured prototype numbers (card inset 2, radius 14, 4:5 reel, 22 dp action row, 2 dp gaps, no gap under stories). |

## 10. Still open
- New questions get added here, not decided in chat and forgotten.
- **Stories:** story content and creation not designed yet. The row shows the people you follow with a local-only "seen" toggle, and "Your story" is a toast. Needs a decision on what a story is (video? text? how long does it live?), a backend, and how it fits the credibility rule, before any real stories exist.
- **Own video replies on Home/threads:** `GET /api/home` and the thread only return READY posts, so a video reply you just posted is not visible anywhere until analysis finishes (the app polls and counts it then). Fine for the alpha; revisit if people find it confusing.
- **Light mode and Discover:** the Discover tab hard-codes a black background with a transparent app bar, so its title is black on black when the phone is in light mode. Needs a one-line change in the Discover screen (owner: friend).
- **Follow state:** if profile pages are ever added, `User` needs a `followedByMe` (or `GET /api/users/:id`).

---

## 11. How we work (process model)

**Agile, iterative-incremental (Scrum-lite)** — not waterfall.

Why not the others:
- **Waterfall / V-model**: assumes requirements are known up front. Ours aren't —
  the closed alpha exists to find out what users actually do. Freezing everything
  now guarantees rework later.
- **Spiral**: risk-driven and heavy on formal risk analysis each loop; built for
  large, expensive projects. We borrow its idea (Phases 0–4 each de-risk the next)
  without the ceremony.
- **Agile, iterative-incremental**: each slice in §8 is an increment that ships
  something working and testable, then we learn from it.

What stops this from turning into "redo everything" (the rules):
1. **Spec before code, per slice.** A slice starts only when its section in this
   doc is written and both founders agree. The doc is the contract.
2. **Freeze the current slice.** New ideas during a slice go to a backlog in this
   doc, and get picked up in a *later* slice — never mid-slice.
3. **Definition of Done** for every slice: matches spec, `flutter analyze` clean,
   tests for new logic, screenshots in the PR, no fake/dead buttons, docs
   updated (`docs/api.md` for API changes).
4. **Contract first.** API shapes (§6) are agreed before either side builds;
   the app is built on fake data of exactly that shape.
5. **One PR per slice**, reviewed by the other founder before merge. Small PRs, merged often.
6. **Sprints of ~1 week** with a short review: what shipped, what we learned,
   what changes in the plan. Plan changes are edits to this file, in git.
7. **Testing at every level** (the good part of the V-model): unit tests for
   models/logic, widget tests for each card/screen, API tests for each endpoint,
   and a manual test on a real phone before an alpha build goes out.
