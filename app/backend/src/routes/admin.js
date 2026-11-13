// Moderation back office, demo level. Everything under /api/admin needs  Authorization: Bearer <MODERATION_TOKEN>.
// With no MODERATION_TOKEN configured the whole thing answers 404, so it cannot be left open by accident.
// GET /admin serves one small page that uses these endpoints (the page itself holds no data; the token is typed in).

const crypto = require('crypto');
const express = require('express');
const { wrap, HttpError } = require('../http');
const { nowIso } = require('../queries');
const { REPORT_REASONS } = require('../moderation');
const { computeInsights } = require('../insights');

const sameToken = (given, expected) => {
  const a = crypto.createHash('sha256').update(String(given)).digest();
  const b = crypto.createHash('sha256').update(String(expected)).digest();
  return crypto.timingSafeEqual(a, b);
};

const PAGE = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>FOREST moderation</title>
<style>body{font:15px system-ui;max-width:900px;margin:20px auto;padding:0 12px}h1{font-size:20px}
.card{border:1px solid #8884;border-radius:8px;padding:10px;margin:10px 0}button{margin:4px 4px 0 0;padding:6px 10px}
small{color:#888}input{padding:6px;width:260px}.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}</style>
<h1>FOREST moderation <small>(demo)</small></h1>
<p><a href="/admin/insights">Founders' numbers</a></p>
<div class="row"><input id="t" type="password" placeholder="moderation token"><button id="go">Load</button><span id="msg"></span></div>
<h2>Reported posts</h2><div id="reports"></div>
<h2>Complaints</h2><div id="complaints"></div>
<h2>Recent actions</h2><div id="log"></div>
<script>
const $=id=>document.getElementById(id);
const api=(m,u,b)=>fetch(u,{method:m,headers:{authorization:'Bearer '+$('t').value,'content-type':'application/json'},body:b?JSON.stringify(b):undefined})
  .then(async r=>{const d=await r.json().catch(()=>({}));if(!r.ok)throw new Error(d.error||r.status);return d});
const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!=null)e.textContent=text;if(cls)e.className=cls;return e};
function btn(label,fn){const b=el('button',label);b.onclick=async()=>{try{await fn();load()}catch(e){$('msg').textContent=e.message}};return b}
async function load(){
  $('msg').textContent='';
  try{
    const r=await api('GET','/api/admin/reports');$('reports').replaceChildren(...(r.reports.length?r.reports.map(p=>{
      const c=el('div',null,'card');
      c.append(el('b',p.kind+' by @'+p.author+' ('+p.status+')'),el('div',(p.title||p.body||'(no text)')),
        el('small',p.reportCount+' report(s): '+Object.entries(p.reasons).map(([k,v])=>k+' x'+v).join(', ')+' · post '+p.postId));
      const row=el('div');
      row.append(btn('Hide',()=>api('POST','/api/admin/posts/'+p.postId+'/hide',{reason:p.topReason})),
        btn('Hide as COPYRIGHT',()=>api('POST','/api/admin/posts/'+p.postId+'/hide',{reason:'COPYRIGHT'})),
        btn('Dismiss reports',()=>api('POST','/api/admin/posts/'+p.postId+'/dismiss',{})),
        btn('Restore',()=>api('POST','/api/admin/posts/'+p.postId+'/restore',{})));
      c.append(row);return c}):[el('small','Nothing open.')]));
    const k=await api('GET','/api/admin/complaints');$('complaints').replaceChildren(...(k.complaints.length?k.complaints.map(x=>{
      const c=el('div',null,'card');c.append(el('b',x.status+' · '+(x.contact||'no contact')),el('div',x.message),el('small',x.createdAt+(x.postId?' · post '+x.postId:'')));
      if(x.status==='OPEN'){const i=el('input');i.placeholder='written reply';c.append(el('div'),i,btn('Resolve',()=>api('POST','/api/admin/complaints/'+x.id+'/resolve',{reply:i.value})))}
      else c.append(el('div','Reply: '+(x.reply||'')));return c}):[el('small','No complaints.')]));
    const l=await api('GET','/api/admin/log');$('log').replaceChildren(...l.log.map(e=>el('div',e.at+' · '+e.actor+' · '+e.action+(e.reason?' ('+e.reason+')':'')+' · post '+(e.postId||'-')+(e.note?' · '+e.note:''))));
  }catch(e){$('msg').textContent=e.message}
}
$('go').onclick=load;
</script>`;

// The founders' page: the same token, one table per question (docs/PRODUCT_REPORT.html). It only reads /api/admin/insights.
const INSIGHTS_PAGE = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>FOREST numbers</title>
<style>body{font:15px system-ui;max-width:980px;margin:20px auto;padding:0 12px}h1{font-size:20px}h2{font-size:16px;margin-top:24px}
table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #8884;padding:5px 8px;text-align:right}th:first-child,td:first-child{text-align:left}
.k{display:flex;gap:12px;flex-wrap:wrap}.k div{border:1px solid #8884;border-radius:8px;padding:8px 12px;min-width:130px}.k b{font-size:22px;display:block}
small{color:#888}input{padding:6px;width:240px}</style>
<h1>FOREST numbers <small>real people only, no bots</small></h1>
<p><input id="t" type="password" placeholder="moderation token"> <select id="d"><option>7</option><option selected>14</option><option>30</option></select> days
<button id="go">Load</button> <span id="msg"></span> · <a href="/admin">Moderation</a></p>
<div id="out"></div>
<script>
const $=id=>document.getElementById(id);
const el=(tag,text)=>{const e=document.createElement(tag);if(text!=null)e.textContent=text;return e};
const table=(head,rows)=>{const t=el('table'),h=el('tr');head.forEach(x=>h.append(el('th',x)));t.append(h);rows.forEach(r=>{const tr=el('tr');r.forEach(x=>tr.append(el('td',x==null?'-':x)));t.append(tr)});return t};
const kpi=(label,value)=>{const d=el('div');d.append(el('b',value==null?'-':value),el('small',label));return d};
$('go').onclick=async()=>{
  $('msg').textContent='';
  try{
    const r=await fetch('/api/admin/insights?days='+$('d').value,{headers:{authorization:'Bearer '+$('t').value}});
    const d=await r.json();if(!r.ok)throw new Error(d.error||r.status);
    const k=el('div');k.className='k';
    k.append(kpi('people',d.totals.people),kpi('opinions',d.totals.opinions),kpi('replies',d.totals.replies),
      kpi('answered within 24h (%)',d.answers.answeredWithin24hPct),kpi('median hours to first reply',d.answers.medianHoursToFirstReply),
      kpi('came back next day (%)',d.nextDayReturn.pct),kpi('joined by invite',d.totals.invitedPeople),kpi('open rooms',d.totals.openRooms));
    const f=d.funnel;
    $('out').replaceChildren(k,el('h2','The first minute (people who joined in this window)'),
      table(['Step','People','% of joined'],f.map(s=>[s.step,s.people,f[0].people?Math.round(s.people/f[0].people*100)+'%':'-'])),
      el('h2','Day by day'),
      table(['Day','Joined','Finished onboarding','Active','Opinions','Replies','Answers to the question'],d.daily.map(x=>[x.day,x.signups,x.onboarded,x.active,x.opinions,x.replies,x.promptAnswers])),
      el('h2','Rooms'),table(['Members','Posts'],[[d.rooms.members,d.rooms.posts]]));
  }catch(e){$('msg').textContent=e.message}
};
</script>`;

const WINDOW_MS = 15 * 60 * 1000;
const MAX_BAD_TOKENS = 10; // wrong guesses per address per window

module.exports = function adminRoutes({ db, moderation, moderationToken, clock = Date.now, promptOffsetMin = 330 }) {
  const router = express.Router();
  const bad = new Map(); // ip -> { count, since }

  // The page itself is public HTML with no data; every endpoint it calls checks the token.
  router.get('/admin', (req, res) => {
    if (!moderationToken) return res.status(404).json({ error: 'Not found' });
    res.set('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'");
    res.type('html').send(PAGE);
  });

  router.get('/admin/insights', (req, res) => {
    if (!moderationToken) return res.status(404).json({ error: 'Not found' });
    res.set('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'");
    res.type('html').send(INSIGHTS_PAGE);
  });

  const api = express.Router();
  api.use((req, res, next) => {
    if (!moderationToken) return res.status(404).json({ error: 'Not found' });
    const now = clock();
    const seen = bad.get(req.ip);
    if (seen && now - seen.since > WINDOW_MS) bad.delete(req.ip);
    if (bad.size > 10000) bad.clear();
    if ((bad.get(req.ip) || { count: 0 }).count >= MAX_BAD_TOKENS) {
      return res.status(429).json({ error: 'Too many wrong tokens. Try again later.', retryAfterSec: Math.ceil(WINDOW_MS / 1000) });
    }
    const m = /^Bearer (.+)$/.exec(req.get('authorization') || '');
    if (!m || !sameToken(m[1], moderationToken)) {
      const e = bad.get(req.ip) || { count: 0, since: now };
      e.count++;
      bad.set(req.ip, e);
      return res.status(401).json({ error: 'Unauthorized' });
    }
    next();
  });

  api.get('/insights', wrap(async (req, res) => {
    res.json(computeInsights(db, { days: req.query.days, clock, offsetMin: promptOffsetMin }));
  }));

  // Posts that have reports, open ones first.
  api.get('/reports', wrap(async (req, res) => {
    const rows = db.all(
      `SELECT p.id, p.kind, p.title, p.body, p.status, u.username AS author,
              SUM(CASE WHEN r.status = 'OPEN' THEN 1 ELSE 0 END) AS open_count, COUNT(*) AS total,
              MAX(r.created_at) AS last_at
       FROM reports r JOIN posts p ON p.id = r.post_id JOIN users u ON u.id = p.user_id
       GROUP BY p.id ORDER BY open_count DESC, last_at DESC LIMIT 100`
    );
    const reasons = db.all('SELECT post_id, reason, COUNT(*) AS n FROM reports GROUP BY post_id, reason');
    res.json({
      reports: rows.map((p) => {
        const mine = reasons.filter((r) => r.post_id === p.id);
        const top = [...mine].sort((a, b) => b.n - a.n)[0];
        return {
          postId: p.id, kind: p.kind, title: p.title, body: p.body, status: p.status, author: p.author,
          reportCount: p.total, openCount: p.open_count,
          reasons: Object.fromEntries(mine.map((r) => [r.reason, r.n])), topReason: top ? top.reason : null
        };
      })
    });
  }));

  api.post('/posts/:id/hide', wrap(async (req, res) => {
    const reason = req.body && req.body.reason ? String(req.body.reason).toUpperCase() : null;
    if (reason && !REPORT_REASONS.includes(reason)) throw new HttpError(400, `reason must be one of ${REPORT_REASONS.join(', ')}`);
    if (!moderation.hidePost(req.params.id, { reason, note: req.body && req.body.note })) {
      throw new HttpError(409, 'Only a visible post can be hidden');
    }
    res.json({ hidden: true });
  }));

  api.post('/posts/:id/restore', wrap(async (req, res) => {
    if (!moderation.restorePost(req.params.id, { note: req.body && req.body.note })) throw new HttpError(409, 'That post is not hidden');
    res.json({ restored: true });
  }));

  api.post('/posts/:id/dismiss', wrap(async (req, res) => {
    res.json({ dismissed: moderation.dismissReports(req.params.id, { note: req.body && req.body.note }) });
  }));

  api.post('/users/:id/unsuspend', wrap(async (req, res) => {
    if (!moderation.unsuspend(req.params.id, req.body && req.body.note)) throw new HttpError(409, 'That account is not suspended');
    res.json({ unsuspended: true });
  }));

  api.get('/log', wrap(async (req, res) => {
    res.json({
      log: db.all('SELECT * FROM moderation_log ORDER BY id DESC LIMIT 100').map((e) => ({
        id: e.id, at: e.at, actor: e.actor, action: e.action, postId: e.post_id, userId: e.user_id, reason: e.reason, note: e.note
      }))
    });
  }));

  api.get('/complaints', wrap(async (req, res) => {
    res.json({
      complaints: db.all("SELECT * FROM complaints ORDER BY (status = 'OPEN') DESC, created_at DESC LIMIT 100").map((c) => ({
        id: c.id, userId: c.user_id, contact: c.contact, postId: c.post_id, message: c.message, createdAt: c.created_at,
        status: c.status, reply: c.reply, resolvedAt: c.resolved_at
      }))
    });
  }));

  api.post('/complaints/:id/resolve', wrap(async (req, res) => {
    const reply = String((req.body && req.body.reply) || '').trim().slice(0, 2000);
    if (!reply) throw new HttpError(400, 'Write the reason you are giving the person');
    const n = db.run("UPDATE complaints SET status = 'RESOLVED', reply = ?, resolved_at = ? WHERE id = ? AND status = 'OPEN'", [reply, nowIso(), req.params.id]);
    if (!n) throw new HttpError(404, 'Complaint not found or already resolved');
    res.json({ resolved: true });
  }));

  router.use('/api/admin', api);
  return router;
};
