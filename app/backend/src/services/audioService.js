// Loaded lazily so tests and the seed script never need the ffmpeg binary.
let ffmpeg = null;
function getFfmpeg() {
  if (!ffmpeg) {
    ffmpeg = require('fluent-ffmpeg');
    // Static binary: no system-level ffmpeg install needed
    ffmpeg.setFfmpegPath(require('ffmpeg-static'));
  }
  return ffmpeg;
}

/**
 * Extracts audio from a video file and saves it as an MP3.
 * @param {string} videoPath - Absolute path to the input video.
 * @param {string} audioPath - Absolute path to save the output audio.
 * @returns {Promise<string>} - Resolves with the audio path when done.
 */
function extractAudio(videoPath, audioPath) {
  return new Promise((resolve, reject) => {
    console.log(`Starting audio extraction from ${videoPath} to ${audioPath}`);
    getFfmpeg()(videoPath)
      .outputOptions([
        '-vn',             // No video
        '-acodec libmp3lame', // MP3 codec
        '-ar 16000',       // 16kHz sample rate (recommended for Whisper)
        '-ac 1'            // Mono audio
      ])
      .save(audioPath)
      .on('end', () => {
        console.log('Audio extraction finished successfully.');
        resolve(audioPath);
      })
      .on('error', (err) => {
        console.error('Error during audio extraction:', err);
        reject(err);
      });
  });
}

module.exports = {
  extractAudio
};
