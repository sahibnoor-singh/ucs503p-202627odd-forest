// The Discover page is mostly each person's own ranking (recommendation.js), plus two bounded extras:
//
//   FRIENDS      A few posts that a friend's taste would pick, when that friend has sent you videos consistently and you have
//                reacted well to them. At most FRIEND_CAP of a page, less when the friendship is weaker.
//   EXPLORATION  At least EXPLORE_FLOOR of a page that is deliberately outside what you usually watch, so a circle of friends
//                (or your own habits) can never close the feed in. This is the point of the app.
//
// Rules that hold whatever the numbers: a friend's profile is only ever used on the server to choose posts, it is never shown or
// sent; viewing is not agreeing (nothing here looks at stance); every extra post must clear a credibility floor (ranking is tied to
// the credibility score, CLAUDE.md); bots are never friends; a person can switch friend influence off and exploration stays.

const rec = require('./recommendation');

const FRIEND_CAP = 0.25; // most of a page that friends may take
const EXPLORE_FLOOR = 0.10; // least of a page that is exploration
const MAX_FRIENDS = 3; // senders considered at once
const MIN_STRENGTH = 0.15; // weaker friendships are ignored
const MIN_SHARES = 3; // "consistently": at least this many sent videos...
const MIN_DAYS = 2; // ...on at least this many different days
const WINDOW_DAYS = 120;
const HALF_LIFE_DAYS = 60;
const SATURATION = 3; // this much net positive reaction is a full-strength friendship
const MIN_TOPICS_KNOWN = 8; // exploration means "away from your habits": a new person has none yet, so everything is exploration already
const MIN_CREDIBILITY = 40; // extra posts (friends, exploration) must have at least this fact-check score
const IGNORE_AFTER_DAYS = 3; // a video nobody touched for this long counts as ignored
const DAY_MS = 24 * 60 * 60 * 1000;

const REACTION = { liked: 1.0, finished: 0.7, watched: 0.4, opened: 0.1, skipped: -0.2, ignored: -0.3 };
const WATCHED_MS = 3000;
const SKIPPED_MS = 2000;

const marks = (n) => new Array(n).fill('?').join(',');

/**
 * How well each person who sent [me] videos is doing at it. Only mutual followers who are not bots, blocked, deleted or suspended
 * count. Returns [{ senderId, strength 0..1, raw, shares, days }] strongest first (strength 0 = not a friend of the feed).
 * What a share earns is what [me] did with the video afterwards: liked it, finished it, watched some, skipped it, or ignored it.
 */
function friendEdges(db, me, now) {
  const since = new Date(now - WINDOW_DAYS * DAY_MS).toISOString();
  const shares = db.all(
    `SELECT s.sender_id, s.post_id, s.created_at, s.opened_at FROM shares s
     JOIN users u ON u.id = s.sender_id
     WHERE s.recipient_id = ? AND s.created_at >= ?
       AND u.is_bot = 0 AND u.deleted_at IS NULL AND u.suspended_at IS NULL
       AND EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ? AND f.followee_id = s.sender_id)
       AND EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = s.sender_id AND f.followee_id = ?)
       AND s.sender_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?)
       AND s.sender_id NOT IN (SELECT blocker_id FROM blocks WHERE blocked_id = ?)`,
    [me, since, me, me, me, me]
  );
  if (!shares.length) return [];

  const posts = [...new Set(shares.map((s) => s.post_id))];
  const likes = new Map();
  db.all(`SELECT post_id, created_at FROM likes WHERE user_id = ? AND post_id IN (${marks(posts.length)})`, [me, ...posts])
    .forEach((r) => likes.set(r.post_id, r.created_at));
  const views = new Map();
  db.all(`SELECT post_id, watched_ms, completed, created_at FROM post_views WHERE user_id = ? AND post_id IN (${marks(posts.length)})`, [me, ...posts])
    .forEach((r) => views.set(r.post_id, [...(views.get(r.post_id) || []), r]));

  const bySender = new Map();
  for (const s of shares) {
    const after = (iso) => iso >= s.created_at;
    const seen = (views.get(s.post_id) || []).filter((v) => after(v.created_at));
    let value;
    if (likes.has(s.post_id) && after(likes.get(s.post_id))) value = REACTION.liked;
    else if (seen.some((v) => v.completed)) value = REACTION.finished;
    else if (seen.some((v) => v.watched_ms >= WATCHED_MS)) value = REACTION.watched;
    else if (seen.length) value = REACTION.skipped;
    else if (s.opened_at) value = REACTION.opened;
    else if (now - new Date(s.created_at).getTime() > IGNORE_AFTER_DAYS * DAY_MS) value = REACTION.ignored;
    else value = 0; // too early to tell

    const ageDays = Math.max(0, (now - new Date(s.created_at).getTime()) / DAY_MS);
    const entry = bySender.get(s.sender_id) || { senderId: s.sender_id, raw: 0, shares: 0, days: new Set() };
    entry.raw += value * Math.pow(0.5, ageDays / HALF_LIFE_DAYS);
    entry.shares += 1;
    entry.days.add(s.created_at.slice(0, 10));
    bySender.set(s.sender_id, entry);
  }

  return [...bySender.values()].map((e) => {
    const consistent = e.shares >= MIN_SHARES && e.days.size >= MIN_DAYS;
    return {
      senderId: e.senderId,
      raw: e.raw,
      shares: e.shares,
      days: e.days.size,
      strength: consistent ? Math.max(0, Math.min(1, e.raw / SATURATION)) : 0
    };
  }).sort((a, b) => b.strength - a.strength);
}

/** How a page of [limit] posts is split ([knownTopics]: how many topics the person's profile has learned): [{ id, strength }] friends to draw from, and how many friend / exploration posts. */
function planPage({ edges, limit, friendsOn, knownTopics = 0 }) {
  const friends = friendsOn ? edges.filter((e) => e.strength >= MIN_STRENGTH).slice(0, MAX_FRIENDS) : [];
  const pull = Math.min(1, friends.reduce((sum, f) => sum + f.strength, 0));
  const friendSlots = friends.length ? Math.min(Math.floor(limit * FRIEND_CAP), Math.round(limit * FRIEND_CAP * pull) || 1) : 0;
  const exploreSlots = limit >= 5 && knownTopics >= MIN_TOPICS_KNOWN ? Math.max(1, Math.round(limit * EXPLORE_FLOOR)) : 0;
  return { friends, friendSlots, exploreSlots };
}

const okToAdd = (v) => v.credibility >= MIN_CREDIBILITY && v.pipsDetails.features.repetitionPenalty === 0;

/**
 * Builds one page.
 * @param ranked      every candidate not yet served, ranked for [me] (recommendation.rankVideos, with pipsDetails)
 * @param profileOf   userId -> taste profile (only called for the chosen friends)
 * @param myName      the caller's username: their own posts are never "picked for" them
 * @returns { page: [video + source ('own'|'friend'|'explore') + via?], rest: how many candidates were left out }
 */
function composePage({ ranked, limit, plan, profileOf, usernameOf, myName, now }) {
  const taken = new Set();
  const picks = []; // { video, source, via, at } where [at] is the place in the page it prefers

  // friends: D'Hondt over their strengths, each friend contributing the posts THEIR taste ranks highest
  const pool = ranked.filter((v) => v.userName !== myName && okToAdd(v));
  const lists = plan.friends.map((f) => ({
    friend: f,
    picked: 0,
    queue: rec.rankVideos(pool, profileOf(f.senderId), { now }).map((v) => v.id)
  }));
  const byId = new Map(ranked.map((v) => [v.id, v]));
  for (let i = 0; i < plan.friendSlots; i++) {
    const next = lists
      .map((l) => ({ l, score: l.friend.strength / (l.picked + 1) }))
      .filter((x) => x.l.queue.some((id) => !taken.has(id)))
      .sort((a, b) => b.score - a.score)[0];
    if (!next) break;
    const id = next.l.queue.find((x) => !taken.has(x));
    taken.add(id);
    next.l.picked++;
    picks.push({ video: byId.get(id), source: 'friend', via: usernameOf(next.l.friend.senderId), at: 1 + (picks.length * 3) });
  }

  // exploration: things far from what this person usually watches, not repeats
  const far = ranked
    .filter((v) => !taken.has(v.id) && v.userName !== myName && okToAdd(v) && v.pipsDetails.features.topicAffinity <= 0.5)
    .sort((a, b) => a.pipsDetails.features.topicAffinity - b.pipsDetails.features.topicAffinity || b.pipsScore - a.pipsScore);
  let explored = 0;
  for (const v of far) {
    if (explored >= plan.exploreSlots) break;
    taken.add(v.id);
    picks.push({ video: v, source: 'explore', at: 2 + (explored * 4) });
    explored++;
  }

  const ownCount = Math.max(0, limit - picks.length);
  const own = ranked.filter((v) => !taken.has(v.id)).slice(0, ownCount);
  const total = own.length + picks.length;
  const page = new Array(total).fill(null);
  for (const p of picks) {
    let at = Math.min(p.at, total - 1);
    while (page[at] && at < total - 1) at++;
    while (page[at] && at > 0) at--;
    page[at] = { ...p.video, source: p.source, ...(p.via ? { via: p.via } : {}) };
  }
  let o = 0;
  for (let i = 0; i < total; i++) if (!page[i]) page[i] = { ...own[o++], source: 'own' };
  return { page, rest: ranked.length - page.length };
}

module.exports = {
  friendEdges, planPage, composePage,
  FRIEND_CAP, EXPLORE_FLOOR, MIN_TOPICS_KNOWN, MAX_FRIENDS, MIN_STRENGTH, MIN_SHARES, MIN_DAYS, MIN_CREDIBILITY, WINDOW_DAYS, HALF_LIFE_DAYS, REACTION
};
