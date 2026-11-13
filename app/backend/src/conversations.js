// One conversation per pair of people. It holds videos that were sent and the emoji reactions to them (no free text).

const { v4: uuid } = require('uuid');
const { nowIso } = require('./queries');

/** The two ids in a fixed order, so a pair always maps to the same row. */
const pair = (a, b) => (a < b ? [a, b] : [b, a]);

function findConversation(db, a, b) {
  const [lo, hi] = pair(a, b);
  return db.get('SELECT * FROM conversations WHERE user_lo = ? AND user_hi = ?', [lo, hi]);
}

function getOrCreateConversation(db, a, b) {
  const found = findConversation(db, a, b);
  if (found) return found;
  const [lo, hi] = pair(a, b);
  const id = uuid();
  const at = nowIso();
  db.run('INSERT INTO conversations (id, user_lo, user_hi, created_at, last_message_at) VALUES (?, ?, ?, ?, ?)', [id, lo, hi, at, at]);
  return { id, user_lo: lo, user_hi: hi, created_at: at, last_message_at: at };
}

/** Adds a message and moves the conversation to the top. The sender has, by sending, read everything so far. */
function addMessage(db, { conversationId, senderId, kind, body = null, postId = null, refId = null }) {
  const id = uuid();
  const at = nowIso();
  db.run(
    'INSERT INTO messages (id, conversation_id, sender_id, kind, body, post_id, ref_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [id, conversationId, senderId, kind, body, postId, refId, at]
  );
  db.run('UPDATE conversations SET last_message_at = ? WHERE id = ?', [at, conversationId]);
  markRead(db, conversationId, senderId, at);
  return { id, created_at: at };
}

function markRead(db, conversationId, userId, at = nowIso()) {
  db.run('INSERT OR REPLACE INTO conversation_reads (conversation_id, user_id, read_at) VALUES (?, ?, ?)', [conversationId, userId, at]);
}

module.exports = { pair, findConversation, getOrCreateConversation, addMessage, markRead };
