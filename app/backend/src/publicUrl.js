// The address people outside the app use to reach this server (links to a debate, an invite). PUBLIC_BASE_URL when it is set (the real
// website address in production); otherwise whatever address the request itself came in on, which is right for testing on a local network.

/** `https://forestapp.in`, with no trailing slash. */
function baseUrl(req, configured) {
  if (configured) return String(configured).replace(/\/+$/, '');
  return `${req.protocol}://${req.get('host')}`;
}

module.exports = { baseUrl };
