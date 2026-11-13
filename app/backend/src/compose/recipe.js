// The "recipe" is a small JSON description of a post made in the editor (docs/EDITOR_PLAN.md). The phone sends it
// with the files; the server renders it to a normal MP4. Nothing in a recipe is trusted: this file rebuilds it field by
// field from a whitelist, with ranges and limits, so a client can neither crash the renderer nor smuggle anything into
// the ffmpeg command (text only ever goes into an ASS file, colours must be #rrggbb, files are ours).

const { HttpError } = require('../http');

const MODES = ['VIDEO', 'TEXT', 'PHOTOS'];
const FONTS = ['sans', 'serif', 'mono'];
const ALIGNS = ['left', 'center', 'right'];
const ANIMATIONS = ['none', 'fade', 'slideUp', 'typewriter', 'wordByWord'];
const TRANSITIONS = ['none', 'fade'];

const MAX_SECONDS = 60;
const MAX_PHOTOS = 10;
const MAX_OVERLAYS = 5;
const MAX_TEXT = 280;
const MAX_OVERLAY_TEXT = 120;

const bad = (field, message) => new HttpError(400, message, { field });

function num(v, field, { min, max, def }) {
  if (v === undefined || v === null || v === '') return def;
  const n = Number(v);
  if (!Number.isFinite(n)) throw bad(field, `${field} must be a number`);
  if (n < min || n > max) throw bad(field, `${field} must be between ${min} and ${max}`);
  return n;
}

function color(v, field, def) {
  if (v === undefined || v === null) return def;
  if (typeof v !== 'string' || !/^#[0-9a-fA-F]{6}$/.test(v)) throw bad(field, `${field} must look like #rrggbb`);
  return v.toLowerCase();
}

function pick(v, list, field, def) {
  if (v === undefined || v === null) return def;
  if (!list.includes(v)) throw bad(field, `${field} must be one of ${list.join(', ')}`);
  return v;
}

/** Text that will be drawn: trimmed, no control characters, length checked in characters (not bytes). */
function text(v, field, max) {
  if (typeof v !== 'string') throw bad(field, `${field} is required`);
  const t = v.replace(/\r\n?/g, '\n').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, '').trim();
  if (!t) throw bad(field, `${field} cannot be empty`);
  if ([...t].length > max) throw bad(field, `${field} is limited to ${max} characters`);
  return t;
}

function adjust(raw) {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== 'object') throw bad('adjust', 'adjust must be an object');
  const a = {
    brightness: num(raw.brightness, 'adjust.brightness', { min: -0.5, max: 0.5, def: 0 }),
    contrast: num(raw.contrast, 'adjust.contrast', { min: 0.5, max: 2, def: 1 }),
    saturation: num(raw.saturation, 'adjust.saturation', { min: 0, max: 3, def: 1 }),
    hue: num(raw.hue, 'adjust.hue', { min: -180, max: 180, def: 0 }),
    blur: num(raw.blur, 'adjust.blur', { min: 0, max: 10, def: 0 })
  };
  const neutral = a.brightness === 0 && a.contrast === 1 && a.saturation === 1 && a.hue === 0 && a.blur === 0;
  return neutral ? null : a;
}

function crop(raw) {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== 'object') throw bad('crop', 'crop must be an object');
  const c = {
    x: num(raw.x, 'crop.x', { min: 0, max: 1, def: 0 }),
    y: num(raw.y, 'crop.y', { min: 0, max: 1, def: 0 }),
    w: num(raw.w, 'crop.w', { min: 0.1, max: 1, def: 1 }),
    h: num(raw.h, 'crop.h', { min: 0.1, max: 1, def: 1 })
  };
  if (c.x + c.w > 1.0001 || c.y + c.h > 1.0001) throw bad('crop', 'the crop box must stay inside the picture');
  return c.x === 0 && c.y === 0 && c.w === 1 && c.h === 1 ? null : c;
}

function overlays(raw, totalSec) {
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw)) throw bad('overlays', 'overlays must be a list');
  if (raw.length > MAX_OVERLAYS) throw bad('overlays', `at most ${MAX_OVERLAYS} text overlays`);
  return raw.map((o, i) => {
    if (!o || typeof o !== 'object') throw bad('overlays', 'each overlay must be an object');
    const f = (name) => `overlays[${i}].${name}`;
    const startSec = num(o.startSec, f('startSec'), { min: 0, max: totalSec, def: 0 });
    const endSec = num(o.endSec, f('endSec'), { min: 0, max: totalSec, def: totalSec });
    if (endSec <= startSec) throw bad('overlays', 'an overlay must end after it starts');
    return {
      text: text(o.text, f('text'), MAX_OVERLAY_TEXT),
      x: num(o.x, f('x'), { min: 0, max: 1, def: 0.5 }),
      y: num(o.y, f('y'), { min: 0, max: 1, def: 0.5 }),
      size: num(o.size, f('size'), { min: 20, max: 120, def: 56 }),
      color: color(o.color, f('color'), '#ffffff'),
      font: pick(o.font, FONTS, f('font'), 'sans'),
      startSec, endSec
    };
  });
}

function background(raw) {
  if (raw === undefined || raw === null) return { type: 'solid', color: '#111111' };
  if (typeof raw !== 'object') throw bad('background', 'background must be an object');
  const type = pick(raw.type, ['solid', 'gradient'], 'background.type', 'solid');
  if (type === 'solid') return { type, color: color(raw.color, 'background.color', '#111111') };
  return {
    type,
    from: color(raw.from, 'background.from', '#0f2027'),
    to: color(raw.to, 'background.to', '#2c5364'),
    angle: num(raw.angle, 'background.angle', { min: 0, max: 360, def: 180 })
  };
}

/**
 * @param {*} raw      the parsed recipe JSON from the client
 * @param {object} ctx
 * @param {number} ctx.photoCount  how many photo files were uploaded
 * @param {boolean} ctx.hasMusic   a music file was uploaded
 * @param {boolean} ctx.hasVideo   a video file was uploaded
 * @param {{durationSec:number, hasAudio:boolean}|null} ctx.videoInfo  probed facts about the video file
 * @returns the normalised recipe, including `durationSec` (length of the finished video)
 */
function validateRecipe(raw, { photoCount = 0, hasMusic = false, hasVideo = false, videoInfo = null } = {}) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw bad('recipe', 'recipe must be a JSON object');
  const mode = pick(raw.mode, MODES, 'mode', undefined);
  if (!mode) throw bad('mode', `mode must be one of ${MODES.join(', ')}`);

  if (mode !== 'VIDEO' && hasVideo) throw bad('video', 'A video file only goes with mode VIDEO');
  if (mode !== 'PHOTOS' && photoCount) throw bad('photos', 'Photos only go with mode PHOTOS');
  const r = { mode };

  if (mode === 'VIDEO') {
    if (!hasVideo || !videoInfo) throw bad('video', 'mode VIDEO needs a video file');
    const trimRaw = raw.trim || {};
    const full = videoInfo.durationSec;
    const startSec = num(trimRaw.startSec, 'trim.startSec', { min: 0, max: Math.max(0, full - 0.5), def: 0 });
    const endSec = num(trimRaw.endSec, 'trim.endSec', { min: 0, max: full + 0.5, def: Math.min(full, startSec + MAX_SECONDS) });
    const length = Math.min(endSec, full) - startSec;
    if (length < 0.5) throw bad('trim', 'the trimmed video must be at least half a second long');
    if (length > MAX_SECONDS + 0.01) throw bad('trim', `videos are limited to ${MAX_SECONDS} seconds: trim it shorter`);
    r.trim = { startSec, endSec: startSec + length };
    r.durationSec = Math.round(length * 100) / 100;
    r.muteOriginal = raw.muteOriginal === true || !videoInfo.hasAudio;
    r.sourceHasAudio = !!videoInfo.hasAudio;
    r.crop = crop(raw.crop);
  } else if (mode === 'TEXT') {
    r.durationSec = num(raw.durationSec, 'durationSec', { min: 3, max: MAX_SECONDS, def: 8 });
    const t = raw.text;
    if (!t || typeof t !== 'object') throw bad('text', 'mode TEXT needs a text object');
    r.text = {
      content: text(t.content, 'text.content', MAX_TEXT),
      color: color(t.color, 'text.color', '#ffffff'),
      font: pick(t.font, FONTS, 'text.font', 'sans'),
      size: num(t.size, 'text.size', { min: 32, max: 120, def: 64 }),
      align: pick(t.align, ALIGNS, 'text.align', 'center'),
      animation: pick(t.animation, ANIMATIONS, 'text.animation', 'fade')
    };
    r.background = background(raw.background);
  } else {
    if (photoCount < 1) throw bad('photos', 'mode PHOTOS needs at least one photo');
    if (photoCount > MAX_PHOTOS) throw bad('photos', `at most ${MAX_PHOTOS} photos`);
    let order = raw.photoOrder;
    if (order === undefined || order === null) order = Array.from({ length: photoCount }, (_, i) => i);
    if (!Array.isArray(order) || order.length !== photoCount ||
        [...order].sort((a, b) => a - b).some((v, i) => v !== i)) {
      throw bad('photoOrder', 'photoOrder must list each photo number once');
    }
    r.photoOrder = order;
    r.slideSeconds = num(raw.slideSeconds, 'slideSeconds', { min: 1, max: 8, def: 3 });
    r.transition = pick(raw.transition, TRANSITIONS, 'transition', 'fade');
    const overlap = r.transition === 'fade' && photoCount > 1 ? 0.5 : 0;
    const total = photoCount * r.slideSeconds - (photoCount - 1) * overlap;
    if (total > MAX_SECONDS) throw bad('slideSeconds', `the slideshow would be ${Math.ceil(total)} s; the limit is ${MAX_SECONDS} s`);
    r.durationSec = Math.round(total * 100) / 100;
    r.crop = crop(raw.crop);
  }

  // The moment (seconds into the finished video) whose picture is shown before the video plays. Text and photo posts have
  // nothing at the very start (the words are still fading in), so they default to a moment in.
  const cover = num(raw.coverSec, 'coverSec', { min: 0, max: r.durationSec, def: null });
  const coverAt = cover === null ? (mode === 'VIDEO' ? 0 : Math.min(2, r.durationSec / 2)) : cover;
  r.coverSec = Math.round(Math.min(coverAt, Math.max(0, r.durationSec - 0.1)) * 100) / 100;

  r.adjust = adjust(raw.adjust);
  r.overlays = overlays(raw.overlays, r.durationSec);

  if (raw.music !== undefined && raw.music !== null && !hasMusic) throw bad('music', 'music settings were sent without a music file');
  if (hasMusic) {
    const m = raw.music && typeof raw.music === 'object' ? raw.music : {};
    r.music = {
      volume: num(m.volume, 'music.volume', { min: 0, max: 1, def: 0.8 }),
      startSec: num(m.startSec, 'music.startSec', { min: 0, max: 3600, def: 0 })
    };
  }
  return r;
}

/** Words that the AI and the word screen should see for a post that has no speech to transcribe. */
function textOf(recipe, caption) {
  const parts = [];
  if (recipe.text) parts.push(recipe.text.content);
  for (const o of recipe.overlays || []) parts.push(o.text);
  if (caption) parts.push(caption);
  return parts.join('\n').trim();
}

module.exports = {
  validateRecipe, textOf,
  MODES, FONTS, ALIGNS, ANIMATIONS, TRANSITIONS, MAX_SECONDS, MAX_PHOTOS, MAX_OVERLAYS, MAX_TEXT, MAX_OVERLAY_TEXT
};
