// Motion rooms: a society or class runs one debate on one motion ("This house believes ...") for a few days. Members post opinions
// into the room; the AI marks each as FOR or AGAINST the motion (posts.room_stance), so the room page can show where the room stands.
// Everything posted in a room is still an ordinary public post. The room is a way to gather and to count, not a hiding place.

const crypto = require('crypto');
const { HttpError } = require('./http');
const { toUser } = require('./queries');

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O or 1/I: codes get read out loud and typed on small phones
const MAX_OWNED = 5;
const MAX_MEMBERS = 500;

function newCode(db) {
  for (let i = 0; i < 20; i++) {
    let code = '';
    for (let j = 0; j < 6; j++) code += ALPHABET[crypto.randomInt(ALPHABET.length)];
    if (!db.get('SELECT 1 AS x FROM rooms WHERE code = ?', [code])) return code;
  }
  throw new HttpError(503, 'Could not make a room code. Try again');
}

/** UPCOMING (not started), OPEN, or CLOSED (ended, or closed by the owner). Posting needs OPEN. */
function roomStatus(room, now) {
  if (room.closed_at) return 'CLOSED';
  if (room.starts_at && now < Date.parse(room.starts_at)) return 'UPCOMING';
  if (room.ends_at && now > Date.parse(room.ends_at)) return 'CLOSED';
  return 'OPEN';
}

const getRoom = (db, id) => db.get('SELECT * FROM rooms WHERE id = ?', [String(id)]);
const memberRow = (db, roomId, userId) => db.get('SELECT * FROM room_members WHERE room_id = ? AND user_id = ?', [roomId, userId]);

/** The room, for a member only (404 otherwise: a room's existence is not shown to people who are not in it). */
function requireMember(db, roomId, userId) {
  const room = getRoom(db, roomId);
  const member = room && memberRow(db, room.id, userId);
  if (!room || !member) throw new HttpError(404, 'Room not found');
  return { room, member };
}

/** Throws unless [userId] may post into the room right now. Returns the room. */
function requireOpenForPosting(db, roomId, userId, now) {
  const { room } = requireMember(db, roomId, userId);
  const status = roomStatus(room, now);
  if (status === 'UPCOMING') throw new HttpError(409, 'This room has not started yet', { field: 'roomId' });
  if (status === 'CLOSED') throw new HttpError(409, 'This room is closed', { field: 'roomId' });
  return room;
}

/** What the room page shows: who stands where. Counts only READY opinions that the AI has placed; the rest are "undecided". */
function standing(db, roomId) {
  const rows = db.all(
    `SELECT room_stance AS side, COUNT(*) AS n FROM posts
     WHERE room_id = ? AND parent_id IS NULL AND status = 'READY' GROUP BY room_stance`,
    [roomId]
  );
  const by = Object.fromEntries(rows.map((r) => [r.side || 'NONE', r.n]));
  return {
    posts: rows.reduce((a, r) => a + r.n, 0),
    forCount: by.FOR || 0,
    againstCount: by.AGAINST || 0,
    undecided: (by.UNRESOLVED || 0) + (by.NONE || 0)
  };
}

function roomJson(db, room, meId, now) {
  const member = memberRow(db, room.id, meId);
  const owner = db.get('SELECT * FROM users WHERE id = ?', [room.owner_id]);
  return {
    id: room.id,
    code: member ? room.code : undefined, // the code is for members to hand on
    name: room.name,
    motion: room.motion,
    description: room.description || null,
    startsAt: room.starts_at || null,
    endsAt: room.ends_at || null,
    status: roomStatus(room, now),
    role: member ? member.role : null,
    owner: owner ? toUser(owner) : null,
    memberCount: db.get('SELECT COUNT(*) AS n FROM room_members WHERE room_id = ?', [room.id]).n,
    ...standing(db, room.id),
    createdAt: room.created_at
  };
}

module.exports = {
  MAX_OWNED, MAX_MEMBERS, newCode, roomStatus, getRoom, memberRow, requireMember, requireOpenForPosting, standing, roomJson
};
