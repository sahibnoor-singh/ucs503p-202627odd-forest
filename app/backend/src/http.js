class HttpError extends Error {
  /** @param extra  more JSON fields for the response, e.g. { field: 'username' } or { retryAfterSec: 20 } */
  constructor(status, message, extra = {}) {
    super(message);
    this.status = status;
    this.extra = extra;
  }
}

const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

function parseLimit(value, def, max) {
  const n = parseInt(value, 10);
  return Number.isFinite(n) && n > 0 ? Math.min(n, max) : def;
}

module.exports = { HttpError, wrap, parseLimit };
