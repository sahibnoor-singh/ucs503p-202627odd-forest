// Who may send things to whom. Direct messages and sent videos share one rule (CLAUDE.md: no unsolicited contact from strangers):
// a person can only reach people they follow who follow them back. Never bots, never yourself, never anyone blocked either way,
// never an account that is deleted or suspended.

const follows = (db, a, b) => !!db.get('SELECT 1 AS x FROM follows WHERE follower_id = ? AND followee_id = ?', [a, b]);

const blockedEitherWay = (db, a, b) => !!db.get(
  'SELECT 1 AS x FROM blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)', [a, b, b, a]
);

/** Why [me] cannot send to [target] (a users row, or undefined), or null when they can. */
function whyNotFriend(db, me, target) {
  if (!target || target.deleted_at || target.suspended_at) return 'UNAVAILABLE';
  if (target.id === me) return 'SELF';
  if (target.is_bot) return 'BOT';
  if (blockedEitherWay(db, me, target.id)) return 'UNAVAILABLE';
  if (!(follows(db, me, target.id) && follows(db, target.id, me))) return 'NOT_FRIENDS';
  return null;
}

module.exports = { follows, blockedEitherWay, whyNotFriend };
