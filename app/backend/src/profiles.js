// Each person's taste profile (topics, creators, recent views, counts; see recommendation.js), kept as JSON in user_profiles.
// Shared by Discover (reads it to rank, updates it from watching), likes (a like is a clear signal) and the friend blend.

const rec = require('./recommendation');
const { nowIso } = require('./queries');
const { videoJson } = require('./videoJson');

function createProfiles(db) {
  function getProfile(userId) {
    const row = db.get('SELECT data FROM user_profiles WHERE user_id = ?', [userId]);
    let p = null;
    try { p = row && JSON.parse(row.data); } catch { /* start fresh */ }
    return {
      userId,
      topics: {}, creators: {}, recentViews: [], watchTimeTotal: 0,
      ...(p || {}),
      interactionCounts: { completions: 0, skips: 0, rewatches: 0, saves: 0, shares: 0, likes: 0, ...((p && p.interactionCounts) || {}) }
    };
  }

  function saveProfile(profile) {
    db.run('INSERT OR REPLACE INTO user_profiles (user_id, data, updated_at) VALUES (?, ?, ?)', [
      profile.userId, JSON.stringify(rec.pruneProfile(profile)), nowIso()
    ]);
  }

  /** A new like on a video teaches the person's profile (topics and creator), like any other sign of interest. */
  function learnFromLike(userId, postRow) {
    if (!postRow || postRow.kind !== 'VIDEO' || !postRow.media_filename) return;
    const [video] = videoJson(db, [postRow], userId);
    saveProfile(rec.updateProfileWithInteraction(getProfile(userId), video, { userId, liked: true, noView: true, at: nowIso() }));
  }

  return { getProfile, saveProfile, learnFromLike };
}

module.exports = { createProfiles };
