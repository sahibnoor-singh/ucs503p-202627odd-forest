// Draws a flat, illustrated profile picture (a PNG) for an account, with no dependencies and no real photos.
// The same name always gives the same picture; an options object picks the look by hand.
//
//   const { renderAvatar } = require('./lib/avatar');
//   fs.writeFileSync('aman_s.png', renderAvatar('aman_s', { hair: 'short', skin: 2, hairColor: 0, shirt: 4, bg: 1 }));
//
// Used by the seed scripts so test accounts have a picture to show. Real users upload their own.

const zlib = require('zlib');

const SKIN = ['#f6d3b3', '#ecb98f', '#d79a6b', '#b87849', '#8f5a35', '#6b4128'];
const HAIR = ['#17120f', '#2b1b12', '#4a2c19', '#6b4325', '#3a3a46', '#a06a35'];
const SHIRT = ['#2f6f4f', '#d4503f', '#2d5fa8', '#e0a030', '#7a4fa3', '#1f8a8a', '#c2527a', '#445066'];
const BG = [
  ['#cfe8d8', '#8fc7a4'], ['#ffd9c2', '#f2a47c'], ['#d5e1fb', '#97b4ee'], ['#f6e3a8', '#e3bf5c'],
  ['#e3d5f5', '#b69ae0'], ['#c8ecec', '#7fc9c9'], ['#fbd3e2', '#ec9ab9'], ['#dfe3ea', '#a9b1c2']
];
const HAIR_STYLES = ['short', 'side', 'long', 'bun', 'turban', 'cap', 'curly'];

function hash(str) {
  let h = 2166136261;
  for (const c of String(str)) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); }
  return h >>> 0;
}
const rgb = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);
const shade = (c, t) => c.map((v) => Math.max(0, Math.min(255, v * (1 + t))));

// signed distances (negative inside), in pixels
const ellipse = (x, y, cx, cy, rx, ry) => (Math.hypot((x - cx) / rx, (y - cy) / ry) - 1) * Math.min(rx, ry);
const circle = (x, y, cx, cy, r) => Math.hypot(x - cx, y - cy) - r;
const box = (x, y, cx, cy, hw, hh, r = 0) => {
  const qx = Math.abs(x - cx) - hw + r;
  const qy = Math.abs(y - cy) - hh + r;
  return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
};
const ring = (d, thick) => Math.abs(d) - thick / 2;
const cover = (d) => Math.max(0, Math.min(1, 0.5 - d)); // 1 pixel of anti-aliasing

/** @returns {Buffer} a PNG, size x size */
function renderAvatar(name, opts = {}) {
  const size = opts.size || 256;
  const h = hash(name);
  const pick = (v, list, shift) => (v != null ? v : (h >>> shift) % list.length) % list.length;
  const skin = rgb(SKIN[pick(opts.skin, SKIN, 0)]);
  const hairColor = rgb(HAIR[pick(opts.hairColor, HAIR, 3)]);
  const shirt = rgb(SHIRT[pick(opts.shirt, SHIRT, 6)]);
  const bg = BG[pick(opts.bg, BG, 9)].map(rgb);
  const style = opts.hair || HAIR_STYLES[(h >>> 12) % HAIR_STYLES.length];
  const glasses = opts.glasses != null ? opts.glasses : ((h >>> 16) & 3) === 0;
  const turban = style === 'turban' ? rgb(opts.turbanColor || SHIRT[(h >>> 4) % SHIRT.length]) : null;
  const k = size / 256;

  const px = Buffer.alloc(size * size * 4);
  for (let j = 0; j < size; j++) {
    for (let i = 0; i < size; i++) {
      const x = (i + 0.5) / k;
      const y = (j + 0.5) / k;
      let c = mix(bg[0], bg[1], Math.min(1, (x * 0.35 + y * 0.65) / 256));
      const paint = (d, color, alpha = 1) => { const a = cover(d * k) * alpha; if (a > 0) c = mix(c, color, a); };

      // long / wavy hair sits behind the head and shoulders
      if (style === 'long') paint(ellipse(x, y, 128, 135, 62, 86), hairColor);
      if (style === 'curly') {
        for (const [cx, cy, r] of [[78, 96, 26], [96, 66, 28], [128, 56, 30], [160, 66, 28], [178, 96, 26], [74, 130, 22], [182, 130, 22]]) paint(circle(x, y, cx, cy, r), hairColor);
      }
      // shoulders, collar, neck
      paint(ellipse(x, y, 128, 292, 112, 100), shirt);
      paint(ellipse(x, y, 128, 214, 30, 16), shade(shirt, -0.25));
      paint(box(x, y, 128, 178, 19, 36, 8), shade(skin, -0.12));
      // ears, head
      paint(ellipse(x, y, 83, 122, 7, 12), shade(skin, -0.08));
      paint(ellipse(x, y, 173, 122, 7, 12), shade(skin, -0.08));
      paint(ellipse(x, y, 128, 112, 46, 54), skin);

      // hair in front
      const hairline = (d) => Math.max(d, -ellipse(x, y, 128, 128, 36, 44)); // keeps the forehead and face clear
      if (style === 'short') paint(hairline(ellipse(x, y, 128, 96, 51, 48)), hairColor);
      if (style === 'side') {
        paint(hairline(ellipse(x, y, 124, 94, 52, 48)), hairColor);
        paint(Math.max(ellipse(x, y, 106, 92, 40, 20), -ellipse(x, y, 130, 118, 32, 28)), hairColor);
      }
      if (style === 'long') paint(hairline(ellipse(x, y, 128, 94, 54, 50)), hairColor);
      if (style === 'bun') {
        paint(circle(x, y, 128, 50, 20), hairColor);
        paint(hairline(ellipse(x, y, 128, 94, 51, 47)), hairColor);
      }
      if (style === 'curly') paint(hairline(ellipse(x, y, 128, 92, 52, 44)), hairColor);
      if (style === 'cap') {
        paint(Math.max(ellipse(x, y, 128, 90, 53, 48), y - 96), hairColor.map((v) => v * 0.4 + 40));
        paint(box(x, y, 148, 100, 44, 5, 5), shade(hairColor.map((v) => v * 0.4 + 40), -0.25));
      }
      if (style === 'turban') {
        paint(Math.max(ellipse(x, y, 128, 84, 56, 54), y - 104), turban);
        paint(Math.max(ellipse(x, y, 128, 88, 56, 50), -(y - 88)), shade(turban, 0.12), 0.0);
        paint(ring(ellipse(x, y, 128, 98, 56, 18), 5), shade(turban, -0.22), 0.8);
        paint(ring(ellipse(x, y, 128, 80, 52, 24), 4), shade(turban, 0.16), 0.7);
      }

      // face
      const eyeY = 118;
      paint(ellipse(x, y, 109, eyeY, 4.6, 5.4), [38, 28, 26]);
      paint(ellipse(x, y, 147, eyeY, 4.6, 5.4), [38, 28, 26]);
      paint(ring(ellipse(x, y, 109, eyeY - 14, 11, 4), 3), shade(hairColor, 0), 0.8);
      paint(ring(ellipse(x, y, 147, eyeY - 14, 11, 4), 3), shade(hairColor, 0), 0.8);
      paint(Math.max(ring(circle(x, y, 128, 128, 22), 3.4), 142 - y), shade(skin, -0.5), 0.9);
      paint(ellipse(x, y, 128, 130, 3, 4), shade(skin, -0.16), 0.9);
      if (glasses) {
        paint(ring(circle(x, y, 109, eyeY, 14), 3), [40, 40, 48]);
        paint(ring(circle(x, y, 147, eyeY, 14), 3), [40, 40, 48]);
        paint(box(x, y, 128, eyeY - 1, 5, 1.5), [40, 40, 48]);
      }

      const o = (j * size + i) * 4;
      px[o] = c[0]; px[o + 1] = c[1]; px[o + 2] = c[2]; px[o + 3] = 255;
    }
  }
  return encodePng(px, size, size);
}

// ---- minimal PNG writer ----
const CRC = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) { let c = n; for (let b = 0; b < 8; b++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c; }
  return t;
})();
function crc32(buf) { let c = -1; for (const b of buf) c = CRC[(c ^ b) & 255] ^ (c >>> 8); return (c ^ -1) >>> 0; }
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}
function encodePng(rgba, w, h) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 4 + 1)] = 0; rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4); }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

module.exports = { renderAvatar, HAIR_STYLES };
