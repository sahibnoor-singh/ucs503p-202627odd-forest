// One still picture of a video, for the Discover grid and as the poster shown before a video plays.
// Loaded lazily (like audioService) so tests and the seed script never need the ffmpeg binary.

const fs = require('fs');
let ffmpeg = null;
function getFfmpeg() {
  if (!ffmpeg) {
    ffmpeg = require('fluent-ffmpeg');
    ffmpeg.setFfmpegPath(require('ffmpeg-static'));
  }
  return ffmpeg;
}

/** The frame at [atSec], scaled so it is at most 720 px high (even sizes), written as a JPEG. Rejects if no frame came out. */
function frameAt(videoPath, outPath, atSec) {
  return new Promise((resolve, reject) => {
    getFfmpeg()(videoPath)
      .seekInput(atSec)
      .frames(1)
      .outputOptions(['-vf', "scale=-2:'min(720,trunc(ih/2)*2)'", '-q:v', '4'])
      .on('end', () => (fs.existsSync(outPath) ? resolve(outPath) : reject(new Error('no frame'))))
      .on('error', reject)
      .save(outPath);
  });
}

/**
 * Writes a JPEG of [videoPath] to [outPath]. A second in is used, so a fade-in from black is skipped; a clip shorter than
 * that falls back to its first frame. Resolves true when the picture exists, false when it could not be made (a missing
 * thumbnail is never a reason to fail a post).
 */
async function makeThumbnail(videoPath, outPath) {
  for (const at of [1, 0]) {
    try {
      await frameAt(videoPath, outPath, at);
      return true;
    } catch {
      fs.rmSync(outPath, { force: true });
    }
  }
  return false;
}

module.exports = { makeThumbnail };
