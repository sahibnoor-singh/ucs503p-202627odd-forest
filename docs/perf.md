# Backend performance notes

Measured with `app/backend/scripts/bench.js` (deterministic synthetic data, the real Express app, fake
Gemini/ffmpeg). Numbers are milliseconds on the machine that ran them, so compare before/after, not
against other machines. Re-run after any change to queries or storage:

```
cd app/backend
node scripts/bench.js                              # 2,000 users, 30k posts, 120k likes, in memory
BENCH_FILE=1 SAVE_DELAY_MS=250 node scripts/bench.js   # same, writing to a real DB file like the server does
USERS=60 ROOTS=300 LIKES=3000 FOLLOWS_PER_USER=15 BENCH_FILE=1 SAVE_DELAY_MS=250 node scripts/bench.js   # closed-alpha size
```

## What was slow, and what changed

| Problem | Fix |
|---|---|
| Home ran **222 queries per request**: each card looked up its author, counts, parent and root one by one | Batched hydration (`toItems` / `toPosts`): a fixed ~12 queries for any page size |
| Reply counts used one recursive query per post | Opinions use one indexed `GROUP BY root_id`; replies use one recursive query seeded with all of them. A test proves they match the old per-post method on random trees |
| Block checks (a per-row subquery) ran for everyone, doubling the feed query | Only added when the caller has blocked someone |
| `sql.js` rewrites the **whole database file** after every change. At 66 MB a like took 164 ms (up to 928 ms) | Writes are coalesced (`DB_SAVE_DELAY_MS`, default 250) and back off to at most ~10% of the time. `flush()` on shutdown and exit |

## Results (30,395 posts, 120,000 likes, 66 MB database)

| endpoint | before p50 | after p50 | before p95 | after p95 |
|---|---|---|---|---|
| `GET /api/home?limit=20` | 39 | 15 | 71 | 21 |
| 500-reply thread | 40 | 16 | 56 | 20 |
| `POST like` (real file) | 164 | 1.6 | 928 | 2.8 |
| `POST text reply` (real file) | 220 | 4.1 | 769 | 7.2 |
| 20 simultaneous Home requests | 762 total | 277 total | | |

Queries per Home request: 222 → 12.

At **closed-alpha size** (60 users, 1.9k posts, 1.8 MB file): Home 5.7 ms, like 1.3 ms, text reply 2.8 ms,
20 simultaneous Home requests 120 ms in total.

Also measured (66 MB database): `GET /api/users/suggested` 54 ms (needs one pass over all posts; it is an
onboarding call, not a hot path), `GET /api/users/:id` 1.3 ms. A missing index on `follows(followee_id)` made
follower counts 90x slower (13 ms vs 0.15 ms each); it is now in the schema.

## Limits to know about
- **SQLite via sql.js keeps the whole database in memory and rewrites the whole file when it saves.**
  Fine for the closed alpha (a few MB). Around 50-100 MB each save stalls the server for hundreds of
  milliseconds (the 66 MB run shows a ~1 s stall). Move to PostgreSQL (already the plan) before the
  college beta.
- Coalesced saves mean a hard crash (power loss, `kill -9`) can lose up to `DB_SAVE_DELAY_MS` (250 ms,
  longer for a big database) of changes. A normal stop (Ctrl+C / SIGTERM) saves first.
- The Home query sorts all posts from followed people. With 300 followees and 30k posts that is
  ~7 ms. At very large scale this wants a precomputed feed table, not a better index.
- One Node process, and `sql.js` is synchronous: requests are handled one at a time. That is fine for
  15-500 users; scale-out comes with Postgres.
