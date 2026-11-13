// The composer = what the server uses to inspect uploaded media and render recipes. Tests pass a fake with the same shape.

const path = require('path');
const render = require('./render');

const FONTS_DIR = path.join(__dirname, '..', '..', 'assets', 'fonts');

/** ffmpeg binary: FFMPEG_PATH if set, else the bundled ffmpeg-static. Loaded lazily so tests never need it. */
function ffmpegBinary() {
  return process.env.FFMPEG_PATH || require('ffmpeg-static');
}

function createComposer({ ffmpegPath = null, fontsDir = FONTS_DIR } = {}) {
  const bin = () => ffmpegPath || ffmpegBinary();
  return {
    probe: (file) => render.probe(bin(), file),
    render: (opts) => render.render({ ffmpegPath: bin(), fontsDir, ...opts })
  };
}

module.exports = { createComposer, FONTS_DIR };
