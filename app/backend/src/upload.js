const path = require('path');
const multer = require('multer');
const { v4: uuid } = require('uuid');
const { HttpError } = require('./http');

// The file's real extension decides how the server labels it when it is served, so only these are accepted.
const ALLOWED_EXT = new Set(['.mp4', '.mov', '.webm', '.mkv', '.avi', '.m4a', '.mp3', '.wav', '.ogg', '.aac']);

function mimeOk(mime) {
  const m = String(mime || '').toLowerCase();
  // Some clients send octet-stream for videos; the extension check still has to pass.
  return m.startsWith('video/') || m.startsWith('audio/') || m === 'application/octet-stream';
}

/** multer instance that stores media in [uploadsDir]. 50 MB cap, video/audio only. */
function createUpload(uploadsDir) {
  return multer({
    storage: multer.diskStorage({
      destination: (req, file, cb) => cb(null, uploadsDir),
      filename: (req, file, cb) => {
        const ext = path.extname(file.originalname).toLowerCase(); // already checked by fileFilter
        const base = path.basename(file.originalname, path.extname(file.originalname))
          .replace(/[^a-zA-Z0-9-]/g, '_').slice(0, 40) || 'video';
        cb(null, `${Date.now()}-${uuid().slice(0, 8)}-${base}${ext}`);
      }
    }),
    limits: { fileSize: 50 * 1024 * 1024 },
    fileFilter: (req, file, cb) => {
      // BOTH must pass. The MIME type is whatever the client claims, so on its own it proves nothing:
      // an "x.html" labelled video/mp4 would otherwise be stored and later served as a web page.
      const ext = path.extname(file.originalname).toLowerCase();
      if (!ALLOWED_EXT.has(ext) || !mimeOk(file.mimetype)) {
        return cb(new HttpError(400, 'Only video and audio files are allowed.'));
      }
      cb(null, true);
    }
  });
}

module.exports = { createUpload, ALLOWED_EXT };
