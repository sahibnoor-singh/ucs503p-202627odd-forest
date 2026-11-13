// Public contact + complaints. The grievance officer's details come from config (GRIEVANCE_OFFICER_NAME / _EMAIL);
// until they are set this says so plainly (null). See docs/LAST_STAGE_POLISH.md: choosing the officer is a launch gate.

const express = require('express');
const { wrap, HttpError } = require('../http');
const { uuid, nowIso, getPost } = require('../queries');

module.exports = function legalRoutes({ db, grievanceOfficer }) {
  const router = express.Router();

  router.get('/legal/contact', (req, res) => {
    res.json({
      grievanceOfficer: grievanceOfficer && grievanceOfficer.name
        ? { name: grievanceOfficer.name, email: grievanceOfficer.email || null }
        : null
    });
  });

  // POST /api/complaints {message, contact?, postId?}: a problem report or an appeal. Works signed out too.
  router.post('/complaints', wrap(async (req, res) => {
    const b = req.body || {};
    const message = String(b.message || '').trim();
    if (message.length < 10) throw new HttpError(400, 'Please describe the problem (at least 10 characters)', { field: 'message' });
    if (message.length > 2000) throw new HttpError(400, 'Please keep it under 2000 characters', { field: 'message' });
    const contact = b.contact ? String(b.contact).trim().slice(0, 200) : null;
    let postId = null;
    if (b.postId) {
      if (!getPost(db, String(b.postId))) throw new HttpError(404, 'That post was not found');
      postId = String(b.postId);
    }
    const id = uuid();
    db.run('INSERT INTO complaints (id, user_id, contact, post_id, message, created_at) VALUES (?, ?, ?, ?, ?, ?)', [
      id, req.user ? req.user.id : null, contact, postId, message, nowIso()
    ]);
    res.status(201).json({ received: true, id });
  }));

  return router;
};
