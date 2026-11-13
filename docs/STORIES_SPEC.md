# Stories = reposts (spec, proposed)

**Founders' decision:** a story is a *repost of a FOREST video you like*. It appears in your story for 24 hours and the
people who follow you can watch it. No photo/image stories and no separate "record a story" flow. Everything below that is
marked *(proposed)* is my default so work can start; change it here before anyone builds it.

## Rules
1. **What can be reposted:** any finished (`READY`) **video** post: an opinion or a video reply. Not text replies. You may repost your own. *(proposed)*
2. **A repost is a pointer, not a copy.** No file is duplicated, so nothing is re-hosted and storage doesn't grow. If the original is
   later removed, fails, or its author blocks you, it silently disappears from stories.
3. **Lasts 24 hours** from the moment of reposting. Expiry is checked when stories are read, so no timer job is needed.
4. **One live repost per person per video.** Reposting again while it is live does nothing (it does not extend the 24 hours).
   After it expires you may repost it again. You can **undo** a repost before then.
5. **Who sees it:** people who follow you. The stories row on Home shows the people *you follow* who have a live story, newest first,
   with your own "Your story" tile first. Someone blocked either way never sees, or appears in, the other's stories.
6. **Seen state is remembered on the server** per viewer, so the grey ring survives restarts and other devices.
7. **No caption in the first version** *(proposed)*.
8. **Limits** *(proposed)*: at most 20 live reposts per person, 30 reposts per hour.
9. **Bots** keep their BOT label on their stories. Content sourcing rules in CLAUDE.md are unchanged (a repost can only point at a FOREST post).
10. **Credibility score (later):** every repost is recorded (who, what, when), so the score can use it. *(proposed: counts like an indirect reply,
    half weight, once per person per video.)* Nothing is computed yet, and rewards never use raw counts alone (CLAUDE.md hard rule).

## Data
```
reposts      (id, user_id, post_id, created_at, expires_at)      -- live = expires_at > now
story_views  (viewer_id, repost_id, seen_at)  PK (viewer_id, repost_id)
```

## API (all signed in)
| | |
|---|---|
| `POST /api/posts/:id/repost` | repost a video. 404 if not a finished video, 403 if blocked either way, 429 over the limits. Idempotent while live. → `{ repost }` |
| `DELETE /api/posts/:id/repost` | undo my live repost |
| `GET /api/stories` | the stories row: `{ mine: {count, hasUnseen}, people: [{ user, count, hasUnseen, latestAt }] }` |
| `GET /api/users/:id/stories` | that person's live reposts, oldest first: `[{ repostId, repostedAt, expiresAt, seen, item }]` where `item` is the usual Item for the original video |
| `POST /api/stories/:repostId/seen` | mark seen |
| existing feed items | gain `post.repostedByMe` and `post.repostCount` so the button can show its state |

## App
- The **Repost** button is already in the prototype (Lab mode). It becomes a real button on the action row.
- **Story viewer:** full-screen video, "Reposted by @x" with the original author, tap to open the debate, swipe to the next person,
  auto-advance when a video ends, a progress bar per story.
- The stories row on Home reads `GET /api/stories` instead of showing fixed placeholders; "Your story" opens your own live reposts.
- *Needs a design pass in the prototype first (viewer screen, "Reposted" confirmation, undo).*

## Not in this spec
Replies to a story, story reactions, view counts shown to the poster, text/photo stories, highlights.
