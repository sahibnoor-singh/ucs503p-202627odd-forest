// The founders' numbers: is anyone coming, do they get past the first minute, do they get answered, do they return. Read only, from the
// tables the app already fills plus the events table. Real people only (no bots, no deleted accounts). Days are calendar days in the
// prompt time zone (India by default), the same ones the daily question uses.

const REAL = 'u.is_bot = 0 AND u.deleted_at IS NULL';

function computeInsights(db, { days = 14, clock = Date.now, offsetMin = 330 } = {}) {
  days = Math.max(1, Math.min(90, Number(days) || 14));
  const off = `'+${offsetMin} minutes'`;
  const dayOf = (col) => `date(${col}, ${off})`;
  const today = new Date(clock() + offsetMin * 60000).toISOString().slice(0, 10);
  const startDay = new Date(Date.parse(`${today}T00:00:00Z`) - (days - 1) * 86400000).toISOString().slice(0, 10);
  const range = [];
  for (let i = 0; i < days; i++) range.push(new Date(Date.parse(`${startDay}T00:00:00Z`) + i * 86400000).toISOString().slice(0, 10));
  const sinceIso = new Date(Date.parse(`${startDay}T00:00:00Z`) - offsetMin * 60000).toISOString();

  const byDay = (rows) => new Map(rows.map((r) => [r.day, r.n]));
  const signups = byDay(db.all(`SELECT ${dayOf('created_at')} AS day, COUNT(*) AS n FROM users u WHERE ${REAL} AND created_at >= ? GROUP BY day`, [sinceIso]));
  const onboarded = byDay(db.all(`SELECT ${dayOf('onboarded_at')} AS day, COUNT(*) AS n FROM users u WHERE ${REAL} AND onboarded_at >= ? GROUP BY day`, [sinceIso]));
  const roots = byDay(db.all(
    `SELECT ${dayOf('p.created_at')} AS day, COUNT(*) AS n FROM posts p JOIN users u ON u.id = p.user_id
     WHERE ${REAL} AND p.parent_id IS NULL AND p.created_at >= ? GROUP BY day`, [sinceIso]));
  const replies = byDay(db.all(
    `SELECT ${dayOf('p.created_at')} AS day, COUNT(*) AS n FROM posts p JOIN users u ON u.id = p.user_id
     WHERE ${REAL} AND p.parent_id IS NOT NULL AND p.created_at >= ? GROUP BY day`, [sinceIso]));
  const prompt = byDay(db.all(
    `SELECT ${dayOf('p.created_at')} AS day, COUNT(*) AS n FROM posts p JOIN users u ON u.id = p.user_id
     WHERE ${REAL} AND p.prompt_day IS NOT NULL AND p.created_at >= ? GROUP BY day`, [sinceIso]));

  // Anyone who did anything on a day: opened the app, posted, liked, watched.
  const activity = (since) => db.all(
    `SELECT day, user_id FROM (
       SELECT ${dayOf('created_at')} AS day, user_id FROM posts WHERE created_at >= ?1
       UNION SELECT ${dayOf('created_at')}, user_id FROM likes WHERE created_at >= ?1
       UNION SELECT ${dayOf('created_at')}, user_id FROM post_views WHERE created_at >= ?1
       UNION SELECT day, user_id FROM events WHERE user_id IS NOT NULL AND at >= ?1
     ) a JOIN users u ON u.id = a.user_id WHERE ${REAL}`.replace(/\?1/g, '?'),
    [since, since, since, since]
  );
  const seen = activity(sinceIso);
  const activeBy = new Map();
  for (const r of seen) activeBy.set(r.day, (activeBy.get(r.day) || new Set()).add(r.user_id));

  const daily = range.map((day) => ({
    day,
    signups: signups.get(day) || 0,
    onboarded: onboarded.get(day) || 0,
    active: activeBy.has(day) ? activeBy.get(day).size : 0,
    opinions: roots.get(day) || 0,
    replies: replies.get(day) || 0,
    promptAnswers: prompt.get(day) || 0
  }));

  // The first minute: of the people who joined in this window, how far did each get.
  const cohort = db.all(`SELECT id, created_at, onboarded_at FROM users u WHERE ${REAL} AND created_at >= ?`, [sinceIso]);
  const has = (table, col = 'user_id') => new Set(db.all(`SELECT DISTINCT ${col} AS id FROM ${table}`).map((r) => r.id));
  const watched = has('post_views');
  const reacted = new Set([...has('likes'), ...has('viewer_opinions')]);
  const posted = has('posts');
  const funnel = [
    { step: 'Signed up', people: cohort.length },
    { step: 'Finished onboarding', people: cohort.filter((u) => u.onboarded_at).length },
    { step: 'Watched a video', people: cohort.filter((u) => watched.has(u.id)).length },
    { step: 'Liked or took a side', people: cohort.filter((u) => reacted.has(u.id)).length },
    { step: 'Posted or replied', people: cohort.filter((u) => posted.has(u.id)).length }
  ];

  // Did the opinions people posted get an answer, and how fast.
  const firsts = db.all(
    `SELECT p.id, p.created_at AS at, MIN(r.created_at) AS first
     FROM posts p JOIN users u ON u.id = p.user_id
     LEFT JOIN posts r ON r.root_id = p.id AND r.id != p.id AND r.user_id != p.user_id AND r.status = 'READY'
     WHERE ${REAL} AND p.parent_id IS NULL AND p.status = 'READY' AND p.created_at >= ?
     GROUP BY p.id`, [sinceIso]);
  const hours = firsts.filter((r) => r.first).map((r) => (Date.parse(r.first) - Date.parse(r.at)) / 3600000).sort((a, b) => a - b);
  const median = hours.length ? hours[Math.floor(hours.length / 2)] : null;
  const answeredIn24h = hours.filter((h) => h <= 24).length;

  // Next-day return: of the people who joined before today, how many were active the calendar day after they joined.
  const earlier = cohort.filter((u) => new Date(Date.parse(u.created_at) + offsetMin * 60000).toISOString().slice(0, 10) < today);
  const activeOn = (id, day) => !!(activeBy.get(day) && activeBy.get(day).has(id));
  const returned = earlier.filter((u) => {
    const joined = new Date(Date.parse(u.created_at) + offsetMin * 60000).toISOString().slice(0, 10);
    const next = new Date(Date.parse(`${joined}T00:00:00Z`) + 86400000).toISOString().slice(0, 10);
    return activeOn(u.id, next);
  }).length;
  const pct = (n, d) => (d ? Math.round((n / d) * 1000) / 10 : null);

  const n = (sql, params = []) => db.get(sql, params).n;
  return {
    generatedAt: new Date(clock()).toISOString(),
    days,
    totals: {
      people: n(`SELECT COUNT(*) AS n FROM users u WHERE ${REAL}`),
      opinions: n('SELECT COUNT(*) AS n FROM posts WHERE parent_id IS NULL'),
      replies: n('SELECT COUNT(*) AS n FROM posts WHERE parent_id IS NOT NULL'),
      openRooms: n('SELECT COUNT(*) AS n FROM rooms WHERE closed_at IS NULL'),
      invitedPeople: n(`SELECT COUNT(*) AS n FROM users u WHERE ${REAL} AND invited_by IS NOT NULL`)
    },
    daily,
    funnel,
    answers: {
      opinions: firsts.length,
      answeredWithin24hPct: pct(answeredIn24h, firsts.length),
      medianHoursToFirstReply: median === null ? null : Math.round(median * 10) / 10
    },
    nextDayReturn: { people: earlier.length, returned, pct: pct(returned, earlier.length) },
    rooms: {
      members: n('SELECT COUNT(*) AS n FROM room_members'),
      posts: n('SELECT COUNT(*) AS n FROM posts WHERE room_id IS NOT NULL')
    }
  };
}

module.exports = { computeInsights };
