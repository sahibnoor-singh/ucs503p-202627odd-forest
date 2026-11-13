// Upload handling for POST /api/posts/compose: photos, one music file, one video. Files go to the *compose* folder, which
// is NOT served to the public (unlike uploads/): they are only inputs for the renderer and are deleted afterwards.

const path = require('path');
const multer = require('multer');
const { v4: uuid } = require('uuid');
const { HttpError } = require('../http');
const { MAX_PHOTOS } = require('./recipe');

const KINDS = {
  photos: { ext: ['.jpg', '.jpeg', '.png', '.webp'], mime: (m) => m.startsWith('image/'), maxBytes: 10 * 1024 * 1024, label: 'Photos' },
  music: { ext: ['.mp3', '.m4a', '.aac', '.wav', '.ogg'], mime: (m) => m.startsWith('audio/') || m === 'application/octet-stream', maxBytes: 15 * 1024 * 1024, label: 'Music' },
  video: { ext: ['.mp4', '.mov', '.webm', '.mkv'], mime: (m) => m.startsWith('video/') || m === 'application/octet-stream', maxBytes: 50 * 1024 * 1024, label: 'Videos' }
};

function createComposeUpload(composeDir) {
  const upload = multer({
    storage: multer.diskStorage({
      destination: (req, file, cb) => cb(null, composeDir),
      // our own name, never the client's: only the checked extension survives
      filename: (req, file, cb) => cb(null, `${Date.now()}-${uuid().slice(0, 8)}-${file.fieldname}${path.extname(file.originalname).toLowerCase()}`)
    }),
    limits: { fileSize: 50 * 1024 * 1024, files: MAX_PHOTOS + 2, fields: 12, fieldSize: 64 * 1024 },
    fileFilter: (req, file, cb) => {
      const kind = KINDS[file.fieldname];
      const ext = path.extname(file.originalname).toLowerCase();
      if (!kind || !kind.ext.includes(ext) || !kind.mime(String(file.mimetype || '').toLowerCase())) {
        return cb(new HttpError(400, `${(kind || { label: 'That file' }).label} must be one of: ${kind ? kind.ext.join(' ') : 'photos, music, video'}`, { field: file.fieldname }));
      }
      cb(null, true);
    }
  }).fields([{ name: 'photos', maxCount: MAX_PHOTOS }, { name: 'music', maxCount: 1 }, { name: 'video', maxCount: 1 }]);

  /** Express middleware; also rejects files bigger than their own kind allows (multer only has one global limit). */
  return (req, res, next) => upload(req, res, (err) => {
    if (err) return next(err);
    for (const [field, list] of Object.entries(req.files || {})) {
      for (const f of list) {
        if (f.size > KINDS[field].maxBytes) {
          removeFiles(req.files);
          return next(new HttpError(413, `${KINDS[field].label} can be at most ${KINDS[field].maxBytes / 1024 / 1024} MB each`, { field }));
        }
      }
    }
    next();
  });
}

function removeFiles(files) {
  const fs = require('fs');
  for (const list of Object.values(files || {})) for (const f of list) fs.rmSync(f.path, { force: true });
}

module.exports = { createComposeUpload, removeFiles };
