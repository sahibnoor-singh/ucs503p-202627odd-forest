// Product events: small facts about what people do, kept so the founders can tell whether anything works (docs/PRODUCT_REPORT.html,
// "measure before building more"). No video, text, search words or contact details are ever stored here; props are a few
// short flags and numbers. Each row has the person's id so a funnel can be followed, and it is cleared from the row when the person
// deletes their account.
//
// Two sources: the server records the important ones itself (a sign-up, finishing onboarding, a post), and the app sends the ones only it
// can see (opening the app, tapping the daily question) through POST /api/events.

const { dayKey } = require('./prompts');

/** Events the app may send. Anything else is dropped, so a client cannot fill the table with arbitrary names. */
const CLIENT_EVENTS = new Set([
  'app_open', 'prompt_opened', 'reply_wanted_opened', 'invite_copied', 'link_copied', 'room_opened', 'onboarding_topics_shown', 'both_sides_heard'
]);

/** Events only the server writes. */
const SERVER_EVENTS = new Set([
  'signup', 'onboarding_done', 'post_created', 'reply_created', 'prompt_answered', 'room_created', 'room_joined', 'invite_accepted'
]);

const MAX_PROPS_BYTES = 300;

/** Props must be a flat object of short strings, numbers and booleans, and small. */
function cleanProps(props) {
  if (!props || typeof props !== 'object' || Array.isArray(props)) return null;
  const out = {};
  for (const [k, v] of Object.entries(props).slice(0, 8)) {
    if (!/^[a-z_]{1,24}$/.test(k)) continue;
    if (typeof v === 'string') out[k] = v.slice(0, 40);
    else if (typeof v === 'number' && Number.isFinite(v)) out[k] = v;
    else if (typeof v === 'boolean') out[k] = v;
  }
  const json = JSON.stringify(out);
  return json === '{}' || json.length > MAX_PROPS_BYTES ? null : json;
}

function createEvents(db, clock = Date.now) {
  /** Records one event from the server's own code. Never throws: measuring must not break the thing being measured. */
  function track(name, userId, props) {
    try {
      if (!SERVER_EVENTS.has(name)) return;
      const at = clock();
      db.run('INSERT INTO events (user_id, name, props, day, at) VALUES (?, ?, ?, ?, ?)', [
        userId || null, name, cleanProps(props), dayKey(at), new Date(at).toISOString()
      ]);
    } catch (err) {
      console.warn('[events] could not record', name, err.message);
    }
  }

  /** Records what the app sent. Returns how many were kept. */
  function trackFromClient(userId, list) {
    let kept = 0;
    const at = clock();
    for (const e of Array.isArray(list) ? list.slice(0, 50) : []) {
      if (!e || typeof e.name !== 'string' || !CLIENT_EVENTS.has(e.name)) continue;
      db.run('INSERT INTO events (user_id, name, props, day, at) VALUES (?, ?, ?, ?, ?)', [
        userId, e.name, cleanProps(e.props), dayKey(at), new Date(at).toISOString()
      ]);
      kept++;
    }
    return kept;
  }

  return { track, trackFromClient };
}

module.exports = { createEvents, CLIENT_EVENTS, SERVER_EVENTS, cleanProps };
