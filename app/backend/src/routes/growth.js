// Small endpoints that help the app grow and be measured:
//   POST /api/events   { events: [{ name, props? }] }   what only the app can see (opening it, tapping the daily question)
//   GET  /api/me/invite                                  the person's invite code and link

const express = require('express');
const { requireUser } = require('../middleware/user');
const { wrap, HttpError } = require('../http');
const invites = require('../invites');
const { baseUrl } = require('../publicUrl');

module.exports = function growthRoutes({ db, events, publicBaseUrl = null }) {
  const router = express.Router();

  router.post('/events', requireUser, wrap(async (req, res) => {
    const list = req.body && req.body.events;
    if (!Array.isArray(list)) throw new HttpError(400, 'events must be a list', { field: 'events' });
    res.json({ recorded: events.trackFromClient(req.user.id, list) });
  }));

  router.get('/me/invite', requireUser, wrap(async (req, res) => {
    const code = invites.inviteCodeFor(db, req.user.id);
    res.json({ code, link: `${baseUrl(req, publicBaseUrl)}/invite/${code}`, invitedCount: invites.invitedCount(db, req.user.id) });
  }));

  return router;
};
