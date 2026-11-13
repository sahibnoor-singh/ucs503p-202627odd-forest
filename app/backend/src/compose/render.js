// Turns a normalised recipe (recipe.js) into an MP4 with ffmpeg. buildArgs() is pure (easy to test and to read);
// render() runs it. All text goes through an ASS file (ass.js), never into the command, and the command is run
// without a shell, so nothing the user typed can become part of it.

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const { buildAss, W, H } = require('./ass');

const FPS = 25;
const FADE = 0.5; // seconds of cross-fade between photos

const hex = (c) => `0x${c.replace('#', '')}`;
const f = (n) => String(Math.round(n * 1000) / 1000);

/** Filters for crop + colour adjustments (+ blur), in the order they must run. Empty array when neither is set. */
function lookFilters(recipe) {
  const out = [];
  if (recipe.crop) {
    const c = recipe.crop;
    out.push(`crop=w=iw*${f(c.w)}:h=ih*${f(c.h)}:x=iw*${f(c.x)}:y=ih*${f(c.y)}`);
  }
  const a = recipe.adjust;
  if (a) {
    if (a.brightness !== 0 || a.contrast !== 1 || a.saturation !== 1) {
      out.push(`eq=brightness=${f(a.brightness)}:contrast=${f(a.contrast)}:saturation=${f(a.saturation)}`);
    }
    if (a.hue !== 0) out.push(`hue=h=${f(a.hue)}`);
    if (a.blur > 0) out.push(`boxblur=luma_radius=${f(a.blur)}:luma_power=1:chroma_radius=${f(a.blur)}:chroma_power=1`);
  }
  return out;
}

const channel = (c, i) => parseInt(c.slice(1 + i * 2, 3 + i * 2), 16);
const n6 = (x) => String(Math.round(x * 1e6) / 1e6);

/**
 * The 720x1280 background of a text post: a solid colour, or a gradient at an angle (0 = c0 at the top, 90 = c0 at the left).
 * The gradient is a pixel formula (geq) drawn on a small 72x128 picture and scaled up, so it is perfectly still and
 * identical on every run. (ffmpeg's own `gradients` source was tried first: it rotates over time and is random per run.)
 */
function backgroundSource(bg, durationSec) {
  if (bg.type === 'solid') return `color=c=${hex(bg.color)}:s=${W}x${H}:r=${FPS}:d=${f(durationSec)}`;
  const rad = (bg.angle * Math.PI) / 180;
  const dx = n6(Math.sin(rad));
  const dy = n6(Math.cos(rad));
  // 0..1 along the gradient line; the denominator makes 0 and 1 land exactly on the two farthest corners
  const t = `clip(((X-W/2)*${dx}+(Y-H/2)*${dy})/(abs(${dx})*W+abs(${dy})*H)+0.5,0,1)`;
  const mix = (i) => `${channel(bg.from, i)}+(${channel(bg.to, i)}-${channel(bg.from, i)})*${t}`;
  // geq on planar RGB: plane order is G, B, R, so name the channels explicitly
  return `color=c=black:s=72x128:r=${FPS}:d=${f(durationSec)},format=gbrp,` +
    `geq=r='${mix(0)}':g='${mix(1)}':b='${mix(2)}',scale=${W}:${H}:flags=bilinear`;
}

/**
 * @param {object} p
 * @param {object} p.recipe   normalised recipe
 * @param {{video?:string, photos?:string[], music?:string}} p.inputs  absolute paths (photos already in show order)
 * @param {string} p.out      absolute path of the MP4 to write
 * @param {boolean} p.hasAss  an overlay.ass exists in the working directory
 * @param {string} [p.voicePath]  also write the original speech (trimmed, no music) here as 16 kHz mono mp3, for the AI transcript
 * @returns {string[]} arguments for ffmpeg (run with the working directory set to the one holding overlay.ass and fonts/)
 */
function buildArgs({ recipe, inputs, out, hasAss, voicePath = null }) {
  const D = recipe.durationSec;
  const args = ['-y', '-hide_banner', '-loglevel', 'error'];
  const graph = [];
  let next = 0; // index of the next input
  let videoLabel;

  // ---- picture ----
  const tail = [...lookFilters(recipe)];
  const finish = (inLabel) => {
    const chain = [...tail];
    if (hasAss) chain.push('ass=filename=overlay.ass:fontsdir=fonts');
    chain.push('format=yuv420p');
    graph.push(`[${inLabel}]${chain.join(',')}[v]`);
    videoLabel = '[v]';
  };

  if (recipe.mode === 'VIDEO') {
    const { startSec, endSec } = recipe.trim;
    args.push('-ss', f(startSec), '-t', f(endSec - startSec), '-i', inputs.video);
    next = 1;
    // an even height (and width, from -2): the video encoder refuses odd sizes, which a crop or an odd source can make
    tail.push(`scale=-2:'min(${H},trunc(ih/2)*2)'`);
    finish('0:v');
  } else if (recipe.mode === 'TEXT') {
    args.push('-f', 'lavfi', '-i', backgroundSource(recipe.background, D));
    next = 1;
    finish('0:v');
  } else {
    const n = inputs.photos.length;
    const S = recipe.slideSeconds;
    inputs.photos.forEach((p) => args.push('-loop', '1', '-framerate', String(FPS), '-t', f(S), '-i', p));
    next = n;
    const fit = [...lookFilters(recipe), `scale=${W}:${H}:force_original_aspect_ratio=decrease`,
      `pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2:color=black`, 'setsar=1', `fps=${FPS}`, 'format=yuv420p'];
    inputs.photos.forEach((_, i) => graph.push(`[${i}:v]${fit.join(',')}[p${i}]`));
    // the look filters were applied per photo above, so they must not run again on the joined result
    tail.length = 0;
    if (n === 1) {
      finish('p0');
    } else if (recipe.transition === 'fade') {
      let prev = 'p0';
      for (let i = 1; i < n; i++) {
        const label = i === n - 1 ? 'joined' : `x${i}`;
        graph.push(`[${prev}][p${i}]xfade=transition=fade:duration=${FADE}:offset=${f(i * (S - FADE))}[${label}]`);
        prev = label;
      }
      finish('joined');
    } else {
      graph.push(`${inputs.photos.map((_, i) => `[p${i}]`).join('')}concat=n=${n}:v=1:a=0[joined]`);
      finish('joined');
    }
  }

  // ---- sound ----
  const stereo = 'aresample=44100,aformat=channel_layouts=stereo';
  const useOriginal = recipe.mode === 'VIDEO' && !recipe.muteOriginal;
  let musicIndex = -1;
  if (recipe.music) {
    musicIndex = next++;
    args.push('-ss', f(recipe.music.startSec), '-stream_loop', '-1', '-i', inputs.music);
  }
  const fadeOut = `afade=t=out:st=${f(Math.max(0, D - 1))}:d=1`;
  const music = recipe.music ? `[${musicIndex}:a]${stereo},volume=${f(recipe.music.volume)},${fadeOut}` : null;
  if (useOriginal && music) {
    graph.push(`[0:a]${stereo}[a0]`, `${music}[a1]`, '[a0][a1]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[a]');
  } else if (useOriginal) {
    graph.push(`[0:a]${stereo}[a]`);
  } else if (music) {
    graph.push(`${music}[a]`);
  } else {
    args.push('-f', 'lavfi', '-t', f(D), '-i', 'anullsrc=r=44100:cl=stereo');
    graph.push(`[${next}:a]anull[a]`); // a silent track keeps every post's file shaped the same
  }

  // The speech for the transcript must not have music mixed into it, so it is written as a second output.
  const wantVoice = !!voicePath && useOriginal;
  if (wantVoice) graph.push('[0:a]aresample=16000,aformat=channel_layouts=mono[voice]');

  args.push('-filter_complex', graph.join(';'), '-map', videoLabel, '-map', '[a]',
    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '26', '-pix_fmt', 'yuv420p',
    '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart', '-t', f(D), out);
  if (wantVoice) args.push('-map', '[voice]', '-c:a', 'libmp3lame', '-ar', '16000', '-ac', '1', '-t', f(D), voicePath);
  return args;
}

function run(ffmpegPath, args, { cwd, timeoutMs, captureStderr = true }) {
  return new Promise((resolve, reject) => {
    const child = spawn(ffmpegPath, args, { cwd, stdio: ['ignore', 'ignore', 'pipe'], windowsHide: true });
    let stderr = '';
    let killed = false;
    const timer = setTimeout(() => { killed = true; child.kill('SIGKILL'); }, timeoutMs);
    child.stderr.on('data', (d) => { if (captureStderr && stderr.length < 20000) stderr += d.toString(); });
    child.on('error', (err) => { clearTimeout(timer); reject(err); });
    child.on('close', (code) => {
      clearTimeout(timer);
      if (killed) return reject(new Error(`ffmpeg timed out after ${timeoutMs} ms`));
      resolve({ code, stderr });
    });
  });
}

/** Duration and streams of a media file, read from `ffmpeg -i` (we ship ffmpeg, not ffprobe). Throws if it is not readable media. */
async function probe(ffmpegPath, file, { timeoutMs = 15000 } = {}) {
  const { stderr } = await run(ffmpegPath, ['-hide_banner', '-i', file], { timeoutMs });
  const d = /Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)/.exec(stderr);
  if (!d && !/Video:/.test(stderr)) throw new Error('not readable media');
  const size = /Video:.*?,\s(\d{2,5})x(\d{2,5})/.exec(stderr);
  return {
    durationSec: d ? Number(d[1]) * 3600 + Number(d[2]) * 60 + Number(d[3]) : 0,
    hasVideo: /Stream #\d+:\d+.*Video:/.test(stderr),
    hasAudio: /Stream #\d+:\d+.*Audio:/.test(stderr),
    width: size ? Number(size[1]) : null,
    height: size ? Number(size[2]) : null
  };
}

/** One JPEG of [videoPath] at [atSec]. A missing cover is not worth failing a post for, so this says whether it worked. */
async function makeCover(ffmpegPath, videoPath, coverPath, atSec, cwd) {
  try {
    const args = ['-y', '-hide_banner', '-loglevel', 'error', '-ss', f(atSec), '-i', videoPath, '-frames:v', '1',
      '-vf', `scale=-2:'min(720,trunc(ih/2)*2)'`, '-q:v', '4', coverPath];
    const { code } = await run(ffmpegPath, args, { cwd, timeoutMs: 30000 });
    if (code === 0 && fs.existsSync(coverPath)) return true;
  } catch {
    // fall through: no cover
  }
  fs.rmSync(coverPath, { force: true });
  return false;
}

/**
 * Renders [recipe] to [outPath]. Resolves when the file is complete; rejects (and removes partial output) on any failure.
 * When [coverPath] is given a JPEG of the moment recipe.coverSec is written there too; resolves { cover: whether it was made }.
 */
async function render({ ffmpegPath, fontsDir, recipe, inputs, outPath, workDir, voicePath = null, coverPath = null, timeoutMs = 150000 }) {
  fs.mkdirSync(workDir, { recursive: true });
  try {
    const built = buildAss(recipe);
    if (built) {
      fs.writeFileSync(path.join(workDir, 'overlay.ass'), built.ass, 'utf8');
      fs.mkdirSync(path.join(workDir, 'fonts'), { recursive: true });
      for (const file of built.fonts) fs.copyFileSync(path.join(fontsDir, file), path.join(workDir, 'fonts', file));
    }
    const args = buildArgs({ recipe, inputs, out: outPath, hasAss: !!built, voicePath });
    const { code, stderr } = await run(ffmpegPath, args, { cwd: workDir, timeoutMs });
    if (code !== 0) throw new Error(`ffmpeg failed (${code}): ${stderr.slice(-600)}`);
    return { cover: coverPath ? await makeCover(ffmpegPath, outPath, coverPath, recipe.coverSec || 0, workDir) : false };
  } catch (err) {
    fs.rmSync(outPath, { force: true });
    if (voicePath) fs.rmSync(voicePath, { force: true });
    throw err;
  } finally {
    fs.rmSync(workDir, { recursive: true, force: true });
  }
}

module.exports = { buildArgs, backgroundSource, lookFilters, render, probe, FPS };
