# Discover: search + grid + a feed that learns from your friends

Status: all four steps built (grid, search, send to a friend, friends' taste) and checked on the emulator, 2026-10-20. Written 2026-10-19.

## What exists today

- The Discover tab (`lib/screens/discovery_feed_screen.dart`) **is** the full-screen reels feed: it opens straight into
  `ReelsFeed` (debate openers, swipe left/right between FOR and AGAINST replies, vertical watch history).
- The server ranks that feed with PIPS (`backend/src/recommendation.js`, route `GET /api/videos/feed`): one taste profile per
  person (`user_profiles`: topics, creators, recent views), updated by `POST /api/videos/:id/interactions`.
  So "an algorithm per person" already exists. Viewing is not treated as agreeing, and novelty/repetition penalties exist.
- There is no search, no grid, no thumbnail for ordinary uploaded videos (only editor posts have `cover_filename`), and no way to
  send a post to a person (Send only copies a link; `shared` in the profile is a flag nothing sets).
- `sql.js` here has no FTS5, so search is `LIKE` plus scoring in JS. Fine for the alpha; becomes Postgres full-text later.

## What Discover becomes

```
Discover tab
├─ search bar (always on top)
├─ not searching: grid of tiles, ranked for this person (+ "sent to you" row when there is something)
└─ searching: tabs  All | Accounts | Posts   (Channels slot reserved, hidden until channels exist)
tap a tile -> the existing ReelsFeed opens on that post and carries on through the grid order (like Instagram)
```

The reels feed is not thrown away. It becomes what a tile opens.

## Step 1: grid (do first)

- **Thumbnails (done).** Every uploaded video gets a JPEG about 1 s in, written by the job queue into the existing `cover_filename`
  column (so Home's poster works for all videos too, not a second column); `npm run thumbnails:backfill` did the existing 44.
  Editor posts keep the frame their author picked. The feed JSON carries `coverUrl`.
- **Endpoint (done, no new one).** The grid reads `GET /api/videos/feed` (24 per page, about 2 KB a post), so it is ranked by the same
  PIPS code as the reels and a tapped tile continues the same cursor. Openers only, blocked people excluded.
- **Layout that fits every phone.** Column count comes from the width (3 below 600 dp, 4 to 5 above), tile size from the column
  width, never fixed pixels. Mixed sizes come from a repeating pattern (a 2x2 feature tile and 1x2 tall tiles among 1x1s,
  feature side alternating) so the same feed looks the same on every device. `flutter_staggered_grid_view` `QuiltedGridView`.
- **Tile content.** Picture, a small kind mark (video / text / photos), FOR vs AGAINST counts, a visible BOT tag on bot accounts
  (hard rule in CLAUDE.md).
- Infinite scroll, pull to refresh, shimmer placeholders, and a plain "can't reach the server" state.

## Step 2: search

- `GET /api/search?q=&type=all|accounts|posts&limit&cursor`.
  - Accounts match username, full name, bio. Posts match title, caption, the AI description, the summary and transcript.
  - A `search_text` column (lower-cased title + body + description + summary + topics) is filled when analysis finishes, so the
    `LIKE` stays cheap. Ranking: exact/prefix beats substring, title beats transcript, then credibility and freshness.
  - Only READY posts (they have passed moderation), never blocked/suspended/deleted people, nobody who blocked you. "All" is a
    mix of the best accounts and posts, each section capped.
- App: 300 ms debounce, recent searches kept on the phone, tabs, empty and error states, tap an account -> profile
  (`openProfile(context, userId)`, the one hook the profile page needs to provide), tap a post -> reels on it.
- Channels: nothing built. The tab slot and a `type=channels` value are reserved so adding them later changes no URLs.

Built as planned, with these specifics: `posts.search_text` is filled by SQLite triggers (insert, and update of title/body/analysis) rather than by each
write path, because `sql.js` has no FTS5 and a trigger cannot be forgotten (it also empties on account deletion); the query word list is checked against
the moderation blocklist; tapping an account opens a small card (`open_profile.dart`, the one function the profile page replaces); tapping a reply
result opens its debate on that reply. Not done: Channels, "did you mean", searching text replies.

## Step 3: send a post to a person (needed for the friends idea)

Without this the "friends who share reels" signal does not exist.

- `shares(id, sender_id, recipient_id, post_id, created_at, opened_at, watched_ms, completed, liked)`.
- Send button on a post -> pick from people you follow who follow you back. No text, no chat. Max per day per sender.
- Recipient sees a "Sent to you" row at the top of Discover; opening it records what they did with it.
- Mutual-only plus the daily limit follow the CLAUDE.md rule on unsolicited contact. Blocks hide shares both ways.

Superseded in part by direct messages (docs/api.md): the "Sent to you" row above the grid was removed because sent videos now arrive in
the messages (the plane at the top of Home): an inbox with unread marks, the videos in each conversation, and emoji reactions. No free text, by
decision (nothing to abuse, no message requests).

Built as planned. The paper-plane on Home cards and in the reels opens a sheet (Copy link, then your friends with a Send button each); videos
only. `shares` stores just sender, recipient, post, time and when it was opened, because watching and liking are already in `post_views` and
`likes` (step 4 reads them from there). "Sent to you" is a row above the grid with a ring on the unopened ones. The Home card's paper-plane
used to copy the link directly; Copy link is now the first row of the sheet.

## Step 4: the feed learns from friends

Each person keeps their own profile. Friends add a **bounded** extra source, never replace it:

1. **Edge strength** sender -> recipient = recent (60-day half-life) reactions to what the sender sent: liked / finished /
   opened count up, ignored counts down. It only counts once the pair has at least 3 shares on 2 or more different days
   ("consistently", not one burst).
2. **Blend for the recipient's feed:** at most 25 % of a page comes from the strongest few senders, scaled by edge strength.
   Those candidates are the posts the *sender's* profile ranks highest (their topics and creators), minus what the recipient has
   seen, blocked, or already has from their own ranking.
3. **If the recipient liked it after watching** (not just reacted), it goes into the recipient's own profile like any liked video,
   so from then on "it is his algorithm anyway". If ignored, the edge fades and the profile is untouched.
4. **Guards.** A credibility floor applies to friend-sourced posts too (ranking stays tied to the credibility score, as CLAUDE.md
   requires). At least 10 % of every page is deliberate exploration (other topics and the other side of a debate) so friend
   circles do not become the echo chamber the app exists to break. The sender's profile is never shown or sent, only posts.
   Bots are never "friends". A setting "Let friends' taste shape my Discover" is on by default and can be switched off.
5. **Tuning and trust.** All numbers (25 %, 10 %, 60 days, 3 shares) are constants in one place. An admin-only "why this post"
   debug view shows which source put each tile on the page. Unit tests pin each rule.

Step 4 as built (`src/friendTaste.js`, `src/profiles.js`): edge strength, the 25 % cap, the 10 % exploration floor (only once 8+ topics are
known, so a new person's whole feed is already exploration), the credibility floor of 40, no repeats, bots never friends, and the off switch
(`PUT /api/me/settings`, a switch on the Account tab) are all as planned. Additions: a like now teaches the profile for every video (this is
how "if they liked it, it is their algorithm anyway" works, for friend-sent videos and any other); `?explain=1` on a dev server shows
`source`/`via` for each post instead of a separate admin view. Not done: tuning the constants against real use (they are all in one place, with
tests that pin the rules rather than the numbers), and a "why am I seeing this" line for people (only the dev explanation exists).

## Order and size

| Step | Work | Ends with |
|---|---|---|
| 1 grid | thumbnails + backfill, `/discover/grid`, tile layout, tap-to-reels | emulator pass on a small and a large screen |
| 2 search | `search_text`, `/search`, search UI | typing "phone" finds posts, accounts, and nothing blocked |
| 3 send | `shares`, send picker, "Sent to you" row | two dev accounts exchange a post on device |
| 4 blend | edge strength, blend, guards, debug view | a test where a consistent friend visibly changes the page, and caps hold |

Each step ships with backend tests (the 211 stay green), app tests and docs/api.md updates, and is committed on its own.

## Decisions (defaults in bold; say if you want any different)

1. Tapping a tile opens the reels feed on that post and continues in grid order: **yes**.
2. Grid shows debate openers only; replies live inside their debate: **yes**.
3. Send only between people who follow each other: **yes**.
4. Friends' share of a page capped at **25 %**, exploration floor **10 %**: **yes**.
5. The profile page belongs to Yaksh/friend; we only call `openProfile(context, userId)` and do not edit `account_screen.dart`.
6. "Shown using AI moderation" means: only posts that already passed the existing moderation pipeline appear in search and grid.
