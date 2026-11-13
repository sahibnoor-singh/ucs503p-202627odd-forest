// The parts of the website that need no login: a debate someone shared (/p/:id), an invite (/invite/:code), and the Terms and Privacy
// pages the Play Store asks for. Plain server-rendered HTML with no scripts. Everything that came from a person is escaped, and the
// pages carry a content policy that forbids script anyway, so a post titled "<script>" is only ever text.

const express = require('express');
const { getPost, parseAnalysis } = require('../queries');
const { baseUrl } = require('../publicUrl');
const invites = require('../invites');
const legal = require('../legalText');
const { threadCounts } = require('../queries');

const esc = (s) => String(s === undefined || s === null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
const clip = (s, n) => { const t = String(s || '').replace(/\s+/g, ' ').trim(); return t.length > n ? `${t.slice(0, n - 1)}…` : t; };

const CSS = `:root{color-scheme:light dark;--bg:#fff;--fg:#111;--fg2:#666;--card:#f6f6f6;--line:#ddd;--accent:#0095f6;--for:#1e7b3f;--against:#c0392b}
@media(prefers-color-scheme:dark){:root{--bg:#121212;--fg:#f5f5f5;--fg2:#a8a8a8;--card:#1c1c1e;--line:#2c2c2e;--for:#5fbf7f;--against:#e5645f}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:640px;margin:0 auto;padding:20px 16px 40px}header{display:flex;align-items:center;gap:10px;margin-bottom:18px}
.mark{width:34px;height:34px;border-radius:10px;background:#1d6b49;display:grid;place-items:center;color:#fff;font-weight:900}
.brand{font-weight:900;letter-spacing:.14em}h1{font-size:26px;line-height:1.2;margin:8px 0}h2{font-size:18px;margin:26px 0 8px}
.by{color:var(--fg2);font-size:14px;margin:0 0 14px}video{width:100%;max-height:70vh;background:#000;border-radius:14px}
.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:12px 14px;margin:10px 0}
.pill{display:inline-block;font-size:12px;font-weight:800;letter-spacing:.06em;padding:2px 8px;border-radius:999px;border:1px solid var(--line)}
.FOR{color:var(--for)}.AGAINST{color:var(--against)}.bar{display:flex;gap:16px;font-weight:700}
.cta{display:block;text-align:center;background:var(--accent);color:#fff;text-decoration:none;font-weight:800;border-radius:14px;padding:14px;margin:22px 0}
.code{font-size:38px;font-weight:900;letter-spacing:.25em;text-align:center;margin:18px 0}small,footer{color:var(--fg2);font-size:13px}
footer{margin-top:32px;border-top:1px solid var(--line);padding-top:14px}a{color:var(--accent)}`;

const POLICY = "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; media-src 'self'; base-uri 'none'; form-action 'none'";

function page({ title, description = '', body, image = null, url = null, noindex = true }) {
  const og = [
    ['og:site_name', 'FOREST'], ['og:title', title], ['og:description', description], ['og:type', 'website'],
    ...(url ? [['og:url', url]] : []), ...(image ? [['og:image', image]] : [])
  ].map(([k, v]) => `<meta property="${k}" content="${esc(v)}">`).join('');
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title><meta name="description" content="${esc(description)}">${noindex ? '<meta name="robots" content="noindex">' : ''}${og}
<style>${CSS}</style></head><body><main><header><div class="mark">F</div><span class="brand">FOREST</span></header>${body}
<footer><a href="/terms">Terms of use</a> · <a href="/privacy">Privacy notice</a></footer></main></body></html>`;
}

module.exports = function publicRoutes({ db, publicBaseUrl = null, playStoreUrl = null }) {
  const router = express.Router();

  const send = (res, status, html) => {
    res.status(status).set('Content-Security-Policy', POLICY).set('Cache-Control', 'public, max-age=60').type('html').send(html);
  };
  const cta = () => playStoreUrl
    ? `<a class="cta" href="${esc(playStoreUrl)}">Get FOREST to answer on video</a>`
    : '<p class="card">FOREST is a debate app: you answer a video opinion with a video of your own. Ask whoever sent you this for the app.</p>';

  const notFound = (res) => send(res, 404, page({
    title: 'Not available · FOREST',
    body: '<h1>This post is not available</h1><p class="by">It may have been removed, or the link may be wrong.</p>'
  }));

  // A shared debate.
  router.get('/p/:id', (req, res) => {
    const post = getPost(db, String(req.params.id).slice(0, 64));
    const author = post && db.get('SELECT * FROM users WHERE id = ?', [post.user_id]);
    if (!post || post.status !== 'READY' || !author || author.deleted_at || author.suspended_at) return notFound(res);

    const root = post.parent_id ? getPost(db, post.root_id) : post;
    const analysis = parseAnalysis(post);
    const counts = threadCounts(db, post.id);
    const title = post.parent_id
      ? `@${author.username} replied${root && root.title ? `: ${root.title}` : ''}`
      : (post.title || `An opinion by @${author.username}`);
    const summary = clip((analysis && analysis.overallSummary) || post.body || '', 240);
    const base = baseUrl(req, publicBaseUrl);

    const replies = db.all(
      `SELECT r.*, (SELECT COUNT(*) FROM likes l WHERE l.post_id = r.id) AS likes FROM posts r JOIN users u ON u.id = r.user_id
       WHERE r.parent_id = ? AND r.status = 'READY' AND u.deleted_at IS NULL AND u.suspended_at IS NULL
       ORDER BY likes DESC, r.created_at DESC LIMIT 5`,
      [post.id]
    );
    const replyHtml = replies.map((r) => {
      const who = db.get('SELECT username, is_bot FROM users WHERE id = ?', [r.user_id]);
      const text = r.kind === 'TEXT' ? r.body : ((parseAnalysis(r) || {}).overallSummary || 'Video reply');
      return `<div class="card"><b>@${esc(who.username)}</b>${who.is_bot ? ' <span class="pill">BOT</span>' : ''}
        ${r.stance === 'FOR' || r.stance === 'AGAINST' ? `<span class="pill ${r.stance}">${r.stance}</span>` : ''}<div>${esc(clip(text, 300))}</div></div>`;
    }).join('');

    const media = post.media_filename
      ? `<video controls playsinline preload="metadata" src="/uploads/${esc(encodeURIComponent(post.media_filename))}"${post.cover_filename ? ` poster="/uploads/${esc(encodeURIComponent(post.cover_filename))}"` : ''}></video>`
      : '';
    const room = post.room_id ? db.get('SELECT name, motion FROM rooms WHERE id = ?', [post.room_id]) : null;

    send(res, 200, page({
      title: `${title} · FOREST`,
      description: summary || `A video opinion by @${author.username} on FOREST.`,
      image: post.cover_filename ? `${base}/uploads/${encodeURIComponent(post.cover_filename)}` : null,
      url: `${base}/p/${post.id}`,
      body: `<h1>${esc(title)}</h1>
<p class="by">@${esc(author.username)}${author.is_bot ? ' <span class="pill">BOT</span>' : ''} · ${esc(post.created_at.slice(0, 10))}</p>
${media}${summary ? `<p>${esc(summary)}</p>` : ''}
${room ? `<p class="card"><b>${esc(room.name)}</b><br><small>Motion: ${esc(room.motion)}</small></p>` : ''}
<div class="bar"><span class="FOR">${counts.forCount} FOR</span><span class="AGAINST">${counts.againstCount} AGAINST</span><span>${counts.replyCount} replies</span></div>
${replyHtml ? `<h2>What people replied</h2>${replyHtml}` : '<p class="by">No replies yet. Be the first to answer.</p>'}
${cta()}`
    }));
  });

  // An invite. The page tells nothing about a code that is not real.
  router.get('/invite/:code', (req, res) => {
    const inviter = invites.findInviter(db, req.params.code);
    if (!inviter) {
      return send(res, 404, page({ title: 'Invite · FOREST', body: '<h1>This invite link is not valid</h1><p class="by">Ask your friend to send it again.</p>' }));
    }
    const code = invites.normalizeCode(req.params.code);
    send(res, 200, page({
      title: `@${inviter.username} invited you to FOREST`,
      description: 'FOREST is a video debate app. Answer opinions with your own video.',
      body: `<h1>@${esc(inviter.username)} invited you to FOREST</h1>
<p>FOREST is where people answer an opinion with a video of their own, and see both sides of an argument.</p>
<p class="by">When you create your account, enter this invite code on the last page. You and @${esc(inviter.username)} will follow each other.</p>
<div class="code">${esc(code)}</div>${cta()}`
    }));
  });

  const legalPage = (doc, title) => (req, res) => send(res, 200, page({
    title: `${title} · FOREST`,
    noindex: false,
    body: `<h1>${esc(title)}</h1><p class="by">${esc(legal.updated)}</p>${legal[doc].map((s) =>
      `<h2>${esc(s.heading)}</h2>${s.body.map((p) => `<p>${esc(p)}</p>`).join('')}`).join('')}`
  }));
  router.get('/terms', legalPage('terms', 'Terms of use'));
  router.get('/privacy', legalPage('privacy', 'Privacy notice'));

  return router;
};

module.exports.esc = esc;
