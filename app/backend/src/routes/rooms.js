// Motion rooms. See src/rooms.js for what they are. Everything here needs a signed-in person; a room is only visible to its members.
//   POST   /api/rooms                 { name, motion, description?, startsAt?, endsAt? }  -> the room (you are the owner)
//   GET    /api/rooms/mine            rooms you are in, soonest first
//   POST   /api/rooms/join            { code }                                             -> the room
//   GET    /api/rooms/:id             the room, where it stands, and the first members
//   GET    /api/rooms/:id/posts       opinions posted into it
//   POST   /api/rooms/:id/leave
//   POST   /api/rooms/:id/close       owner only; a closed room can still be read

const express = require('express');
const { requireUser } = require('../middleware/user');
const { wrap, HttpError, parseLimit } = require('../http');
const { uuid, nowIso, toUser, toItems } = require('../queries');
const rooms = require('../rooms');
const invites = require('../invites');

const clean = (v) => String(v === undefined || v === null ? '' : v).replace(/\s+/g, ' ').trim();
const chars = (s) => [...s].length;

function time(raw, field) {
  if (raw === undefined || raw === null || raw === '') return null;
  const t = Date.parse(String(raw));
  if (Number.isNaN(t)) throw new HttpError(400, 'That date and time does not look right', { field });
  return new Date(t).toISOString();
}

module.exports = function roomRoutes({ db, clock = Date.now, events = { track() {} } }) {
  const router = express.Router();
  router.use(requireUser);

  router.post('/', wrap(async (req, res) => {
    const b = req.body || {};
    const name = clean(b.name);
    const motion = clean(b.motion);
    const description = clean(b.description) || null;
    if (!name || chars(name) > 60) throw new HttpError(400, 'Give the room a name (up to 60 characters)', { field: 'name' });
    if (chars(motion) < 10 || chars(motion) > 200) throw new HttpError(400, 'Write the motion as one statement (10 to 200 characters)', { field: 'motion' });
    if (description && chars(description) > 500) throw new HttpError(400, 'Keep the description under 500 characters', { field: 'description' });
    const startsAt = time(b.startsAt, 'startsAt');
    const endsAt = time(b.endsAt, 'endsAt');
    if (endsAt && Date.parse(endsAt) <= clock()) throw new HttpError(400, 'The end must be in the future', { field: 'endsAt' });
    if (startsAt && endsAt && Date.parse(endsAt) <= Date.parse(startsAt)) throw new HttpError(400, 'The end must come after the start', { field: 'endsAt' });
    const owned = db.get("SELECT COUNT(*) AS n FROM rooms WHERE owner_id = ? AND closed_at IS NULL", [req.user.id]).n;
    if (owned >= rooms.MAX_OWNED) throw new HttpError(429, `You can run ${rooms.MAX_OWNED} open rooms at once. Close one first`);

    const id = uuid();
    const at = nowIso();
    db.tx(() => {
      db.run(
        `INSERT INTO rooms (id, code, name, motion, description, owner_id, starts_at, ends_at, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [id, rooms.newCode(db), name, motion, description, req.user.id, startsAt, endsAt, at]
      );
      db.run("INSERT INTO room_members (room_id, user_id, role, joined_at) VALUES (?, ?, 'OWNER', ?)", [id, req.user.id, at]);
    });
    events.track('room_created', req.user.id);
    res.status(201).json({ room: rooms.roomJson(db, rooms.getRoom(db, id), req.user.id, clock()) });
  }));

  router.get('/mine', wrap(async (req, res) => {
    const list = db.all(
      `SELECT r.* FROM rooms r JOIN room_members m ON m.room_id = r.id WHERE m.user_id = ?
       ORDER BY (r.closed_at IS NOT NULL), r.created_at DESC LIMIT 100`,
      [req.user.id]
    );
    res.json({ rooms: list.map((r) => rooms.roomJson(db, r, req.user.id, clock())) });
  }));

  router.post('/join', wrap(async (req, res) => {
    const code = invites.normalizeCode(req.body && req.body.code);
    const room = code.length === 6 ? db.get('SELECT * FROM rooms WHERE code = ?', [code]) : null;
    if (!room) throw new HttpError(404, 'No room has that code. Check it and try again', { field: 'code' });
    if (rooms.roomStatus(room, clock()) === 'CLOSED') throw new HttpError(409, 'That room is closed');
    if (!rooms.memberRow(db, room.id, req.user.id)) {
      const members = db.get('SELECT COUNT(*) AS n FROM room_members WHERE room_id = ?', [room.id]).n;
      if (members >= rooms.MAX_MEMBERS) throw new HttpError(409, 'That room is full');
      db.run("INSERT INTO room_members (room_id, user_id, role, joined_at) VALUES (?, ?, 'MEMBER', ?)", [room.id, req.user.id, nowIso()]);
      events.track('room_joined', req.user.id);
    }
    res.json({ room: rooms.roomJson(db, room, req.user.id, clock()) });
  }));

  router.get('/:id', wrap(async (req, res) => {
    const { room } = rooms.requireMember(db, req.params.id, req.user.id);
    const members = db.all(
      `SELECT u.* FROM room_members m JOIN users u ON u.id = m.user_id
       WHERE m.room_id = ? AND u.deleted_at IS NULL
         AND u.id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?)
         AND u.id NOT IN (SELECT blocker_id FROM blocks WHERE blocked_id = ?)
       ORDER BY (m.role = 'OWNER') DESC, m.joined_at LIMIT 30`,
      [room.id, req.user.id, req.user.id]
    );
    res.json({ room: rooms.roomJson(db, room, req.user.id, clock()), members: members.map(toUser) });
  }));

  router.get('/:id/posts', wrap(async (req, res) => {
    const { room } = rooms.requireMember(db, req.params.id, req.user.id);
    const limit = parseLimit(req.query.limit, 20, 50);
    const rows = db.all(
      `SELECT p.* FROM posts p JOIN users u ON u.id = p.user_id
       WHERE p.room_id = ? AND p.parent_id IS NULL AND p.status = 'READY' AND u.deleted_at IS NULL AND u.suspended_at IS NULL
         AND p.user_id NOT IN (SELECT blocked_id FROM blocks WHERE blocker_id = ?)
         AND p.user_id NOT IN (SELECT blocker_id FROM blocks WHERE blocked_id = ?)
       ORDER BY p.created_at DESC, p.id DESC LIMIT ?`,
      [room.id, req.user.id, req.user.id, limit]
    );
    res.json({ items: toItems(db, rows, req.user.id) });
  }));

  router.post('/:id/leave', wrap(async (req, res) => {
    const { room, member } = rooms.requireMember(db, req.params.id, req.user.id);
    if (member.role === 'OWNER') throw new HttpError(409, 'The owner cannot leave. Close the room instead');
    db.run('DELETE FROM room_members WHERE room_id = ? AND user_id = ?', [room.id, req.user.id]);
    res.json({ left: true });
  }));

  router.post('/:id/close', wrap(async (req, res) => {
    const { room, member } = rooms.requireMember(db, req.params.id, req.user.id);
    if (member.role !== 'OWNER') throw new HttpError(403, 'Only the owner can close the room');
    db.run('UPDATE rooms SET closed_at = COALESCE(closed_at, ?) WHERE id = ?', [nowIso(), room.id]);
    res.json({ room: rooms.roomJson(db, rooms.getRoom(db, room.id), req.user.id, clock()) });
  }));

  return router;
};
